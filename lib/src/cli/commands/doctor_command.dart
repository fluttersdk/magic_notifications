import 'dart:io';

import 'package:magic_cli/magic_cli.dart';
import 'package:magic_notifications/src/cli/cli.dart';

/// Diagnostic command for checking Magic Notifications health.
///
/// Performs a comprehensive health check across plugin installation, config
/// validity, and platform-specific setup. Replaces the [StatusCommand] with
/// richer validation including UUID format and polling_interval range checks.
///
/// Exits with code 0 when all checks pass, code 1 when any check fails.
///
/// ## Usage
/// ```bash
/// dart run magic_notifications doctor
/// dart run magic_notifications doctor --verbose
/// ```
class DoctorCommand extends Command {
  @override
  String get name => 'doctor';

  @override
  String get description =>
      'Check Magic Notifications installation and configuration health';

  /// Absolute path to the Flutter project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolve the Flutter project root — may be overridden in tests.
  String getProjectRoot() => FileHelper.findProjectRoot();

  @override
  void configure(ArgParser parser) {
    parser.addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show detailed diagnostic information',
    );
  }

  @override
  Future<void> handle() async {
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // 1. Collect missing requirements before printing — we need both for output.
    final verbose = arguments['verbose'] as bool;
    final missing = getMissingRequirements();

    // 2. Print human-readable report.
    stdout.write(generateReport(verbose: verbose));

    // 3. Exit with appropriate code.
    if (missing.isEmpty) {
      success('All checks passed!');
      newLine();
      exit(0);
    } else {
      newLine();
      warn('Issues detected. Run the following to fix:');
      stdout.writeln('  • Install: dart run magic_notifications install');
      stdout.writeln('  • Configure: dart run magic_notifications configure');
      exit(1);
    }
  }

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------

  /// Check if the plugin is listed under `dependencies` in pubspec.yaml.
  ///
  /// Looks specifically for `magic_notifications` — NOT the legacy package name.
  bool checkPluginInstalled() {
    final pubspecPath = '$projectRoot/pubspec.yaml';

    if (!FileHelper.fileExists(pubspecPath)) {
      return false;
    }

    try {
      final yaml = FileHelper.readYamlFile(pubspecPath);
      final dependencies = yaml['dependencies'];

      if (dependencies is Map) {
        return dependencies.containsKey('magic_notifications');
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if `lib/config/notifications.dart` exists in the project root.
  bool checkConfigExists() {
    final configPath = '$projectRoot/lib/config/notifications.dart';
    return FileHelper.fileExists(configPath);
  }

  /// Validate that the `app_id` is a proper UUID and that `polling_interval`
  /// falls within the accepted range of 5–600 seconds.
  ///
  /// Returns a list of human-readable issue strings; empty means valid.
  List<String> validateConfig() {
    final configPath = '$projectRoot/lib/config/notifications.dart';

    if (!FileHelper.fileExists(configPath)) {
      return ['Config file not found at lib/config/notifications.dart'];
    }

    final content = FileHelper.readFile(configPath);
    final issues = <String>[];

    // 1. Validate app_id presence and UUID format.
    final appIdMatch = RegExp(r"'app_id':\s*'([^']*)'").firstMatch(content);
    if (appIdMatch == null) {
      issues.add('App ID not found in config');
    } else {
      final appId = appIdMatch.group(1)!;
      if (appId.isEmpty || appId == 'YOUR_APP_ID') {
        issues.add('App ID is placeholder/empty — set a real OneSignal App ID');
      } else if (!validateAppIdFormat(appId)) {
        issues.add(
          'App ID "$appId" is not valid UUID format '
          '(expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)',
        );
      }
    }

    // 2. Validate polling_interval range (5–600 seconds).
    final pollingMatch =
        RegExp(r"'polling_interval':\s*(\d+)").firstMatch(content);
    if (pollingMatch != null) {
      final interval = int.tryParse(pollingMatch.group(1)!);
      if (interval != null && (interval < 5 || interval > 600)) {
        issues.add(
          'polling_interval ($interval) is out of valid range (5–600 seconds)',
        );
      }
    }

    // 3. Ensure soft_prompt section is present.
    if (!content.contains("'soft_prompt'")) {
      issues.add(
        'soft_prompt section missing from config — '
        'add a soft_prompt block to notifications.dart',
      );
    }

    return issues;
  }

  /// Validate that [appId] matches the OneSignal UUID format (8-4-4-4-12 hex).
  ///
  /// Reuses the same regex as [InstallCommand.validateOneSignalAppId].
  bool validateAppIdFormat(String appId) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(appId);
  }

  /// Check platform-specific setup for all detected platforms.
  ///
  /// Uses [PlatformHelper.detectPlatforms] to find which platforms exist, then
  /// inspects each platform's configuration files for required entries.
  Map<String, dynamic> checkPlatformSetup() {
    final platforms = PlatformHelper.detectPlatforms(projectRoot);
    final result = <String, dynamic>{};

    if (platforms.contains('android')) {
      result['android'] = _checkAndroidSetup();
    }

    if (platforms.contains('ios')) {
      result['ios'] = _checkIOSSetup();
    }

    if (platforms.contains('web')) {
      result['web'] = _checkWebSetup();
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Platform checks (private)
  // ---------------------------------------------------------------------------

  /// Inspect AndroidManifest.xml for the POST_NOTIFICATIONS permission.
  Map<String, dynamic> _checkAndroidSetup() {
    final manifestPath = PlatformHelper.androidManifestPath(projectRoot);

    if (!FileHelper.fileExists(manifestPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['AndroidManifest.xml not found'],
      };
    }

    final manifest = FileHelper.readFile(manifestPath);
    final hasPermission = manifest.contains('POST_NOTIFICATIONS');

    return {
      'configured': hasPermission,
      'exists': true,
      'issues': hasPermission
          ? <String>[]
          : ['Missing POST_NOTIFICATIONS permission in AndroidManifest.xml'],
    };
  }

  /// Inspect ios/Runner/Info.plist for basic existence.
  Map<String, dynamic> _checkIOSSetup() {
    final infoPlistPath = PlatformHelper.infoPlistPath(projectRoot);

    if (!FileHelper.fileExists(infoPlistPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['Info.plist not found'],
      };
    }

    return {
      'configured': false,
      'exists': true,
      'issues': ['iOS configuration requires manual setup in Xcode'],
    };
  }

  /// Check for the OneSignal service worker file in the web directory.
  Map<String, dynamic> _checkWebSetup() {
    final workerPath = '$projectRoot/web/OneSignalSDKWorker.js';

    if (!FileHelper.fileExists(workerPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['OneSignalSDKWorker.js not found in web/'],
      };
    }

    return {
      'configured': true,
      'exists': true,
      'issues': <String>[],
    };
  }

  // ---------------------------------------------------------------------------
  // Report
  // ---------------------------------------------------------------------------

  /// Return every unmet requirement across plugin, config, validation, and
  /// platform checks.
  List<String> getMissingRequirements() {
    final missing = <String>[];

    // 1. Plugin installation.
    if (!checkPluginInstalled()) {
      missing.add('Magic notifications plugin not installed in pubspec.yaml');
    }

    // 2. Config file existence.
    if (!checkConfigExists()) {
      missing
          .add('Configuration file not found (lib/config/notifications.dart)');
    }

    // 3. Config content validation (only when the file exists).
    if (checkConfigExists()) {
      missing.addAll(validateConfig());
    }

    // 4. Platform setup.
    final platformStatus = checkPlatformSetup();
    for (final entry in platformStatus.entries) {
      final platform = entry.key;
      final status = entry.value as Map<String, dynamic>;
      final issues = status['issues'] as List;

      for (final issue in issues) {
        missing.add('[$platform] $issue');
      }
    }

    return missing;
  }

  /// Generate a human-readable diagnostic report.
  ///
  /// When [verbose] is `true`, additional detail lines are shown for each
  /// check (paths, required keys, etc.).
  String generateReport({bool verbose = false}) {
    final buffer = StringBuffer();
    buffer.writeln('Magic Notifications — Doctor Report');
    buffer.writeln('=' * 50);
    buffer.writeln();

    // 1. Plugin installation.
    final pluginInstalled = checkPluginInstalled();
    buffer.writeln('Plugin Installed: ${pluginInstalled ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Location: pubspec.yaml → dependencies');
      buffer.writeln('    Package: magic_notifications');
    }

    // 2. Config file.
    final configExists = checkConfigExists();
    buffer.writeln('Configuration File: ${configExists ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Path: lib/config/notifications.dart');
    }
    buffer.writeln();

    // 3. Config validation (only when config exists).
    buffer.writeln('Config Validation:');
    if (!configExists) {
      buffer.writeln('  ✗ Skipped — config file missing');
    } else {
      final configIssues = validateConfig();
      if (configIssues.isEmpty) {
        buffer.writeln('  ✓ All config checks passed');
      } else {
        for (final issue in configIssues) {
          buffer.writeln('  ✗ $issue');
        }
      }
    }
    buffer.writeln();

    // 4. Platform setup.
    buffer.writeln('Platform Setup:');
    final platformStatus = checkPlatformSetup();

    if (platformStatus.isEmpty) {
      buffer.writeln('  No platforms detected');
    } else {
      for (final entry in platformStatus.entries) {
        final platform = entry.key;
        final status = entry.value as Map<String, dynamic>;
        final configured = status['configured'] as bool;
        final exists = status['exists'] as bool;
        final issues = status['issues'] as List;

        buffer.write('  ${platform.toUpperCase()}: ');
        if (configured) {
          buffer.writeln('✓ Configured');
        } else if (exists) {
          buffer.writeln('⚠ Needs configuration');
        } else {
          buffer.writeln('✗ Not found');
        }

        if (verbose) {
          switch (platform) {
            case 'android':
              buffer.writeln(
                '      Manifest: android/app/src/main/AndroidManifest.xml',
              );
              buffer.writeln('      Required: POST_NOTIFICATIONS permission');
            case 'ios':
              buffer.writeln('      Info.plist: ios/Runner/Info.plist');
              buffer.writeln(
                '      Required: Push Notifications capability in Xcode',
              );
            case 'web':
              buffer.writeln(
                '      Service Worker: web/OneSignalSDKWorker.js',
              );
              buffer.writeln('      Required: OneSignal SDK in index.html');
          }
          for (final issue in issues) {
            buffer.writeln('      Issue: $issue');
          }
        }
      }
    }

    buffer.writeln();

    // 5. Summary.
    final missing = getMissingRequirements();
    if (missing.isEmpty) {
      buffer.writeln('✓ All requirements met!');
    } else {
      buffer.writeln('Missing Requirements:');
      for (final issue in missing) {
        buffer.writeln('  ✗ $issue');
      }
    }

    return buffer.toString();
  }
}
