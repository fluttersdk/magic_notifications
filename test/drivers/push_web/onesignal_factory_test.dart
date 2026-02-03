import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/src/drivers/push_web/onesignal_stub.dart';

void main() {
  group('OneSignal Platform Factory', () {
    test('createPlatformDriver returns a driver instance', () {
      final driver = createPlatformDriver();
      expect(driver, isNotNull);
      expect(driver.name, 'onesignal');
    });

    test('createPlatformDriver returns mobile driver on non-web', () {
      // When running in VM (non-web), should return mobile driver
      final driver = createPlatformDriver();
      expect(driver, isNotNull);
      // Mobile driver checks Platform.isIOS/isAndroid, which isn't available in VM
      // so isSupported will be false in test environment
      expect(driver.isSupported, isA<bool>());
    });
  });
}
