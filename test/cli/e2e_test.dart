import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('CLI End-to-End', () {
    test('all bin entry points exist', () {
      final commands = ['install', 'configure', 'status', 'test'];

      for (final cmd in commands) {
        final binFile = File('bin/$cmd.dart');
        expect(binFile.existsSync(), isTrue,
            reason: 'bin/$cmd.dart should exist');

        final content = binFile.readAsStringSync();
        expect(content, contains('void main('),
            reason: 'bin/$cmd.dart should have main function');
      }
    });

    test('all commands show help', () async {
      final commands = ['install', 'configure', 'status', 'test'];

      for (final cmd in commands) {
        final result = await Process.run('dart', ['bin/$cmd.dart', '--help']);

        expect(result.exitCode, equals(0),
            reason: '$cmd command should exit with code 0 on --help');
        expect(result.stdout.toString(), contains('Usage'),
            reason: '$cmd command should show usage in help');
      }
    });

    test('install command validates app-id format', () async {
      final result = await Process.run('dart', [
        'bin/install.dart',
        '--non-interactive',
        '--app-id',
        'invalid-id',
      ]);

      // Should fail with invalid format
      expect(result.exitCode, equals(1));
      expect(result.stdout.toString(), contains('Invalid'));
    });

    test('configure command requires existing config', () async {
      // Create a temp directory without config
      final tempDir = Directory.systemTemp.createTempSync('config_test_');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('name: test');

      // Get absolute path to bin directory
      final binPath = File('bin/configure.dart').absolute.path;

      final result = await Process.run(
        'dart',
        [binPath, '--show'],
        workingDirectory: tempDir.path,
      );

      // Should fail without config
      expect(result.exitCode, equals(1));
      expect(result.stdout.toString(), contains('not found'));

      tempDir.deleteSync(recursive: true);
    });

    test('test command supports dry-run', () async {
      final result = await Process.run('dart', [
        'bin/test.dart',
        '--dry-run',
      ]);

      // Should show preview
      expect(result.stdout.toString(), contains('Preview'));
      expect(result.stdout.toString(), contains('Dry run'));
    });

    test('status command detects missing setup', () async {
      // Create a temp directory with minimal setup
      final tempDir = Directory.systemTemp.createTempSync('status_test_');
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');

      // Get absolute path to bin directory
      final binPath = File('bin/status.dart').absolute.path;

      final result = await Process.run(
        'dart',
        [binPath],
        workingDirectory: tempDir.path,
      );

      // Should detect missing plugin
      expect(result.exitCode, equals(1));
      expect(result.stdout.toString(), contains('plugin'));

      tempDir.deleteSync(recursive: true);
    });
  });
}
