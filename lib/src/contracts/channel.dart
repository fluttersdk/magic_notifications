import 'notification.dart';
import 'notifiable.dart';

/// Base class for notification channels
///
/// Example:
/// ```dart
/// class DatabaseChannel extends NotificationChannel {
///   @override
///   String get name => 'database';
///
///   @override
///   bool get isAvailable => true;
///
///   @override
///   Future<void> send(Notifiable notifiable, Notification notification) async {
///     final data = notification.toDatabase(notifiable);
///     if (data != null) {
///       await Http.post('/notifications', data: data);
///     }
///   }
/// }
/// ```
abstract class NotificationChannel {
  /// Channel identifier (e.g., 'database', 'push', 'mail')
  String get name;

  /// Whether this channel is available and configured
  bool get isAvailable;

  /// Send notification through this channel
  Future<void> send(Notifiable notifiable, Notification notification);
}
