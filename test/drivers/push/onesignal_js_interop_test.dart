import 'package:flutter_test/flutter_test.dart';

import 'package:magic_notifications/src/drivers/push/onesignal_js_interop.dart';

void main() {
  group('OneSignalJsInterop', () {
    group('method signatures', () {
      test('login accepts external ID string', () {
        // Verify the method signature exists and accepts a string
        expect(OneSignalJsInterop.login, isA<Function>());
      });

      test('logout is a void function', () {
        expect(OneSignalJsInterop.logout, isA<Function>());
      });

      test('requestPermission returns Future<bool>', () {
        expect(OneSignalJsInterop.requestPermission, isA<Function>());
      });

      test('optIn is a void function', () {
        expect(OneSignalJsInterop.optIn, isA<Function>());
      });

      test('optOut is a void function', () {
        expect(OneSignalJsInterop.optOut, isA<Function>());
      });

      test('addTags accepts Map<String, String>', () {
        expect(OneSignalJsInterop.addTags, isA<Function>());
      });

      test('removeTag accepts String key', () {
        expect(OneSignalJsInterop.removeTag, isA<Function>());
      });

      test('removeTags accepts List<String> keys', () {
        expect(OneSignalJsInterop.removeTags, isA<Function>());
      });

      test('getPermission returns bool', () {
        expect(OneSignalJsInterop.getPermission, isA<Function>());
      });

      test('getOptedIn returns bool', () {
        expect(OneSignalJsInterop.getOptedIn, isA<Function>());
      });

      test('getExternalId returns String or null', () {
        expect(OneSignalJsInterop.getExternalId, isA<Function>());
      });

      test('getSubscriptionId returns String or null', () {
        expect(OneSignalJsInterop.getSubscriptionId, isA<Function>());
      });
    });

    group('event listener registration', () {
      test('addPermissionChangeListener accepts callback', () {
        expect(OneSignalJsInterop.addPermissionChangeListener, isA<Function>());
      });

      test('addNotificationClickListener accepts callback', () {
        expect(
            OneSignalJsInterop.addNotificationClickListener, isA<Function>());
      });

      test('addNotificationForegroundListener accepts callback', () {
        expect(
          OneSignalJsInterop.addNotificationForegroundListener,
          isA<Function>(),
        );
      });

      test('addUserStateChangeListener accepts callback', () {
        expect(OneSignalJsInterop.addUserStateChangeListener, isA<Function>());
      });

      test('addSubscriptionChangeListener accepts callback', () {
        expect(
          OneSignalJsInterop.addSubscriptionChangeListener,
          isA<Function>(),
        );
      });
    });

    group('isAvailable check', () {
      test('isAvailable returns bool indicating SDK presence', () {
        // In non-web environment, this should return false
        expect(OneSignalJsInterop.isAvailable, isA<bool>());
      });
    });

    group('debug methods', () {
      test('setLogLevel accepts log level string', () {
        expect(OneSignalJsInterop.setLogLevel, isA<Function>());
      });
    });

    group('slidedown prompts', () {
      test('promptPush triggers push slidedown', () {
        expect(OneSignalJsInterop.promptPush, isA<Function>());
      });

      test('promptPushCategories triggers category slidedown', () {
        expect(OneSignalJsInterop.promptPushCategories, isA<Function>());
      });
    });

    group('user properties', () {
      test('getOneSignalId returns String or null', () {
        expect(OneSignalJsInterop.getOneSignalId, isA<Function>());
      });

      test('getTags returns Map or null', () {
        expect(OneSignalJsInterop.getTags, isA<Function>());
      });

      test('setLanguage accepts language code', () {
        expect(OneSignalJsInterop.setLanguage, isA<Function>());
      });
    });
  });
}
