import 'dart:io';
import 'package:test/test.dart';
import 'package:fluttersdk_magic_notifications/src/cli/commands/status_command.dart';

void main() {
  group('StatusCommand', () {
    late Directory tempDir;
    late StatusCommand command;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('status_cmd_test_');
      command = StatusCommand(projectRoot: tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('checkPluginInstalled returns true when dependency exists', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
dependencies:
  fluttersdk_magic_notifications:
    path: ./plugins/fluttersdk_magic_notifications
''');
      expect(command.checkPluginInstalled(), isTrue);
    });

    test('checkPluginInstalled returns false when missing', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
dependencies:
  flutter:
    sdk: flutter
''');
      expect(command.checkPluginInstalled(), isFalse);
    });

    test('checkConfigExists returns true when config file exists', () {
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('final config = {};');
      expect(command.checkConfigExists(), isTrue);
    });

    test('checkConfigExists returns false when missing', () {
      expect(command.checkConfigExists(), isFalse);
    });

    test('checkPlatformSetup returns status for each platform', () {
      Directory('${tempDir.path}/android/app/src/main')
          .createSync(recursive: true);
      File('${tempDir.path}/android/app/src/main/AndroidManifest.xml')
          .writeAsStringSync(
              '<manifest><uses-permission android:name="POST_NOTIFICATIONS"/></manifest>');

      final status = command.checkPlatformSetup();
      expect(status['android']['configured'], isTrue);
      expect(status['ios']['configured'], isFalse);
      expect(status['web']['configured'], isFalse);
    });

    test('getMissingRequirements returns list of issues', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('name: test');

      final missing = command.getMissingRequirements();
      expect(missing, contains(contains('notifications plugin')));
    });

    test('generateReport returns formatted status report', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test
dependencies:
  fluttersdk_magic_notifications: any
''');

      final report = command.generateReport();
      expect(report, contains('Plugin Installed'));
      expect(report.contains('✓') || report.contains('✗'), isTrue);
    });

    test('generateReport with verbose shows detailed information', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test
dependencies:
  fluttersdk_magic_notifications: any
''');

      final report = command.generateReport(verbose: true);

      // Verbose should include location details
      expect(report, contains('Location: pubspec.yaml'));
      expect(report, contains('Package: fluttersdk_magic_notifications'));
      expect(report, contains('Path: lib/config/notifications.dart'));

      // Verbose should include platform details
      expect(report,
          contains('Manifest: android/app/src/main/AndroidManifest.xml'));
      expect(report, contains('POST_NOTIFICATIONS permission'));
      expect(report, contains('Info.plist: ios/Runner/Info.plist'));
      expect(report, contains('Service Worker: web/OneSignalSDKWorker.js'));
    });

    test('generateReport without verbose is compact', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test
dependencies:
  fluttersdk_magic_notifications: any
''');

      final report = command.generateReport(verbose: false);

      // Non-verbose should NOT include location details
      expect(report, isNot(contains('Location: pubspec.yaml')));
      expect(report, isNot(contains('Manifest: android/app/src/main')));
    });
  });
}
