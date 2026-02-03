import 'dart:io';
import 'package:test/test.dart';
import 'package:fluttersdk_magic_notifications/src/cli/commands/install_command.dart';

void main() {
  group('InstallCommand', () {
    late Directory tempDir;
    late InstallCommand command;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('install_cmd_test_');
      command = InstallCommand(projectRoot: tempDir.path);
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('detectProjectType identifies Flutter project', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
      expect(command.detectProjectType(), equals(ProjectType.flutter));
    });

    test('detectProjectType identifies Dart project', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  args: ^2.0.0
''');
      expect(command.detectProjectType(), equals(ProjectType.dart));
    });

    test('detectProjectType returns unknown for no pubspec', () {
      expect(command.detectProjectType(), equals(ProjectType.unknown));
    });

    test('validateOneSignalAppId accepts valid UUID format', () {
      expect(
        command.validateOneSignalAppId('12345678-1234-1234-1234-123456789012'),
        isTrue,
      );
    });

    test('validateOneSignalAppId rejects invalid format', () {
      expect(command.validateOneSignalAppId('invalid'), isFalse);
    });

    test('getRequiredPlatformFiles returns iOS files', () {
      final files = command.getRequiredPlatformFiles(PlatformType.ios);
      expect(files, contains('ios/Runner/Info.plist'));
    });

    test('getRequiredPlatformFiles returns Android files', () {
      final files = command.getRequiredPlatformFiles(PlatformType.android);
      expect(files, contains('android/app/build.gradle'));
    });

    test('getRequiredPlatformFiles returns Web files', () {
      final files = command.getRequiredPlatformFiles(PlatformType.web);
      expect(files, contains('web/index.html'));
    });

    group('setupWeb', () {
      test('creates OneSignalSDKWorker.js file', () async {
        // Create web directory
        Directory('${tempDir.path}/web').createSync();
        File('${tempDir.path}/web/index.html').writeAsStringSync('''
<!DOCTYPE html>
<html>
<head>
  <title>Test App</title>
</head>
<body></body>
</html>
''');

        await command.executeNonInteractive(
          oneSignalAppId: '12345678-1234-1234-1234-123456789012',
          platforms: ['web'],
          enableSoftPrompt: true,
        );

        final workerFile = File('${tempDir.path}/web/OneSignalSDKWorker.js');
        expect(workerFile.existsSync(), isTrue);
        // Service Worker must use .sw.js (not .page.js which is for HTML page)
        expect(
          workerFile.readAsStringSync(),
          contains('OneSignalSDK.sw.js'),
        );
      });

      test('injects OneSignal SDK script into index.html', () async {
        Directory('${tempDir.path}/web').createSync();
        File('${tempDir.path}/web/index.html').writeAsStringSync('''
<!DOCTYPE html>
<html>
<head>
  <title>Test App</title>
</head>
<body></body>
</html>
''');

        await command.executeNonInteractive(
          oneSignalAppId: '12345678-1234-1234-1234-123456789012',
          platforms: ['web'],
          enableSoftPrompt: true,
        );

        final htmlContent =
            File('${tempDir.path}/web/index.html').readAsStringSync();
        // SDK script is loaded
        expect(htmlContent, contains('OneSignalSDK.page.js'));
        // OneSignalDeferred array is initialized
        expect(htmlContent, contains('OneSignalDeferred'));
        // Init is handled by Dart config, NOT in HTML
        expect(htmlContent, isNot(contains('OneSignal.init')));
      });

      test('does not duplicate script if already present', () async {
        Directory('${tempDir.path}/web').createSync();
        File('${tempDir.path}/web/index.html').writeAsStringSync('''
<!DOCTYPE html>
<html>
<head>
  <title>Test App</title>
  <script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
</head>
<body></body>
</html>
''');

        await command.executeNonInteractive(
          oneSignalAppId: '12345678-1234-1234-1234-123456789012',
          platforms: ['web'],
          enableSoftPrompt: true,
        );

        final htmlContent =
            File('${tempDir.path}/web/index.html').readAsStringSync();
        // Count occurrences - should be exactly 1
        final matches = 'OneSignalSDK.page.js'.allMatches(htmlContent);
        expect(matches.length, equals(1));
      });
    });

    group('notification config generation', () {
      test('generates config with safari_web_id', () async {
        // Create required directories
        Directory('${tempDir.path}/lib/config').createSync(recursive: true);
        Directory('${tempDir.path}/web').createSync();
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
        File('${tempDir.path}/web/index.html').writeAsStringSync('''
<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body></body>
</html>
''');

        await command.executeNonInteractive(
          oneSignalAppId: '12345678-1234-1234-1234-123456789012',
          platforms: ['web'],
          enableSoftPrompt: true,
          safariWebId: 'web.onesignal.auto.test123',
        );

        final configContent =
            File('${tempDir.path}/lib/config/notifications.dart')
                .readAsStringSync();
        expect(configContent,
            contains("'safari_web_id': 'web.onesignal.auto.test123'"));
      });

      test('generates config with notify_button_enabled', () async {
        Directory('${tempDir.path}/lib/config').createSync(recursive: true);
        Directory('${tempDir.path}/web').createSync();
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
        File('${tempDir.path}/web/index.html').writeAsStringSync('''
<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body></body>
</html>
''');

        await command.executeNonInteractive(
          oneSignalAppId: '12345678-1234-1234-1234-123456789012',
          platforms: ['web'],
          enableSoftPrompt: true,
          notifyButtonEnabled: true,
        );

        final configContent =
            File('${tempDir.path}/lib/config/notifications.dart')
                .readAsStringSync();
        expect(configContent, contains("'notify_button_enabled': true"));
      });

      test('generates config with all web options', () async {
        Directory('${tempDir.path}/lib/config').createSync(recursive: true);
        Directory('${tempDir.path}/web').createSync();
        File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
        File('${tempDir.path}/web/index.html').writeAsStringSync('''
<!DOCTYPE html>
<html>
<head><title>Test</title></head>
<body></body>
</html>
''');

        await command.executeNonInteractive(
          oneSignalAppId: 'aabbccdd-1234-5678-90ab-cdef12345678',
          platforms: ['web'],
          enableSoftPrompt: false,
          safariWebId: 'web.onesignal.auto.xyz',
          notifyButtonEnabled: true,
        );

        final configContent =
            File('${tempDir.path}/lib/config/notifications.dart')
                .readAsStringSync();
        expect(configContent,
            contains("'app_id': 'aabbccdd-1234-5678-90ab-cdef12345678'"));
        expect(configContent,
            contains("'safari_web_id': 'web.onesignal.auto.xyz'"));
        expect(configContent, contains("'notify_button_enabled': true"));
      });
    });
  });
}
