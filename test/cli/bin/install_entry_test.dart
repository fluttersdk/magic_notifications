import 'dart:io';
import 'package:test/test.dart';

void main() {
  group('bin/install.dart', () {
    test('file exists in bin directory', () {
      final file = File('bin/install.dart');
      expect(file.existsSync(), isTrue);
    });

    test('file imports InstallCommand', () {
      final content = File('bin/install.dart').readAsStringSync();
      expect(content, contains('InstallCommand'));
    });

    test('file has main function', () {
      final content = File('bin/install.dart').readAsStringSync();
      expect(content, contains('void main('));
    });

    test('--help flag shows usage', () async {
      final result = await Process.run('dart', ['bin/install.dart', '--help']);
      expect(result.stdout.toString(), contains('Usage'));
    });
  });
}
