import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

void main() {
  late NotificationManager manager;

  setUp(() {
    manager = NotificationManager();
    manager.forgetChannels();
    manager.forgetPushDriver(); // Clear any existing driver
  });

  group('NotificationManager - Push', () {
    test('pushDriver throws if not configured', () {
      expect(
        () => manager.pushDriver,
        throwsA(isA<NotificationException>()),
      );
    });

    test('setPushDriver() configures driver', () {
      final driver = MockPushDriver();
      manager.setPushDriver(driver);

      expect(manager.pushDriver, driver);
    });

    test('initializePush() initializes driver', () async {
      final driver = MockPushDriver();
      manager.setPushDriver(driver);

      await manager.initializePush({'app_id': 'test-123'});

      expect(driver.initialized, isTrue);
      expect(driver.initConfig, {'app_id': 'test-123'});
    });

    test('initializePush() logs in user if external ID provided', () async {
      final driver = MockPushDriver();
      manager.setPushDriver(driver);

      await manager.initializePush(
        {'app_id': 'test-123'},
        externalId: 'user-123',
      );

      expect(driver.initialized, isTrue);
      expect(driver.loggedInAs, 'user-123');
    });

    test('requestPushPermission() calls driver', () async {
      final driver = MockPushDriver();
      manager.setPushDriver(driver);
      await manager.initializePush({'app_id': 'test'});

      final result = await manager.requestPushPermission();

      expect(driver.permissionRequested, isTrue);
      expect(result, isTrue);
    });

    test('initializePushWithUserId() throws if no driver configured', () async {
      expect(
        () => manager.initializePushWithUserId('user-123'),
        throwsA(
          isA<NotificationException>().having(
            (e) => e.code,
            'code',
            'PUSH_DRIVER_NOT_CONFIGURED',
          ),
        ),
      );
    });

    test('initializePushWithUserId() logs in user when driver configured',
        () async {
      final driver = MockPushDriver();
      manager.setPushDriver(driver);
      // Initialize the driver first (as boot() would do)
      await driver.initialize({'app_id': 'test'});

      await manager.initializePushWithUserId('user-456');

      expect(driver.loggedInAs, 'user-456');
    });
  });
}

class MockPushDriver extends PushDriver {
  bool initialized = false;
  Map<String, dynamic>? initConfig;
  String? loggedInAs;
  bool permissionRequested = false;

  @override
  String get name => 'mock';
  @override
  bool get isSupported => true;
  @override
  PushPermissionState get permissionState => PushPermissionState.notDetermined;
  @override
  bool get isOptedIn => false;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    initialized = true;
    initConfig = config;
  }

  @override
  Future<void> login(String externalId) async {
    loggedInAs = externalId;
  }

  @override
  Future<void> logout() async {
    loggedInAs = null;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequested = true;
    return true;
  }

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
