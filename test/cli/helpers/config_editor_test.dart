import 'dart:io';
import 'package:test/test.dart';
import 'package:fluttersdk_magic_notifications/src/cli/cli.dart';

void main() {
  group('NotificationConfigHelper', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('config_helper_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('createNotificationConfig creates config file', () {
      final configPath = '${tempDir.path}/lib/config/notifications.dart';

      NotificationConfigHelper.createNotificationConfig(
        configPath: configPath,
        oneSignalAppId: 'test-app-id',
        softPromptEnabled: true,
      );

      expect(File(configPath).existsSync(), isTrue);
      final content = File(configPath).readAsStringSync();
      expect(content, contains('test-app-id'));
      expect(content, contains("'enabled': true"));
    });

    test('createNotificationConfig includes all required sections', () {
      final configPath = '${tempDir.path}/lib/config/notifications.dart';

      NotificationConfigHelper.createNotificationConfig(
        configPath: configPath,
        oneSignalAppId: 'abc-123',
        softPromptEnabled: false,
      );

      final content = File(configPath).readAsStringSync();
      expect(content, contains("'push'"));
      expect(content, contains("'database'"));
      expect(content, contains("'mail'"));
      expect(content, contains("'soft_prompt'"));
      expect(content, contains("'enabled': false"));
    });

    test('updateMainDart adds import and configFactory entry', () {
      final mainPath = '${tempDir.path}/lib/main.dart';
      File(mainPath).createSync(recursive: true);
      File(mainPath).writeAsStringSync('''
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
  runApp(MyApp());
}
''');

      NotificationConfigHelper.updateMainDart(
        mainPath: mainPath,
        addImports: ["import 'config/notifications.dart';"],
        configFactoryEntry: '() => notificationConfig',
      );

      final content = File(mainPath).readAsStringSync();
      expect(content, contains("import 'config/notifications.dart'"));
      expect(content, contains('() => notificationConfig'));
    });

    test('updateMainDart does not duplicate configFactory entry', () {
      final mainPath = '${tempDir.path}/lib/main.dart';
      File(mainPath).createSync(recursive: true);
      File(mainPath).writeAsStringSync('''
import 'package:flutter/material.dart';
import 'config/notifications.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationConfig,
    ],
  );
  runApp(MyApp());
}
''');

      NotificationConfigHelper.updateMainDart(
        mainPath: mainPath,
        addImports: ["import 'config/notifications.dart';"],
        configFactoryEntry: '() => notificationConfig',
      );

      final content = File(mainPath).readAsStringSync();
      // Count occurrences - should only have 1
      final matches = '() => notificationConfig'.allMatches(content).length;
      expect(matches, equals(1));
    });

    test('createNotificationConfig uses getter pattern with notifications key',
        () {
      final configPath = '${tempDir.path}/lib/config/notifications.dart';

      NotificationConfigHelper.createNotificationConfig(
        configPath: configPath,
        oneSignalAppId: 'test-id',
        softPromptEnabled: true,
      );

      final content = File(configPath).readAsStringSync();
      expect(content, contains('Map<String, dynamic> get notificationConfig'));
      expect(content, contains("'notifications':"));
    });

    group('Web config options', () {
      test('createNotificationConfig includes safari_web_id when provided', () {
        final configPath = '${tempDir.path}/lib/config/notifications.dart';

        NotificationConfigHelper.createNotificationConfig(
          configPath: configPath,
          oneSignalAppId: 'test-app-id',
          softPromptEnabled: true,
          safariWebId: 'web.onesignal.auto.abc123',
        );

        final content = File(configPath).readAsStringSync();
        expect(content, contains("'safari_web_id'"));
        expect(content, contains('web.onesignal.auto.abc123'));
      });

      test('createNotificationConfig omits safari_web_id when null', () {
        final configPath = '${tempDir.path}/lib/config/notifications.dart';

        NotificationConfigHelper.createNotificationConfig(
          configPath: configPath,
          oneSignalAppId: 'test-app-id',
          softPromptEnabled: true,
        );

        final content = File(configPath).readAsStringSync();
        expect(content, isNot(contains("'safari_web_id'")));
      });

      test('createNotificationConfig includes notify_button_enabled true', () {
        final configPath = '${tempDir.path}/lib/config/notifications.dart';

        NotificationConfigHelper.createNotificationConfig(
          configPath: configPath,
          oneSignalAppId: 'test-app-id',
          softPromptEnabled: true,
          notifyButtonEnabled: true,
        );

        final content = File(configPath).readAsStringSync();
        expect(content, contains("'notify_button_enabled': true"));
      });

      test(
          'createNotificationConfig includes notify_button_enabled false by default',
          () {
        final configPath = '${tempDir.path}/lib/config/notifications.dart';

        NotificationConfigHelper.createNotificationConfig(
          configPath: configPath,
          oneSignalAppId: 'test-app-id',
          softPromptEnabled: true,
        );

        final content = File(configPath).readAsStringSync();
        expect(content, contains("'notify_button_enabled': false"));
      });

      test('createNotificationConfig includes all web options together', () {
        final configPath = '${tempDir.path}/lib/config/notifications.dart';

        NotificationConfigHelper.createNotificationConfig(
          configPath: configPath,
          oneSignalAppId: 'my-app-id',
          softPromptEnabled: false,
          safariWebId: 'web.onesignal.auto.xyz789',
          notifyButtonEnabled: true,
        );

        final content = File(configPath).readAsStringSync();
        expect(content, contains("'app_id': 'my-app-id'"));
        expect(
            content, contains("'safari_web_id': 'web.onesignal.auto.xyz789'"));
        expect(content, contains("'notify_button_enabled': true"));
      });
    });
  });
}
