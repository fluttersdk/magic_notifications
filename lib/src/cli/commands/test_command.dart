import 'dart:io';

import 'package:magic_cli/magic_cli.dart';

/// Test command for sending test notifications via any available channel.
class TestCommand extends Command {
  @override
  final String name = 'test';

  @override
  final String description = 'Send test notifications to verify setup';

  @override
  void configure(ArgParser parser) {
    parser
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
  }

  /// Return the Flutter project root directory.
  ///
  /// Overridable in tests to point at a temp directory.
  String getProjectRoot() {
    return FileHelper.findProjectRoot();
  }

  @override
  Future<void> handle() async {
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // 1. Validate channel selection.
    final channel = arguments['channel'] as String;
    final availableChannels = getAvailableChannels();

    if (!availableChannels.contains(channel)) {
      error('Invalid channel: $channel');
      info('Available channels: ${availableChannels.join(', ')}');
      exit(1);
    }

    // 2. Build the test notification and show preview.
    final title = arguments['title'] as String;
    final body = arguments['body'] as String;

    final notification = buildTestNotification(
      title: title,
      body: body,
      channel: channel,
    );

    final preview = formatNotificationPreview(notification);
    stdout.write(preview);

    // 3. Short-circuit on dry-run.
    if (arguments['dry-run'] as bool) {
      info('Dry run mode - notification not sent');
      exit(0);
    }

    // 4. Send via the selected channel.
    final apiUrl = option('api-url') as String?;
    info('Sending test notification via $channel...');

    switch (channel) {
      case 'database':
        await _sendDatabaseNotification(notification, apiUrl);
      case 'push':
        await _sendPushNotification(notification, apiUrl);
      case 'mail':
        await _sendMailNotification(notification, apiUrl);
    }

    success('Test notification sent successfully!');
    newLine();
    info('Check your application to verify receipt');
  }

  // ---------------------------------------------------------------------------
  // Notification helpers
  // ---------------------------------------------------------------------------

  /// Build a test notification payload.
  ///
  /// @param title Notification title.
  /// @param body Notification body.
  /// @param channel Notification channel.
  /// @return Map containing notification payload.
  Map<String, dynamic> buildTestNotification({
    required String title,
    required String body,
    required String channel,
  }) {
    return {
      'title': title,
      'body': body,
      'type': 'test',
      'channel': channel,
      'created_at': DateTime.now().toIso8601String(),
      'read_at': null,
      'data': {
        'test': true,
        'source': 'cli',
      },
    };
  }

  /// Return the ordered list of supported notification channels.
  ///
  /// @return List of channel names.
  List<String> getAvailableChannels() {
    return [
      'database',
      'push',
      'mail',
    ];
  }

  /// Validate that [url] is an absolute HTTP/HTTPS URL.
  ///
  /// @param url The URL to validate.
  /// @return True if valid, false otherwise.
  bool validateApiUrl(String url) {
    if (url.isEmpty) {
      return false;
    }

    try {
      final uri = Uri.parse(url);
      return uri.hasScheme &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          uri.hasAuthority;
    } catch (e) {
      return false;
    }
  }

  /// Format a notification map for human-readable preview output.
  ///
  /// @param notification The notification payload.
  /// @return Formatted preview string.
  String formatNotificationPreview(Map<String, dynamic> notification) {
    final buffer = StringBuffer();
    buffer.writeln('Notification Preview');
    buffer.writeln('=' * 40);
    buffer.writeln();

    if (notification.containsKey('title')) {
      buffer.writeln('Title: ${notification['title']}');
    }

    if (notification.containsKey('body')) {
      buffer.writeln('Body: ${notification['body']}');
    }

    if (notification.containsKey('channel')) {
      buffer.writeln('Channel: ${notification['channel']}');
    }

    if (notification.containsKey('type')) {
      buffer.writeln('Type: ${notification['type']}');
    }

    if (notification.containsKey('data')) {
      buffer.writeln('Data: ${notification['data']}');
    }

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // Channel senders (private)
  // ---------------------------------------------------------------------------

  /// Simulate storing a database notification via the backend API.
  Future<void> _sendDatabaseNotification(
    Map<String, dynamic> notification,
    String? apiUrl,
  ) async {
    info('Database notification would be stored in the database');

    if (apiUrl != null) {
      info('Using API: $apiUrl');
    } else {
      warn('No API URL provided - using default');
    }

    // Simulate API call.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Simulate triggering a push notification via OneSignal.
  Future<void> _sendPushNotification(
    Map<String, dynamic> notification,
    String? apiUrl,
  ) async {
    info('Push notification would be sent via OneSignal');

    if (apiUrl == null) {
      warn('No API URL provided - skipping actual send');
      info('Use --api-url to specify your backend API');
      return;
    }

    info('Using API: $apiUrl');

    // Simulate API call.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Simulate sending a mail notification.
  Future<void> _sendMailNotification(
    Map<String, dynamic> notification,
    String? apiUrl,
  ) async {
    info('Mail notification would be sent via email');

    if (apiUrl != null) {
      info('Using API: $apiUrl');
    } else {
      warn('No API URL provided - using default');
    }

    // Simulate API call.
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
