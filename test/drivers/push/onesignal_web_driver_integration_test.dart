import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';

import 'package:fluttersdk_magic_notifications/src/drivers/push/onesignal_web_driver.dart';
import 'package:fluttersdk_magic_notifications/src/drivers/push/push_driver.dart';
import 'package:fluttersdk_magic_notifications/src/models/push_subscription.dart';

void main() {
  group('OneSignalWebDriver Integration', () {
    late OneSignalWebDriver driver;

    setUp(() {
      driver = OneSignalWebDriver();
    });

    tearDown(() {
      driver.dispose();
    });

    group('isSupported', () {
      test('returns true only on web platform', () {
        expect(driver.isSupported, equals(kIsWeb));
      });
    });

    group('name', () {
      test('returns onesignal', () {
        // Same name as mobile driver for consistent config
        expect(driver.name, equals('onesignal'));
      });
    });

    group('login (non-web)', () {
      test('throws NotInitializedException when not initialized', () async {
        expect(
          () => driver.login('user-123'),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('logout (non-web)', () {
      test('does nothing when not initialized', () async {
        // Should not throw even when not initialized
        await driver.logout();
        expect(true, isTrue);
      });
    });

    group('requestPermission (non-web)', () {
      test('throws NotInitializedException when not initialized', () async {
        expect(
          () => driver.requestPermission(),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('streams', () {
      test('onNotificationReceived returns a stream', () {
        expect(driver.onNotificationReceived,
            isA<Stream<PushNotificationEvent>>());
      });

      test('onNotificationClicked returns a stream', () {
        expect(
            driver.onNotificationClicked, isA<Stream<PushNotificationEvent>>());
      });

      test('onPermissionChanged returns a stream', () {
        expect(driver.onPermissionChanged, isA<Stream<PushPermissionState>>());
      });
    });

    group('default state before initialization', () {
      test('permissionState is notDetermined', () {
        expect(
            driver.permissionState, equals(PushPermissionState.notDetermined));
      });

      test('isOptedIn is false', () {
        expect(driver.isOptedIn, isFalse);
      });

      test('subscriptionId is null', () {
        expect(driver.subscriptionId, isNull);
      });

      test('externalId is null', () {
        expect(driver.externalId, isNull);
      });

      test('oneSignalId is null', () {
        expect(driver.oneSignalId, isNull);
      });
    });

    // Web-only tests should be run with: flutter test --platform chrome
    group('web platform tests', () {
      test('initialize throws on non-web platform', () async {
        if (!kIsWeb) {
          expect(
            () => driver.initialize({'app_id': 'test-app-id'}),
            throwsA(isA<Exception>()),
          );
        }
      }, skip: kIsWeb ? 'This test only runs on non-web platforms' : null);
    });
  });
}
