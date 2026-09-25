import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import 'test_helper.dart';

/// A push driver minimal enough to drive one reconcile pass at a time.
///
/// Modeled on `_RecordingPushDriver` in `notification_manager_reconcile_test.dart`:
/// the same held-read mechanism ([readGate]) is what lets a test park a pass
/// mid-read and change the intent underneath it, which is the race
/// [onPushIdentityReconciled] has to survive.
class _FakePushDriver extends PushDriver {
  _FakePushDriver({String? subscribedAs, this.failLogin = false})
      : _externalId = subscribedAs;

  /// Whether [login] throws, standing in for a call the SDK refused.
  final bool failLogin;

  /// The external id the device currently reports, mutated the way the SDK
  /// mutates its local user: immediately, before any server round trip.
  String? _externalId;

  /// When set, the NEXT [currentExternalId] parks on it after reading the
  /// device, so a test can hold a reconcile pass open and drive the intent
  /// into a different state before letting it finish.
  Completer<void>? readGate;

  final StreamController<PushNotificationEvent> _received =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _clicked =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushIdentityChange> _identity =
      StreamController<PushIdentityChange>.broadcast();

  @override
  String get name => 'fake';

  @override
  bool get isSupported => true;

  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.authorized;

  @override
  bool get isOptedIn => true;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> login(String externalId) async {
    if (failLogin) throw StateError('the SDK refused the identity call');
    _externalId = externalId;
  }

  @override
  Future<void> logout() async {
    _externalId = null;
  }

  @override
  Future<String?> currentExternalId() async {
    final String? reported = _externalId;

    final Completer<void>? gate = readGate;
    if (gate != null) {
      readGate = null;
      await gate.future;
    }

    return reported;
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
  Stream<PushNotificationEvent> get onNotificationReceived => _received.stream;

  @override
  Stream<PushNotificationEvent> get onNotificationClicked => _clicked.stream;

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      const Stream<PushPermissionState>.empty();

  @override
  Stream<PushIdentityChange> get onIdentityChanged => _identity.stream;

  /// Closes the three controllers a test opened.
  void dispose() {
    _received.close();
    _clicked.close();
    _identity.close();
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

  /// Registers [driver] the way a consumer registers one, through the
  /// registry and with no provider booted.
  _FakePushDriver use(_FakePushDriver driver) {
    Notify.extend(driver.name, () => driver);
    addTearDown(Notify.forgetDrivers);
    addTearDown(driver.dispose);

    return driver;
  }

  group('onPushIdentityReconciled', () {
    test('a converging pass emits the intent, converged and no error',
        () async {
      use(_FakePushDriver());
      await manager.want('user_1');

      final List<PushIdentityReconciled> events = <PushIdentityReconciled>[];
      manager.onPushIdentityReconciled.listen(events.add);

      await manager.reconcilePushIdentity();
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.intent, 'user_1');
      expect(events.single.converged, isTrue);
      expect(events.single.error, isNull);
    });

    test('a pass whose login throws still emits, carrying the error', () async {
      use(_FakePushDriver(failLogin: true));
      await manager.want('user_1');

      final List<PushIdentityReconciled> events = <PushIdentityReconciled>[];
      manager.onPushIdentityReconciled.listen(events.add);

      await manager.reconcilePushIdentity();
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.intent, 'user_1');
      expect(events.single.converged, isFalse);
      expect(events.single.error, isNotNull);
    });

    test(
        'a pass whose intent moved before it finished emits nothing for the '
        'stale intent', () async {
      final _FakePushDriver driver = use(_FakePushDriver());
      await manager.want('user_1');

      final Completer<void> gate = Completer<void>();
      driver.readGate = gate;

      final List<PushIdentityReconciled> events = <PushIdentityReconciled>[];
      manager.onPushIdentityReconciled.listen(events.add);

      final Future<void> pass = manager.reconcilePushIdentity();
      await pumpEventQueue();

      // The device changed hands while the pass was parked on its read, so
      // whatever this pass concludes about "user_1" is stale by the time it
      // returns.
      await manager.want('user_2');
      gate.complete();
      await pass;

      expect(events, isEmpty);
    });

    test('a pass with no driver emits nothing', () async {
      final List<PushIdentityReconciled> events = <PushIdentityReconciled>[];
      manager.onPushIdentityReconciled.listen(events.add);

      await manager.want('user_1');
      await manager.reconcilePushIdentity();

      expect(events, isEmpty);
    });

    test('two joined callers produce one event', () async {
      final _FakePushDriver driver = use(_FakePushDriver());
      await manager.want('user_1');

      final Completer<void> gate = Completer<void>();
      driver.readGate = gate;

      final List<PushIdentityReconciled> events = <PushIdentityReconciled>[];
      manager.onPushIdentityReconciled.listen(events.add);

      final Future<void> first = manager.reconcilePushIdentity();
      await pumpEventQueue();
      final Future<void> second = manager.reconcilePushIdentity();
      await pumpEventQueue();

      gate.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(events, hasLength(1));
      expect(events.single.intent, 'user_1');
      expect(events.single.converged, isTrue);
    });
  });
}
