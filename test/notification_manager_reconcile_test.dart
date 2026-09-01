import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import 'test_helper.dart';

/// A push driver that records the ORDER of the calls it was asked to make.
///
/// A boolean ("did it log in?") passes on a login issued for the wrong person,
/// which is the exact defect this file covers, so every assertion here reads the
/// call list instead.
class _RecordingPushDriver extends PushDriver {
  _RecordingPushDriver({
    String? subscribedAs,
    this.failLogout = false,
    this.failRead = false,
    this.permission = PushPermissionState.authorized,
    this.optedIn = true,
    this.subscriptionId = 'sub-1',
    this.canOpenPlatformSettings = false,
  }) : _externalId = subscribedAs;

  /// Every driver call in the order it was made, logins carrying their subject.
  final List<String> calls = <String>[];

  /// The permission the platform reports, which is what drives reachability.
  final PushPermissionState permission;

  /// Whether the device is opted in, the second half of reachability.
  final bool optedIn;

  /// The subscription id the device holds, or null for a device with none.
  final String? subscriptionId;

  /// Whether a request on a DENIED device can still route to the platform
  /// setting, which is the mobile `fallbackToSettings` capability.
  @override
  final bool canOpenPlatformSettings;

  /// How many times the platform permission request was raised.
  int permissionRequests = 0;

  /// Whether [logout] throws, standing in for a sign-out with no network.
  final bool failLogout;

  /// Whether [currentExternalId] throws, standing in for an SDK that is not
  /// initialised behind a platform channel.
  final bool failRead;

  /// The external id the device currently reports, mutated the way the SDK
  /// mutates its local user: immediately, before any server round trip.
  String? _externalId;

  /// Who this device is subscribed as right now.
  ///
  /// The outcome an identity race is judged on: a call list says which calls
  /// were made, this says which person the device was left carrying.
  String? get subscribedAs => _externalId;

  /// When set, the NEXT [currentExternalId] parks on it after reading the
  /// device, so a test can hold one reconcile pass open across the platform
  /// channel and drive a second caller into the window.
  Completer<void>? readGate;

  final StreamController<PushNotificationEvent> received =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> clicked =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushIdentityChange> identity =
      StreamController<PushIdentityChange>.broadcast();

  /// The tags this device carries right now, as the SDK's local user holds
  /// them: a write merges, a removal drops one key.
  final Map<String, String> tags = <String, String>{};

  /// The email subscriptions attached to the identity this device carries.
  ///
  /// A set rather than a single value, because both OneSignal SDKs ADD an
  /// email subscription: a user owns zero or more, and an address that is
  /// never removed simply stays.
  final Set<String> emails = <String>{};

  /// The calls that CHANGE the device's identity, which is what a reconcile is
  /// judged on.
  ///
  /// Named rather than subtracted: a read-back, a permission request and an
  /// attribute write are all calls this driver records and none of them moves
  /// the device from one person to another, so the list says which calls
  /// count instead of growing an exclusion every time a new one is recorded.
  List<String> get identityCalls => calls
      .where((String call) =>
          call == 'initialize' || call == 'logout' || call.startsWith('login:'))
      .toList();

  /// Every call but the read-back, in the order it was made.
  ///
  /// The ORDER is the assertion the attribute tests turn on: a removal issued
  /// after the identity call runs against the person who has just arrived, not
  /// against the one who left.
  List<String> get orderedCalls =>
      calls.where((String call) => call != 'currentExternalId').toList();

  @override
  String get name => 'recording';

  @override
  bool get isSupported => true;

  @override
  Future<PushPermissionState> permissionState() async => permission;

  @override
  bool get isOptedIn => optedIn;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    calls.add('initialize');
  }

  @override
  Future<void> login(String externalId) async {
    calls.add('login:$externalId');
    _externalId = externalId;
  }

  @override
  Future<void> logout() async {
    calls.add('logout');
    if (failLogout) throw StateError('no network');
    _externalId = null;
  }

  @override
  Future<String?> currentExternalId() async {
    calls.add('currentExternalId');
    if (failRead) throw StateError('the SDK is not initialized');

    // The answer is what the device reported when it was ASKED, so a held read
    // reports the pre-call state the way a slow platform channel does.
    final String? reported = _externalId;

    final Completer<void>? gate = readGate;
    if (gate != null) {
      readGate = null;
      await gate.future;
    }

    return reported;
  }

  @override
  Future<String?> currentSubscriptionId() async => subscriptionId;

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    permissionRequests++;

    return permission == PushPermissionState.notDetermined;
  }

  @override
  Future<void> optIn() async {}

  @override
  Future<void> optOut() async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {
    calls.add('setTags:${tags.keys.join(',')}');
    this.tags.addAll(tags);
  }

  /// [PushDriver.removeTags] is deliberately NOT overridden here, so the base
  /// class's own loop over this method is what the manager's clear path
  /// actually runs; a driver whose SDK batches removals overrides it, and the
  /// two have to reach the same device state.
  @override
  Future<void> removeTag(String key) async {
    calls.add('removeTag:$key');
    tags.remove(key);
  }

  @override
  Future<void> addEmail(String email) async {
    calls.add('addEmail:$email');
    emails.add(email);
  }

  @override
  Future<void> removeEmail(String email) async {
    calls.add('removeEmail:$email');
    emails.remove(email);
  }

  @override
  Stream<PushNotificationEvent> get onNotificationReceived => received.stream;

  @override
  Stream<PushNotificationEvent> get onNotificationClicked => clicked.stream;

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      const Stream<PushPermissionState>.empty();

  @override
  Stream<PushIdentityChange> get onIdentityChanged => identity.stream;

  /// Closes the three controllers a test opened.
  void dispose() {
    received.close();
    clicked.close();
    identity.close();
  }
}

/// A vault whose reads finish when the TEST says so.
///
/// The shipped [FakeVaultService] answers within a microtask, which cannot
/// express a second caller arriving while the first one's read is still
/// suspended. That interleaving is the whole defect these tests cover, so the
/// read has to be holdable.
class _GatedVaultService extends FakeVaultService {
  _GatedVaultService([super.initialValues]);

  /// When set, the NEXT [get] parks on it before answering.
  Completer<void>? readGate;

  @override
  Future<String?> get(String key) async {
    final Completer<void>? gate = readGate;
    if (gate != null) {
      readGate = null;
      await gate.future;
    }

    return super.get(key);
  }
}

void main() {
  late NotificationManager manager;

  setUpAll(() async {
    await initMagicForTests();
  });

  setUp(() {
    manager = NotificationManager();
    manager.forgetDrivers();
    Http.fake(<String, MagicResponse>{
      'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
    });
  });

  tearDown(() {
    manager.forgetDrivers();
  });

  /// Registers [driver] the way a consumer registers one, through the registry
  /// and with no provider booted, which is the seam Step 6 exists to open.
  _RecordingPushDriver use(_RecordingPushDriver driver) {
    Notify.extend(driver.name, () => driver);
    addTearDown(Notify.forgetDrivers);
    addTearDown(driver.dispose);

    return driver;
  }

  group('push identity reconciliation', () {
    test('an intent the device already carries issues no SDK call', () async {
      final _RecordingPushDriver driver = use(_RecordingPushDriver());

      await manager.want('user_A');
      await manager.reconcilePushIdentity();
      await manager.want('user_A');
      await manager.reconcilePushIdentity();

      // One login for two reconciles: the second read the device back, saw the
      // subject it wanted and asked the SDK for nothing. This is what makes a
      // team switch free, because the id belongs to the person, not the team.
      expect(driver.identityCalls, <String>['login:user_A']);
      expect(manager.pushIntent, 'user_A');
      expect(manager.isPushIdentityConverged, isTrue);
    });

    test('a sign-out that lands reports converged', () async {
      use(_RecordingPushDriver(subscribedAs: 'user_A'));

      await manager.want(null);
      await manager.reconcilePushIdentity();

      // The positive twin of the test below: without it, "not converged" after a
      // FAILED sign-out would pass on an implementation that never converges.
      expect(manager.isPushIdentityConverged, isTrue);
      expect(manager.pushIdentityError, isNull);
    });

    test('a failed sign-out leaves the intent null and un-converged', () async {
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(subscribedAs: 'user_A', failLogout: true),
      );

      await manager.want(null);
      await manager.reconcilePushIdentity();

      expect(driver.identityCalls, <String>['logout']);
      expect(manager.pushIntent, isNull);
      expect(manager.isPushIdentityConverged, isFalse);
      expect(manager.pushIdentityError, isNotNull);

      // The next person on this device still gets their login issued: the
      // failure is recorded, not remembered as a reason to stop trying.
      await manager.want('user_B');
      await manager.reconcilePushIdentity();

      expect(driver.identityCalls, <String>['logout', 'login:user_B']);
    });

    test('the SDK observer confirms convergence, a stale id revokes it',
        () async {
      final _RecordingPushDriver driver = use(_RecordingPushDriver());

      await manager.want('user_B');
      await manager.reconcilePushIdentity();
      expect(manager.isPushIdentityConverged, isTrue);

      driver.identity.add(const PushIdentityChange(externalId: 'user_A'));
      await pumpEventQueue();

      expect(manager.isPushIdentityConverged, isFalse);

      driver.identity.add(const PushIdentityChange(externalId: 'user_B'));
      await pumpEventQueue();

      expect(manager.isPushIdentityConverged, isTrue);
    });

    test('an event reporting no external id says nothing either way', () async {
      final _RecordingPushDriver driver = use(_RecordingPushDriver());

      await manager.want('user_B');
      await manager.reconcilePushIdentity();

      // A subscription-change event carries only the subscription half, so a
      // null external id is "not reported", never "the device carries none".
      driver.identity.add(const PushIdentityChange(subscriptionId: 'sub-2'));
      await pumpEventQueue();

      expect(manager.isPushIdentityConverged, isTrue);
    });

    test('the intent is persisted and reloaded on a cold boot', () async {
      final FakeVaultService vault = Vault.fake();
      addTearDown(Vault.unfake);

      await manager.want('user_A');
      vault.assertWritten(NotificationManager.pushIntentKey);

      // A fresh process: nothing in memory, everything in the vault.
      manager.forgetDrivers();
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      await manager.reconcilePushIdentity();

      expect(manager.pushIntent, 'user_A');
      expect(driver.identityCalls, <String>['login:user_A']);
    });

    test('a sign-out clears the persisted intent', () async {
      final FakeVaultService vault = Vault.fake();
      addTearDown(Vault.unfake);

      await manager.want('user_A');
      await manager.want(null);

      vault.assertDeleted(NotificationManager.pushIntentKey);
      vault.assertMissing(NotificationManager.pushIntentKey);
    });

    test('a read-back that throws is recorded, not raised', () async {
      use(_RecordingPushDriver(failRead: true));

      await manager.want('user_A');

      // It runs from an auth-state listener and from boot, so a throw escaping
      // here takes the caller's whole lifecycle pass with it.
      await expectLater(manager.reconcilePushIdentity(), completes);
      expect(manager.isPushIdentityConverged, isFalse);
      expect(manager.pushIdentityError, isNotNull);
    });

    test('two overlapping reconciles issue one login, not two', () async {
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      await manager.want('user_A');

      final Completer<void> gate = Completer<void>();
      driver.readGate = gate;

      // The consumer fires this unawaited from two paths that overlap on a
      // restore-then-bump, so both passes read `actual != intent` and both call
      // login: the exact double-call the SDK's own single-flight patch exists to
      // survive, re-created one layer above it.
      final Future<void> first = manager.reconcilePushIdentity();
      await pumpEventQueue();
      final Future<void> second = manager.reconcilePushIdentity();
      await pumpEventQueue();

      gate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(driver.identityCalls, <String>['login:user_A']);
      expect(manager.isPushIdentityConverged, isTrue);
    });

    test('an intent that moved under an in-flight pass gets its own pass',
        () async {
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      await manager.want('user_A');

      final Completer<void> gate = Completer<void>();
      driver.readGate = gate;

      final Future<void> first = manager.reconcilePushIdentity();
      await pumpEventQueue();

      // The person on the device changed while the first pass was parked, so
      // joining it and returning would leave this device subscribed as somebody
      // who is no longer signed in. Single-flight is not "drop the second call".
      await manager.want('user_B');
      final Future<void> second = manager.reconcilePushIdentity();
      await pumpEventQueue();

      gate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(driver.identityCalls, contains('login:user_B'));
      expect(manager.pushIntent, 'user_B');
      expect(manager.isPushIdentityConverged, isTrue);
    });

    test('a sign-out clears an intent this process never read', () async {
      final FakeVaultService vault = Vault.fake();
      addTearDown(Vault.unfake);
      await Vault.put(NotificationManager.pushIntentKey, 'user_A');

      // A cold boot: the vault holds the previous person, memory holds nobody,
      // so the equality check inside `want` matches null against null.
      manager.forgetDrivers();

      await manager.logoutPush();

      // Left behind, the stale id is read back on the next boot and LOGGED IN
      // on a signed-out device, which is the wrong-recipient page this whole
      // design exists to prevent.
      vault.assertMissing(NotificationManager.pushIntentKey);

      manager.forgetDrivers();
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      await manager.reconcilePushIdentity();

      expect(driver.identityCalls, isEmpty);
      expect(manager.pushIntent, isNull);
    });

    test('a sign-out racing the first vault read is not overtaken by it',
        () async {
      final _GatedVaultService vault = _GatedVaultService(<String, String>{
        NotificationManager.pushIntentKey: 'user_A',
      });
      Magic.app.setInstance('vault', vault);
      addTearDown(Vault.unfake);

      // The device came up still carrying the person the vault remembers.
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(subscribedAs: 'user_A'),
      );

      final Completer<void> read = Completer<void>();
      vault.readGate = read;
      addTearDown(() {
        if (!read.isCompleted) read.complete();
      });

      // The restore path asks for the person it just re-authenticated ...
      final Future<void> restoring = manager.initializePushWithUserId('user_A');
      await pumpEventQueue();

      // ... and the sign-out arrives while that vault read is still suspended.
      final Future<void> signingOut = manager.logoutPush();
      await pumpEventQueue();

      read.complete();
      await Future.wait(<Future<void>>[restoring, signingOut]);

      // What is at stake is not a flag, it is which external id this device is
      // left subscribed as. A second caller waved past a load that has only
      // STARTED compares against an intent nothing has read, signs the device
      // out, and is then overtaken by the first caller's login.
      expect(
        driver.subscribedAs,
        isNull,
        reason:
            'the device must not stay subscribed as somebody who signed out',
      );
      expect(manager.pushIntent, isNull);
    });

    test('a pass in flight at forgetDrivers is not joined by the next one',
        () async {
      final FakeVaultService vault = Vault.fake(<String, String>{
        NotificationManager.pushIntentKey: 'user_A',
      });
      addTearDown(Vault.unfake);

      final _RecordingPushDriver stale = use(_RecordingPushDriver());
      await manager.want('user_A');

      final Completer<void> gate = Completer<void>();
      stale.readGate = gate;
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      final Future<void> parked = manager.reconcilePushIdentity();
      await pumpEventQueue();

      manager.forgetDrivers();

      // The seam deliberately leaves the PERSISTED intent alone: a test helper
      // that signed a real device out would be worse than the leak it fixes.
      vault.assertContains(NotificationManager.pushIntentKey);

      final _RecordingPushDriver fresh = use(_RecordingPushDriver());
      await manager.want('user_B');
      final Future<void> next = manager.reconcilePushIdentity();
      await pumpEventQueue();

      // Held in a field the reset never cleared, the parked pass is still what
      // a joiner awaits, so this one does nothing at all until a test that is
      // already over releases it.
      expect(fresh.identityCalls, <String>['login:user_B']);

      gate.complete();
      await Future.wait(<Future<void>>[parked, next]);
    });

    test('a vault read in flight at forgetDrivers lands nowhere', () async {
      final _GatedVaultService vault = _GatedVaultService(<String, String>{
        NotificationManager.pushIntentKey: 'user_A',
      });
      Magic.app.setInstance('vault', vault);
      addTearDown(Vault.unfake);

      final Completer<void> read = Completer<void>();
      vault.readGate = read;
      final Future<void> loading = manager.loadPushIntent();
      await pumpEventQueue();

      manager.forgetDrivers();

      // The read was issued for a manager state the seam has since replaced,
      // so its answer belongs to nobody: assigning it would hand the next test
      // an intent nothing there ever asked for, which is the leak the seam
      // exists to close.
      read.complete();
      await loading;

      expect(manager.pushIntent, isNull);
      vault.assertContains(NotificationManager.pushIntentKey);
    });

    test('a reconcile with no driver at all is quiet', () async {
      await manager.want('user_A');

      await expectLater(manager.reconcilePushIdentity(), completes);
      expect(manager.isPushIdentityConverged, isFalse);
    });
  });

  group('the receive-side subject guard', () {
    test('drops a push addressed to somebody else, delivers an unaddressed one',
        () async {
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(subscribedAs: 'user_B'),
      );
      await manager.want('user_B');
      await manager.reconcilePushIdentity();

      final List<Map<String, dynamic>> delivered = <Map<String, dynamic>>[];
      final StreamSubscription<PushNotificationEvent> subscription =
          manager.onPushReceived.listen(
        (PushNotificationEvent event) => delivered.add(event.data),
      );
      addTearDown(subscription.cancel);

      driver.received.add(
        const PushNotificationEvent(<String, dynamic>{
          'subject': 'user_A',
          'incident_id': 'i-1',
        }),
      );
      await pumpEventQueue();

      expect(delivered, isEmpty);

      // No subject is UN-CHECKABLE, not wrong: a backend older than the payload
      // key sends none, and silencing it would be worse than the leak.
      driver.received.add(
        const PushNotificationEvent(<String, dynamic>{'incident_id': 'i-2'}),
      );
      await pumpEventQueue();

      expect(delivered.map((Map<String, dynamic> d) => d['incident_id']),
          <String>['i-2']);

      driver.received.add(
        const PushNotificationEvent(<String, dynamic>{
          'subject': 'user_B',
          'incident_id': 'i-3',
        }),
      );
      await pumpEventQueue();

      expect(delivered.map((Map<String, dynamic> d) => d['incident_id']),
          <String>['i-2', 'i-3']);
    });

    test('an intent nobody has read yet is not evidence of misaddressing',
        () async {
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(subscribedAs: 'user_A'),
      );
      // Resolving a driver ATTACHES these listeners, and that happens before
      // anything reads the persisted intent. A cold start from a notification
      // tap replays into exactly this window.
      expect(manager.pushDriverOrNull, isNotNull);

      final List<Map<String, dynamic>> delivered = <Map<String, dynamic>>[];
      final StreamSubscription<PushNotificationEvent> subscription =
          manager.onPushReceived.listen(
        (PushNotificationEvent event) => delivered.add(event.data),
      );
      addTearDown(subscription.cancel);

      driver.received.add(
        const PushNotificationEvent(<String, dynamic>{
          'subject': 'user_A',
          'incident_id': 'i-1',
        }),
      );
      await pumpEventQueue();

      // An UNREAD intent says nothing about who this device is subscribed as,
      // which is the same reasoning that already delivers a payload carrying no
      // subject at all. Dropping here loses a real page.
      expect(
        delivered.map((Map<String, dynamic> d) => d['incident_id']),
        <String>['i-1'],
      );
    });

    test('a push arriving while the vault read is still open is delivered',
        () async {
      final _GatedVaultService vault = _GatedVaultService(<String, String>{
        NotificationManager.pushIntentKey: 'user_A',
      });
      Magic.app.setInstance('vault', vault);
      addTearDown(Vault.unfake);

      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(subscribedAs: 'user_A'),
      );
      expect(manager.pushDriverOrNull, isNotNull);

      final List<Map<String, dynamic>> delivered = <Map<String, dynamic>>[];
      final StreamSubscription<PushNotificationEvent> subscription =
          manager.onPushReceived.listen(
        (PushNotificationEvent event) => delivered.add(event.data),
      );
      addTearDown(subscription.cancel);

      final Completer<void> read = Completer<void>();
      vault.readGate = read;
      addTearDown(() {
        if (!read.isCompleted) read.complete();
      });
      final Future<void> loading = manager.loadPushIntent();
      await pumpEventQueue();

      // The read has STARTED and has not answered yet, which is precisely the
      // window the SDK replays a cold-start tap into. Counting a read that
      // started as one that finished closes the escape hatch there and drops a
      // real page in silence.
      driver.received.add(
        const PushNotificationEvent(<String, dynamic>{
          'subject': 'user_A',
          'incident_id': 'i-1',
        }),
      );
      await pumpEventQueue();

      expect(
        delivered.map((Map<String, dynamic> d) => d['incident_id']),
        <String>['i-1'],
      );

      read.complete();
      await loading;
    });

    test('drops a CLICK addressed to somebody else', () async {
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(subscribedAs: 'user_B'),
      );
      await manager.want('user_B');
      await manager.reconcilePushIdentity();

      final List<Map<String, dynamic>> opened = <Map<String, dynamic>>[];
      final StreamSubscription<PushNotificationEvent> subscription =
          manager.onPushClicked.listen(
        (PushNotificationEvent event) => opened.add(event.data),
      );
      addTearDown(subscription.cancel);

      driver.clicked.add(
        const PushNotificationEvent(<String, dynamic>{'subject': 'user_A'}),
      );
      driver.clicked.add(
        const PushNotificationEvent(<String, dynamic>{'subject': 'user_B'}),
      );
      await pumpEventQueue();

      expect(opened.map((Map<String, dynamic> d) => d['subject']),
          <String>['user_B']);
    });

    test('a delivered push refreshes the list', () async {
      final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
      });
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      // The manager listens to a driver when it RESOLVES one, which in
      // production is the provider's boot reconcile; a registration alone must
      // not build the platform SDK wrapper.
      await manager.reconcilePushIdentity();

      driver.received.add(
        const PushNotificationEvent(<String, dynamic>{'incident_id': 'i-9'}),
      );
      await pumpEventQueue();

      network.assertSent(
        (MagicRequest request) => request.url.contains('notifications'),
      );
    });
  });

  group('the push driver registry', () {
    test('extend makes a driver resolvable without booting a provider', () {
      final _RecordingPushDriver driver = _RecordingPushDriver();
      addTearDown(driver.dispose);
      Notify.extend(driver.name, () => driver);
      addTearDown(Notify.forgetDrivers);

      expect(identical(manager.pushDriver, driver), isTrue);
    });

    test('a configured driver name is never served by a different one', () {
      Config.set('notifications.push.driver', 'onesignal');
      addTearDown(() => Config.forget('notifications.push.driver'));

      final _RecordingPushDriver driver = _RecordingPushDriver();
      addTearDown(driver.dispose);
      Notify.extend('fcm', () => driver);
      addTearDown(Notify.forgetDrivers);

      // Serving the only registered factory regardless of the name the config
      // asked for hands the app a driver nobody selected, and it silences the
      // provider's unservable-value error too: that check consults
      // `pushDriverOrNull` first and reads a served value as "somebody supplied
      // their own driver".
      expect(manager.pushDriverOrNull, isNull);
    });

    test('the single-factory fallback still serves an ABSENT config value', () {
      final _RecordingPushDriver driver = _RecordingPushDriver();
      addTearDown(driver.dispose);
      Notify.extend('fcm', () => driver);
      addTearDown(Notify.forgetDrivers);

      // The other half of the pair above. Without a configured name there is no
      // instruction to contradict, and this is the path a test (or an app that
      // registers exactly one driver in code) reaches the registry through.
      expect(identical(manager.pushDriver, driver), isTrue);
    });

    test('attaching a driver announces it, so a late one can be acted on',
        () async {
      final List<String> announced = <String>[];
      final StreamSubscription<PushDriver> subscription =
          manager.onPushDriverAttached.listen(
        (PushDriver driver) => announced.add(driver.name),
      );
      addTearDown(subscription.cancel);

      // Subscribed with no driver at all, which is the only state a host that
      // needs this signal can subscribe from: its own provider boots ahead of
      // the one that resolves a driver.
      expect(manager.pushDriverOrNull, isNull);

      final _RecordingPushDriver driver = _RecordingPushDriver();
      addTearDown(driver.dispose);
      Notify.extend(driver.name, () => driver);
      addTearDown(Notify.forgetDrivers);

      // A registration alone builds nothing, so the announcement rides the
      // ATTACHMENT, which is the moment a driver becomes usable.
      expect(announced, isEmpty);
      expect(identical(manager.pushDriver, driver), isTrue);
      await pumpEventQueue();

      expect(announced, <String>['recording']);
    });

    test('forgetDrivers drops the registry and the resolved instance', () {
      final _RecordingPushDriver driver = _RecordingPushDriver();
      addTearDown(driver.dispose);
      Notify.extend(driver.name, () => driver);

      expect(identical(manager.pushDriver, driver), isTrue);

      Notify.forgetDrivers();

      expect(() => manager.pushDriver, throwsA(isA<NotificationException>()));
    });
  });

  group('the automatic permission request', () {
    /// Turns [key] on for one test and takes it back afterwards.
    void configure(String key, Object value) {
      Config.set(key, value);
      addTearDown(() => Config.forget(key));
    }

    test('an app that sets neither key behaves exactly as it did before',
        () async {
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(permission: PushPermissionState.notDetermined),
      );

      await manager.initializePushWithUserId('user_A');
      await pumpEventQueue();

      // The upgrade guarantee. A device that has never been asked is the one
      // an automatic request would fire on, so if an absent key changed
      // anything at all it would change it here.
      expect(driver.permissionRequests, 0);
      expect(driver.identityCalls, <String>['login:user_A']);

      // And the second cadence is silent too: with no interval configured, a
      // device that turned the reminder down is never reminded again.
      final PushPromptAdvice advice = await manager.pushPromptAdvice(
        declinedAt: DateTime.now().subtract(const Duration(days: 365)),
      );
      expect(advice.show, isFalse);
    });

    test('a device that was never asked is asked once, and only once',
        () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(permission: PushPermissionState.notDetermined),
      );

      await manager.initializePushWithUserId('user_A');
      await pumpEventQueue();

      expect(driver.permissionRequests, 1);

      // A consumer wires this to auth state, which bumps on every cold-boot
      // restore and every team switch. Asking again on each of those is a
      // dialog the operator already answered.
      await manager.initializePushWithUserId('user_A');
      await manager.want('user_B');
      await pumpEventQueue();

      expect(driver.permissionRequests, 1);
    });

    test('a declaration made before any driver exists does not spend the ask',
        () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);

      // The ordering a consumer's provider list actually produces, and the one
      // no fixture in this file had: the auth provider that restores a stored
      // session is registered AHEAD of the notifications one (it has to be,
      // notifications follow a session), so its state bump declares an identity
      // while nothing has resolved a driver yet.
      await manager.want('user_A');
      await pumpEventQueue();

      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(permission: PushPermissionState.notDetermined),
      );

      await manager.want('user_B');
      await pumpEventQueue();

      // Claiming the one-shot before reading the driver spends it having asked
      // nobody: no OS prompt can be raised for the rest of the launch, on a
      // device that has never been asked, in an app that switched the key on.
      expect(driver.permissionRequests, 1);

      // And it is still a one-shot. The pass that actually reached a platform
      // is the one that took the turn.
      await manager.want('user_C');
      await pumpEventQueue();

      expect(driver.permissionRequests, 1);
    });

    test('a blocked device is never asked, whatever the config says', () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(permission: PushPermissionState.denied),
      );

      await manager.initializePushWithUserId('user_A');
      await pumpEventQueue();

      // Every platform answers a request on a denied origin immediately and
      // shows the user nothing, so this would be a prompt that never appears
      // and an operator watching nothing happen.
      expect(driver.permissionRequests, 0);
    });

    test('a device already subscribed is not asked', () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);
      final _RecordingPushDriver driver = use(_RecordingPushDriver());

      await manager.initializePushWithUserId('user_A');
      await pumpEventQueue();

      expect(driver.permissionRequests, 0);
    });

    test('a device that was asked once and opted out is not asked again',
        () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(optedIn: false),
      );

      await manager.initializePushWithUserId('user_A');
      await pumpEventQueue();

      // Reachable is not the same as promptable. This device reads `off`, like
      // one that was never asked, but the permission was granted long ago and
      // a request here resolves without showing anybody anything.
      expect(await driver.reachability(), PushReachability.off);
      expect(driver.permissionRequests, 0);
    });

    test('a sign-out declares no identity, so nothing is asked', () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(permission: PushPermissionState.notDetermined),
      );

      await manager.logoutPush();
      await pumpEventQueue();

      // The trigger is a person signing IN. A device being detached from
      // whoever was on it has nobody to ask on behalf of.
      expect(driver.permissionRequests, 0);
    });

    test('a reconcile pass never raises a prompt', () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(permission: PushPermissionState.notDetermined),
      );

      await manager.reconcilePushIdentity();
      await pumpEventQueue();

      // The reconciler runs on every auth-state change, on boot, and from the
      // provider on a signed-out device. A dialog raised from there arrives
      // with no login in front of it to explain what it is for.
      expect(driver.permissionRequests, 0);
    });

    test('a permission request that throws does not take the login with it',
        () async {
      configure(NotificationManager.autoRequestOnLoginKey, true);
      final _RecordingPushDriver driver = use(
        _ThrowingRequestDriver(permission: PushPermissionState.notDetermined),
      );

      await expectLater(manager.initializePushWithUserId('user_A'), completes);
      await pumpEventQueue();

      expect(driver.identityCalls, <String>['login:user_A']);
    });
  });

  group('the reminder policy', () {
    /// Sets [key] for one test and takes it back afterwards.
    void configure(String key, Object value) {
      Config.set(key, value);
      addTearDown(() => Config.forget(key));
    }

    /// [hours] ago.
    DateTime hoursAgo(int hours) =>
        DateTime.now().subtract(Duration(hours: hours));

    test(
        'a device that was never asked may be reminded, and the reminder can '
        'raise the OS prompt', () async {
      use(_RecordingPushDriver(permission: PushPermissionState.notDetermined));

      final PushPromptAdvice advice = await manager.pushPromptAdvice();

      expect(advice.show, isTrue);
      expect(advice.reachability, PushReachability.off);
      expect(advice.action, PushPromptAction.request);
    });

    test(
        'a reachability read that throws answers unavailable rather than '
        'taking the caller down with it', () async {
      use(_ThrowingReachabilityDriver());

      // The only caller of this is a widget deciding whether to render a
      // reminder. A throw here is a failure to ASK, not an answer, and letting
      // it escape would blank the surface that asked. `pushDeliverySnapshot()`
      // has always guarded its own read the same way; this one had not.
      final PushPromptAdvice advice = await manager.pushPromptAdvice();

      expect(advice.reachability, PushReachability.unavailable);
      expect(advice.action, PushPromptAction.none);
      expect(advice.show, isFalse);
    });

    test('the interval governs when a decline may be reminded again', () async {
      configure(NotificationManager.repromptAfterHoursKey, 24);
      use(_RecordingPushDriver(permission: PushPermissionState.notDetermined));

      // Before: the operator said no eleven hours ago and meant it.
      expect((await manager.pushPromptAdvice(declinedAt: hoursAgo(11))).show,
          isFalse);

      // At: a full interval has passed, so the reminder is due.
      expect((await manager.pushPromptAdvice(declinedAt: hoursAgo(24))).show,
          isTrue);

      // After.
      expect((await manager.pushPromptAdvice(declinedAt: hoursAgo(48))).show,
          isTrue);
    });

    test('with no interval configured a decline is permanent', () async {
      use(_RecordingPushDriver(permission: PushPermissionState.notDetermined));

      expect(
          (await manager.pushPromptAdvice(declinedAt: hoursAgo(24 * 365))).show,
          isFalse);

      // Explicit zero reads the same as absent, so an app can turn the cadence
      // back off without deleting the key.
      configure(NotificationManager.repromptAfterHoursKey, 0);
      expect(
          (await manager.pushPromptAdvice(declinedAt: hoursAgo(24 * 365))).show,
          isFalse);
    });

    test(
        'a blocked device is reminded too, and its action is the settings '
        'page when the platform has one', () async {
      configure(NotificationManager.repromptAfterHoursKey, 24);
      use(
        _RecordingPushDriver(
          permission: PushPermissionState.denied,
          canOpenPlatformSettings: true,
        ),
      );

      final PushPromptAdvice due = await manager.pushPromptAdvice(
        declinedAt: hoursAgo(25),
      );

      // The OS prompt is spent here, the app's own reminder is not: on mobile
      // the tap lands on the app's settings page, where the operator really
      // can turn notifications back on.
      expect(due.show, isTrue);
      expect(due.reachability, PushReachability.blocked);
      expect(due.action, PushPromptAction.openSettings);

      // And the same interval still holds it back inside the window.
      expect(
        (await manager.pushPromptAdvice(declinedAt: hoursAgo(1))).show,
        isFalse,
      );
    });

    test(
        'a blocked device on a platform with no settings route can only be '
        'told where the switch is', () async {
      use(_RecordingPushDriver(permission: PushPermissionState.denied));

      final PushPromptAdvice advice = await manager.pushPromptAdvice();

      // The web case. No browser API opens Chrome's site settings from a page,
      // so a control here would be a button that does nothing.
      expect(advice.show, isTrue);
      expect(advice.action, PushPromptAction.instructions);
    });

    test('a subscribed device is never reminded', () async {
      configure(NotificationManager.repromptAfterHoursKey, 1);
      use(_RecordingPushDriver());

      final PushPromptAdvice advice = await manager.pushPromptAdvice(
        declinedAt: hoursAgo(24),
      );

      expect(advice.reachability, PushReachability.on);
      expect(advice.action, PushPromptAction.none);
      expect(advice.show, isFalse);
    });

    test('a build with no push driver has nothing to remind anybody about',
        () async {
      final PushPromptAdvice advice = await manager.pushPromptAdvice();

      expect(advice.reachability, PushReachability.unavailable);
      expect(advice.action, PushPromptAction.none);
      expect(advice.show, isFalse);
    });

    test('the host can switch the reminder off entirely', () async {
      configure('notifications.soft_prompt.enabled', false);
      use(_RecordingPushDriver(permission: PushPermissionState.notDetermined));

      final PushPromptAdvice advice = await manager.pushPromptAdvice();

      // The state and the action are still reported, because a caller that
      // renders the state without a prompt still needs them; only the
      // permission to interrupt is withdrawn.
      expect(advice.show, isFalse);
      expect(advice.action, PushPromptAction.request);
    });

    test('a decline timestamp in the future is not a licence to ask now',
        () async {
      configure(NotificationManager.repromptAfterHoursKey, 24);
      use(_RecordingPushDriver(permission: PushPermissionState.notDetermined));

      // A device whose clock is ahead, or a timestamp written by a server in
      // another timezone: the elapsed time is negative, which is not an
      // interval that has passed.
      expect(
        (await manager.pushPromptAdvice(declinedAt: hoursAgo(-48))).show,
        isFalse,
      );
    });
  });

  group('the delivery snapshot', () {
    test('reports the address and the reachability a server needs', () async {
      use(_RecordingPushDriver(subscribedAs: 'user_A'));

      final PushDeliverySnapshot snapshot =
          await manager.pushDeliverySnapshot();

      expect(snapshot.externalId, 'user_A');
      expect(snapshot.subscriptionId, 'sub-1');
      expect(snapshot.reachability, PushReachability.on);
      expect(snapshot.canReceive, isTrue);
    });

    test('a device that cannot be paged says so', () async {
      use(
        _RecordingPushDriver(
          subscribedAs: 'user_A',
          permission: PushPermissionState.denied,
        ),
      );

      final PushDeliverySnapshot snapshot =
          await manager.pushDeliverySnapshot();

      expect(snapshot.reachability, PushReachability.blocked);
      expect(snapshot.canReceive, isFalse);
    });

    test('a permitted device holding no subscription reports it', () async {
      use(_RecordingPushDriver(subscribedAs: 'user_A', subscriptionId: null));

      final PushDeliverySnapshot snapshot =
          await manager.pushDeliverySnapshot();

      // The subtlest un-pageable state: permitted, opted in, and with no
      // address to deliver to. A server reading only the permission would page
      // into nothing here.
      expect(snapshot.subscriptionId, isNull);
      expect(snapshot.reachability, PushReachability.off);
      expect(snapshot.canReceive, isFalse);
    });

    test('a build with no push driver reports unavailable rather than throwing',
        () async {
      final PushDeliverySnapshot snapshot =
          await manager.pushDeliverySnapshot();

      expect(snapshot.reachability, PushReachability.unavailable);
      expect(snapshot.externalId, isNull);
      expect(snapshot.subscriptionId, isNull);
    });

    test('a platform read that throws reports un-pageable, not an exception',
        () async {
      use(_RecordingPushDriver(failRead: true));

      // The consumer posts this from a lifecycle path. A throw would take that
      // path down, and claiming reachable on a read that failed would leave an
      // escalation waiting on a device nobody can prove is there.
      final PushDeliverySnapshot snapshot =
          await manager.pushDeliverySnapshot();

      expect(snapshot.canReceive, isFalse);
      expect(snapshot.reachability, PushReachability.unavailable);
    });
  });

  group('the user attributes a host describes', () {
    /// Sets [key] for one test and takes it back afterwards.
    void configure(String key, Object value) {
      Config.set(key, value);
      addTearDown(() => Config.forget(key));
    }

    /// Opts this deployment in to sending what the host describes.
    void optInToSharing() {
      configure(NotificationManager.shareUserAttributesKey, true);
    }

    /// What a host would describe each of two people with.
    ///
    /// Two different shapes on purpose: Grace carries one tag where Ada
    /// carries two, so a key that belongs only to the person who left has
    /// somewhere to survive if nothing takes it back.
    PushUserAttributes? describe(String externalId) {
      return switch (externalId) {
        'user_A' => const PushUserAttributes(
            email: 'ada@example.com',
            tags: <String, String>{
              'first_name': 'Ada',
              'last_name': 'Lovelace',
            },
          ),
        'user_B' => const PushUserAttributes(
            email: 'grace@example.com',
            tags: <String, String>{'first_name': 'Grace'},
          ),
        _ => null,
      };
    }

    test('a login applies what the host described for that identity', () async {
      optInToSharing();
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      manager.describePushUserUsing(describe);

      await manager.initializePushWithUserId('user_A');

      expect(driver.emails, <String>{'ada@example.com'});
      expect(driver.tags, <String, String>{
        'first_name': 'Ada',
        'last_name': 'Lovelace',
      });
    });

    test('an account switch leaves nothing of the previous person behind',
        () async {
      optInToSharing();
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      manager.describePushUserUsing(describe);

      await manager.initializePushWithUserId('user_A');
      driver.calls.clear();

      // The person on this device changed. Everything Ada was described with
      // has to be off it before Grace's first push is addressed.
      await manager.initializePushWithUserId('user_B');

      expect(driver.emails, <String>{'grace@example.com'});
      expect(driver.tags, <String, String>{'first_name': 'Grace'});

      // And the removals were issued while the SDK still pointed at Ada.
      // Issued after the login they run against GRACE's own user record, where
      // a tag she set from another device is not this device's to take back.
      final int login = driver.orderedCalls.indexOf('login:user_B');
      expect(login, greaterThanOrEqualTo(0));
      expect(
        driver.orderedCalls.indexOf('removeEmail:ada@example.com'),
        inExclusiveRange(-1, login),
      );
      expect(
        driver.orderedCalls.indexOf('removeTag:last_name'),
        inExclusiveRange(-1, login),
      );
    });

    test('a sign-out detaches the email and the tags before it logs out',
        () async {
      optInToSharing();
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      manager.describePushUserUsing(describe);

      await manager.initializePushWithUserId('user_A');
      driver.calls.clear();

      await manager.logoutPush();

      expect(driver.emails, isEmpty);
      expect(driver.tags, isEmpty);

      // Before the logout, because a write made after it lands on the
      // device-scoped user the SDK creates, and the operations of a
      // device-scoped user are applied to the next user login CREATES.
      final int logout = driver.orderedCalls.indexOf('logout');
      expect(logout, greaterThanOrEqualTo(0));
      expect(
        driver.orderedCalls.indexOf('removeEmail:ada@example.com'),
        inExclusiveRange(-1, logout),
      );
    });

    test('the description is registered once and serves every later login',
        () async {
      optInToSharing();
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      manager.describePushUserUsing(describe);

      await manager.initializePushWithUserId('user_A');
      await manager.logoutPush();
      driver.calls.clear();

      // Nothing re-registers here. A host wires this at boot, and the identity
      // lifecycle is what re-applies it.
      await manager.initializePushWithUserId('user_A');

      expect(driver.emails, <String>{'ada@example.com'});
      expect(driver.tags, <String, String>{
        'first_name': 'Ada',
        'last_name': 'Lovelace',
      });
    });

    test('a device already carrying the intent still gets its attributes',
        () async {
      optInToSharing();
      final _RecordingPushDriver driver = use(
        _RecordingPushDriver(subscribedAs: 'user_A'),
      );
      manager.describePushUserUsing(describe);

      await manager.initializePushWithUserId('user_A');

      // A cold boot onto a device the SDK already has logged in issues no
      // identity call at all, and the attributes still have to land: nothing
      // in this process has written them yet.
      expect(driver.identityCalls, isEmpty);
      expect(driver.emails, <String>{'ada@example.com'});
    });

    test('a host that describes nothing behaves exactly as it does today',
        () async {
      optInToSharing();
      final _RecordingPushDriver driver = use(_RecordingPushDriver());

      await manager.initializePushWithUserId('user_A');
      await manager.logoutPush();

      expect(driver.orderedCalls, <String>['login:user_A', 'logout']);
      expect(driver.tags, isEmpty);
      expect(driver.emails, isEmpty);
    });

    test('nothing is sent until the deployment opts in', () async {
      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      manager.describePushUserUsing(describe);

      await manager.initializePushWithUserId('user_A');

      // An absent key is off, which is the state every existing deployment
      // upgrades into: an email address reaching a third party must be a
      // decision somebody made, not one they discover afterwards.
      expect(driver.orderedCalls, <String>['login:user_A']);
      expect(driver.emails, isEmpty);
      expect(driver.tags, isEmpty);
    });

    test('an attribute write that fails leaves the identity converged',
        () async {
      optInToSharing();
      final _RecordingPushDriver driver = use(_ThrowingTagDriver());
      manager.describePushUserUsing(describe);

      await manager.initializePushWithUserId('user_A');

      // Tags are the soft half. The device carrying the right subject is what
      // keeps somebody else's outage off this screen, and a segmentation write
      // that failed must not be reported as an identity that did not land.
      expect(driver.identityCalls, <String>['login:user_A']);
      expect(manager.isPushIdentityConverged, isTrue);
      expect(manager.pushIdentityError, isNull);
    });

    test('forgetDrivers drops the description with the drivers', () async {
      optInToSharing();
      manager.describePushUserUsing(describe);

      manager.forgetDrivers();

      final _RecordingPushDriver driver = use(_RecordingPushDriver());
      await manager.initializePushWithUserId('user_A');

      // The registration is a registration like a driver factory, so the one
      // seam every test resets has to take it too, or a description registered
      // in one test describes the person in the next.
      expect(driver.emails, isEmpty);
      expect(driver.tags, isEmpty);
    });
  });
}

/// A driver whose tag write throws, standing in for an SDK that rejects the
/// attribute call while the identity call itself lands.
class _ThrowingTagDriver extends _RecordingPushDriver {
  @override
  Future<void> setTags(Map<String, String> tags) async {
    await super.setTags(tags);

    throw StateError('the SDK refused the tags');
  }
}

/// A driver whose permission request throws, standing in for a platform
/// channel that is not there.
class _ThrowingRequestDriver extends _RecordingPushDriver {
  _ThrowingRequestDriver({required super.permission});

  @override
  Future<bool> requestPermission() async {
    await super.requestPermission();

    throw StateError('the SDK is not initialized');
  }
}

/// A driver whose reachability read throws, standing in for a platform channel
/// that answers neither yes nor no.
class _ThrowingReachabilityDriver extends _RecordingPushDriver {
  @override
  Future<PushReachability> reachability() async {
    throw StateError('the platform channel is gone');
  }
}
