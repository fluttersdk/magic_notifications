import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('bin/test.dart', () {
    test('file exists', () {
      expect(File('bin/test.dart').existsSync(), isTrue);
    });

    test('file imports TestCommand', () {
      final content = File('bin/test.dart').readAsStringSync();
      expect(content, contains('TestCommand'));
    });

    test('file has main function', () {
      final content = File('bin/test.dart').readAsStringSync();
      expect(content, contains('void main('));
    });

    test('--help shows usage', () async {
      final result = await Process.run('dart', ['bin/test.dart', '--help']);
      expect(result.stdout.toString(), contains('Send test notification'));
    });

    test('--dry-run shows preview without sending', () async {
      final result = await Process.run('dart', ['bin/test.dart', '--dry-run']);
      expect(result.stdout.toString(), contains('Preview'));
    });
  });
}
