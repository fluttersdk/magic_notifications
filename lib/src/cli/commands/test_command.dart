/// Test command for sending test notifications
class TestCommand {
  TestCommand();

  /// Build a test notification structure
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

  /// Get list of available notification channels
  List<String> getAvailableChannels() {
    return [
      'database',
      'push',
      'mail',
    ];
  }

  /// Validate API URL format
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

  /// Format notification for preview display
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
}
