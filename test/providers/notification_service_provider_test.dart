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
}
