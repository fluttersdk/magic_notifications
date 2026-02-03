import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('bin/configure.dart', () {
    test('file exists in bin directory', () {
      expect(File('bin/configure.dart').existsSync(), isTrue);
    });

    test('file imports ConfigureCommand', () {
      final content = File('bin/configure.dart').readAsStringSync();
      expect(content, contains('ConfigureCommand'));
    });

    test('file has main function', () {
      final content = File('bin/configure.dart').readAsStringSync();
      expect(content, contains('void main('));
    });

    test('--help flag shows usage', () async {
      final result =
          await Process.run('dart', ['bin/configure.dart', '--help']);
      expect(result.stdout.toString(), contains('Usage'));
    });

    test('--show flag option exists', () async {
      final result =
          await Process.run('dart', ['bin/configure.dart', '--help']);
      expect(result.stdout.toString(), contains('--show'));
    });
  });
}
