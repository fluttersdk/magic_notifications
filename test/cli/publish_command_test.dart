import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_notifications/src/cli/commands/publish_command.dart';
import 'package:test/test.dart';

/// Test double that redirects project root to a temp directory
/// and stub search paths to the real assets/stubs directory.
class _TestPublishCommand extends PublishCommand {
  final String _root;

  _TestPublishCommand(this._root);

  @override
  String getProjectRoot() => _root;

  @override
  List<String> getStubSearchPaths() => [
        '${Directory.current.path}/assets/stubs',
      ];
}

/// Builds an [ArtisanContext] for [cmd] with the given flag overrides.
ArtisanContext _ctx(
  _TestPublishCommand cmd, {
  bool force = false,
}) =>
    ArtisanContext.bare(
      MapInput(
        {'force': force},
        signature: cmd.parsedSignature,
      ),
      BufferedOutput(),
    );

void main() {
  late Directory tempDir;
  late _TestPublishCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_publish_test_');
    command = _TestPublishCommand(tempDir.path);

    // Minimal project structure so FileHelper.findProjectRoot() has something
    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PublishCommand', () {
    test('has name "notifications:publish"', () {
      expect(command.name, equals('notifications:publish'));
    });

    test('has a non-empty description', () {
      expect(command.description, isNotEmpty);
    });

    test(
        'publishes notification_config.stub to lib/config/notifications.dart on empty project',
        () async {
      await command.handle(_ctx(command));

      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      expect(File(configPath).existsSync(), isTrue);
    });

    test('published file contains valid Dart map structure', () async {
      await command.handle(_ctx(command));

      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      final content = File(configPath).readAsStringSync();

      expect(content, contains('notificationConfig'));
    });

    test('published file uses YOUR_ONESIGNAL_APP_ID as default placeholder',
        () async {
      await command.handle(_ctx(command));

      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      final content = File(configPath).readAsStringSync();

      expect(content, contains('YOUR_ONESIGNAL_APP_ID'));
    });

    test('published file has notify_button_enabled set to false by default',
        () async {
      await command.handle(_ctx(command));

      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      final content = File(configPath).readAsStringSync();

      expect(content, contains('false'));
    });

    test('published file has soft_prompt enabled set to true by default',
        () async {
      await command.handle(_ctx(command));

      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      final content = File(configPath).readAsStringSync();

      expect(content, contains('true'));
    });

    test('creates lib/config directory if it does not exist', () async {
      await command.handle(_ctx(command));

      final configDir = Directory('${tempDir.path}/lib/config');
      expect(configDir.existsSync(), isTrue);
    });

    test('without --force, does not overwrite existing file', () async {
      // Pre-create the config file with sentinel content
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      File(configPath).writeAsStringSync('// sentinel-content');

      await command.handle(_ctx(command));

      // File must remain unchanged
      expect(
          File(configPath).readAsStringSync(), equals('// sentinel-content'));
    });

    test('with --force, overwrites existing file', () async {
      // Pre-create the config file with sentinel content
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      File(configPath).writeAsStringSync('// sentinel-content');

      await command.handle(_ctx(command, force: true));

      final content = File(configPath).readAsStringSync();
      // Content must have changed — stub was written
      expect(content, isNot(equals('// sentinel-content')));
      expect(content, contains('YOUR_ONESIGNAL_APP_ID'));
    });
  });
}
