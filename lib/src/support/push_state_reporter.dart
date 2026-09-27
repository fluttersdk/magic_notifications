import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:magic/magic.dart';

import '../drivers/push/push_driver.dart';
import '../models/push_delivery_snapshot.dart';
import '../models/push_identity_reconciled.dart';
import '../models/push_subscription.dart';
import '../notification_manager.dart';
import 'notification_log.dart';

/// Tells the host's backend whether a push sent to this device would arrive,
/// and stops this device vouching for a person who signs out of it.
///
/// The server cannot see any of this. The permission, the opt-in flag and the
/// subscription id all live on the device, and OneSignal accepts a push for an
/// unreachable subscription without complaint, so this report is the only
/// evidence a backend deciding whom to page will ever have that the device can
/// actually be woken.
///
/// Reached as `Notify.pushState`. Off until the app names both endpoints:
///
/// ```dart
/// 'push_state': {
///   'report_path': '/devices/push-state',
///   'release_path': '/devices/push-state/release',
/// },
/// ```
///
/// There is no default path, so an app whose backend has no such endpoint
/// sends nothing. The report body is [PushDeliverySnapshot.toMap] verbatim and
/// the release body is the subscription id alone: the person always comes from
/// the session on the server side, never from a body field.
///
/// ## Reported on change, never on a timer
///
/// This fact changes a handful of times in a device's life: a permission
/// granted or revoked, a subscription minted or swapped, a person signing in.
/// Every one of those is an event the platform already reports, so [watch]
/// follows those events and a memo stops the repeats. A starter kit
/// re-declares the push identity on every auth bump (restore, token refresh,
/// team switch), and none of those move the device.
class PushStateReporter {
  /// Creates a reporter reading the device through [manager].
  PushStateReporter(this._manager);

  /// Config key for the report endpoint, relative to the HTTP base url.
  static const String reportPathKey = 'notifications.push_state.report_path';

  /// Config key for the release endpoint, relative to the HTTP base url.
  static const String releasePathKey = 'notifications.push_state.release_path';

  /// Config key for the prefix the signed-in person's external id carries.
  ///
  /// Has to match whatever the app declares through `Notify.initializePush`
  /// and whatever the backend addresses pushes to, because a pass is only
  /// reported when its intent is `<prefix><Auth.id()>`.
  static const String externalIdPrefixKey =
      'notifications.push_state.external_id_prefix';

  /// The prefix this package documents for `Notify.initializePush`.
  static const String _defaultExternalIdPrefix = 'user_';

  /// The manager whose driver is read and whose streams are followed.
  final NotificationManager _manager;

  /// The last state the server accepted, or `null` when nothing has been.
  ///
  /// The device's own facts only: reachability, external id, subscription id.
  /// `captured_at` is deliberately left out, since it moves on every read and
  /// would turn the memo into a permanent miss.
  ///
  /// It goes with the session: [forget] runs on every `AuthLogout`. Two people
  /// share one handset, and the second one's state can be identical to the
  /// first's; a memo surviving the sign-out would read it as already reported
  /// and the server would have no row for the person now holding the phone.
  String? _lastReportedState;

  /// The subscription id the last ACCEPTED report was written under.
  ///
  /// Held beside the memo rather than parsed out of it because it answers a
  /// different question: which server row a release has to remove. [release]
  /// falls back to it when the live read produces no subscription id. [forget]
  /// leaves it alone, since it names this device's own row and is only ever
  /// read by a release made under a live session.
  String? _reportedSubscriptionId;

  /// The subscription id this session already released, so a second
  /// [release] before anything new was reported posts nothing.
  String? _releasedSubscriptionId;

  /// The release currently in the air, joined by a caller arriving mid-flight.
  Future<void>? _releaseInFlight;

  /// The driver whose change streams are watched, compared by identity so a
  /// replaced driver is picked up rather than left unheard.
  PushDriver? _watchedDriver;

  StreamSubscription<PushIdentityChange>? _identityChanges;
  StreamSubscription<PushPermissionState>? _permissionChanges;
  StreamSubscription<PushIdentityReconciled>? _reconciledPasses;
  StreamSubscription<PushDriver>? _driverArrivals;

  /// The auth notifier the driver-less listener was added to, held so it is
  /// removed from that same notifier even after the guard was rebound.
  ValueNotifier<int>? _authState;

  /// Stops the `AuthLogout` listener [watch] installs.
  void Function()? _stopForgettingOnLogout;

  /// Whether this app names both endpoints.
  ///
  /// Both or neither: a device reported with no release path configured could
  /// never be withdrawn at sign-out, and would keep vouching for whoever
  /// signed out of it last. [watch] logs an app that names only one.
  ///
  /// A starter kit asks this before calling [release] from its sign-out path,
  /// so an app without the backend half pays nothing on the way out.
  bool get isConfigured => _reportPath != null && _releasePath != null;

  /// Starts keeping the backend's picture of this device current.
  ///
  /// Follows three signals, and each covers a case the others cannot:
  ///
  /// 1. `NotificationManager.onPushIdentityReconciled`. The report describes
  ///    the device AS THE SIGNED-IN PERSON, and the pass is what makes that
  ///    true, so the report rides the pass rather than the declaration. A pass
  ///    that threw or read back a mismatch still reports, so the server hears
  ///    the device's real state. Only a pass towards `<prefix><Auth.id()>`
  ///    reports: a sign-out pass carries no intent, and a pass for another
  ///    subject would be refused by a server that checks the alias against
  ///    the session.
  /// 2. The attached driver's permission and identity streams, attached from
  ///    `NotificationManager.onPushDriverAttached` because the driver is
  ///    normally resolved after the auth provider restored a session.
  /// 3. `Auth.stateNotifier`, for a build with no driver at all. No pass is
  ///    emitted for a driver-less reconcile, so without this such a device
  ///    would report nothing for the whole session. It posts `unavailable`
  ///    rather than withholding: withholding leaves whatever the server held,
  ///    and on a device that lost its driver that is a stale `on` promising a
  ///    page nobody receives.
  ///
  /// Also forgets the memo on every `AuthLogout`. Idempotent: a second call
  /// replaces the first watch rather than doubling it. Call it once auth is
  /// registered, from a provider's `boot()`.
  void watch() {
    _stopWatching();
    if (!isConfigured) {
      if (_reportPath != null || _releasePath != null) {
        NotificationLog.error(
          'Push state reporting stays off: set both '
          'notifications.push_state.report_path and '
          'notifications.push_state.release_path, or neither',
        );
      }

      return;
    }

    _reconciledPasses = _manager.onPushIdentityReconciled.listen(
      _reportIfReconciledForCurrentUser,
    );
    _driverArrivals = _manager.onPushDriverAttached.listen(
      (PushDriver _) => _watchDriverChanges(),
    );
    _stopForgettingOnLogout = Event.listenAny(_forgetOnLogout);

    final ValueNotifier<int> authState = Auth.stateNotifier;
    authState.addListener(_reportWhenDriverless);
    _authState = authState;

    // The attach signal does not replay, so a driver already resolved when
    // this is armed is read here. It runs before the driver-less check so an
    // existing driver is seen before that check decides there is none.
    _watchDriverChanges();
    _reportWhenDriverless();
  }

  /// Tells the backend to stop counting this device as reaching the person
  /// signing out of it.
  ///
  /// Has to run BEFORE `Auth.logout()`: that call drops the bearer token, and
  /// a release posted after it is a guaranteed 401. Awaiting it costs the
  /// person one request on the way out.
  ///
  /// Names one device, by its subscription id, and not every row the person
  /// owns: an operator signing out of a browser tab still carries the phone
  /// that pages them. The live read is preferred and the last accepted
  /// report's subscription id is the fallback, so a driver that stopped
  /// answering still releases the row it created. With neither there is
  /// nothing to release.
  ///
  /// Safe to call twice: a caller arriving mid-flight joins the release in
  /// the air, and a subscription this session already released is not posted
  /// again until a new report is accepted for it.
  ///
  /// A refused or failed release is logged and the sign-out proceeds; the
  /// memo is left as it was, because the server still holds the old row.
  Future<void> release() {
    final Future<void>? inFlight = _releaseInFlight;
    if (inFlight != null) return inFlight;

    final Future<void> attempt = _release();
    _releaseInFlight = attempt;

    return attempt.whenComplete(() {
      if (identical(_releaseInFlight, attempt)) _releaseInFlight = null;
    });
  }

  /// Forgets what the server was last told for this session.
  ///
  /// Runs on every `AuthLogout` once [watch] is armed. The reported
  /// subscription id stays: it names this device's own row.
  void forget() {
    _lastReportedState = null;
    _releasedSubscriptionId = null;
  }

  /// Leaves the reporter as a fresh process would find it: nothing watched,
  /// nothing remembered.
  ///
  /// The test-isolation seam, run from `NotificationManager.forgetDrivers`.
  /// The manager is a `static final` singleton that outlives a container
  /// reset, so a subscription left on its streams would turn the next test's
  /// reconcile into a report nothing there asked for.
  void reset() {
    _stopWatching();
    _stopWatchingDriver();

    _watchedDriver = null;
    _lastReportedState = null;
    _reportedSubscriptionId = null;
    _releasedSubscriptionId = null;
    _releaseInFlight = null;
  }

  /// The configured report endpoint, or `null` when the app names none.
  String? get _reportPath => _configuredPath(reportPathKey);

  /// The configured release endpoint, or `null` when the app names none.
  String? get _releasePath => _configuredPath(releasePathKey);

  /// Reads [key], answering `null` for an absent or blank value.
  String? _configuredPath(String key) {
    final String? path = Config.get<String>(key)?.trim();
    if (path == null || path.isEmpty) return null;

    return path;
  }

  /// The external id the signed-in person is subscribed as, or `null` for a
  /// session whose user has not resolved yet.
  String? _currentExternalId() {
    final String userId = '${Auth.id() ?? ''}';
    if (userId.isEmpty) return null;

    final String? configured = Config.get<String>(externalIdPrefixKey)?.trim();
    final String prefix = configured == null || configured.isEmpty
        ? _defaultExternalIdPrefix
        : configured;

    return '$prefix$userId';
  }

  /// Posts the device's state when it differs from what the server accepted.
  ///
  /// The memo advances only on an accepted report. A refused post left
  /// nothing behind, so remembering it would silence this device until its
  /// state changed again, which for a device that is off is never. A refusal
  /// is logged rather than surfaced: nothing the person can do about it.
  Future<void> _report() async {
    final String? path = _reportPath;
    if (path == null) return;

    // The endpoint sits behind the session, so a signed-out report is a
    // guaranteed 401.
    if (!Auth.check()) return;

    try {
      final PushDeliverySnapshot snapshot =
          await _manager.pushDeliverySnapshot();
      final String state = '${snapshot.reachability.name}'
          '|${snapshot.externalId ?? ''}'
          '|${snapshot.subscriptionId ?? ''}';

      if (state == _lastReportedState) return;

      final MagicResponse response = await Http.post(
        path,
        data: snapshot.toMap(),
      );

      if (!response.successful) {
        NotificationLog.error(
          'Push delivery report refused with ${response.statusCode}',
        );

        return;
      }

      _lastReportedState = state;
      _reportedSubscriptionId = snapshot.subscriptionId;
      _releasedSubscriptionId = null;
    } catch (error) {
      // Logged and left: the memo is untouched, so the next lifecycle event
      // reports again rather than this device going quiet.
      NotificationLog.error('Push delivery report failed: $error');
    }
  }

  /// One release attempt, with no single-flight of its own.
  Future<void> _release() async {
    // 1. Nowhere to send it, nobody to release, or no token to do it with.
    final String? path = _releasePath;
    if (path == null) return;
    if (!Auth.check()) return;

    try {
      // 2. Which device this is. The manager's read answers `unavailable` with
      //    no ids for a driver that throws rather than failing the sign-out.
      final PushDeliverySnapshot snapshot =
          await _manager.pushDeliverySnapshot();
      final String? subscriptionId =
          snapshot.subscriptionId ?? _reportedSubscriptionId;
      if (subscriptionId == null) return;
      if (subscriptionId == _releasedSubscriptionId) return;

      final MagicResponse response = await Http.post(
        path,
        data: <String, dynamic>{
          'subscription_id': subscriptionId,
        },
      );

      if (!response.successful) {
        NotificationLog.error(
          'Push device release refused with ${response.statusCode}',
        );

        return;
      }

      // 3. The server holds no row for this device any more, so neither half
      //    of the memo may claim it does: the next person reports from scratch.
      _lastReportedState = null;
      _reportedSubscriptionId = null;
      _releasedSubscriptionId = subscriptionId;
    } catch (error) {
      NotificationLog.error('Push device release failed: $error');
    }
  }

  /// Reports after [pass] when it reconciled towards the signed-in person.
  void _reportIfReconciledForCurrentUser(PushIdentityReconciled pass) {
    if (!Auth.check()) return;

    final String? expected = _currentExternalId();
    if (expected == null || pass.intent != expected) return;

    unawaited(_report());
  }

  /// Reports this device's reachability when it has no push driver at all.
  void _reportWhenDriverless() {
    if (!Auth.check()) return;
    if (_manager.pushDriverOrNull != null) return;

    unawaited(_report());
  }

  /// Forgets the memo when a session ends, on every sign-out path.
  void _forgetOnLogout(MagicEvent event) {
    if (event is AuthLogout) forget();
  }

  /// Watches the current driver's change streams, if it is not already
  /// watching that driver.
  ///
  /// Both subscriptions carry an `onError` because both streams carry errors
  /// (a failed platform-channel read is piped into the controller), and an
  /// unhandled one would reach the zone as an app error.
  void _watchDriverChanges() {
    final PushDriver? driver = _manager.pushDriverOrNull;
    if (driver == null || identical(driver, _watchedDriver)) return;

    _stopWatchingDriver();
    _watchedDriver = driver;

    _identityChanges = driver.onIdentityChanged.listen(
      (PushIdentityChange _) => unawaited(_report()),
      onError: (Object error) => NotificationLog.error(
        'Push identity stream failed: $error',
      ),
    );
    _permissionChanges = driver.onPermissionChanged.listen(
      (PushPermissionState _) => unawaited(_report()),
      onError: (Object error) => NotificationLog.error(
        'Push permission stream failed: $error',
      ),
    );
  }

  /// Drops the pass, driver-arrival, auth and logout listeners [watch] holds.
  void _stopWatching() {
    unawaited(_reconciledPasses?.cancel());
    unawaited(_driverArrivals?.cancel());
    _reconciledPasses = null;
    _driverArrivals = null;

    _authState?.removeListener(_reportWhenDriverless);
    _authState = null;

    _stopForgettingOnLogout?.call();
    _stopForgettingOnLogout = null;
  }

  /// Drops both driver change subscriptions, keeping the watched driver.
  void _stopWatchingDriver() {
    unawaited(_identityChanges?.cancel());
    unawaited(_permissionChanges?.cancel());
    _identityChanges = null;
    _permissionChanges = null;
  }
}
