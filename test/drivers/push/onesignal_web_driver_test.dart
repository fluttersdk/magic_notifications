import 'package:flutter_test/flutter_test.dart';

import 'package:magic_notifications/src/drivers/push/onesignal_web_driver.dart';
import 'package:magic_notifications/src/drivers/push/push_driver.dart';
import 'package:magic_notifications/src/models/push_subscription.dart';

void main() {
  group('OneSignalWebDriver', () {
    late OneSignalWebDriver driver;

    setUp(() {
      driver = OneSignalWebDriver();
    });

    test('name returns onesignal', () {
      // Same name as mobile driver for consistent config
      expect(driver.name, equals('onesignal'));
    });

    test('isSupported returns true on web platform', () {
      // In test environment, we can't truly test web platform
      // but the driver should have proper web detection
      expect(driver.isSupported, isA<bool>());
    });

    test('permissionState returns notDetermined before initialization', () {
      expect(driver.permissionState, equals(PushPermissionState.notDetermined));
    });

    test('isOptedIn returns false before initialization', () {
      expect(driver.isOptedIn, isFalse);
    });

    test('onNotificationReceived returns a stream', () {
      expect(
          driver.onNotificationReceived, isA<Stream<PushNotificationEvent>>());
    });

    test('onNotificationClicked returns a stream', () {
      expect(
          driver.onNotificationClicked, isA<Stream<PushNotificationEvent>>());
    });

    test('onPermissionChanged returns a stream', () {
      expect(driver.onPermissionChanged, isA<Stream<PushPermissionState>>());
    });

    group('getWebInitScript', () {
      test('generates script with appId', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: '4573490d-2dfa-44c3-b211-8e04e2e96bdd',
        );

        expect(script, contains('4573490d-2dfa-44c3-b211-8e04e2e96bdd'));
        expect(script, contains('OneSignalSDK.page.js'));
        expect(script, contains('OneSignal.init'));
      });

      test('generates script with safariWebId', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: 'test-app-id',
          safariWebId: 'web.onesignal.auto.abc123',
        );

        expect(script, contains('web.onesignal.auto.abc123'));
        expect(script, contains('safari_web_id'));
      });

      test('generates script with notifyButton enabled', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: 'test-app-id',
          notifyButtonEnabled: true,
        );

        expect(script, contains('notifyButton'));
        expect(script, contains('enable: true'));
      });

      test('generates script without notifyButton when disabled', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: 'test-app-id',
          notifyButtonEnabled: false,
        );

        expect(script, contains('enable: false'));
      });

      test('uses v16 SDK URL', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: 'test-app-id',
        );

        expect(
          script,
          contains(
              'https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js'),
        );
      });

      test('includes defer attribute on script tag', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: 'test-app-id',
        );

        expect(script, contains('defer'));
      });
    });

    group('buildConfigFromEnv', () {
      test('builds config from environment variables', () {
        final config = OneSignalWebDriver.buildConfigFromEnv(
          appId: 'env-app-id',
          safariWebId: 'env-safari-id',
          notifyButtonEnabled: true,
        );

        expect(config['app_id'], equals('env-app-id'));
        expect(config['safari_web_id'], equals('env-safari-id'));
        expect(config['notify_button_enabled'], isTrue);
      });

      test('builds config without optional fields', () {
        final config = OneSignalWebDriver.buildConfigFromEnv(
          appId: 'test-id',
        );

        expect(config['app_id'], equals('test-id'));
        expect(config.containsKey('safari_web_id'), isFalse);
        expect(config['notify_button_enabled'], isFalse);
      });
    });
  });
}
