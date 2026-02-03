import 'dart:io';
import 'package:fluttersdk_magic_notifications/src/cli/cli.dart';

/// Status command for checking Magic Notifications installation
class StatusCommand {
  final String projectRoot;

  StatusCommand({required this.projectRoot});

  /// Check if the plugin is installed in pubspec.yaml
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

  /// Check if config file exists
  bool checkConfigExists() {
    final configPath = '$projectRoot/lib/config/notifications.dart';
    return FileHelper.fileExists(configPath);
  }

  /// Check platform-specific setup
  Map<String, dynamic> checkPlatformSetup() {
    return {
      'android': _checkAndroidSetup(),
      'ios': _checkIOSSetup(),
      'web': _checkWebSetup(),
    };
  }

  /// Check Android platform setup
  Map<String, dynamic> _checkAndroidSetup() {
    final manifestPath =
        '$projectRoot/android/app/src/main/AndroidManifest.xml';

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

  /// Check iOS platform setup
  Map<String, dynamic> _checkIOSSetup() {
    final infoPlistPath = '$projectRoot/ios/Runner/Info.plist';

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

  /// Check Web platform setup
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

  /// Get list of missing requirements
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

      if (issues.isNotEmpty) {
        for (final issue in issues) {
          missing.add('[$platform] $issue');
        }
      }
    }

    return missing;
  }

  /// Generate status report
  ///
  /// If [verbose] is true, shows detailed information about each check.
  String generateReport({bool verbose = false}) {
    final buffer = StringBuffer();
    buffer.writeln('Magic Notifications - Status Report');
    buffer.writeln('=' * 50);
    buffer.writeln();

    // Plugin installation
    final pluginInstalled = checkPluginInstalled();
    buffer.writeln('Plugin Installed: ${pluginInstalled ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Location: pubspec.yaml → dependencies');
      buffer.writeln('    Package: fluttersdk_magic_notifications');
    }

    // Config file
    final configExists = checkConfigExists();
    buffer.writeln('Configuration File: ${configExists ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Path: lib/config/notifications.dart');
    }
    buffer.writeln();

    // Platform status
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

      // Show verbose details per platform
      if (verbose) {
        switch (platform) {
          case 'android':
            buffer.writeln(
                '      Manifest: android/app/src/main/AndroidManifest.xml');
            buffer.writeln('      Required: POST_NOTIFICATIONS permission');
            break;
          case 'ios':
            buffer.writeln('      Info.plist: ios/Runner/Info.plist');
            buffer.writeln(
                '      Required: Push Notifications capability in Xcode');
            break;
          case 'web':
            buffer.writeln('      Service Worker: web/OneSignalSDKWorker.js');
            buffer.writeln('      Required: OneSignal SDK in index.html');
            break;
        }
        if (issues.isNotEmpty) {
          for (final issue in issues) {
            buffer.writeln('      Issue: $issue');
          }
        }
      }
    }

    buffer.writeln();

    // Missing requirements
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
