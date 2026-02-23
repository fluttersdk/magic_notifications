import 'dart:io';
import 'package:magic_notifications/src/cli/cli.dart';

/// Configuration command for updating Magic Notifications settings
class ConfigureCommand {
  final String projectRoot;

  ConfigureCommand({required this.projectRoot});

  /// Get path to notifications config file
  String get _configPath => '$projectRoot/lib/config/notifications.dart';

  /// Check if config file exists
  bool configExists() {
    return FileHelper.fileExists(_configPath);
  }

  /// Read and parse current configuration
  Map<String, dynamic> readCurrentConfig() {
    if (!configExists()) {
      throw FileSystemException('Configuration file not found', _configPath);
    }

    final content = File(_configPath).readAsStringSync();

    // Parse the Dart config file
    // This is a simple parser - extracts values from the map structure
    final config = <String, dynamic>{};

    // Extract push config
    final pushAppIdMatch = RegExp(r"'app_id':\s*'([^']*)'").firstMatch(content);
    if (pushAppIdMatch != null) {
      config['push'] = {'app_id': pushAppIdMatch.group(1)};
    }

    // Extract database config
    final pollingMatch =
        RegExp(r"'polling_interval':\s*(\d+)").firstMatch(content);
    final dbEnabledMatch = RegExp(r"'enabled':\s*(true|false)").firstMatch(
      content.substring(content.indexOf("'database'")),
    );

    if (pollingMatch != null || dbEnabledMatch != null) {
      config['database'] = {
        if (pollingMatch != null)
          'polling_interval': int.parse(pollingMatch.group(1)!),
        if (dbEnabledMatch != null)
          'enabled': dbEnabledMatch.group(1) == 'true',
      };
    }

    // Extract soft_prompt config
    final softPromptMatch =
        RegExp(r"'soft_prompt':\s*\{[^}]*'enabled':\s*(true|false)")
            .firstMatch(content);
    if (softPromptMatch != null) {
      config['soft_prompt'] = {'enabled': softPromptMatch.group(1) == 'true'};
    }

    return config;
  }

  /// Update configuration with new values
  void updateConfig(Map<String, dynamic> updates) {
    if (!configExists()) {
      throw FileSystemException('Configuration file not found', _configPath);
    }

    var content = File(_configPath).readAsStringSync();

    // Update push app_id
    if (updates.containsKey('push') && updates['push']['app_id'] != null) {
      final newAppId = updates['push']['app_id'];
      content = content.replaceAllMapped(
        RegExp(r"'app_id':\s*'[^']*'"),
        (match) => "'app_id': '$newAppId'",
      );
    }

    // Update database polling_interval
    if (updates.containsKey('database') &&
        updates['database']['polling_interval'] != null) {
      final newInterval = updates['database']['polling_interval'];
      content = content.replaceAllMapped(
        RegExp(r"'polling_interval':\s*\d+"),
        (match) => "'polling_interval': $newInterval",
      );
    }

    // Update database enabled
    if (updates.containsKey('database') &&
        updates['database']['enabled'] != null) {
      final newEnabled = updates['database']['enabled'];
      // Find the database section and update its enabled value
      final dbSection = RegExp(
        r"('database':\s*\{[^}]*'enabled':\s*)(true|false)",
      );
      content = content.replaceAllMapped(
        dbSection,
        (match) => '${match.group(1)}$newEnabled',
      );
    }

    // Update soft_prompt enabled
    if (updates.containsKey('soft_prompt') &&
        updates['soft_prompt']['enabled'] != null) {
      final newEnabled = updates['soft_prompt']['enabled'];
      final softPromptSection = RegExp(
        r"('soft_prompt':\s*\{[^}]*'enabled':\s*)(true|false)",
      );
      content = content.replaceAllMapped(
        softPromptSection,
        (match) => '${match.group(1)}$newEnabled',
      );
    }

    File(_configPath).writeAsStringSync(content);
  }

  /// Get list of configurable options
  List<String> getConfigOptions() {
    return [
      'OneSignal App ID',
      'Soft Prompt',
      'Polling Interval',
      'Database Notifications',
      'Mail Notifications',
    ];
  }

  /// Validate polling interval (must be between 5 and 600 seconds)
  bool validatePollingInterval(int interval) {
    return interval >= 5 && interval <= 600;
  }
}
