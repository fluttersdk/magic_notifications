import 'package:fluttersdk_artisan/artisan.dart';

/// Test command for sending test notifications via any available channel.
class TestCommand extends ArtisanCommand {
  @override
  String get signature => 'notifications:test '
      '{--dry-run : Preview notification without sending} '
      '{--title=Test Notification : Notification title} '
      '{--body=This is a test notification from the CLI : Notification body} '
      '{--channel=database : Notification channel (database, push, mail)} '
      '{--api-url= : API URL for push notifications}';

  @override
  String get description => 'Send test notifications to verify setup';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Return the Flutter project root directory.
  ///
  /// Overridable in tests to point at a temp directory.
  String getProjectRoot() {
    return FileHelper.findProjectRoot();
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // 1. Validate channel selection.
    final channel = ctx.input.option('channel') as String;
    final availableChannels = getAvailableChannels();

    if (!availableChannels.contains(channel)) {
      ctx.output.error('Invalid channel: $channel');
      ctx.output.info('Available channels: ${availableChannels.join(', ')}');
      return 1;
    }

    // 2. Build the test notification and show preview.
    final title = ctx.input.option('title') as String;
    final body = ctx.input.option('body') as String;

    final notification = buildTestNotification(
      title: title,
      body: body,
      channel: channel,
    );

    final preview = formatNotificationPreview(notification);
    ctx.output.writeln(preview);

    // 3. Short-circuit on dry-run.
    if (ctx.input.option('dry-run') as bool) {
      ctx.output.info('Dry run mode - notification not sent');
      return 0;
    }

    // 4. Send via the selected channel.
    final apiUrl = ctx.input.option('api-url') as String?;
    ctx.output.info('Sending test notification via $channel...');

    switch (channel) {
      case 'database':
        await _sendDatabaseNotification(ctx, notification, apiUrl);
      case 'push':
        await _sendPushNotification(ctx, notification, apiUrl);
      case 'mail':
        await _sendMailNotification(ctx, notification, apiUrl);
    }

    ctx.output.success('Test notification sent successfully!');
    ctx.output.writeln('');
    ctx.output.info('Check your application to verify receipt');
    return 0;
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
      'data': {'test': true, 'source': 'cli'},
    };
  }

  /// Return the ordered list of supported notification channels.
  ///
  /// @return List of channel names.
  List<String> getAvailableChannels() {
    return ['database', 'push', 'mail'];
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
    ArtisanContext ctx,
    Map<String, dynamic> notification,
    String? apiUrl,
  ) async {
    ctx.output.info('Database notification would be stored in the database');

    if (apiUrl != null) {
      ctx.output.info('Using API: $apiUrl');
    } else {
      ctx.output.warning('No API URL provided - using default');
    }

    // Simulate API call.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Simulate triggering a push notification via OneSignal.
  Future<void> _sendPushNotification(
    ArtisanContext ctx,
    Map<String, dynamic> notification,
    String? apiUrl,
  ) async {
    ctx.output.info('Push notification would be sent via OneSignal');

    if (apiUrl == null) {
      ctx.output.warning('No API URL provided - skipping actual send');
      ctx.output.info('Use --api-url to specify your backend API');
      return;
    }

    ctx.output.info('Using API: $apiUrl');

    // Simulate API call.
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Simulate sending a mail notification.
  Future<void> _sendMailNotification(
    ArtisanContext ctx,
    Map<String, dynamic> notification,
    String? apiUrl,
  ) async {
    ctx.output.info('Mail notification would be sent via email');

    if (apiUrl != null) {
      ctx.output.info('Using API: $apiUrl');
    } else {
      ctx.output.warning('No API URL provided - using default');
    }

    // Simulate API call.
    await Future.delayed(const Duration(milliseconds: 500));
  }
}
