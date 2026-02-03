import 'dart:io';
import 'package:test/test.dart';
import 'package:fluttersdk_magic_notifications/src/cli/commands/install_command.dart';

void main() {
  group('InstallCommand Flow', () {
    late Directory tempDir;
    late InstallCommand command;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('install_flow_test_');
      // Create minimal Flutter project structure
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
  fluttersdk_magic:
    path: ../plugins/fluttersdk_magic
''');
      Directory('${tempDir.path}/lib').createSync();
      File('${tempDir.path}/lib/main.dart').writeAsStringSync('''
import 'package:flutter/material.dart';
void main() { runApp(MyApp()); }
''');

      command = InstallCommand(projectRoot: tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('execute creates notification config file', () async {
      await command.executeNonInteractive(
        oneSignalAppId: 'test-app-id',
        platforms: ['android', 'web'],
        enableSoftPrompt: true,
      );

      expect(
        File('${tempDir.path}/lib/config/notifications.dart').existsSync(),
        isTrue,
      );
    });

    test('execute updates pubspec.yaml with dependency', () async {
      await command.executeNonInteractive(
        oneSignalAppId: 'test-app-id',
        platforms: ['android'],
        enableSoftPrompt: false,
      );

      final pubspec = File('${tempDir.path}/pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('fluttersdk_magic_notifications'));
    });

    test('execute generates platform-specific files for Android', () async {
      Directory('${tempDir.path}/android/app/src/main')
          .createSync(recursive: true);
      File('${tempDir.path}/android/app/build.gradle')
          .writeAsStringSync('android {}');
      File('${tempDir.path}/android/app/src/main/AndroidManifest.xml')
          .writeAsStringSync('<manifest/>');

      await command.executeNonInteractive(
        oneSignalAppId: 'test-app-id',
        platforms: ['android'],
        enableSoftPrompt: false,
      );

      final manifest =
          File('${tempDir.path}/android/app/src/main/AndroidManifest.xml')
              .readAsStringSync();
      expect(manifest, contains('POST_NOTIFICATIONS'));
    });

    test('execute generates web service worker', () async {
      Directory('${tempDir.path}/web').createSync(recursive: true);
      File('${tempDir.path}/web/index.html')
          .writeAsStringSync('<html><head></head></html>');
      File('${tempDir.path}/web/manifest.json').writeAsStringSync('{}');

      await command.executeNonInteractive(
        oneSignalAppId: 'test-app-id',
        platforms: ['web'],
        enableSoftPrompt: false,
      );

      expect(
        File('${tempDir.path}/web/OneSignalSDKWorker.js').existsSync(),
        isTrue,
      );
    });
  });
}
