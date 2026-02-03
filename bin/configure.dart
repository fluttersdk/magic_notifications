import 'dart:io';
import 'package:fluttersdk_magic_notifications/src/cli/commands/configure_command.dart';
import 'package:fluttersdk_magic_cli/fluttersdk_magic_cli.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Display this help message',
    )
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

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      _showHelp(parser);
      exit(0);
    }

    print(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // Find project root
    String projectRoot;
    try {
      projectRoot = FileHelper.findProjectRoot();
    } catch (e) {
      print(ConsoleStyle.error(
          'Could not find pubspec.yaml in current directory or parent directories'));
      print(ConsoleStyle.info(
          'Please run this command from your Flutter/Dart project directory'));
      exit(1);
    }

    final command = ConfigureCommand(projectRoot: projectRoot);

    // Check if config exists
    if (!command.configExists()) {
      print(ConsoleStyle.error('Configuration file not found'));
      print(ConsoleStyle.info(
          'Run installation first: dart run fluttersdk_magic_notifications:install'));
      exit(1);
    }

    // Show current configuration
    if (results['show'] as bool) {
      _showConfig(command);
      exit(0);
    }

    // Update configuration
    final updates = <String, dynamic>{};
    bool hasUpdates = false;

    // Update app ID
    if (results['app-id'] != null) {
      final appId = results['app-id'] as String;
      updates['push'] = {'app_id': appId};
      hasUpdates = true;
      print(ConsoleStyle.info('Updating OneSignal App ID...'));
    }

    // Update polling interval
    if (results['polling-interval'] != null) {
      final intervalStr = results['polling-interval'] as String;
      final interval = int.tryParse(intervalStr);

      if (interval == null) {
        print(ConsoleStyle.error('Invalid polling interval: must be a number'));
        exit(1);
      }

      if (!command.validatePollingInterval(interval)) {
        print(ConsoleStyle.error(
            'Invalid polling interval: must be between 5 and 600'));
        exit(1);
      }

      updates['database'] = {'polling_interval': interval};
      hasUpdates = true;
      print(ConsoleStyle.info('Updating polling interval...'));
    }

    // Update soft prompt
    if (results['soft-prompt'] == true) {
      updates['soft_prompt'] = {'enabled': true};
      hasUpdates = true;
      print(ConsoleStyle.info('Enabling soft prompt...'));
    } else if (results['no-soft-prompt'] == true) {
      updates['soft_prompt'] = {'enabled': false};
      hasUpdates = true;
      print(ConsoleStyle.info('Disabling soft prompt...'));
    }

    if (!hasUpdates) {
      print(ConsoleStyle.warning('No configuration updates specified'));
      print(ConsoleStyle.info('Use --help to see available options'));
      print(ConsoleStyle.info('Use --show to view current configuration'));
      exit(0);
    }

    // Apply updates
    command.updateConfig(updates);
    print(ConsoleStyle.success('Configuration updated successfully!'));
    print('');

    // Show updated config
    _showConfig(command);
  } catch (e) {
    print(ConsoleStyle.error('Error: $e'));
    exit(1);
  }
}

void _showHelp(ArgParser parser) {
  print('''
Magic Notifications - Configuration Manager

Usage: dart run fluttersdk_magic_notifications:configure [options]

Options:
${parser.usage}

Examples:
  # Show current configuration
  dart run fluttersdk_magic_notifications:configure --show

  # Update OneSignal App ID
  dart run fluttersdk_magic_notifications:configure --app-id NEW_APP_ID

  # Update polling interval
  dart run fluttersdk_magic_notifications:configure --polling-interval 60

  # Enable soft prompt
  dart run fluttersdk_magic_notifications:configure --soft-prompt

  # Disable soft prompt
  dart run fluttersdk_magic_notifications:configure --no-soft-prompt

  # Multiple updates
  dart run fluttersdk_magic_notifications:configure --app-id NEW_ID --polling-interval 45
''');
}

void _showConfig(ConfigureCommand command) {
  try {
    final config = command.readCurrentConfig();

    print(ConsoleStyle.info('Current Configuration:'));
    print('');

    if (config.containsKey('push')) {
      print('  ${ConsoleStyle.step(1, 3, 'Push Notifications')}');
      print('    App ID: ${config['push']['app_id']}');
      print('');
    }

    if (config.containsKey('database')) {
      print('  ${ConsoleStyle.step(2, 3, 'Database Notifications')}');
      print('    Enabled: ${config['database']['enabled'] ?? 'N/A'}');
      print(
          '    Polling Interval: ${config['database']['polling_interval'] ?? 'N/A'}s');
      print('');
    }

    if (config.containsKey('soft_prompt')) {
      print('  ${ConsoleStyle.step(3, 3, 'Soft Prompt')}');
      print('    Enabled: ${config['soft_prompt']['enabled']}');
      print('');
    }
  } catch (e) {
    print(ConsoleStyle.error('Error reading configuration: $e'));
  }
}
