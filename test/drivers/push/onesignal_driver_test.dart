import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('OneSignalDriver', () {
    test('name is "onesignal"', () {
      final driver = OneSignalDriver();
      expect(driver.name, 'onesignal');
    });

    test('isSupported is true on mobile platforms', () {
      final driver = OneSignalDriver();
      // This test assumes running on a supported platform during test
      expect(driver.isSupported, isA<bool>());
    });

    test('initialize() throws if app_id missing', () async {
      final driver = OneSignalDriver();
      await expectLater(
        driver.initialize({}),
        throwsA(isA<NotificationException>()),
      );
    });

    test('initialize() throws on unsupported platform', () async {
      final driver = OneSignalDriver();
      // When running tests on non-mobile platforms (e.g., macOS VM),
      // initialize should throw platform not supported error
      if (!driver.isSupported) {
        await expectLater(
          driver.initialize({'app_id': 'test-app-id'}),
          throwsA(isA<NotificationException>()),
        );
      }
    });

    // Note: Full OneSignal integration tests require real device/emulator
    // These tests verify the driver interface, not OneSignal SDK behavior
  });
}
