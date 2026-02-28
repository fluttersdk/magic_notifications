import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('CLI End-to-End', () {
    test('main entry point shows help', () async {
      final result = await Process.run('dart', ['bin/magic_notifications.dart', '--help']);

      expect(result.exitCode, equals(0));
      expect(result.stdout.toString(), contains('Usage: magic_notifications <command> [arguments]'));
      expect(result.stdout.toString(), contains('Available commands:'));
      expect(result.stdout.toString(), contains('install'));
      expect(result.stdout.toString(), contains('configure'));
      expect(result.stdout.toString(), contains('test'));
      expect(result.stdout.toString(), contains('doctor'));
      expect(result.stdout.toString(), contains('uninstall'));
      expect(result.stdout.toString(), contains('publish'));
      expect(result.stdout.toString(), contains('channels'));
    });

    test('all commands show help via main entry point', () async {
      final commands = ['install', 'configure', 'test', 'doctor', 'uninstall', 'publish', 'channels'];

      for (final cmd in commands) {
        final result = await Process.run('dart', ['bin/magic_notifications.dart', cmd, '--help']);

        expect(result.exitCode, equals(0),
            reason: '$cmd command should exit with code 0 on --help');
        expect(result.stdout.toString(), contains('Usage: magic_notifications $cmd'),
            reason: '$cmd command should show usage in help');
      }
    });

    test('test command supports dry-run via main entry point', () async {
      final result = await Process.run('dart', [
        'bin/magic_notifications.dart',
        'test',
        '--dry-run',
      ]);

      expect(result.stdout.toString(), contains('Preview'));
      expect(result.stdout.toString(), contains('Dry run'));
    });
  });
}
