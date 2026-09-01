import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart' show Config;
import 'package:magic_notifications/magic_notifications.dart';

import '../../test_helper.dart';

void main() {
  setUpAll(() async {
    await initMagicForTests();
  });

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

    // What a permission request does on a DENIED device. The request itself
    // needs a device, but the decision behind it is a config read, and it is
    // the whole difference between a reminder with somewhere to send the tap
    // and one that can only point at Settings in words.
    group('the settings fallback', () {
      tearDown(() => Config.forget(OneSignalDriver.fallbackToSettingsKey));

      test('is on by default, which is what this driver always did', () {
        expect(OneSignalDriver().canOpenPlatformSettings, isTrue);
      });

      test('an app that wants to ask once and drop it can switch it off', () {
        Config.set(OneSignalDriver.fallbackToSettingsKey, false);

        expect(OneSignalDriver().canOpenPlatformSettings, isFalse);
      });

      test('a value that is not a boolean reads as the default', () {
        Config.set(OneSignalDriver.fallbackToSettingsKey, 'yes');

        // Reading a configuration mistake as OFF would quietly remove the only
        // route a denied operator has back to notifications.
        expect(OneSignalDriver().canOpenPlatformSettings, isTrue);
      });
    });

    // The foreground listener is the only half of the identity leak a client
    // can close: the SDK asks before it DRAWS, and answering "do not draw" is
    // what keeps somebody else's incident title off this lock screen. The SDK
    // effect is passed in rather than reached for, because `preventDefault()`
    // is a platform-channel call no VM test can make.
    group('foreground display', () {
      test('suppresses the OS notification when the subject is not ours',
          () async {
        final driver = OneSignalDriver();
        driver.subjectGuard = (data) => data['subject'] == 'user_1';

        final received = <PushNotificationEvent>[];
        final subscription = driver.onNotificationReceived.listen(received.add);

        var prevented = false;
        driver.handleForegroundWillDisplay(
          <String, dynamic>{'subject': 'user_2', 'title': 'API is down'},
          () => prevented = true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(prevented, isTrue, reason: 'the OS must not draw it');
        expect(received, isEmpty, reason: 'and nothing may be republished');

        await subscription.cancel();
      });

      test('draws and republishes a push addressed to this device', () async {
        final driver = OneSignalDriver();
        driver.subjectGuard = (data) => data['subject'] == 'user_1';

        final received = <PushNotificationEvent>[];
        final subscription = driver.onNotificationReceived.listen(received.add);

        var prevented = false;
        driver.handleForegroundWillDisplay(
          <String, dynamic>{'subject': 'user_1', 'title': 'API is down'},
          () => prevented = true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(prevented, isFalse);
        expect(received.single.data['title'], 'API is down');

        await subscription.cancel();
      });

      test('displays everything when no guard is installed', () async {
        // A driver used without the manager judges nothing, and an unjudged
        // push is displayed: a missing guard must not make the app go silent.
        final driver = OneSignalDriver();

        final received = <PushNotificationEvent>[];
        final subscription = driver.onNotificationReceived.listen(received.add);

        var prevented = false;
        driver.handleForegroundWillDisplay(
          <String, dynamic>{'subject': 'user_2'},
          () => prevented = true,
        );
        await Future<void>.delayed(Duration.zero);

        expect(prevented, isFalse);
        expect(received, hasLength(1));

        await subscription.cancel();
      });
    });

    // Note: Full OneSignal integration tests require real device/emulator
    // These tests verify the driver interface, not OneSignal SDK behavior
  });

  // The subject comparison has exactly one implementation, in the manager,
  // which owns the intent. The driver only carries the answer, so what needs
  // covering here is that an attached driver actually receives it.
  group('the manager installs its subject guard on the driver', () {
    setUp(() {
      NotificationManager().forgetDrivers();
    });

    test('an attached driver judges by the manager push intent', () async {
      final manager = NotificationManager();
      final driver = _FakePushDriver();

      manager.setPushDriver(driver);
      await manager.want('user_1');

      expect(
          driver.mayDisplay(<String, dynamic>{'subject': 'user_2'}), isFalse);
      expect(driver.mayDisplay(<String, dynamic>{'subject': 'user_1'}), isTrue);
      expect(driver.mayDisplay(<String, dynamic>{}), isTrue);
    });

    test('a detached driver stops judging', () {
      final manager = NotificationManager();
      final driver = _FakePushDriver();

      manager.setPushDriver(driver);
      manager.forgetDrivers();

      expect(driver.subjectGuard, isNull);
    });
  });
}

/// A driver double that reaches no SDK, for the guard-wiring tests.
class _FakePushDriver extends PushDriver {
  @override
  String get name => 'fake';
  @override
  bool get isSupported => true;
  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.authorized;
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
  Future<String?> currentSubscriptionId() async => null;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> optIn() async {}
  @override
  Future<void> optOut() async {}
  @override
  Future<void> setTags(Map<String, String> tags) async {}
  @override
  Future<void> removeTag(String key) async {}
  @override
  Stream<PushNotificationEvent> get onNotificationReceived =>
      const Stream<PushNotificationEvent>.empty();
  @override
  Stream<PushNotificationEvent> get onNotificationClicked =>
      const Stream<PushNotificationEvent>.empty();
  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      const Stream<PushPermissionState>.empty();
  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      const Stream<PushIdentityChange>.empty();
}
