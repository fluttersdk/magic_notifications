import 'dart:io';

import 'package:magic_cli/magic_cli.dart';
import 'package:magic_notifications/src/cli/commands/install_command.dart'
    as MN;
import 'package:test/test.dart';

class _TestInstallCommand extends MN.InstallCommand {
  final String _root;

  _TestInstallCommand(this._root);

  @override
  String getProjectRoot() => _root;

  @override
  List<String> getStubSearchPaths() => [
        '${Directory.current.path}/assets/stubs',
      ];
}

void main() {
  late Directory tempDir;
  late _TestInstallCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_notifications_test_');
    command = _TestInstallCommand(tempDir.path);

    // Create necessary base files
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');

    Directory('${tempDir.path}/lib/config').createSync(recursive: true);

    // Mock app.dart
    File('${tempDir.path}/lib/config/app.dart').writeAsStringSync('''
import 'package:magic/magic.dart';

final appConfig = {
  'providers': [
    (app) => RouteServiceProvider(app),
  ],
};
''');

    // Mock main.dart
    File('${tempDir.path}/lib/main.dart').writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
}
''');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('InstallCommand', () {
    test('validateOneSignalAppId accepts valid UUID', () {
      expect(
        command.validateOneSignalAppId('12345678-1234-1234-1234-123456789012'),
        isTrue,
      );
      expect(
        command.validateOneSignalAppId('invalid-uuid'),
        isFalse,
      );
    });

    test('creates config and injects providers on fresh install with force',
        () async {
      final kernel = Kernel()..register(command);

      await kernel.handle([
        'install',
        '--non-interactive',
        '--app-id=12345678-1234-1234-1234-123456789012',
        '--platforms=android,ios',
        '--force',
      ]);

      // Verify config created
      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      expect(File(configPath).existsSync(), isTrue);

      final configContent = File(configPath).readAsStringSync();
      expect(configContent, contains('12345678-1234-1234-1234-123456789012'));
      expect(configContent, contains("'notify_button_enabled': false"));
      expect(configContent, contains("'enabled': true")); // softPrompt

      // Verify app.dart injection
      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      expect(
          appContent,
          contains(
              "import 'package:magic_notifications/magic_notifications.dart';"));
      expect(
          appContent, contains("(app) => NotificationServiceProvider(app),"));

      // Verify main.dart injection
      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainContent, contains("import 'config/notifications.dart';"));
      expect(mainContent, contains("() => notificationConfig,"));
    });

    test('does not overwrite existing config without force', () async {
      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      File(configPath).writeAsStringSync('existing-content');

      final kernel = Kernel()..register(command);

      await kernel.handle([
        'install',
        '--non-interactive',
        '--app-id=12345678-1234-1234-1234-123456789012',
      ]);

      // Content should remain the same
      expect(File(configPath).readAsStringSync(), equals('existing-content'));
    });

    test('creates web worker when web platform is selected', () async {
      Directory('${tempDir.path}/web').createSync();
      File('${tempDir.path}/web/index.html')
          .writeAsStringSync('<html><head></head></html>');

      final kernel = Kernel()..register(command);

      await kernel.handle([
        'install',
        '--non-interactive',
        '--app-id=12345678-1234-1234-1234-123456789012',
        '--platforms=web',
        '--safari-web-id=web.onesignal.auto.123',
      ]);

      // Verify worker exists
      final workerPath = '${tempDir.path}/web/OneSignalSDKWorker.js';
      expect(File(workerPath).existsSync(), isTrue);
      expect(
        File(workerPath).readAsStringSync(),
        contains(
            'importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");'),
      );

      // Verify index.html was updated
      final indexContent =
          File('${tempDir.path}/web/index.html').readAsStringSync();
      expect(indexContent, contains('OneSignalSDK.page.js'));

      // Verify config has safari id
      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      final configContent = File(configPath).readAsStringSync();
      expect(
          configContent, contains("'safari_web_id': 'web.onesignal.auto.123'"));
    });
  });
}
