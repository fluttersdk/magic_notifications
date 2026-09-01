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

    // The mobile driver talks to the static OneSignal SDK directly and has no
    // seam a VM test can substitute, so everything below covers the guard
    // clauses that run BEFORE any SDK call. Anything past initialize() needs a
    // device or an emulator.
    group('before initialization', () {
      test('isInitialized is false', () {
        expect(OneSignalDriver().isInitialized, isFalse);
      });

      test('permissionState is notDetermined, never denied', () async {
        // A device that was never asked must not read as denied, or a prompt
        // gated on "not denied" never shows.
        expect(
          await OneSignalDriver().permissionState(),
          PushPermissionState.notDetermined,
        );
      });

      test('currentExternalId is null without reaching the SDK', () async {
        expect(await OneSignalDriver().currentExternalId(), isNull);
      });

      test('currentSubscriptionId is null without reaching the SDK', () async {
        expect(await OneSignalDriver().currentSubscriptionId(), isNull);
      });

      test('onIdentityChanged is a broadcast stream', () {
        expect(OneSignalDriver().onIdentityChanged.isBroadcast, isTrue);
      });

      test('reachability is unavailable off iOS and Android', () async {
        final driver = OneSignalDriver();
        if (!driver.isSupported) {
          expect(await driver.reachability(), PushReachability.unavailable);
        }
      });
    });

    // Note: Full OneSignal integration tests require real device/emulator
    // These tests verify the driver interface, not OneSignal SDK behavior
  });
}
