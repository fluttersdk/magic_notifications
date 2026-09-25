import 'dart:async' show StreamSubscription, unawaited;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../drivers/push/push_driver.dart';
import '../../../facades/notify.dart';
import '../../../models/push_prompt_advice.dart';
import '../../../models/push_subscription.dart' show PushReachability;
import '../../../notification_manager.dart' show NotificationManager;
import '../../../support/notification_log.dart';
import 'push_prompt.recipe.dart';

/// **The push permission soft prompt.**
///
/// A single row explaining what push notifications buy the user and asking
/// for them BEFORE the platform's own one-shot prompt is spent. Presentational
/// on purpose: it renders the [reachability] and [action] it is handed and
/// reports the two decisions back, so its whole surface is reachable from a
/// widget test. [PushPromptHost] is the half that asks
/// `Notify.manager.pushPromptAdvice()` what this device's state actually is.
///
/// ### Why it takes an [action] as well as a [reachability]
///
/// Reachability alone cannot name a presentation. A `blocked` device on mobile
/// still has a route back (the SDK's `fallbackToSettings` lands a request on
/// the app's settings page), and a `blocked` browser has none, because no web
/// API opens the site settings panel from a page. That split is a property of
/// the PLATFORM, not of the reading, and the package answers it in
/// [PushPromptAction] rather than leaving each consumer to guess.
///
/// ### The four presentations
///
/// - **`unavailable`** ([PushPromptAction.none]): this build has no push driver
///   at all. One muted line.
/// - **`blocked`**: the OS prompt is spent. With
///   [PushPromptAction.openSettings] the row keeps a real control that opens
///   the platform setting; with [PushPromptAction.instructions] there is
///   nowhere to send a tap, so it says where the switch lives instead of
///   offering a control that silently does nothing.
/// - **`off`** ([PushPromptAction.request]): a real dialog will appear. Not yet
///   resolved ([declined] false) shows the soft prompt with an explicit
///   decline; a resolved ask ([declined] true) leaves the compact enable
///   control, because a declined soft prompt must never be a dead end.
/// - **`on`** ([PushPromptAction.none]): subscribed. One confirming line.
///
/// ### Example Usage:
///
/// ```dart
/// final advice = await Notify.manager.pushPromptAdvice();
///
/// PushPrompt(
///   reachability: advice.reachability,
///   action: advice.action,
///   onEnable: () => Notify.requestPushPermission(),
///   onDecline: () => myVault.recordDecline(),
/// )
/// ```
@immutable
class PushPrompt extends StatelessWidget {
  /// Identifies the instruction row a blocked device with no route back gets.
  ///
  /// Exported rather than private because "a platform that cannot open its own
  /// setting renders an instruction and NOT a control" is the assertion this
  /// component exists to hold, and a test should not have to match on copy to
  /// make it. It is deliberately absent from the [PushPromptAction.openSettings]
  /// arm, which is a control.
  static const ValueKey<String> blockedInstructionKey = ValueKey<String>(
    'push-prompt-blocked-instruction',
  );

  /// The glyph for the soft prompt and the compact enable row.
  static const IconData _askIcon = Icons.notifications_active_outlined;

  /// The glyph for the blocked row.
  static const IconData _blockedIcon = Icons.notifications_off_outlined;

  /// The glyph for the subscribed row.
  static const IconData _onIcon = Icons.check_circle_outline;

  /// Whether push can reach this device right now, as the platform reports it.
  final PushReachability reachability;

  /// What this row's control can actually accomplish here, as
  /// `Notify.manager.pushPromptAdvice()` resolved it.
  final PushPromptAction action;

  /// Whether the soft ask has already been resolved on this device.
  ///
  /// Only meaningful while [action] is [PushPromptAction.request]: it swaps the
  /// soft prompt for the compact enable control.
  final bool declined;

  /// Whether an enable request is in flight, driving the button's spinner.
  final bool busy;

  /// Invoked when the user asks for push. The caller owns the platform
  /// request; this widget never touches the SDK.
  final Future<void> Function()? onEnable;

  /// Invoked when the user declines the soft prompt.
  final VoidCallback? onDecline;

  /// Creates a [PushPrompt] for the given [reachability] and [action].
  const PushPrompt({
    super.key,
    required this.reachability,
    required this.action,
    this.declined = false,
    this.busy = false,
    this.onEnable,
    this.onDecline,
  });

  /// The recipe state axis value for the current presentation.
  ///
  /// Keyed on [reachability] rather than [action]: the tokens carry what the
  /// device's STATE is (a blocked device gets the warning tint whether or not
  /// this platform can route the tap back), while [action] decides what the
  /// body offers.
  String get _state => switch (reachability) {
        PushReachability.unavailable => kPushPromptStateUnavailable,
        PushReachability.blocked => kPushPromptStateBlocked,
        PushReachability.on => kPushPromptStateOn,
        PushReachability.off => kPushPromptStateAsk,
      };

  /// The glyph for the current presentation.
  IconData get _icon => switch (reachability) {
        PushReachability.unavailable => _blockedIcon,
        PushReachability.blocked => _blockedIcon,
        PushReachability.on => _onIcon,
        PushReachability.off => _askIcon,
      };

  /// Where the user has to go to unblock notifications.
  ///
  /// Three answers rather than one, because the setting lives somewhere
  /// different on each: a browser hides it behind the padlock in the address
  /// bar, iOS keeps it under Settings, Android under the app's own entry.
  String get _blockedInstruction {
    if (kIsWeb) return trans('notifications.push_prompt.blocked_body_web');

    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS ||
      TargetPlatform.macOS =>
        trans('notifications.push_prompt.blocked_body_ios'),
      _ => trans('notifications.push_prompt.blocked_body_android'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final String state = _state;

    return WDiv(
      className: pushPromptRecipe(
        variants: {kPushPromptStateAxis: state},
      ),
      children: [
        WDiv(
          className: pushPromptTileRecipe(
            variants: {kPushPromptStateAxis: state},
          ),
          child: WIcon(
            _icon,
            className: pushPromptIconRecipe(
              variants: {kPushPromptStateAxis: state},
            ),
          ),
        ),
        WDiv(
          className: 'min-w-0 flex-1 flex flex-col gap-2',
          children: _buildBody(),
        ),
      ],
    );
  }

  /// The message column for the current presentation.
  ///
  /// Driven by [action], because that is the only input that knows what a tap
  /// could accomplish. [reachability] appears once, to tell the two states with
  /// nothing to offer apart: a subscribed device and a build with no push.
  List<Widget> _buildBody() {
    return switch (action) {
      PushPromptAction.none when reachability == PushReachability.on => [
          _buildLine(trans('notifications.push_prompt.on_body')),
        ],
      PushPromptAction.none => [
          _buildLine(trans('notifications.push_prompt.unavailable_body')),
        ],
      // The OS prompt is spent, but this platform routes the same request to
      // the app's settings page, so the row is a control again.
      PushPromptAction.openSettings => [
          _buildTitle(trans('notifications.push_prompt.blocked_title')),
          _buildLine(trans('notifications.push_prompt.blocked_body_settings')),
          WDiv(
            className: pushPromptActionsClassName,
            children: [_buildEnable()],
          ),
        ],
      // Nowhere to send a tap. A control here would silently do nothing, so
      // the row says where the switch actually lives instead.
      PushPromptAction.instructions => [
          _buildTitle(trans('notifications.push_prompt.blocked_title')),
          WDiv(
            key: blockedInstructionKey,
            child: _buildLine(_blockedInstruction),
          ),
        ],
      PushPromptAction.request when declined => [
          _buildLine(trans('notifications.push_prompt.declined_body')),
          WDiv(
            className: pushPromptActionsClassName,
            children: [_buildEnable()],
          ),
        ],
      PushPromptAction.request => [
          _buildTitle(trans('notifications.push_prompt.ask_title')),
          _buildLine(trans('notifications.push_prompt.ask_body')),
          WDiv(
            className: pushPromptActionsClassName,
            children: [_buildEnable(), _buildDecline()],
          ),
        ],
    };
  }

  /// A heading line.
  Widget _buildTitle(String text) {
    return WText(text, className: 'text-sm font-semibold text-fg');
  }

  /// A body line.
  Widget _buildLine(String text) {
    return WText(text, className: 'text-sm leading-relaxed text-fg-muted');
  }

  /// The primary action, labelled for what the tap will actually do.
  ///
  /// One control and one callback for both arms, because the platform call is
  /// the same one: `requestPermission()` raises the dialog on a device that has
  /// never been asked, and opens the app's settings page on one that has. Only
  /// the promise made to the user changes, and promising "turn on push" where
  /// the tap opens Settings is the kind of small lie that costs the next tap.
  Widget _buildEnable() {
    final String label = action == PushPromptAction.openSettings
        ? trans('notifications.push_prompt.open_settings')
        : trans('notifications.push_prompt.enable');

    return WButton(
      key: const ValueKey<String>('push-prompt-enable'),
      onTap: busy ? null : onEnable,
      isLoading: busy,
      loadingSize: 14,
      className: pushPromptEnableButtonClassName,
      child: WText(label),
    );
  }

  /// The decline action, which resolves the soft ask WITHOUT touching the
  /// platform's one-shot prompt.
  Widget _buildDecline() {
    return WButton(
      key: const ValueKey<String>('push-prompt-decline'),
      onTap: busy ? null : onDecline,
      className: pushPromptDeclineButtonClassName,
      child: WText(trans('notifications.push_prompt.not_now')),
    );
  }
}

/// The reading both platform-wired widgets below fall back to when the
/// platform read throws: nothing known about this device, and nothing to
/// offer.
///
/// Deliberately the same answer a build with no push driver gets. A failed
/// read is not evidence that push works, and the two are indistinguishable
/// from here; what neither of them is, is a reason to raise an error out of a
/// lifecycle path.
const PushPromptAdvice _unreadableDevice = PushPromptAdvice(
  show: false,
  reachability: PushReachability.unavailable,
  action: PushPromptAction.none,
);

/// **The push prompt wired to the platform.**
///
/// Reads the one fact `NotificationManager.pushPromptAdvice` refuses to own,
/// the moment the user last turned the reminder down on THIS device, from
/// [declinedVaultKey], hands it to `Notify.manager.pushPromptAdvice()`, and
/// renders [PushPrompt] from the answer.
///
/// ### Why the host supplies the vault key and the package stores nothing
///
/// The POLICY (is a reminder due, and what can its control do) is the part
/// two consumers would each get wrong in their own way, so it lives in
/// `NotificationManager.pushPromptAdvice`. The decline is the HOST's own UI
/// event, and a second copy inside this package would be a second answer to
/// drift out of sync with the host's own. The two meet at
/// `pushPromptAdvice(declinedAt:)`.
///
/// The vault key itself is a host parameter for the same reason: a fixed key
/// here would collide with whatever else a host already stores, or force
/// every host onto one name. See [declinedVaultKey] for what this widget does
/// and does not do with whatever it reads back.
class PushPromptHost extends StatefulWidget {
  /// Creates a [PushPromptHost] reading its decline timestamp from
  /// [declinedVaultKey].
  const PushPromptHost({super.key, required this.declinedVaultKey});

  /// The [Vault] key recording WHEN the reminder was last turned down on this
  /// device.
  ///
  /// The value this widget WRITES is always an ISO-8601 instant in UTC; UTC
  /// rather than local wall-clock, because a wall-clock string parsed back in
  /// a different zone can name an instant most of a reprompt interval away
  /// from the one it recorded.
  ///
  /// This widget only ever READS an ISO-8601 timestamp: anything else stored
  /// under this key (absent, or a value some other shape wrote) is read as
  /// "never declined". It does not migrate an older value in place, unlike
  /// the value this key held before this widget existed on some apps; a host
  /// carrying such a value migrates it itself, once, before ever constructing
  /// this widget, because only the host knows what shape that value is in.
  final String declinedVaultKey;

  @override
  State<PushPromptHost> createState() => _PushPromptHostState();
}

class _PushPromptHostState extends State<PushPromptHost> {
  /// The package's answer, or null while the first read is in flight.
  PushPromptAdvice? _advice;

  /// When the reminder was last turned down on this device, or null.
  DateTime? _declinedAt;

  /// Rises by one every time [_read], [_decline], or [_enable] starts a new
  /// pass through [_apply].
  ///
  /// A permission or identity event can fire [_read] while an earlier
  /// [_read] (or [_decline]) is still waiting on the platform, and the two
  /// can then land in either order. Without a generation to compare against,
  /// whichever finishes LAST wins the screen even when it started first, so a
  /// decline that already landed can be undone by a read that was already
  /// stale the moment it started. [_apply] drops any call whose generation is
  /// no longer the latest one issued, rather than trusting arrival order.
  int _generation = 0;

  /// Whether the platform prompt has already been raised in THIS session.
  ///
  /// Not persisted, and separate from [_declinedAt] because it answers a
  /// different question: a granted request whose subscription has not arrived
  /// yet still reads as `off`, and asking again in the same breath is noise.
  /// Both collapse into the compact enable row.
  bool _asked = false;

  /// Whether an enable request is in flight.
  bool _busy = false;

  /// The driver reports this widget listens to while it is mounted.
  ///
  /// The same pair, and for the same reason, as [PushOffNotice]: either stream
  /// can end the state this prompt is about. It matters MORE here, because
  /// this is the surface a user is sent to in order to fix push, and the fix
  /// almost always lands out of band. `requestPermission` on an
  /// already-denied device opens the platform settings page rather than a
  /// dialog, so the grant arrives while this widget is backgrounded and
  /// unchanged; and a granted request whose subscription has not landed yet
  /// reads as `off` until the identity stream carries it (see [_asked]).
  /// Without these two, the one screen that exists to turn push on is the
  /// only one that never notices push was turned on.
  final List<StreamSubscription<Object?>> _watching =
      <StreamSubscription<Object?>>[];

  /// The driver [_watching] currently follows, or null while none has been
  /// found yet.
  ///
  /// Tracked so a later attachment can tell "no driver yet" apart from
  /// "already following this one" and, on a replacement, cancel the old pair
  /// before wiring the new one rather than leaking a subscription to a
  /// driver nobody uses any more.
  PushDriver? _watchedDriver;

  /// Follows [NotificationManager.onPushDriverAttached], for a driver that
  /// resolves after this widget is already mounted.
  ///
  /// A build with no factory registered at `initState` finds no driver in
  /// [_watch] and stops there for good without this: `pushDriverOrNull`
  /// resolves and attaches lazily, on whichever call happens to read it
  /// first, and that call is not necessarily this widget's own. Without
  /// following the attachment announcement, this host would read
  /// `unavailable` forever once the driver becomes available in the same
  /// session, since nothing else prompts a re-read.
  StreamSubscription<PushDriver>? _driverAttachedSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _watch();
    _driverAttachedSubscription = Notify.manager.onPushDriverAttached.listen(
      _onDriverAttached,
      onError: (Object error) => NotificationLog.error(
        '[PushPromptHost] driver-attached stream failed: $error',
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_driverAttachedSubscription?.cancel());
    _driverAttachedSubscription = null;
    _cancelDriverWatchers();
    super.dispose();
  }

  /// Follows everything the driver reports about this device's state.
  ///
  /// Re-reads through [_read] rather than [_apply] so the stored decline is
  /// re-fetched too: a grant arriving after a decline has to clear the compact
  /// row, not re-render it against a stale timestamp.
  void _watch() {
    final PushDriver? driver = Notify.manager.pushDriverOrNull;
    if (driver == null) return;

    _watchDriver(driver);
  }

  /// Reacts to a driver resolving or being replaced after this widget already
  /// mounted: re-reads the advice, then follows [driver]'s own streams.
  void _onDriverAttached(PushDriver driver) {
    _watchDriver(driver);
    unawaited(_read());
  }

  /// Wires [_watching] to [driver], first cancelling any subscription to a
  /// previous one.
  ///
  /// Keyed on identity rather than unconditionally replacing: an attachment
  /// announcement is not necessarily a NEW driver (see [_onDriverAttached]),
  /// and re-subscribing to the one already followed would only cost a frame
  /// of duplicate listeners.
  void _watchDriver(PushDriver driver) {
    if (identical(_watchedDriver, driver)) return;

    _cancelDriverWatchers();
    _watchedDriver = driver;

    _watching.add(
      driver.onPermissionChanged.listen(
        (_) => unawaited(_read()),
        onError: (Object error) => NotificationLog.error(
          '[PushPromptHost] permission stream failed: $error',
        ),
      ),
    );
    _watching.add(
      driver.onIdentityChanged.listen(
        (_) => unawaited(_read()),
        onError: (Object error) => NotificationLog.error(
          '[PushPromptHost] identity stream failed: $error',
        ),
      ),
    );
  }

  /// Cancels every subscription in [_watching] and forgets [_watchedDriver].
  void _cancelDriverWatchers() {
    for (final StreamSubscription<Object?> subscription in _watching) {
      unawaited(subscription.cancel());
    }
    _watching.clear();
    _watchedDriver = null;
  }

  /// Reads the decline this device carries, then what the package makes of it.
  Future<void> _read() async {
    final int generation = ++_generation;
    await _apply(generation, await _readDeclinedAt());
  }

  /// Re-derives the advice for [declinedAt] and puts both on screen, unless
  /// [generation] has already been overtaken by a newer [_read], [_decline],
  /// or [_enable].
  ///
  /// The one place this widget's state moves, so the timestamp it asked with
  /// and the answer it got can never be a frame apart. The generation check
  /// is what keeps a call that started earlier but answers later from
  /// clobbering one that started after it and already landed; see
  /// [_generation].
  Future<void> _apply(int generation, DateTime? declinedAt) async {
    final PushPromptAdvice advice = await _readAdvice(declinedAt);

    if (!mounted || generation != _generation) return;

    setState(() {
      _declinedAt = declinedAt;
      _advice = advice;
    });
  }

  /// Asks the package what to do, answering "nothing to offer" when the
  /// platform read throws.
  ///
  /// `pushPromptAdvice` reaches `permissionState()` through `reachability()`,
  /// a platform-channel call that can throw, and it does not guard that read
  /// itself the way `pushDeliverySnapshot()` does. Left unhandled the throw
  /// escapes as an unhandled async error and [_advice] stays null, which
  /// renders nothing at all rather than a state the user can act on.
  Future<PushPromptAdvice> _readAdvice(DateTime? declinedAt) async {
    try {
      return await Notify.manager.pushPromptAdvice(declinedAt: declinedAt);
    } catch (error) {
      NotificationLog.warning(
        '[PushPromptHost] push prompt advice failed: $error',
      );

      return _unreadableDevice;
    }
  }

  /// Reads the persisted decline timestamp.
  ///
  /// Anything that is not a valid ISO-8601 instant (nothing stored, or a
  /// value written in some other shape) reads as "never declined" rather
  /// than being repaired here: see [PushPromptHost.declinedVaultKey] for why
  /// that migration is the host's to make, once, before this widget exists.
  ///
  /// A vault failure answers null too, because a broken read must not take the
  /// preference screen down and the safe default is to ask: the reminder is a
  /// question, not an action.
  Future<DateTime?> _readDeclinedAt() async {
    final String? stored = await _readVault();
    if (stored == null) return null;

    return DateTime.tryParse(stored);
  }

  /// The raw stored value, or null when there is none or the vault is
  /// unreachable.
  Future<String?> _readVault() async {
    try {
      return await Vault.get(widget.declinedVaultKey);
    } catch (error) {
      NotificationLog.warning('[PushPromptHost] vault read failed: $error');

      return null;
    }
  }

  /// Writes [at] to this device, answering whether it landed.
  Future<bool> _persistDeclinedAt(DateTime at) async {
    try {
      await Vault.put(
        widget.declinedVaultKey,
        at.toUtc().toIso8601String(),
      );

      return true;
    } catch (error) {
      NotificationLog.warning('[PushPromptHost] vault write failed: $error');

      return false;
    }
  }

  /// Records the decline on this device, then re-reads the advice.
  ///
  /// The write comes FIRST and the row only changes when it landed. A decline
  /// that failed to persist will not survive the next launch, so reporting it
  /// as resolved would leave the user looking at a row that says their answer
  /// was taken when it was not; the reminder (decline control and all) stays
  /// on screen instead.
  ///
  /// The generation is taken AFTER the write lands, not before: a read that
  /// starts while the write is still running reads the vault before the
  /// decline is in it, so it is the stale one and has to lose. A failed write
  /// takes no generation, so it drops no read that is still in flight.
  Future<void> _decline() async {
    final DateTime at = DateTime.now().toUtc();
    if (!await _persistDeclinedAt(at)) return;

    await _apply(++_generation, at);
  }

  /// Raises the platform request, then re-reads what the platform now says.
  ///
  /// One handler for both live actions, because both are the same call: on a
  /// device that has never been asked it raises the dialog, and on a denied
  /// one the driver's `fallbackToSettings` turns it into the app's settings
  /// page.
  ///
  /// The request is guarded the same way the vault reads are: a throw is
  /// logged rather than left to escape as an unhandled async error, and
  /// control still falls through to [_apply] afterward so the row never gets
  /// stuck on the spinner with a stale reading. The re-read keeps the decline
  /// this device already carries rather than going back to the vault for it.
  Future<void> _enable() async {
    if (_busy) return;
    if (Notify.manager.pushDriverOrNull == null) return;

    setState(() {
      _busy = true;
      _asked = true;
    });

    try {
      await Notify.requestPushPermission();
    } catch (error) {
      NotificationLog.warning(
        '[PushPromptHost] push permission request failed: $error',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    await _apply(++_generation, _declinedAt);
  }

  /// Whether the host app has left the reminder turned on at all.
  ///
  /// Read here as well as inside `pushPromptAdvice`, and the duplication is
  /// deliberate: `pushPromptAdvice` folds this switch into `advice.show`, but
  /// a false `show` cannot say WHICH of the two reasons produced it, and the
  /// two render differently. "Not due yet" still owes the user a status line
  /// on a screen they opened on purpose; "switched off" owes them nothing at
  /// all.
  bool get _softPromptEnabled =>
      Config.get<bool>(NotificationManager.softPromptEnabledKey) ?? true;

  @override
  Widget build(BuildContext context) {
    if (!_softPromptEnabled) return const SizedBox.shrink();

    final PushPromptAdvice? advice = _advice;

    // Nothing is known yet. One frame, and only ever the first: every other
    // state below renders a row, so this cannot become a permanently empty
    // child costing a gap slot in a flex column that expects one.
    if (advice == null) return const SizedBox.shrink();

    return PushPrompt(
      reachability: advice.reachability,
      action: advice.action,
      // `show` is the package's answer to "may I interrupt", and a screen the
      // user opened deliberately still states the device's status when the
      // answer is no. That is exactly the compact row: no title, no decline,
      // and the way back left in place.
      declined: !advice.show || _asked,
      busy: _busy,
      onEnable: _enable,
      onDecline: _decline,
    );
  }
}

/// **A quiet, tappable marker that this device cannot be reached by push.**
///
/// A glyph and one line for a sidebar row, the glyph alone for a compact top
/// bar. Tapping it calls [onOpenPreferences], which a host wires to wherever
/// [PushPromptHost] and its controls actually live.
///
/// ### Why it exists at all, and why it is not louder
///
/// The soft prompt lives on a settings screen most people open rarely, so on
/// the surfaces they DO look at, a device that cannot be reached is
/// indistinguishable from one that can. It is still not an alarm: it carries
/// no colour beyond the glyph, and never blocks anything, which is also why
/// the reminder's own cadence lives in
/// `NotificationManager.repromptAfterHoursKey` rather than here.
///
/// ### When it says nothing
///
/// Exactly when there is nothing to do about it, which is
/// [PushPromptAction.none]: a device that is already subscribed, and a build
/// with no push driver at all (a platform the SDK does not cover, and a
/// platform read that failed). A permanent marker nobody can resolve is the
/// fastest way to train people to ignore the one that matters.
///
/// ### Example Usage:
///
/// ```dart
/// PushOffNotice(onOpenPreferences: () => MagicRoute.to('/settings/notifications'))
/// PushOffNotice(compact: true, onOpenPreferences: () => MagicRoute.to('/settings/notifications'))
/// ```
class PushOffNotice extends StatefulWidget {
  /// Creates the shell notice.
  const PushOffNotice({
    super.key,
    required this.onOpenPreferences,
    this.compact = false,
  });

  /// Called when the marker is tapped.
  ///
  /// A required callback rather than a route this package navigates to
  /// itself: this package does not know where a host mounts its preference
  /// screen, and routing through a fixed path here would make this widget
  /// depend on whatever starter kit or router convention a host happens to
  /// use. The caller owns the navigation, the same way [PushPrompt]'s
  /// [PushPrompt.onEnable] leaves the platform call to its caller.
  final VoidCallback onOpenPreferences;

  /// Whether to render the glyph alone, for a bar with no room for a label.
  final bool compact;

  @override
  State<PushOffNotice> createState() => _PushOffNoticeState();
}

class _PushOffNoticeState extends State<PushOffNotice> {
  /// The glyph. Extracted rather than written inline so the icon tree-shakes.
  static const IconData _icon = Icons.notifications_off_outlined;

  /// What the package makes of this device, or null while the first read is in
  /// flight.
  PushPromptAdvice? _advice;

  /// The driver reports this widget listens to while it is mounted.
  ///
  /// Both of them, because either can end the state this marker is about: the
  /// permission stream carries a grant, and the identity stream carries the
  /// subscription landing afterwards, which is the half that turns an `off`
  /// device into an `on` one. Without them a persistent shell keeps claiming
  /// push is off for as long as this widget stays mounted, which can be the
  /// whole session.
  final List<StreamSubscription<Object?>> _watching =
      <StreamSubscription<Object?>>[];

  /// The driver [_watching] currently follows, or null while none has been
  /// found yet. See [_PushPromptHostState._watchedDriver] for why this is
  /// tracked rather than re-subscribed unconditionally.
  PushDriver? _watchedDriver;

  /// Follows [NotificationManager.onPushDriverAttached], for a driver that
  /// resolves after this widget is already mounted. See
  /// [_PushPromptHostState._driverAttachedSubscription] for why a build with
  /// no factory registered at `initState` needs this to ever notice one.
  StreamSubscription<PushDriver>? _driverAttachedSubscription;

  @override
  void initState() {
    super.initState();
    unawaited(_read());
    _watch();
    _driverAttachedSubscription = Notify.manager.onPushDriverAttached.listen(
      _onDriverAttached,
      onError: (Object error) => NotificationLog.error(
        '[PushOffNotice] driver-attached stream failed: $error',
      ),
    );
  }

  @override
  void dispose() {
    unawaited(_driverAttachedSubscription?.cancel());
    _driverAttachedSubscription = null;
    _cancelDriverWatchers();
    super.dispose();
  }

  /// Follows everything the driver reports about this device's state.
  void _watch() {
    final PushDriver? driver = Notify.manager.pushDriverOrNull;
    if (driver == null) return;

    _watchDriver(driver);
  }

  /// Reacts to a driver resolving or being replaced after this widget already
  /// mounted: re-reads the advice, then follows [driver]'s own streams.
  void _onDriverAttached(PushDriver driver) {
    _watchDriver(driver);
    unawaited(_read());
  }

  /// Wires [_watching] to [driver], first cancelling any subscription to a
  /// previous one. See [_PushPromptHostState._watchDriver] for why this is
  /// keyed on identity rather than unconditional.
  void _watchDriver(PushDriver driver) {
    if (identical(_watchedDriver, driver)) return;

    _cancelDriverWatchers();
    _watchedDriver = driver;

    // Both carry an `onError`: the driver pipes a failed platform read into
    // these streams instead of swallowing it, and a subscription without a
    // handler would hand that to the zone as an unhandled async error.
    _watching.add(
      driver.onPermissionChanged.listen(
        (_) => unawaited(_read()),
        onError: (Object error) => NotificationLog.error(
          '[PushOffNotice] permission stream failed: $error',
        ),
      ),
    );
    _watching.add(
      driver.onIdentityChanged.listen(
        (_) => unawaited(_read()),
        onError: (Object error) => NotificationLog.error(
          '[PushOffNotice] identity stream failed: $error',
        ),
      ),
    );
  }

  /// Cancels every subscription in [_watching] and forgets [_watchedDriver].
  void _cancelDriverWatchers() {
    for (final StreamSubscription<Object?> subscription in _watching) {
      unawaited(subscription.cancel());
    }
    _watching.clear();
    _watchedDriver = null;
  }

  /// Asks the package where this device stands.
  ///
  /// No decline timestamp is passed, and that is deliberate: `declinedAt`
  /// only moves `advice.show`, which is the answer to "may I interrupt". This
  /// marker never interrupts, so it reads [PushPromptAdvice.action] instead,
  /// and a device stays marked whether or not the user turned the reminder
  /// down.
  ///
  /// A platform read that throws answers "nothing to offer" rather than
  /// raising on a lifecycle path. That hides the marker, which is the quieter
  /// of the two wrong answers and matches the no-driver case it cannot be
  /// told apart from: the preferences screen still states the device's
  /// status honestly.
  Future<void> _read() async {
    PushPromptAdvice advice;

    try {
      advice = await Notify.manager.pushPromptAdvice();
    } catch (error) {
      NotificationLog.warning(
        '[PushOffNotice] push prompt advice failed: $error',
      );

      advice = _unreadableDevice;
    }

    if (!mounted) return;

    setState(() => _advice = advice);
  }

  @override
  Widget build(BuildContext context) {
    final PushPromptAdvice? advice = _advice;
    if (advice == null || advice.action == PushPromptAction.none) {
      return const SizedBox.shrink();
    }

    final String label = trans('notifications.push_prompt.shell_notice');

    // Named for assistive technology on both forms, not just the compact one:
    // the row's own label would otherwise be read as loose text with an
    // unnamed tap target beside it.
    return MergeSemantics(
      child: Semantics(
        label: trans('notifications.push_prompt.shell_notice_a11y'),
        button: true,
        child: WAnchor(
          onTap: widget.onOpenPreferences,
          child: WDiv(
            className: pushOffNoticeRecipe(
              variants: {
                kPushOffNoticeDensityAxis: widget.compact
                    ? kPushOffNoticeDensityCompact
                    : kPushOffNoticeDensityFull,
              },
            ),
            children: [
              WIcon(_icon, className: pushOffNoticeIconClassName),
              if (!widget.compact)
                Expanded(
                  child: WText(label, className: pushOffNoticeLabelClassName),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
