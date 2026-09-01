import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('PushDriver', () {
    test('concrete implementation must provide name', () {
      final driver = TestPushDriver();
      expect(driver.name, 'test');
    });

    test('concrete implementation must provide isSupported', () {
      final driver = TestPushDriver();
      expect(driver.isSupported, isA<bool>());
    });

    test('initialize() is callable', () async {
      final driver = TestPushDriver();
      await expectLater(
        driver.initialize({}),
        completes,
      );
    });

    test('login() sets external ID', () async {
      final driver = TestPushDriver();
      await driver.login('user-123');
      expect(driver.lastLoginId, 'user-123');
    });

    test('currentExternalId() reads back who the device is subscribed as',
        () async {
      final driver = TestPushDriver();
      expect(await driver.currentExternalId(), isNull);

      await driver.login('user-123');

      expect(await driver.currentExternalId(), 'user-123');
    });

    test('onIdentityChanged carries the SDK change the driver observed',
        () async {
      final driver = TestPushDriver();

      final events = <PushIdentityChange>[];
      driver.onIdentityChanged.listen(events.add);
      driver.emitIdentityChange(
        const PushIdentityChange(
          externalId: 'user-123',
          subscriptionId: 'sub-1',
          optedIn: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single.externalId, 'user-123');
      expect(events.single.subscriptionId, 'sub-1');
      expect(events.single.optedIn, isTrue);
    });

    test('onIdentityChanged is a broadcast stream', () {
      final driver = TestPushDriver();

      expect(driver.onIdentityChanged.isBroadcast, isTrue);
    });
  });

  group('PushDriver.reachability', () {
    test('is unavailable when the platform has no driver', () async {
      final driver = TestPushDriver(supported: false);

      expect(await driver.reachability(), PushReachability.unavailable);
    });

    test('is blocked when permission was denied', () async {
      final driver = TestPushDriver(
        permission: PushPermissionState.denied,
        optedIn: true,
        subscriptionId: 'sub-1',
      );

      expect(await driver.reachability(), PushReachability.blocked);
    });

    test('is off when permission was never asked', () async {
      final driver = TestPushDriver(
        permission: PushPermissionState.notDetermined,
        optedIn: true,
        subscriptionId: 'sub-1',
      );

      expect(await driver.reachability(), PushReachability.off);
    });

    test('is off when permitted but not opted in', () async {
      final driver = TestPushDriver(
        permission: PushPermissionState.authorized,
        subscriptionId: 'sub-1',
      );

      expect(await driver.reachability(), PushReachability.off);
    });

    test('is off when permitted and opted in without a subscription', () async {
      final driver = TestPushDriver(
        permission: PushPermissionState.authorized,
        optedIn: true,
      );

      expect(await driver.reachability(), PushReachability.off);
    });

    test('is on when permitted, opted in and subscribed', () async {
      final driver = TestPushDriver(
        permission: PushPermissionState.authorized,
        optedIn: true,
        subscriptionId: 'sub-1',
      );

      expect(await driver.reachability(), PushReachability.on);
    });

    test('provisional authorization is still reachable', () async {
      final driver = TestPushDriver(
        permission: PushPermissionState.provisional,
        optedIn: true,
        subscriptionId: 'sub-1',
      );

      expect(await driver.reachability(), PushReachability.on);
    });
  });
}

class TestPushDriver extends PushDriver {
  TestPushDriver({
    this.supported = true,
    this.permission = PushPermissionState.notDetermined,
    this.optedIn = false,
    this.subscriptionId,
  });

  final bool supported;
  final PushPermissionState permission;
  final bool optedIn;
  final String? subscriptionId;

  final StreamController<PushIdentityChange> _identityController =
      StreamController<PushIdentityChange>.broadcast();

  String? lastLoginId;

  /// Emits a change the way a real driver's SDK observer would.
  void emitIdentityChange(PushIdentityChange change) =>
      _identityController.add(change);

  @override
  String get name => 'test';
  @override
  bool get isSupported => supported;
  @override
  Future<PushPermissionState> permissionState() async => permission;
  @override
  bool get isOptedIn => optedIn;
  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> login(String externalId) async => lastLoginId = externalId;
  @override
  Future<void> logout() async => lastLoginId = null;
  @override
  Future<String?> currentExternalId() async => lastLoginId;
  @override
  Future<String?> currentSubscriptionId() async => subscriptionId;
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
  Stream<PushNotificationEvent> get onNotificationReceived => Stream.empty();
  @override
  Stream<PushNotificationEvent> get onNotificationClicked => Stream.empty();
  @override
  Stream<PushPermissionState> get onPermissionChanged => Stream.empty();
  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      _identityController.stream;
}
