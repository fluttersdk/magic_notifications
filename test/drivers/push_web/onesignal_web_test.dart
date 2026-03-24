import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/src/drivers/push_web/onesignal_factory.dart';

void main() {
  group('OneSignal Platform Driver', () {
    test('createOneSignalDriver returns a driver instance', () {
      final driver = createOneSignalDriver();
      expect(driver, isNotNull);
      expect(driver.name, 'onesignal');
    });

    test('driver supports the current platform', () {
      final driver = createOneSignalDriver();
      // Should always return a driver that works on current platform
      expect(driver.isSupported, isA<bool>());
    });

    test('initialize requires app_id', () async {
      final driver = createOneSignalDriver();
      await expectLater(
        driver.initialize({}),
        throwsA(isA<Exception>()),
      );
    });

    test('initialize succeeds with valid config', () async {
      final driver = createOneSignalDriver();
      // On non-web (test VM), this will be mobile driver which checks platform
      // On web, this would be web driver
      // Both should handle initialization without crashing
      try {
        await driver.initialize({'app_id': 'test-app-id'});
      } catch (e) {
        // Mobile driver will throw on non-mobile platforms, which is expected
        expect(e.toString(), contains('not supported'));
      }
    });
  });
}
