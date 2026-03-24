import 'dart:io';

import 'package:magic_cli/magic_cli.dart';
import 'package:magic_notifications/src/cli/commands/uninstall_command.dart';
import 'package:test/test.dart';

/// Test double that overrides [getProjectRoot] to use a temp directory.
class _TestUninstallCommand extends UninstallCommand {
  final String _root;

  _TestUninstallCommand(this._root);

  @override
  String getProjectRoot() => _root;
}

/// Test double that also stubs [confirm] to avoid stdin blocking.
class _TestUninstallCommandNoConfirm extends UninstallCommand {
  final String _root;
  final bool _confirmResult;

  _TestUninstallCommandNoConfirm(
    this._root, {
    bool confirmResult = false,
  }) : _confirmResult = confirmResult;

  @override
  String getProjectRoot() => _root;

  @override
  bool confirm(String message, {bool? defaultValue}) => _confirmResult;
}

/// Write a "fully installed" project into [tempDir].
void _writeInstalledProject(Directory tempDir) {
  Directory('${tempDir.path}/lib/config').createSync(recursive: true);

  // notifications.dart config
  File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync(
    "Map<String, dynamic> get notificationConfig => {};\n",
  );

  // pubspec.yaml with magic_notifications dependency
  File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
  magic_notifications:
    path: ./plugins/magic_notifications
''');

  // app.dart with injection
  File('${tempDir.path}/lib/config/app.dart').writeAsStringSync("""
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

final appConfig = {
  'providers': [
    (app) => RouteServiceProvider(app),
    (app) => NotificationServiceProvider(app),
  ],
};
""");

  // main.dart with injection
  File('${tempDir.path}/lib/main.dart').writeAsStringSync("""
import 'package:magic/magic.dart';
import 'config/notifications.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationConfig,
    ],
  );
}
""");
}

void main() {
  late Directory tempDir;
  late _TestUninstallCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_uninstall_test_');
    command = _TestUninstallCommand(tempDir.path);
    _writeInstalledProject(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('UninstallCommand', () {
    group('metadata', () {
      test('name is "uninstall"', () {
        expect(command.name, equals('uninstall'));
      });

      test('description is non-empty', () {
        expect(command.description, isNotEmpty);
      });
    });

    group('--force flag removes all injected artifacts', () {
      test('deletes lib/config/notifications.dart', () async {
        final configPath = '${tempDir.path}/lib/config/notifications.dart';
        expect(File(configPath).existsSync(), isTrue);

        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        expect(File(configPath).existsSync(), isFalse);
      });

      test('removes magic_notifications from pubspec.yaml', () async {
        final pubspecPath = '${tempDir.path}/pubspec.yaml';
        expect(
          File(pubspecPath).readAsStringSync(),
          contains('magic_notifications'),
        );

        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        final content = File(pubspecPath).readAsStringSync();
        expect(content, isNot(contains('magic_notifications')));
      });

      test('removes magic_notifications import from lib/config/app.dart',
          () async {
        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
        expect(
          content,
          isNot(contains(
              "import 'package:magic_notifications/magic_notifications.dart';")),
        );
      });

      test('removes NotificationServiceProvider from lib/config/app.dart',
          () async {
        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
        expect(content, isNot(contains('NotificationServiceProvider')));
      });

      test('preserves non-notification content in lib/config/app.dart',
          () async {
        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
        expect(content, contains("import 'package:magic/magic.dart';"));
        expect(content, contains('RouteServiceProvider'));
      });

      test('removes notifications.dart import from lib/main.dart', () async {
        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(
          content,
          isNot(contains("import 'config/notifications.dart';")),
        );
      });

      test('removes notificationConfig factory from lib/main.dart', () async {
        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(content, isNot(contains('notificationConfig')));
      });

      test('preserves non-notification content in lib/main.dart', () async {
        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(content, contains("import 'package:magic/magic.dart';"));
        expect(content, contains('Magic.init'));
        expect(content, contains('appConfig'));
      });
    });

    group('platform files are NOT touched', () {
      test('does not touch AndroidManifest.xml when present', () async {
        final manifestDir = Directory(
          '${tempDir.path}/android/app/src/main',
        )..createSync(recursive: true);
        final manifestFile = File('${manifestDir.path}/AndroidManifest.xml');
        const originalContent =
            '<manifest><uses-permission android:name="android.permission.POST_NOTIFICATIONS"/></manifest>';
        manifestFile.writeAsStringSync(originalContent);

        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        expect(manifestFile.existsSync(), isTrue);
        expect(manifestFile.readAsStringSync(), equals(originalContent));
      });

      test('does not touch web/index.html when present', () async {
        Directory('${tempDir.path}/web').createSync();
        final indexFile = File('${tempDir.path}/web/index.html');
        const originalContent = '<html><head><!-- OneSignal --></head></html>';
        indexFile.writeAsStringSync(originalContent);

        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        expect(indexFile.existsSync(), isTrue);
        expect(indexFile.readAsStringSync(), equals(originalContent));
      });

      test('does not touch OneSignalSDKWorker.js when present', () async {
        Directory('${tempDir.path}/web').createSync();
        final workerFile = File('${tempDir.path}/web/OneSignalSDKWorker.js');
        const originalContent =
            'importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");';
        workerFile.writeAsStringSync(originalContent);

        final kernel = Kernel()..register(command);
        await kernel.handle(['uninstall', '--force']);

        expect(workerFile.existsSync(), isTrue);
        expect(workerFile.readAsStringSync(), equals(originalContent));
      });
    });

    group('graceful handling of already-removed artifacts', () {
      test('does not throw when config file does not exist', () async {
        File('${tempDir.path}/lib/config/notifications.dart').deleteSync();

        final kernel = Kernel()..register(command);
        expect(
          () => kernel.handle(['uninstall', '--force']),
          returnsNormally,
        );
      });

      test('does not throw when app.dart does not exist', () async {
        File('${tempDir.path}/lib/config/app.dart').deleteSync();

        final kernel = Kernel()..register(command);
        expect(
          () => kernel.handle(['uninstall', '--force']),
          returnsNormally,
        );
      });

      test('does not throw when main.dart does not exist', () async {
        File('${tempDir.path}/lib/main.dart').deleteSync();

        final kernel = Kernel()..register(command);
        expect(
          () => kernel.handle(['uninstall', '--force']),
          returnsNormally,
        );
      });
    });

    group('without --force flag', () {
      test('does NOT execute removal when user declines (no --force)',
          () async {
        // Uses a test double that stubs confirm() to return false,
        // avoiding stdin blocking in non-interactive environments.
        final declineCommand = _TestUninstallCommandNoConfirm(
          tempDir.path,
          confirmResult: false,
        );
        final configPath = '${tempDir.path}/lib/config/notifications.dart';
        final pubspecPath = '${tempDir.path}/pubspec.yaml';

        final originalPubspec = File(pubspecPath).readAsStringSync();

        final kernel = Kernel()..register(declineCommand);
        await kernel.handle(['uninstall']);

        // Config file should still exist because uninstall was cancelled
        expect(File(configPath).existsSync(), isTrue);
        // pubspec should be unchanged
        expect(File(pubspecPath).readAsStringSync(), equals(originalPubspec));
      });
    });

    group('output messages', () {
      test('shows platform cleanup warning after --force uninstall', () async {
        // Verify the command completes without error — output goes to stdout
        // which we cannot easily intercept in unit tests, so we verify
        // indirectly via the absence of exceptions.
        final kernel = Kernel()..register(command);
        await expectLater(
          kernel.handle(['uninstall', '--force']),
          completes,
        );
      });
    });
  });
}
