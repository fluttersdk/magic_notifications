import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/drivers/push/push_driver.dart';
import 'package:magic_notifications/src/exceptions/notification_exception.dart';
import 'package:magic_notifications/src/models/push_subscription.dart';
import 'package:magic_notifications/src/notification_manager.dart';
import 'package:magic_notifications/src/providers/notification_service_provider.dart';

import '../test_helper.dart';

void main() {
  late MagicApp app;
  late FakeLogManager log;
  late NotificationServiceProvider provider;

  setUpAll(() async {
    await initMagicForTests();
  });

  setUp(() {
    app = MagicApp.instance;
    app.flush();
    Config.flush();
    // The manager is a `static final` that outlives a container flush, so its
    // channels, driver registry and push intent have to be dropped by hand.
    NotificationManager().forgetDrivers();
    // Bound AFTER the flush, which would otherwise drop it.
    log = Log.fake();
    provider = NotificationServiceProvider(app);
  });

  group('NotificationServiceProvider', () {
    test('register() binds manager singleton', () {
      provider.register();

      expect(app.bound('notifications'), isTrue);

      final manager1 = app.make<NotificationManager>('notifications');
      final manager2 = app.make<NotificationManager>('notifications');

      expect(identical(manager1, manager2), isTrue);
    });

    test('boot() resolves the manager through the container', () async {
      // No register(), so the container is empty. Resolving the singleton
      // directly would boot happily against a binding no consumer can reach;
      // going through the container turns that into magic's own diagnostic.
      await expectLater(
        provider.boot(),
        throwsA(
          isA<Exception>().having(
            (Exception e) => e.toString(),
            'message',
            contains('[notifications] is not registered'),
          ),
        ),
      );
    });

    test(
        'boot() reports an unservable driver value and does not degrade '
        'silently', () async {
      Config.set('notifications.push.driver', 'fcm');

      provider.register();
      await provider.boot();

      final List<FakeLogEntry> errors =
          log.entries.where((FakeLogEntry e) => e.level == 'error').toList();

      expect(errors, isNotEmpty);
      expect(errors.first.message, contains('fcm'));
      expect(errors.first.message, contains('Notify.extend'));
      expect(
        () => app.make<NotificationManager>('notifications').pushDriver,
        throwsA(isA<NotificationException>()),
      );
    });

    test('boot() stays quiet when the driver key is absent', () async {
      provider.register();
      await provider.boot();

      // The other half of the pair above: the same spy caught the wrong value,
      // so an empty error log here is a real answer rather than a spy that
      // could never have seen anything.
      log.assertNothingLogged('error');
      expect(
        () => app.make<NotificationManager>('notifications').pushDriver,
        throwsA(isA<NotificationException>()),
      );
    });

    test('boot() resolves the driver through the manager registry', () async {
      provider.register();

      final NotificationManager manager =
          app.make<NotificationManager>('notifications');
      final _RecordingPushDriver driver = _RecordingPushDriver();
      manager.extend('onesignal', () => driver);

      Config.set('notifications.push.driver', 'onesignal');
      Config.set('notifications.push.app_id', 'test-app-123');

      await provider.boot();

      // A registered factory is reached, so the built-in and an override travel
      // one path.
      expect(identical(manager.pushDriver, driver), isTrue);
      expect(driver.initConfig?['app_id'], 'test-app-123');
      expect(NotificationServiceProvider.pushInitializationError, isNull);
      log.assertNothingLogged('error');
    });

    test('boot() registers both channels when push is configured', () async {
      provider.register();

      final NotificationManager manager =
          app.make<NotificationManager>('notifications');
      manager.extend('onesignal', () => _RecordingPushDriver());

      Config.set('notifications.push.driver', 'onesignal');
      Config.set('notifications.push.app_id', 'test-app-123');

      await provider.boot();

      expect(manager.hasChannel('database'), isTrue);
      expect(manager.hasChannel('push'), isTrue);
    });

    test('boot() registers the database channel with no push driver', () async {
      provider.register();
      await provider.boot();

      final NotificationManager manager =
          app.make<NotificationManager>('notifications');

      expect(manager.hasChannel('database'), isTrue);
      expect(manager.hasChannel('push'), isFalse);
    });

    test('boot() records an initialisation failure rather than swallowing it',
        () async {
      provider.register();

      final NotificationManager manager =
          app.make<NotificationManager>('notifications');
      final _RecordingPushDriver driver = _RecordingPushDriver()
        ..initializeError = StateError('the SDK refused');
      manager.extend('onesignal', () => driver);

      Config.set('notifications.push.driver', 'onesignal');
      Config.set('notifications.push.app_id', 'test-app-123');

      await expectLater(provider.boot(), completes);

      // Readable afterwards, not only logged: a broken push setup has to be
      // distinguishable from an absent one.
      expect(
        NotificationServiceProvider.pushInitializationError,
        isA<StateError>(),
      );
      expect(
        log.entries.where((FakeLogEntry e) => e.level == 'error'),
        isNotEmpty,
      );
      // And it keeps degrading rather than aborting the boot.
      expect(manager.hasChannel('push'), isTrue);
    });

    test('boot() does not report a platform that cannot carry push', () async {
      provider.register();

      final NotificationManager manager = app.make<NotificationManager>(
        'notifications',
      );
      final _RecordingPushDriver driver = _RecordingPushDriver()
        ..supported = false;
      manager.extend('onesignal', () => driver);

      Config.set('notifications.push.driver', 'onesignal');
      Config.set('notifications.push.app_id', 'test-app-123');

      await provider.boot();

      // An unsupported platform is an ABSENT capability, not a broken setup, so
      // it stays as quiet as an absent config key.
      expect(driver.calls, isNot(contains('initialize')));
      expect(NotificationServiceProvider.pushInitializationError, isNull);
      log.assertNothingLogged('error');
    });

    test('boot() drives one reconcile so the signed-out cold boot is covered',
        () async {
      provider.register();

      final NotificationManager manager =
          app.make<NotificationManager>('notifications');
      final _RecordingPushDriver driver = _RecordingPushDriver();
      manager.extend('onesignal', () => driver);

      Config.set('notifications.push.driver', 'onesignal');
      Config.set('notifications.push.app_id', 'test-app-123');

      await provider.boot();

      // A signed-out cold boot bumps no auth notifier at all, so the boot pass
      // is the only thing that reads the device back.
      expect(driver.calls, contains('currentExternalId'));
      expect(manager.isPushIdentityConverged, isTrue);
      // Nobody wanted, and the device carries nobody, so the SDK is untouched.
      expect(driver.calls, isNot(contains('logout')));
      expect(driver.calls, isNot(contains('login')));
    });
  });
}

/// A [PushDriver] double that records the ORDER of the calls it received.
///
/// A boolean per call would pass for an implementation that reconciled before
/// it initialized, which is the failure this step's boot sequence has to avoid.
class _RecordingPushDriver extends PushDriver {
  /// Every call this driver saw, in arrival order.
  final List<String> calls = <String>[];

  /// The config [initialize] was handed, so a test can prove the provider read
  /// the package's own config keys.
  Map<String, dynamic>? initConfig;

  /// When set, [initialize] throws it.
  Object? initializeError;

  /// The external id the device is subscribed as.
  String? externalId;

  /// Whether this build can carry push at all.
  bool supported = true;

  @override
  String get name => 'onesignal';

  @override
  bool get isSupported => supported;

  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.notDetermined;

  @override
  bool get isOptedIn => false;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    calls.add('initialize');
    initConfig = config;

    final Object? failure = initializeError;
    if (failure != null) throw failure;
  }

  @override
  Future<void> login(String id) async {
    calls.add('login');
    externalId = id;
  }

  @override
  Future<void> logout() async {
    calls.add('logout');
    externalId = null;
  }

  @override
  Future<String?> currentExternalId() async {
    calls.add('currentExternalId');

    return externalId;
  }

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
