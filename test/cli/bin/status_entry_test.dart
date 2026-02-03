import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('bin/status.dart', () {
    test('file exists', () {
      expect(File('bin/status.dart').existsSync(), isTrue);
    });

    test('file imports StatusCommand', () {
      final content = File('bin/status.dart').readAsStringSync();
      expect(content, contains('StatusCommand'));
    });

    test('file has main function', () {
      final content = File('bin/status.dart').readAsStringSync();
      expect(content, contains('void main('));
    });

    test('runs without error', () async {
      final result = await Process.run('dart', ['bin/status.dart']);
      expect(result.exitCode, anyOf([0, 1])); // 0 = all good, 1 = issues found
    });

    test('--help flag shows usage', () async {
      final result = await Process.run('dart', ['bin/status.dart', '--help']);
      expect(result.stdout.toString(), contains('Usage'));
    });
  });
}
