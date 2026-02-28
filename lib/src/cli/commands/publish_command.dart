import 'dart:convert';
import 'dart:io';

import 'package:magic_cli/magic_cli.dart';

/// CLI command to publish Magic Notifications stub files to the project.
///
/// Copies the notification config stub to `lib/config/notifications.dart`
/// with default placeholder values filled in for user customization.
/// This is the Laravel `vendor:publish` equivalent — no wizard, no injection.
///
/// Use the `install` command to inject providers and perform platform setup.
///
/// ## Usage
///
/// ```bash
/// dart run magic_notifications publish
/// dart run magic_notifications publish --force
/// ```
class PublishCommand extends Command {
  @override
  String get name => 'publish';

  @override
  String get description =>
      'Publish Magic Notifications config stub for customization';

  /// Absolute path to the Flutter project root, resolved on first access.
  String get projectRoot => getProjectRoot();

  /// Resolve the Flutter project root — may be overridden in tests.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Returns the paths to search for stubs.
  ///
  /// Overridable in tests.
  List<String> getStubSearchPaths() {
    return [
      _resolvePluginStubsDir(),
      '${Directory.current.path}/assets/stubs',
    ];
  }

  @override
  void configure(ArgParser parser) {
    parser.addFlag(
      'force',
      abbr: 'f',
      help: 'Overwrite existing published files.',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  Future<void> handle() async {
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    final force = arguments['force'] as bool? ?? false;
    final configPath = '$projectRoot/lib/config/notifications.dart';

    // 1. Guard against overwriting existing file without explicit --force flag.
    if (FileHelper.fileExists(configPath) && !force) {
      warn('lib/config/notifications.dart already exists.');
      warn('Use --force to overwrite.');
      return;
    }

    // 2. Load the notification_config stub and replace placeholders with
    //    sensible defaults so the user has a ready-to-edit starting point.
    final stub = StubLoader.load(
      'install/notification_config',
      searchPaths: getStubSearchPaths(),
    );
    final content = StubLoader.replace(stub, {
      'oneSignalAppId': 'YOUR_ONESIGNAL_APP_ID',
      'safariWebIdLine': '',
      'notifyButtonEnabled': 'false',
      'softPromptEnabled': 'true',
    });

    // 3. Ensure the target directory exists before writing.
    final configDir = Directory('$projectRoot/lib/config');
    if (!configDir.existsSync()) {
      configDir.createSync(recursive: true);
    }

    // 4. Write the populated stub to the project.
    FileHelper.writeFile(configPath, content);
    success('Published lib/config/notifications.dart');

    // 5. Guide the user toward their next actions.
    newLine();
    info('Next steps:');
    info(
      "  1. Update 'YOUR_ONESIGNAL_APP_ID' with your actual OneSignal App ID",
    );
    info(
      '  2. Run: ${ConsoleStyle.cyan}dart run magic_notifications install'
      '${ConsoleStyle.reset}',
    );
    info('     to inject providers and platform setup');
  }

  /// Resolve the package assets directory from `.dart_tool/package_config.json`.
  ///
  /// Tries to locate the `magic_notifications` rootUri and derive the
  /// `assets/stubs` path from it.  Falls back to `Directory.current` when the
  /// config file is absent or the package entry cannot be found.
  String _resolvePluginStubsDir() {
    final packageConfigPath =
        '${Directory.current.path}/.dart_tool/package_config.json';

    if (File(packageConfigPath).existsSync()) {
      final content = File(packageConfigPath).readAsStringSync();
      try {
        final map = jsonDecode(content) as Map<String, dynamic>;
        final packages = map['packages'] as List<dynamic>? ?? [];
        for (final package in packages) {
          if (package['name'] == 'magic_notifications') {
            final rootUri = package['rootUri'] as String;
            String parsedPath;
            if (rootUri.startsWith('file://')) {
              parsedPath = Uri.parse(rootUri).toFilePath();
            } else if (rootUri.startsWith('../')) {
              parsedPath = File(packageConfigPath)
                  .parent
                  .parent
                  .uri
                  .resolve(rootUri)
                  .toFilePath();
            } else {
              parsedPath = rootUri;
            }
            return '$parsedPath/assets/stubs'.replaceAll('//', '/');
          }
        }
      } catch (_) {
        // Fallback below.
      }
    }

    return '${Directory.current.path}/assets/stubs';
  }
}
