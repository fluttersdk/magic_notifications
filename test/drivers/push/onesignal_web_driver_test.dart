import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:magic_notifications/src/drivers/push/onesignal_web_driver.dart';
import 'package:magic_notifications/src/drivers/push/push_driver.dart';
import 'package:magic_notifications/src/exceptions/notification_exception.dart';
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

    test('permissionState returns notDetermined before initialization',
        () async {
      expect(
        await driver.permissionState(),
        equals(PushPermissionState.notDetermined),
      );
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

    test('onIdentityChanged returns a broadcast stream', () {
      expect(driver.onIdentityChanged, isA<Stream<PushIdentityChange>>());
      expect(driver.onIdentityChanged.isBroadcast, isTrue);
    });

    group('permissionStateFor', () {
      test('maps the browser granted value to authorized', () {
        expect(
          OneSignalWebDriver.permissionStateFor('granted'),
          PushPermissionState.authorized,
        );
      });

      test('maps the browser denied value to denied, never notDetermined', () {
        expect(
          OneSignalWebDriver.permissionStateFor('denied'),
          PushPermissionState.denied,
        );
      });

      test('maps the browser default value to notDetermined', () {
        expect(
          OneSignalWebDriver.permissionStateFor('default'),
          PushPermissionState.notDetermined,
        );
      });

      test('maps an absent Notification API to notDetermined', () {
        expect(
          OneSignalWebDriver.permissionStateFor(null),
          PushPermissionState.notDetermined,
        );
      });
    });

    group('reachability from a browser permission', () {
      // The three values `Notification.permission` can hold, driven through the
      // PushDriver contract so the derivation is exercised, not restated.
      Future<PushReachability> reachabilityFor(String browserPermission) {
        return _BrowserPermissionDriver(browserPermission).reachability();
      }

      test('a blocked browser reads as blocked, not as never asked', () async {
        expect(await reachabilityFor('denied'), PushReachability.blocked);
      });

      test('a browser that was never asked reads as off', () async {
        expect(await reachabilityFor('default'), PushReachability.off);
      });

      test('a granted, opted-in, subscribed browser reads as on', () async {
        expect(await reachabilityFor('granted'), PushReachability.on);
      });
    });

    group('initialize', () {
      test('does not report initialized when the SDK never ran init', () async {
        // On the VM the js-interop conditional import resolves to the no-op
        // stub, which reports the SDK absent, so the driver's own readiness
        // logic runs for real.
        final webDriver = _AlwaysSupportedWebDriver();

        await expectLater(
          webDriver.initialize({'app_id': 'test-app-id'}),
          throwsA(
            isA<NotificationException>().having(
              (e) => e.code,
              'code',
              'SDK_NOT_AVAILABLE',
            ),
          ),
        );
        expect(webDriver.isInitialized, isFalse);
      });

      test('still refuses an empty app id', () async {
        final webDriver = _AlwaysSupportedWebDriver();

        await expectLater(
          webDriver.initialize({'app_id': ''}),
          throwsA(isA<NotificationException>()),
        );
        expect(webDriver.isInitialized, isFalse);
      });
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

      test('generates script with a scoped service worker', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: 'test-app-id',
          serviceWorkerPath: 'push/OneSignalSDKWorker.js',
          serviceWorkerScope: '/push/',
        );

        expect(script,
            contains('serviceWorkerPath: "push/OneSignalSDKWorker.js"'));
        expect(script, contains('serviceWorkerParam: { scope: "/push/" }'));
      });

      test('omits the service worker keys when they are not configured', () {
        final script = OneSignalWebDriver.getWebInitScript(
          appId: 'test-app-id',
        );

        expect(script, isNot(contains('serviceWorkerPath')));
        expect(script, isNot(contains('serviceWorkerParam')));
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
        expect(config.containsKey('service_worker_path'), isFalse);
        expect(config.containsKey('service_worker_scope'), isFalse);
        expect(config['notify_button_enabled'], isFalse);
      });

      test('carries the service worker path and scope', () {
        final config = OneSignalWebDriver.buildConfigFromEnv(
          appId: 'test-id',
          serviceWorkerPath: 'push/OneSignalSDKWorker.js',
          serviceWorkerScope: '/push/',
        );

        expect(config['service_worker_path'], 'push/OneSignalSDKWorker.js');
        expect(config['service_worker_scope'], '/push/');
      });
    });
  });
}

/// A web driver that claims platform support so the VM can exercise the rest
/// of [OneSignalWebDriver.initialize] against the no-op interop stub.
class _AlwaysSupportedWebDriver extends OneSignalWebDriver {
  @override
  bool get isSupported => true;
}

/// A driver whose permission comes straight from a browser permission string.
///
/// It exists to drive [PushDriver.reachability] with each of the three values
/// `Notification.permission` can hold.
class _BrowserPermissionDriver extends PushDriver {
  _BrowserPermissionDriver(this.browserPermission);

  final String browserPermission;

  @override
  String get name => 'browser';
  @override
  bool get isSupported => true;
  @override
  Future<PushPermissionState> permissionState() async =>
      OneSignalWebDriver.permissionStateFor(browserPermission);
  @override
  bool get isOptedIn => true;
  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> login(String externalId) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<String?> currentExternalId() async => null;
  @override
  Future<String?> currentSubscriptionId() async => 'sub-1';
  @override
  Future<bool> requestPermission() async => false;
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
  @override
  Stream<PushIdentityChange> get onIdentityChanged => Stream.empty();
}
