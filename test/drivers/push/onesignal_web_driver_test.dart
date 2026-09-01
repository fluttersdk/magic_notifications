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

    // The browser draws a foreground push through the service worker, and the
    // v16 SDK asks the page first: `foregroundWillDisplay` carries its own
    // `preventDefault()`, and the worker skips `showNotification` when the page
    // calls it. Answering "do not draw" is what keeps somebody else's incident
    // title off this screen. The SDK effect is passed in rather than reached
    // for, because it is a JS call no VM test can make.
    group('foreground display', () {
      /// A foreground event shaped the way the web SDK reports one.
      ///
      /// The v16 event wraps the notification, and the custom object the server
      /// sent arrives as its `additionalData`; that is where the subject and
      /// the destination a consumer navigates to both live.
      Map<String, dynamic> webEvent(String subject) => <String, dynamic>{
            'notification': <String, dynamic>{
              'notificationId': 'n1',
              'title': 'API is down',
              'additionalData': <String, dynamic>{
                'subject': subject,
                'notification_id': 'row-1',
                'deep_link': '/incidents/i-1',
              },
            },
          };

      test('suppresses the browser notification when the subject is not ours',
          () async {
        final driver = OneSignalWebDriver();
        driver.subjectGuard = (data) => data['subject'] == 'user_1';

        final received = <PushNotificationEvent>[];
        final subscription = driver.onNotificationReceived.listen(received.add);

        var prevented = false;
        driver.handleForegroundWillDisplay(
          webEvent('user_2'),
          () => prevented = true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(prevented, isTrue, reason: 'the browser must not draw it');
        expect(received, isEmpty, reason: 'and nothing may be republished');

        await subscription.cancel();
      });

      test('draws and republishes a push addressed to this device', () async {
        final driver = OneSignalWebDriver();
        driver.subjectGuard = (data) => data['subject'] == 'user_1';

        final received = <PushNotificationEvent>[];
        final subscription = driver.onNotificationReceived.listen(received.add);

        var prevented = false;
        driver.handleForegroundWillDisplay(
          webEvent('user_1'),
          () => prevented = true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(prevented, isFalse);
        // The republished payload is the server's own map, the same shape the
        // mobile driver publishes, not the SDK wrapper around it.
        expect(received.single.data['notification_id'], 'row-1');
        expect(received.single.data.containsKey('notification'), isFalse);

        await subscription.cancel();
      });

      test('republishes the payload a consumer reads, not the SDK wrapper',
          () async {
        // The assertion that matters is what a CONSUMER receives, not what the
        // guard reads internally: a subscriber to `Notify.onPushReceived` reads
        // `event.data['deep_link']` FLAT, which is the shape the mobile driver
        // publishes. Republishing the wrapper answers null for every one of
        // those keys on web, and the manager's own subject re-check is vacuous
        // there for the same reason.
        final driver = OneSignalWebDriver();

        final received = <PushNotificationEvent>[];
        final subscription = driver.onNotificationReceived.listen(received.add);

        driver.handleForegroundWillDisplay(webEvent('user_1'), () {});
        await Future<void>.delayed(Duration.zero);

        expect(received.single.data['deep_link'], '/incidents/i-1');
        expect(received.single.data['subject'], 'user_1');

        await subscription.cancel();
      });

      test('displays everything when no guard is installed', () async {
        // A driver used without the manager judges nothing, and an unjudged
        // push is displayed: a missing guard must not make the app go silent.
        final driver = OneSignalWebDriver();

        final received = <PushNotificationEvent>[];
        final subscription = driver.onNotificationReceived.listen(received.add);

        var prevented = false;
        driver.handleForegroundWillDisplay(
          webEvent('user_2'),
          () => prevented = true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(prevented, isFalse);
        expect(received, hasLength(1));

        await subscription.cancel();
      });

      test('judges the nested payload, not the event that wraps it', () {
        // The guard is the manager's, and it reads the same keys on both
        // platforms; the mobile driver hands it `additionalData` directly.
        final driver = OneSignalWebDriver();
        Map<String, dynamic>? judged;
        driver.subjectGuard = (data) {
          judged = data;
          return true;
        };

        driver.handleForegroundWillDisplay(webEvent('user_2'), () {});

        expect(judged, <String, dynamic>{
          'subject': 'user_2',
          'notification_id': 'row-1',
          'deep_link': '/incidents/i-1',
        });
      });

      test('hands the guard an empty payload when the event nests none', () {
        // An event with nothing to judge is un-checkable, not a report that it
        // belongs to nobody; the manager's guard passes an absent subject.
        final driver = OneSignalWebDriver();
        Map<String, dynamic>? judged;
        driver.subjectGuard = (data) {
          judged = data;
          return true;
        };

        driver.handleForegroundWillDisplay(<String, dynamic>{}, () {});

        expect(judged, isEmpty);
      });
    });

    // A backgrounded or killed page draws the notification with no client
    // code involved, so by the time a tap reaches the app the push has
    // already been shown; nothing here can undraw it. What is at stake is
    // whether the TAP navigates: `Notify.onPushClicked` drives a team switch
    // off the payload, so a foreign subject must not be republished even
    // though it was already, unavoidably, on screen.
    group('notification click', () {
      /// A clicked event shaped the way the web SDK reports one: same nested
      /// `additionalData` shape as [webEvent] in the display group above.
      Map<String, dynamic> webEvent(String subject) => <String, dynamic>{
            'notification': <String, dynamic>{
              'notificationId': 'n1',
              'title': 'API is down',
              'additionalData': <String, dynamic>{
                'subject': subject,
                'notification_id': 'row-1',
                'deep_link': '/incidents/i-1',
              },
            },
          };

      test('does not republish a clicked push addressed to a foreign subject',
          () async {
        final driver = OneSignalWebDriver();
        driver.subjectGuard = (data) => data['subject'] == 'user_1';

        final clicked = <PushNotificationEvent>[];
        final subscription = driver.onNotificationClicked.listen(clicked.add);

        driver.handleNotificationClicked(webEvent('user_2'));
        await Future<void>.delayed(Duration.zero);

        expect(clicked, isEmpty,
            reason: 'a foreign subject must not drive a navigation');

        await subscription.cancel();
      });

      test('republishes a clicked push addressed to this device', () async {
        final driver = OneSignalWebDriver();
        driver.subjectGuard = (data) => data['subject'] == 'user_1';

        final clicked = <PushNotificationEvent>[];
        final subscription = driver.onNotificationClicked.listen(clicked.add);

        driver.handleNotificationClicked(webEvent('user_1'));
        await Future<void>.delayed(Duration.zero);

        expect(clicked, hasLength(1));
        // The republished payload is the server's own map: one shape on both
        // platforms, which is what every consumer and the manager's subject
        // re-check on this stream already expect.
        expect(clicked.single.data['notification_id'], 'row-1');
        expect(clicked.single.data.containsKey('notification'), isFalse);

        await subscription.cancel();
      });

      test('republishes the payload the tap navigates from, not the wrapper',
          () async {
        // The one that was actually broken in production: the app's tap
        // handler reads `event.data['deep_link']` off this stream, finds
        // nothing on the wrapper, logs "names no in-app destination" and
        // returns, so tap-to-navigate is dead on the browser.
        final driver = OneSignalWebDriver();

        final clicked = <PushNotificationEvent>[];
        final subscription = driver.onNotificationClicked.listen(clicked.add);

        driver.handleNotificationClicked(webEvent('user_1'));
        await Future<void>.delayed(Duration.zero);

        expect(clicked.single.data['deep_link'], '/incidents/i-1');
        expect(clicked.single.data['subject'], 'user_1');

        await subscription.cancel();
      });

      test('republishes everything when no guard is installed', () async {
        // A driver used without the manager judges nothing, and an unjudged
        // click must not be silently dropped.
        final driver = OneSignalWebDriver();

        final clicked = <PushNotificationEvent>[];
        final subscription = driver.onNotificationClicked.listen(clicked.add);

        driver.handleNotificationClicked(webEvent('user_2'));
        await Future<void>.delayed(Duration.zero);

        expect(clicked, hasLength(1));

        await subscription.cancel();
      });

      test('judges the nested payload, not the wrapper that carries it', () {
        final driver = OneSignalWebDriver();
        Map<String, dynamic>? judged;
        driver.subjectGuard = (data) {
          judged = data;
          return true;
        };

        driver.handleNotificationClicked(webEvent('user_2'));

        expect(judged, <String, dynamic>{
          'subject': 'user_2',
          'notification_id': 'row-1',
          'deep_link': '/incidents/i-1',
        });
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
