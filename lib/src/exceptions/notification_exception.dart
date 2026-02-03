/// Base exception for notification errors
class NotificationException implements Exception {
  /// Error message
  final String message;

  /// Optional error code
  final String? code;

  NotificationException(this.message, {this.code});

  @override
  String toString() =>
      'NotificationException: $message${code != null ? ' ($code)' : ''}';
}

/// Exception thrown when push notifications are not supported on the platform
class PushNotSupportedException extends NotificationException {
  PushNotSupportedException()
      : super('Push notifications are not supported on this platform');
}
