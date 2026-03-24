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
  });
}

class TestPushDriver extends PushDriver {
  String? lastLoginId;
  @override
  String get name => 'test';
  @override
  bool get isSupported => true;
  @override
  PushPermissionState get permissionState => PushPermissionState.notDetermined;
  @override
  bool get isOptedIn => false;
  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> login(String externalId) async => lastLoginId = externalId;
  @override
  Future<void> logout() async {}
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
}
