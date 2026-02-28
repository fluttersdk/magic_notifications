import 'dart:io';
import 'package:magic_cli/magic_cli.dart';

/// CLI command to display all notification channels and their configuration.
///
/// Reads the current `lib/config/notifications.dart` and shows the status
/// of each channel (database, push, mail) in a formatted table.
///
/// ## Usage
/// ```bash
/// dart run magic_notifications channels
/// ```
class ChannelsCommand extends Command {
  @override
  String get name => 'channels';

  @override
  String get description =>
      'Show notification channels and their configuration status';

  /// Get the project root directory.
  ///
  /// @return Absolute path to the project root.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Shortcut for projectRoot.
  String get projectRoot => getProjectRoot();

  @override
  void configure(ArgParser parser) {
    // No options for this command
  }

  @override
  Future<void> handle() async {
    // 1. Display banner with version.
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    final configPath = '$projectRoot/lib/config/notifications.dart';

    // 2. Check if configuration file exists.
    if (!FileHelper.fileExists(configPath)) {
      error('Configuration file not found.');
      info(
        'Run: ${ConsoleStyle.cyan}dart run magic_notifications install${ConsoleStyle.reset} to set up notifications.',
      );
      exit(1);
    }

    // 3. Parse and display channel configuration.
    final config = parseChannelConfig(configPath);
    _displayChannels(config);
  }

  /// Parse channel configuration from the notifications config file.
  ///
  /// @param configPath Absolute path to the notifications.dart config file.
  /// @return Map with 'push', 'database', 'mail' channel data.
  Map<String, dynamic> parseChannelConfig(String configPath) {
    // 1. Read the config file content using FileHelper.
    final content = FileHelper.readFile(configPath);
    final result = <String, dynamic>{};

    // 2. Parse push channel configuration.
    final appIdMatch = RegExp(r"'app_id':\s*'([^']*)'").firstMatch(content);
    final notifyButtonMatch =
        RegExp(r"'notify_button_enabled':\s*(true|false)").firstMatch(content);

    result['push'] = {
      'driver': 'onesignal',
      'app_id': appIdMatch?.group(1) ?? 'NOT SET',
      'notify_button_enabled': notifyButtonMatch?.group(1) == 'true',
    };

    // 3. Parse database channel configuration.
    final pollingMatch =
        RegExp(r"'polling_interval':\s*(\d+)").firstMatch(content);
    final dbContent = content.contains("'database'")
        ? content.substring(content.indexOf("'database'"))
        : '';
    final dbEnabledMatch =
        RegExp(r"'enabled':\s*(true|false)").firstMatch(dbContent);

    result['database'] = {
      'enabled': dbEnabledMatch?.group(1) == 'true',
      'polling_interval': pollingMatch != null
          ? int.tryParse(pollingMatch.group(1)!) ?? 30
          : 30,
    };

    // 4. Parse mail channel configuration.
    final mailContent = content.contains("'mail'")
        ? content.substring(content.indexOf("'mail'"))
        : '';
    final mailEnabledMatch =
        RegExp(r"'enabled':\s*(true|false)").firstMatch(mailContent);

    result['mail'] = {
      'enabled': mailEnabledMatch?.group(1) == 'true',
    };

    // 5. Parse soft_prompt configuration.
    final softContent = content.contains("'soft_prompt'")
        ? content.substring(content.indexOf("'soft_prompt'"))
        : '';
    final softEnabledMatch =
        RegExp(r"'enabled':\s*(true|false)").firstMatch(softContent);

    result['soft_prompt'] = {
      'enabled': softEnabledMatch?.group(1) == 'true',
    };

    return result;
  }

  /// Display the parsed configuration in a formatted output.
  ///
  /// @param config The parsed configuration map.
  void _displayChannels(Map<String, dynamic> config) {
    newLine();
    info('Notification Channels');
    info('=' * 50);
    newLine();

    // 1. Push channel display.
    final push = config['push'] as Map<String, dynamic>;
    final appId = push['app_id'] as String;
    final maskedId = appId.length > 8 ? '${appId.substring(0, 8)}...' : appId;
    info('${ConsoleStyle.cyan}push${ConsoleStyle.reset}');
    info('  Driver:       onesignal');
    info('  App ID:       $maskedId');
    info(
        '  Notify Button: ${push['notify_button_enabled'] == true ? "enabled" : "disabled"}');
    newLine();

    // 2. Database channel display.
    final db = config['database'] as Map<String, dynamic>;
    final dbEnabled = db['enabled'] as bool;
    info('${ConsoleStyle.cyan}database${ConsoleStyle.reset}');
    info('  Status:          ${dbEnabled ? "enabled" : "disabled"}');
    info('  Polling Interval: ${db['polling_interval']}s');
    newLine();

    // 3. Mail channel display.
    final mail = config['mail'] as Map<String, dynamic>;
    final mailEnabled = mail['enabled'] as bool;
    info('${ConsoleStyle.cyan}mail${ConsoleStyle.reset}');
    info('  Status: ${mailEnabled ? "enabled" : "disabled"}');
    newLine();
  }
}
