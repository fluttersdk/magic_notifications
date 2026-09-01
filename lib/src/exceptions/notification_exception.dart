/// Base exception for notification errors
class NotificationException implements Exception {
  /// Error message
  final String message;

  /// Optional error code
  final String? code;

  const NotificationException(this.message, {this.code});

  @override
  String toString() =>
      'NotificationException: $message${code != null ? ' ($code)' : ''}';
}

/// Thrown when a call needs a push driver this build has no arm for.
///
/// The stub arm of the platform factory throws this instead of returning a
/// driver that would silently do nothing: a caller that only wants "push did
/// not work" catches [NotificationException] for free, and a caller that
/// wants to say something specific about the platform catches this subtype.
class UnsupportedPlatformException extends NotificationException {
  const UnsupportedPlatformException(super.message);
}
