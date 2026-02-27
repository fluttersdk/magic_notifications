import 'dart:io';

import 'package:magic_notifications/src/cli/cli.dart';

/// Status command for checking Magic Notifications installation and platform setup.
class StatusCommand extends Command {
  @override
  final String name = 'status';

  @override
  final String description = 'Check Magic Notifications installation status';

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
      help: 'Show detailed status information',
    );
  }

  @override
  Future<void> handle() async {
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // 1. Generate and print the status report.
    final verbose = arguments['verbose'] as bool;
    final report = generateReport(verbose: verbose);
    stdout.write(report);

    // 2. Evaluate missing requirements and exit appropriately.
    final missing = getMissingRequirements();

    if (missing.isEmpty) {
      success('All checks passed!');
      newLine();
      info('Next steps:');
      stdout.writeln(
          '  • Test notifications: dart run magic_notifications:notifications test');
      stdout.writeln(
          '  • Update configuration: dart run magic_notifications:notifications configure');
      exit(0);
    } else {
      newLine();
      warn('Issues detected. Run the following to fix:');
      stdout.writeln(
          '  • Install: dart run magic_notifications:notifications install');
      stdout.writeln(
          '  • Configure: dart run magic_notifications:notifications configure');
      exit(1);
    }
  }

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------

  /// Check if the plugin is installed in pubspec.yaml.
  bool checkPluginInstalled() {
    final pubspecPath = '$projectRoot/pubspec.yaml';

    if (!FileHelper.fileExists(pubspecPath)) {
      return false;
    }

    try {
      final yaml = FileHelper.readYamlFile(pubspecPath);
      final dependencies = yaml['dependencies'];

      if (dependencies is Map) {
        return dependencies.containsKey('fluttersdk_magic_notifications');
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if the notifications config file exists.
  bool checkConfigExists() {
    final configPath = '$projectRoot/lib/config/notifications.dart';
    return FileHelper.fileExists(configPath);
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

  /// Inspect AndroidManifest.xml for POST_NOTIFICATIONS permission.
  Map<String, dynamic> _checkAndroidSetup() {
    final manifestPath = PlatformHelper.androidManifestPath(projectRoot);

    if (!FileHelper.fileExists(manifestPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['AndroidManifest.xml not found'],
      };
    }

    final manifest = File(manifestPath).readAsStringSync();
    final hasPermission = manifest.contains('POST_NOTIFICATIONS');

    return {
      'configured': hasPermission,
      'exists': true,
      'issues': hasPermission
          ? []
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
      'issues': ['iOS configuration requires manual setup'],
    };
  }

  /// Check for the OneSignal service worker file.
  Map<String, dynamic> _checkWebSetup() {
    final workerPath = '$projectRoot/web/OneSignalSDKWorker.js';

    if (!FileHelper.fileExists(workerPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['OneSignalSDKWorker.js not found'],
      };
    }

    return {
      'configured': true,
      'exists': true,
      'issues': [],
    };
  }

  // ---------------------------------------------------------------------------
  // Report
  // ---------------------------------------------------------------------------

  /// Return a list of every unmet requirement across plugin, config, and platforms.
  List<String> getMissingRequirements() {
    final missing = <String>[];

    if (!checkPluginInstalled()) {
      missing.add('Magic notifications plugin not installed in pubspec.yaml');
    }

    if (!checkConfigExists()) {
      missing
          .add('Configuration file not found (lib/config/notifications.dart)');
    }

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

  /// Generate a human-readable status report.
  ///
  /// If [verbose] is true, shows detailed information about each check.
  String generateReport({bool verbose = false}) {
    final buffer = StringBuffer();
    buffer.writeln('Magic Notifications - Status Report');
    buffer.writeln('=' * 50);
    buffer.writeln();

    // 1. Plugin installation.
    final pluginInstalled = checkPluginInstalled();
    buffer.writeln('Plugin Installed: ${pluginInstalled ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Location: pubspec.yaml → dependencies');
      buffer.writeln('    Package: fluttersdk_magic_notifications');
    }

    // 2. Config file.
    final configExists = checkConfigExists();
    buffer.writeln('Configuration File: ${configExists ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Path: lib/config/notifications.dart');
    }
    buffer.writeln();

    // 3. Platform setup.
    buffer.writeln('Platform Setup:');
    final platformStatus = checkPlatformSetup();

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
                '      Manifest: android/app/src/main/AndroidManifest.xml');
            buffer.writeln('      Required: POST_NOTIFICATIONS permission');
          case 'ios':
            buffer.writeln('      Info.plist: ios/Runner/Info.plist');
            buffer.writeln(
                '      Required: Push Notifications capability in Xcode');
          case 'web':
            buffer.writeln('      Service Worker: web/OneSignalSDKWorker.js');
            buffer.writeln('      Required: OneSignal SDK in index.html');
        }
        for (final issue in issues) {
          buffer.writeln('      Issue: $issue');
        }
      }
    }

    buffer.writeln();

    // 4. Summary.
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
