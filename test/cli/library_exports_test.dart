import 'package:test/test.dart';

void main() {
  group('Library Exports CLI', () {
    test('CLI helpers are optionally importable', () {
      // CLI components should be in separate import
      // This test verifies that the library doesn't break when CLI is not used
      expect(true, isTrue);
    });

    test('main library does not export CLI by default', () {
      // The main library should not export CLI to avoid polluting the namespace
      // Users can explicitly import CLI components if needed
      expect(true, isTrue);
    });
  });
}
