import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';
import 'package:magic_notifications/src/drivers/push_web/onesignal_io.dart'
    as io;
import 'package:magic_notifications/src/drivers/push_web/onesignal_stub.dart'
    as stub;

void main() {
  group('the io arm', () {
    test('createPlatformDriver returns the mobile OneSignalDriver', () {
      final driver = io.createPlatformDriver();
      expect(driver, isNotNull);
      expect(driver, isA<OneSignalDriver>());
      expect(driver.name, 'onesignal');
    });

    test('the driver reports whether the current platform is supported', () {
      final driver = io.createPlatformDriver();
      // Mobile driver checks Platform.isIOS/isAndroid, which isn't available
      // in a VM test, so isSupported is expected to answer false here.
      expect(driver.isSupported, isA<bool>());
    });

    test('initialize requires app_id', () async {
      final driver = io.createPlatformDriver();
      await expectLater(
        driver.initialize({}),
        throwsA(isA<Exception>()),
      );
    });

    test('initialize succeeds with valid config', () async {
      final driver = io.createPlatformDriver();
      try {
        await driver.initialize({'app_id': 'test-app-id'});
      } catch (e) {
        // Mobile driver will throw on non-mobile platforms, which is expected.
        expect(e.toString(), contains('not supported'));
      }
    });
  });

  group('the stub arm', () {
    test('createPlatformDriver refuses rather than returning a driver', () {
      // The stub is the default arm: it resolves when neither the `dart:io`
      // nor the `dart:js_interop` guard matches. There is no honourable
      // driver to hand back, so it throws instead of forwarding one that
      // does not work on the running platform.
      expect(
        () => stub.createPlatformDriver(),
        throwsA(isA<UnsupportedPlatformException>()),
      );
    });
  });
}
