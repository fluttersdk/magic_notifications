import 'dart:io';

import 'package:magic_cli/magic_cli.dart';

/// CLI command for reading and updating Magic Notifications configuration.
///
/// Supports displaying the current config (--show) and mutating individual
/// fields via named options. All file I/O is delegated to [FileHelper] so that
/// tests can safely intercept by overriding [getProjectRoot].
class ConfigureCommand extends Command {
  @override
  final String name = 'configure';

  @override
  final String description = 'Update Magic Notifications settings';

  /// Absolute path to the Flutter project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolve the Flutter project root — may be overridden in tests.
  String getProjectRoot() => FileHelper.findProjectRoot();

  @override
  void configure(ArgParser parser) {
    parser
      ..addFlag(
        'show',
        negatable: false,
        help: 'Show current configuration',
      )
      ..addOption(
        'app-id',
        help: 'Update OneSignal App ID',
      )
      ..addOption(
        'polling-interval',
        help: 'Update polling interval (seconds, 5-600)',
      )
      ..addFlag(
        'soft-prompt',
        help: 'Enable soft prompt',
      )
      ..addFlag(
        'no-soft-prompt',
        negatable: false,
        help: 'Disable soft prompt',
      );
  }

  /// Absolute path to the notifications config file.
  String get _configPath => '$projectRoot/lib/config/notifications.dart';

  /// Returns true when the notifications config file exists on disk.
  bool configExists() {
    return FileHelper.fileExists(_configPath);
  }

  @override
  Future<void> handle() async {
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // Check if config exists before proceeding with any operation.
    if (!configExists()) {
      error('Configuration file not found');
      info('Run installation first: dart run magic_notifications install');
      exit(1);
    }

    // Show current configuration and exit early.
    if (hasOption('show') && arguments['show'] as bool) {
      _showConfig();
      return;
    }

    // Accumulate requested updates before applying them.
    final updates = <String, dynamic>{};
    bool hasUpdates = false;

    // Update app ID
    if (hasOption('app-id')) {
      final appId = option('app-id') as String;
      updates['push'] = {'app_id': appId};
      hasUpdates = true;
      info('Updating OneSignal App ID...');
    }

    // Update polling interval
    if (hasOption('polling-interval')) {
      final intervalStr = option('polling-interval') as String;
      final interval = int.tryParse(intervalStr);

      if (interval == null) {
        error('Invalid polling interval: must be a number');
        exit(1);
      }

      if (!validatePollingInterval(interval)) {
        error('Invalid polling interval: must be between 5 and 600');
        exit(1);
      }

      updates['database'] = {'polling_interval': interval};
      hasUpdates = true;
      info('Updating polling interval...');
    }

    // Update soft prompt
    if (hasOption('soft-prompt') && arguments.wasParsed('soft-prompt')) {
      if (arguments['soft-prompt'] == true) {
        updates['soft_prompt'] = {'enabled': true};
        hasUpdates = true;
        info('Enabling soft prompt...');
      }
    } else if (hasOption('no-soft-prompt') &&
        arguments.wasParsed('no-soft-prompt')) {
      if (arguments['no-soft-prompt'] == true) {
        updates['soft_prompt'] = {'enabled': false};
        hasUpdates = true;
        info('Disabling soft prompt...');
      }
    }

    if (!hasUpdates) {
      warn('No configuration updates specified');
      info('Use --help to see available options');
      info('Use --show to view current configuration');
      return;
    }

    // Apply updates and confirm success.
    updateConfig(updates);
    success('Configuration updated successfully!\n');

    // Show updated config so the user can verify the changes.
    _showConfig();
  }

  /// Print a formatted summary of the current config values.
  void _showConfig() {
    try {
      final config = readCurrentConfig();

      info('Current Configuration:\n');

      if (config.containsKey('push')) {
        info('  ${ConsoleStyle.step(1, 3, 'Push Notifications')}');
        info('    App ID: ${config['push']['app_id']}\n');
      }

      if (config.containsKey('database')) {
        info('  ${ConsoleStyle.step(2, 3, 'Database Notifications')}');
        info('    Enabled: ${config['database']['enabled'] ?? 'N/A'}');
        info(
          '    Polling Interval: ${config['database']['polling_interval'] ?? 'N/A'}s\n',
        );
      }

      if (config.containsKey('soft_prompt')) {
        info('  ${ConsoleStyle.step(3, 3, 'Soft Prompt')}');
        info('    Enabled: ${config['soft_prompt']['enabled']}\n');
      }
    } catch (e) {
      error('Error reading configuration: $e');
    }
  }

  /// Read and parse the current configuration from the Dart config file.
  ///
  /// Uses simple regex extraction — NOT an AST parser. The format is
  /// intentionally kept stable so regex remains sufficient.
  ///
  /// Throws [FileSystemException] when the config file does not exist.
  Map<String, dynamic> readCurrentConfig() {
    if (!configExists()) {
      throw FileSystemException('Configuration file not found', _configPath);
    }

    // 1. Read raw Dart source via FileHelper — avoids direct File() usage.
    final content = FileHelper.readFile(_configPath);

    final config = <String, dynamic>{};

    // 2. Extract push.app_id.
    // Matches: 'app_id': 'some-uuid-value'
    final pushAppIdMatch = RegExp(r"'app_id':\s*'([^']*)'").firstMatch(content);
    if (pushAppIdMatch != null) {
      config['push'] = {'app_id': pushAppIdMatch.group(1)};
    }

    // 3. Extract database.polling_interval and database.enabled.
    // Matches: 'polling_interval': 30
    final pollingMatch =
        RegExp(r"'polling_interval':\s*(\d+)").firstMatch(content);

    // Matches: 'enabled': true|false within the database section specifically.
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

    // 4. Extract soft_prompt.enabled.
    // Matches: 'enabled': true|false within the soft_prompt section.
    final softPromptMatch =
        RegExp(r"'soft_prompt':\s*\{[^}]*'enabled':\s*(true|false)")
            .firstMatch(content);
    if (softPromptMatch != null) {
      config['soft_prompt'] = {'enabled': softPromptMatch.group(1) == 'true'};
    }

    return config;
  }

  /// Apply [updates] to the config file using regex replacement.
  ///
  /// Supports updating: push.app_id, database.polling_interval,
  /// database.enabled, and soft_prompt.enabled.
  ///
  /// Throws [FileSystemException] when the config file does not exist.
  void updateConfig(Map<String, dynamic> updates) {
    if (!configExists()) {
      throw FileSystemException('Configuration file not found', _configPath);
    }

    // 1. Read current content via FileHelper.
    var content = FileHelper.readFile(_configPath);

    // 2. Update push.app_id.
    // Matches: 'app_id': 'some-uuid-value'
    if (updates.containsKey('push') && updates['push']['app_id'] != null) {
      final newAppId = updates['push']['app_id'];
      content = content.replaceAllMapped(
        RegExp(r"'app_id':\s*'[^']*'"),
        (match) => "'app_id': '$newAppId'",
      );
    }

    // 3. Update database.polling_interval.
    // Matches: 'polling_interval': <integer>
    if (updates.containsKey('database') &&
        updates['database']['polling_interval'] != null) {
      final newInterval = updates['database']['polling_interval'];
      content = content.replaceAllMapped(
        RegExp(r"'polling_interval':\s*\d+"),
        (match) => "'polling_interval': $newInterval",
      );
    }

    // 4. Update database.enabled.
    // Matches: 'enabled': true|false within database section.
    if (updates.containsKey('database') &&
        updates['database']['enabled'] != null) {
      final newEnabled = updates['database']['enabled'];
      final dbSection = RegExp(
        r"('database':\s*\{[^}]*'enabled':\s*)(true|false)",
      );
      content = content.replaceAllMapped(
        dbSection,
        (match) => '${match.group(1)}$newEnabled',
      );
    }

    // 5. Update soft_prompt.enabled.
    // Matches: 'enabled': true|false within soft_prompt section.
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

    // 6. Write updated content back via FileHelper.
    FileHelper.writeFile(_configPath, content);
  }

  /// Returns the list of configurable option names.
  List<String> getConfigOptions() {
    return [
      'OneSignal App ID',
      'Soft Prompt',
      'Polling Interval',
      'Database Notifications',
      'Mail Notifications',
    ];
  }

  /// Validates that [interval] is within the accepted range (5–600 seconds).
  bool validatePollingInterval(int interval) {
    return interval >= 5 && interval <= 600;
  }
}
