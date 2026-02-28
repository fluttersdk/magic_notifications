import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('README CLI Section', () {
    test('README contains CLI commands section', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('## CLI Commands'));
    });

    test('README documents install command', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('dart run magic_notifications install'));
    });

    test('README documents configure command', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('dart run magic_notifications configure'));
    });

    test('README documents all commands', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('dart run magic_notifications install'));
      expect(readme, contains('dart run magic_notifications configure'));
      expect(readme, contains('dart run magic_notifications doctor'));
      expect(readme, contains('dart run magic_notifications test'));
    });

    test('README has examples for each command', () {
      final readme = File('README.md').readAsStringSync();
      expect(readme, contains('### Install'));
      expect(readme, contains('### Configure'));
      expect(readme, contains('### Doctor'));
      expect(readme, contains('### Test'));
    });
  });
}
