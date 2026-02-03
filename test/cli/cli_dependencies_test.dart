import 'dart:io';
import 'package:test/test.dart';
// ignore: depend_on_referenced_packages
import 'package:yaml/yaml.dart';

void main() {
  group('CLI Dependencies', () {
    test('pubspec.yaml includes fluttersdk_magic_cli package', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final yaml = loadYaml(pubspec);
      expect(yaml['dependencies']['fluttersdk_magic_cli'], isNotNull,
          reason:
              'notifications plugin should depend on CLI base for shared helpers');
    });

    test('pubspec.yaml does NOT include redundant CLI deps', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final yaml = loadYaml(pubspec);

      // These should come from fluttersdk_magic_cli, not be direct dependencies
      expect(yaml['dependencies']['interact_cli'], isNull,
          reason: 'interact_cli should come from fluttersdk_magic_cli');
      expect(yaml['dependencies']['args'], isNull,
          reason: 'args should come from fluttersdk_magic_cli');
      expect(yaml['dependencies']['yaml'], isNull,
          reason: 'yaml should come from fluttersdk_magic_cli');
      expect(yaml['dependencies']['yaml_edit'], isNull,
          reason: 'yaml_edit should come from fluttersdk_magic_cli');
    });

    test('CLI base plugin is accessible', () {
      // Verify we can import from the CLI base
      expect(() {
        // This will fail at import if the path is wrong
        final testFile = File('lib/src/cli/cli.dart');
        expect(testFile.existsSync(), isTrue);

        final content = testFile.readAsStringSync();
        expect(content, contains('fluttersdk_magic_cli'));
      }, returnsNormally);
    });
  });
}
