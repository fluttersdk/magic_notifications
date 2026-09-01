import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_notifications/src/cli/commands/uninstall_command.dart';
import 'package:test/test.dart';

/// Uninstall coverage for the getter name the project ACTUALLY declares.
///
/// The baseline removal coverage (pubspec, app.dart, platform files left
/// alone, the confirmation prompt) lives in
/// `test/cli/commands/uninstall_command_test.dart` against a project wired
/// with the stub's own `notificationConfig`. This file covers the case that
/// broke a real adopter: a hand-written config declaring a DIFFERENT getter,
/// where matching `main.dart` by the stub's literal name removes nothing and
/// the operator is told the package is gone while the project still
/// references it.

/// Test double pinning the project root and deciding the confirmation without
/// reading stdin.
class _TestUninstallCommand extends UninstallCommand {
  /// Creates the double rooted at [_root].
  _TestUninstallCommand(this._root);

  /// Temp directory standing in for the consumer project.
  final String _root;

  @override
  String getProjectRoot() => _root;

  @override
  bool confirmRemoval() => true;
}

/// Builds an [ArtisanContext] running the uninstall with `--force`.
ArtisanContext _ctx(_TestUninstallCommand cmd) => ArtisanContext.bare(
      MapInput(<String, dynamic>{'force': true},
          signature: cmd.parsedSignature),
      BufferedOutput(),
    );

/// Writes a project whose config declares [getter] and whose `main.dart`
/// imports the config with [importLine] and names [getter] in a factory.
void _writeWiredProject(
  Directory tempDir,
  String getter, {
  String importLine = "import 'config/notifications.dart';",
}) {
  Directory('${tempDir.path}/lib/config').createSync(recursive: true);

  File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync('''
/// Notifications configuration.
Map<String, dynamic> get $getter => {
  'notifications': {
    'push': {'driver': 'onesignal'},
  },
};
''');

  File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
  magic_notifications: ^0.0.1
''');

  File('${tempDir.path}/lib/config/app.dart').writeAsStringSync('''
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

final appConfig = {
  'providers': [
    (app) => RouteServiceProvider(app),
    (app) => NotificationServiceProvider(app),
  ],
};
''');

  File('${tempDir.path}/lib/main.dart').writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';
$importLine

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => $getter,
    ],
  );
}
''');
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_uninstall_getter_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('UninstallCommand main.dart cleanup', () {
    test('removes the factory naming the getter the config declares', () async {
      _writeWiredProject(tempDir, 'notificationsConfig');
      final command = _TestUninstallCommand(tempDir.path);

      await command.handle(_ctx(command));

      final main = File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(
        main,
        isNot(contains('notificationsConfig')),
        reason: 'the factory names the getter the config declared, not the '
            "stub's name, and uninstall has to match on that",
      );
      expect(main, isNot(contains('config/notifications.dart')));
      expect(main, contains('() => appConfig,'),
          reason: 'unrelated factories survive');
    });

    test('removes a package: spelled import of the config', () async {
      _writeWiredProject(
        tempDir,
        'notificationsConfig',
        importLine: "import 'package:test_app/config/notifications.dart';",
      );
      final command = _TestUninstallCommand(tempDir.path);

      await command.handle(_ctx(command));

      final main = File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(main, isNot(contains('config/notifications.dart')));
      expect(main, isNot(contains('notificationsConfig')));
    });

    test('leaves main.dart untouched when the config file is absent', () async {
      _writeWiredProject(tempDir, 'notificationsConfig');
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();
      final mainPath = '${tempDir.path}/lib/main.dart';
      final before = File(mainPath).readAsStringSync();
      final command = _TestUninstallCommand(tempDir.path);

      final ctx = _ctx(command);
      await command.handle(ctx);

      expect(
        File(mainPath).readAsStringSync(),
        before,
        reason: 'nothing on disk names the getter, and a guessed match would '
            'delete a line the project still needs',
      );
      expect(
        (ctx.output as BufferedOutput).content,
        contains('lib/main.dart'),
        reason: 'the operator has to be told what was left behind',
      );
    });

    test('leaves main.dart untouched when the config declares no getter',
        () async {
      _writeWiredProject(tempDir, 'notificationsConfig');
      File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync(
        '// Hand-rolled: this file declares nothing the CLI can name.\n'
        'const int placeholder = 1;\n',
      );
      final mainPath = '${tempDir.path}/lib/main.dart';
      final before = File(mainPath).readAsStringSync();
      final command = _TestUninstallCommand(tempDir.path);

      final ctx = _ctx(command);
      await command.handle(ctx);

      expect(File(mainPath).readAsStringSync(), before);
      expect((ctx.output as BufferedOutput).content, contains('lib/main.dart'));
    });

    test('a commented-out declaration does not count as the getter', () async {
      _writeWiredProject(tempDir, 'notificationsConfig');
      File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync(
        '// Map<String, dynamic> get ghostConfig => {};\n'
        'Map<String, dynamic> get notificationsConfig => {};\n',
      );
      final command = _TestUninstallCommand(tempDir.path);

      await command.handle(_ctx(command));

      final main = File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(main, isNot(contains('notificationsConfig')));
    });
  });
}
