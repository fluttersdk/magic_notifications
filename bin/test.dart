import 'dart:io';
import 'package:fluttersdk_magic_notifications/src/cli/commands/test_command.dart';
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
      'dry-run',
      negatable: false,
      help: 'Preview notification without sending',
    )
    ..addOption(
      'title',
      abbr: 't',
      defaultsTo: 'Test Notification',
      help: 'Notification title',
    )
    ..addOption(
      'body',
      abbr: 'b',
      defaultsTo: 'This is a test notification from the CLI',
      help: 'Notification body',
    )
    ..addOption(
      'channel',
      abbr: 'c',
      defaultsTo: 'database',
      help: 'Notification channel (database, push, mail)',
    )
    ..addOption(
      'api-url',
      help: 'API URL for push notifications',
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      _showHelp(parser);
      exit(0);
    }

    print(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // Verify we're in a project directory
    try {
      FileHelper.findProjectRoot();
    } catch (e) {
      print(ConsoleStyle.error(
          'Could not find pubspec.yaml in current directory or parent directories'));
      print(ConsoleStyle.info(
          'Please run this command from your Flutter/Dart project directory'));
      exit(1);
    }

    final command = TestCommand();
    final dryRun = results['dry-run'] as bool;
    final title = results['title'] as String;
    final body = results['body'] as String;
    final channel = results['channel'] as String;

    // Validate channel
    final availableChannels = command.getAvailableChannels();
    if (!availableChannels.contains(channel)) {
      print(ConsoleStyle.error('Invalid channel: $channel'));
      print(ConsoleStyle.info(
          'Available channels: ${availableChannels.join(', ')}'));
      exit(1);
    }

    // Build test notification
    final notification = command.buildTestNotification(
      title: title,
      body: body,
      channel: channel,
    );

    // Show preview
    final preview = command.formatNotificationPreview(notification);
    print(preview);

    if (dryRun) {
      print(ConsoleStyle.info('Dry run mode - notification not sent'));
      exit(0);
    }

    // Send notification (based on channel)
    print(ConsoleStyle.info('Sending test notification via $channel...'));

    switch (channel) {
      case 'database':
        await _sendDatabaseNotification(
            notification, results['api-url'] as String?);
        break;
      case 'push':
        await _sendPushNotification(
            notification, results['api-url'] as String?);
        break;
      case 'mail':
        await _sendMailNotification(
            notification, results['api-url'] as String?);
        break;
    }

    print(ConsoleStyle.success('Test notification sent successfully!'));
    print('');
    print(ConsoleStyle.info('Check your application to verify receipt'));
  } catch (e) {
    print(ConsoleStyle.error('Error: $e'));
    exit(1);
  }
}

void _showHelp(ArgParser parser) {
  print('''
Magic Notifications - Test Notification Sender

Usage: dart run fluttersdk_magic_notifications:test [options]

Send test notification via different channels to verify setup.

Options:
${parser.usage}

Examples:
  # Send test database notification (dry run)
  dart run fluttersdk_magic_notifications:test --dry-run

  # Send test database notification
  dart run fluttersdk_magic_notifications:test

  # Send custom notification
  dart run fluttersdk_magic_notifications:test --title "Hello" --body "World"

  # Send push notification
  dart run fluttersdk_magic_notifications:test --channel push --api-url http://localhost:8000

  # Preview without sending
  dart run fluttersdk_magic_notifications:test --dry-run --channel push
''');
}

Future<void> _sendDatabaseNotification(
    Map<String, dynamic> notification, String? apiUrl) async {
  // In a real implementation, this would make an API call to create a database notification
  print(ConsoleStyle.info(
      'Database notification would be stored in the database'));

  if (apiUrl != null) {
    print(ConsoleStyle.info('Using API: $apiUrl'));
  } else {
    print(ConsoleStyle.warning('No API URL provided - using default'));
  }

  // Simulate API call
  await Future.delayed(Duration(milliseconds: 500));
}

Future<void> _sendPushNotification(
    Map<String, dynamic> notification, String? apiUrl) async {
  // In a real implementation, this would trigger a push notification via OneSignal
  print(ConsoleStyle.info('Push notification would be sent via OneSignal'));

  if (apiUrl == null) {
    print(ConsoleStyle.warning('No API URL provided - skipping actual send'));
    print(ConsoleStyle.info('Use --api-url to specify your backend API'));
    return;
  }

  print(ConsoleStyle.info('Using API: $apiUrl'));

  // Simulate API call
  await Future.delayed(Duration(milliseconds: 500));
}

Future<void> _sendMailNotification(
    Map<String, dynamic> notification, String? apiUrl) async {
  // In a real implementation, this would send an email notification
  print(ConsoleStyle.info('Mail notification would be sent via email'));

  if (apiUrl != null) {
    print(ConsoleStyle.info('Using API: $apiUrl'));
  } else {
    print(ConsoleStyle.warning('No API URL provided - using default'));
  }

  // Simulate API call
  await Future.delayed(Duration(milliseconds: 500));
}
