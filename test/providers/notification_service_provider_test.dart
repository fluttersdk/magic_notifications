import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  late MagicApp app;
  late NotificationServiceProvider provider;

  setUp(() {
    app = MagicApp.instance;
    // Clear any previous bindings
    app.flush();
    // Clear any previous config
    Config.flush();
    // Clear push driver from manager
    NotificationManager().forgetPushDriver();
    provider = NotificationServiceProvider(app);
    // Auth must be faked so boot() can access Auth.stateNotifier
    Auth.fake();
  });

  tearDown(() {
    Auth.unfake();
  });

  group('NotificationServiceProvider', () {
    test('register() binds manager singleton', () {
      provider.register();

      expect(app.bound('notifications'), isTrue);

      final manager1 = app.make<NotificationManager>('notifications');
      final manager2 = app.make<NotificationManager>('notifications');

      expect(identical(manager1, manager2), isTrue);
    });

    test('boot() completes without error', () async {
      provider.register();

      await expectLater(
        provider.boot(),
        completes,
      );
    });

    test('boot() sets push driver when onesignal is configured', () async {
      // Set up onesignal config
      Config.set('notifications.push.driver', 'onesignal');
      Config.set('notifications.push.app_id', 'test-app-123');

      provider.register();
      await provider.boot();

      final manager = NotificationManager();
      // Should not throw since driver is configured
      expect(() => manager.pushDriver, returnsNormally);
      expect(manager.pushDriver.name, 'onesignal');
    });

    test('boot() does not set push driver when driver is not onesignal',
        () async {
      // Set up different driver
      Config.set('notifications.push.driver', 'fcm');

      provider.register();
      await provider.boot();

      final manager = NotificationManager();
      // Should throw since driver is not configured
      expect(
        () => manager.pushDriver,
        throwsA(isA<NotificationException>()),
      );
    });

    test('boot() does not set push driver when config is empty', () async {
      provider.register();
      await provider.boot();

      final manager = NotificationManager();
      // Should throw since no config
      expect(
        () => manager.pushDriver,
        throwsA(isA<NotificationException>()),
      );
    });
  });

  group('auth auto-attach', () {
    late MockPushDriver driver;

    setUp(() {
      driver = MockPushDriver();
      NotificationManager().setPushDriver(driver);
    });

    tearDown(() {
      Auth.unfake();
    });

    test('listener calls initializePush with prefixed ID on login', () async {
      Auth.fake();

      provider.register();
      await provider.boot();

      await Auth.guard().login({'token': 'tok'}, _makeUser(id: 42));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.loggedInAs, 'user_42');
    });

    test(
        'listener calls requestPushPermission when auto_request_permission is true',
        () async {
      Config.set('notifications.push.auto_request_permission', true);
      Auth.fake();

      provider.register();
      await provider.boot();

      await Auth.guard().login({'token': 'tok'}, _makeUser(id: 1));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.permissionRequested, isTrue);
    });

    test(
        'listener does NOT call requestPushPermission when auto_request_permission is false',
        () async {
      Config.set('notifications.push.auto_request_permission', false);
      Auth.fake();

      provider.register();
      await provider.boot();

      await Auth.guard().login({'token': 'tok'}, _makeUser(id: 1));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.permissionRequested, isFalse);
    });

    test('listener calls logoutPush and stopPolling on logout', () async {
      Auth.fake(user: _makeUser(id: 5));

      provider.register();
      await provider.boot();

      await Auth.logout();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.loggedOut, isTrue);
    });

    test('listener skips re-initialization for same user ID', () async {
      Auth.fake();

      provider.register();
      await provider.boot();

      await Auth.guard().login({'token': 'tok'}, _makeUser(id: 7));
      await Future.delayed(const Duration(milliseconds: 50));

      final firstLoginCount = driver.loginCount;

      // Second login with same user ID — should be skipped
      await Auth.guard().login({'token': 'tok2'}, _makeUser(id: 7));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.loginCount, equals(firstLoginCount));
    });

    test('no listener registered when auto_attach_on_auth is false', () async {
      Config.set('notifications.push.auto_attach_on_auth', false);
      Auth.fake();

      provider.register();
      await provider.boot();

      await Auth.guard().login({'token': 'tok'}, _makeUser(id: 3));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(driver.loggedInAs, isNull);
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

class _TestUser extends Model with HasTimestamps, Authenticatable {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';

  @override
  List<String> get fillable => ['id', 'name', 'email'];
}

_TestUser _makeUser({int id = 1}) {
  final user = _TestUser();
  user.fill({'id': id, 'name': 'Test', 'email': 'test@example.com'});
  user.exists = true;
  return user;
}

// ---------------------------------------------------------------------------
// MockPushDriver
// ---------------------------------------------------------------------------

class MockPushDriver extends PushDriver {
  String? loggedInAs;
  bool permissionRequested = false;
  bool loggedOut = false;
  int loginCount = 0;

  @override
  String get name => 'mock';

  @override
  bool get isSupported => true;

  @override
  PushPermissionState get permissionState => PushPermissionState.notDetermined;

  @override
  bool get isOptedIn => false;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> login(String externalId) async {
    loggedInAs = externalId;
    loginCount++;
  }

  @override
  Future<void> logout() async {
    loggedInAs = null;
    loggedOut = true;
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequested = true;
    return true;
  }

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
}
