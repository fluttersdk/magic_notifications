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
  }) : _externalId = subscribedAs;

  /// Every driver call in the order it was made, logins carrying their subject.
  final List<String> calls = <String>[];

  /// Whether [logout] throws, standing in for a sign-out with no network.
  final bool failLogout;

  /// Whether [currentExternalId] throws, standing in for an SDK that is not
  /// initialised behind a platform channel.
  final bool failRead;

  /// The external id the device currently reports, mutated the way the SDK
  /// mutates its local user: immediately, before any server round trip.
  String? _externalId;

  final StreamController<PushNotificationEvent> received =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> clicked =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushIdentityChange> identity =
      StreamController<PushIdentityChange>.broadcast();

  /// The calls that CHANGE the device's identity, which is what a reconcile is
  /// judged on; a read-back is not an operation.
  List<String> get identityCalls =>
      calls.where((String call) => call != 'currentExternalId').toList();

  @override
  String get name => 'recording';

  @override
  bool get isSupported => true;

  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.authorized;

  @override
  bool get isOptedIn => true;

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

    return _externalId;
  }

  @override
  Future<String?> currentSubscriptionId() async => 'sub-1';

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> optIn() async {}

  @override
  Future<void> optOut() async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> removeTag(String key) async {}

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

    test('forgetDrivers drops the registry and the resolved instance', () {
      final _RecordingPushDriver driver = _RecordingPushDriver();
      addTearDown(driver.dispose);
      Notify.extend(driver.name, () => driver);

      expect(identical(manager.pushDriver, driver), isTrue);

      Notify.forgetDrivers();

      expect(() => manager.pushDriver, throwsA(isA<NotificationException>()));
    });
  });
}
