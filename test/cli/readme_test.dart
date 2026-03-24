import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('README CLI Section', () {
    test('README contains CLI tools section', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('## CLI Tools'));
    });

    test('README documents install command', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('dart run magic_notifications install'));
    });

    test('README documents configure command', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('configure'));
    });

    test('README documents all commands', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('install'));
      expect(readme, contains('configure'));
      expect(readme, contains('doctor'));
      expect(readme, contains('uninstall'));
      expect(readme, contains('publish'));
      expect(readme, contains('channels'));
    });

    test('README links to CLI reference docs', () {
      final readme = File('README.md').readAsStringSync();
      expect(
        readme,
        contains('magic.fluttersdk.com/packages/notifications/basics/cli'),
      );
    });
  });
}
