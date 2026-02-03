import 'package:test/test.dart';
import 'package:fluttersdk_magic_notifications/src/cli/cli.dart';

void main() {
  group('CLI Exports', () {
    test('ConsoleStyle is exported', () {
      expect(ConsoleStyle, isNotNull);
    });

    test('FileHelper is exported', () {
      expect(FileHelper, isNotNull);
    });

    test('ConfigEditor is exported', () {
      expect(ConfigEditor, isNotNull);
    });
  });
}
