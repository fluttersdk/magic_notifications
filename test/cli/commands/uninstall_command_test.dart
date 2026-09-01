import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_notifications/src/cli/commands/uninstall_command.dart';
import 'package:test/test.dart';

/// Test double that overrides [getProjectRoot] to use a temp directory and
/// [confirmRemoval] to decide the confirmation result without reading stdin.
class _TestUninstallCommand extends UninstallCommand {
  final String _root;
  final bool _confirm;

  _TestUninstallCommand(this._root, {bool confirm = false})
      : _confirm = confirm;

  @override
  String getProjectRoot() => _root;

  @override
  bool confirmRemoval() => _confirm;
}

/// Builds an [ArtisanContext] for [cmd] with the given flag overrides.
ArtisanContext _ctx(
  _TestUninstallCommand cmd, {
  bool force = false,
}) =>
    ArtisanContext.bare(
      MapInput(
        {'force': force},
        signature: cmd.parsedSignature,
      ),
      BufferedOutput(),
    );

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
      test('name is "notifications:uninstall"', () {
        expect(command.name, equals('notifications:uninstall'));
      });

      test('description is non-empty', () {
        expect(command.description, isNotEmpty);
      });
    });

    group('--force flag removes all injected artifacts', () {
      test('deletes lib/config/notifications.dart', () async {
        final configPath = '${tempDir.path}/lib/config/notifications.dart';
        expect(File(configPath).existsSync(), isTrue);

        await command.handle(_ctx(command, force: true));

        expect(File(configPath).existsSync(), isFalse);
      });

      test('removes magic_notifications from pubspec.yaml', () async {
        final pubspecPath = '${tempDir.path}/pubspec.yaml';
        expect(
          File(pubspecPath).readAsStringSync(),
          contains('magic_notifications'),
        );

        await command.handle(_ctx(command, force: true));

        final content = File(pubspecPath).readAsStringSync();
        expect(content, isNot(contains('magic_notifications')));
      });

      test('removes magic_notifications import from lib/config/app.dart',
          () async {
        await command.handle(_ctx(command, force: true));

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
        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
        expect(content, isNot(contains('NotificationServiceProvider')));
      });

      test('preserves non-notification content in lib/config/app.dart',
          () async {
        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
        expect(content, contains("import 'package:magic/magic.dart';"));
        expect(content, contains('RouteServiceProvider'));
      });

      test('removes notifications.dart import from lib/main.dart', () async {
        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(
          content,
          isNot(contains("import 'config/notifications.dart';")),
        );
      });

      test('removes notificationConfig factory from lib/main.dart', () async {
        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(content, isNot(contains('notificationConfig')));
      });

      test('preserves non-notification content in lib/main.dart', () async {
        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(content, contains("import 'package:magic/magic.dart';"));
        expect(content, contains('Magic.init'));
        expect(content, contains('appConfig'));
      });
    });

    // Detection strips comments before it decides a project is wired, so
    // removal has to read the file the same way. Cutting the text out of the
    // middle of a comment left a dangling `//` in a project that was correctly
    // judged "not wired" a moment earlier.
    group('commented-out wiring is left in its comment', () {
      test('a commented import is not cut out of the comment', () async {
        File('${tempDir.path}/lib/main.dart').writeAsStringSync("""
import 'package:magic/magic.dart';
// import 'config/notifications.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
}
""");

        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(content, contains("// import 'config/notifications.dart';"));
      });

      test('a commented factory entry is not cut out of the comment', () async {
        File('${tempDir.path}/lib/main.dart').writeAsStringSync("""
import 'package:magic/magic.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      // () => notificationConfig,
    ],
  );
}
""");

        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(content, contains('// () => notificationConfig,'));
      });

      test('real wiring still goes while a comment quoting it stays', () async {
        File('${tempDir.path}/lib/main.dart').writeAsStringSync("""
import 'package:magic/magic.dart';
import 'config/notifications.dart';

// Wiring reference: import 'config/notifications.dart'; then add
// "() => notificationConfig," to configFactories.
void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationConfig,
    ],
  );
}
""");

        await command.handle(_ctx(command, force: true));

        final content =
            File('${tempDir.path}/lib/main.dart').readAsStringSync();
        expect(content, contains('// Wiring reference: '));
        expect(content, contains('// "() => notificationConfig," to '));
        expect(
          content,
          isNot(contains("\nimport 'config/notifications.dart';")),
        );
        expect(
          content,
          isNot(contains('      () => notificationConfig,')),
        );
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

        await command.handle(_ctx(command, force: true));

        expect(manifestFile.existsSync(), isTrue);
        expect(manifestFile.readAsStringSync(), equals(originalContent));
      });

      test('does not touch web/index.html when present', () async {
        Directory('${tempDir.path}/web').createSync();
        final indexFile = File('${tempDir.path}/web/index.html');
        const originalContent = '<html><head><!-- OneSignal --></head></html>';
        indexFile.writeAsStringSync(originalContent);

        await command.handle(_ctx(command, force: true));

        expect(indexFile.existsSync(), isTrue);
        expect(indexFile.readAsStringSync(), equals(originalContent));
      });

      test('does not touch OneSignalSDKWorker.js when present', () async {
        Directory('${tempDir.path}/web').createSync();
        final workerFile = File('${tempDir.path}/web/OneSignalSDKWorker.js');
        const originalContent =
            'importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");';
        workerFile.writeAsStringSync(originalContent);

        await command.handle(_ctx(command, force: true));

        expect(workerFile.existsSync(), isTrue);
        expect(workerFile.readAsStringSync(), equals(originalContent));
      });
    });

    group('graceful handling of already-removed artifacts', () {
      test('does not throw when config file does not exist', () async {
        File('${tempDir.path}/lib/config/notifications.dart').deleteSync();

        expect(
          () => command.handle(_ctx(command, force: true)),
          returnsNormally,
        );
      });

      test('does not throw when app.dart does not exist', () async {
        File('${tempDir.path}/lib/config/app.dart').deleteSync();

        expect(
          () => command.handle(_ctx(command, force: true)),
          returnsNormally,
        );
      });

      test('does not throw when main.dart does not exist', () async {
        File('${tempDir.path}/lib/main.dart').deleteSync();

        expect(
          () => command.handle(_ctx(command, force: true)),
          returnsNormally,
        );
      });
    });

    group('without --force flag', () {
      test('does NOT execute removal when confirmation is declined', () async {
        // Without --force the command asks confirmRemoval(); the test double
        // returns false (declined), so the uninstall is cancelled and every
        // artifact remains intact.
        final configPath = '${tempDir.path}/lib/config/notifications.dart';
        final pubspecPath = '${tempDir.path}/pubspec.yaml';
        final originalPubspec = File(pubspecPath).readAsStringSync();

        await command.handle(_ctx(command, force: false));

        // Config file must still exist because uninstall was cancelled.
        expect(File(configPath).existsSync(), isTrue);
        // pubspec must be unchanged.
        expect(File(pubspecPath).readAsStringSync(), equals(originalPubspec));
      });

      test('executes removal when confirmation is accepted', () async {
        // confirmRemoval() returns true (accepted), so the uninstall proceeds
        // exactly as the --force path would, without reading stdin.
        final confirmed = _TestUninstallCommand(tempDir.path, confirm: true);
        final configPath = '${tempDir.path}/lib/config/notifications.dart';

        await confirmed.handle(_ctx(confirmed, force: false));

        expect(File(configPath).existsSync(), isFalse);
      });
    });

    group('output messages', () {
      test('command completes without error after --force uninstall', () async {
        await expectLater(
          command.handle(_ctx(command, force: true)),
          completes,
        );
      });
    });
  });
}
