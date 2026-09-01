import 'package:fluttersdk_artisan/artisan.dart';

import '../notifications_artisan_provider.dart';

/// CLI command to display all notification channels and their configuration.
///
/// Reads the current `lib/config/notifications.dart` and shows the status
/// of each channel (database, push, mail) in a formatted table.
///
/// ## Usage
/// ```bash
/// dart run <app>:artisan notifications:channels
/// ```
class ChannelsCommand extends ArtisanCommand {
  @override
  String get signature => 'notifications:channels';

  @override
  String get description =>
      'Show notification channels and their configuration status';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Get the project root directory.
  ///
  /// @return Absolute path to the project root.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Shortcut for projectRoot.
  String get projectRoot => getProjectRoot();

  @override
  Future<int> handle(ArtisanContext ctx) async {
    // 1. Display banner with version.
    ctx.output.info(
        ConsoleStyle.banner('Magic Notifications', magicNotificationsVersion));

    final configPath = '$projectRoot/lib/config/notifications.dart';

    // 2. Check if configuration file exists.
    if (!FileHelper.fileExists(configPath)) {
      ctx.output.error('Configuration file not found.');
      ctx.output.info(
        'Run: ${ConsoleStyle.cyan}dart run <app>:artisan notifications:install${ConsoleStyle.reset} to set up notifications.',
      );
      return 1;
    }

    // 3. Parse and display channel configuration.
    final config = parseChannelConfig(configPath);
    _displayChannels(ctx, config);
    return 0;
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
    final notifyButtonMatch = RegExp(
      r"'notify_button_enabled':\s*(true|false)",
    ).firstMatch(content);

    result['push'] = {
      'driver': 'onesignal',
      'app_id': appIdMatch?.group(1) ?? 'NOT SET',
      'notify_button_enabled': notifyButtonMatch?.group(1) == 'true',
    };

    // 3. Parse database channel configuration.
    final pollingMatch = RegExp(
      r"'polling_interval':\s*(\d+)",
    ).firstMatch(content);
    final dbContent = content.contains("'database'")
        ? content.substring(content.indexOf("'database'"))
        : '';
    final dbEnabledMatch = RegExp(
      r"'enabled':\s*(true|false)",
    ).firstMatch(dbContent);

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
    final mailEnabledMatch = RegExp(
      r"'enabled':\s*(true|false)",
    ).firstMatch(mailContent);

    result['mail'] = {'enabled': mailEnabledMatch?.group(1) == 'true'};

    // 5. Parse soft_prompt configuration.
    final softContent = content.contains("'soft_prompt'")
        ? content.substring(content.indexOf("'soft_prompt'"))
        : '';
    final softEnabledMatch = RegExp(
      r"'enabled':\s*(true|false)",
    ).firstMatch(softContent);

    result['soft_prompt'] = {'enabled': softEnabledMatch?.group(1) == 'true'};

    return result;
  }

  /// Display the parsed configuration in a formatted output.
  ///
  /// @param config The parsed configuration map.
  void _displayChannels(ArtisanContext ctx, Map<String, dynamic> config) {
    ctx.output.writeln('');
    ctx.output.info('Notification Channels');
    ctx.output.info('=' * 50);
    ctx.output.writeln('');

    // 1. Push channel display.
    final push = config['push'] as Map<String, dynamic>;
    final appId = push['app_id'] as String;
    final maskedId = appId.length > 8 ? '${appId.substring(0, 8)}...' : appId;
    ctx.output.info('${ConsoleStyle.cyan}push${ConsoleStyle.reset}');
    ctx.output.info('  Driver:       onesignal');
    ctx.output.info('  App ID:       $maskedId');
    ctx.output.info(
      '  Notify Button: ${push['notify_button_enabled'] == true ? "enabled" : "disabled"}',
    );
    ctx.output.writeln('');

    // 2. Database channel display.
    final db = config['database'] as Map<String, dynamic>;
    final dbEnabled = db['enabled'] as bool;
    ctx.output.info('${ConsoleStyle.cyan}database${ConsoleStyle.reset}');
    ctx.output.info('  Status:          ${dbEnabled ? "enabled" : "disabled"}');
    ctx.output.info('  Polling Interval: ${db['polling_interval']}s');
    ctx.output.writeln('');

    // 3. Mail channel display.
    final mail = config['mail'] as Map<String, dynamic>;
    final mailEnabled = mail['enabled'] as bool;
    ctx.output.info('${ConsoleStyle.cyan}mail${ConsoleStyle.reset}');
    ctx.output.info('  Status: ${mailEnabled ? "enabled" : "disabled"}');
    ctx.output.writeln('');
  }
}
