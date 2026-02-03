import '../contracts/channel.dart';
import '../contracts/notifiable.dart';
import '../contracts/notification.dart';

/// Database channel for in-app notifications.
///
/// In the Magic Framework notification architecture:
/// - **Backend (Laravel)**: Creates and stores notifications in the database
/// - **Frontend (Flutter)**: Reads notifications via API and displays them
///
/// This channel's `send()` method is a no-op because database notifications
/// are typically created server-side (e.g., when a monitor goes down).
/// The Flutter app receives these notifications via the polling mechanism
/// in [NotificationManager.fetchNotifications()].
///
/// For client-initiated notifications that need to be stored in the database,
/// use the backend API endpoint directly via [Http.post('/notifications', ...)].
class DatabaseChannel extends NotificationChannel {
  @override
  String get name => 'database';

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    final data = notification.toDatabase(notifiable);

    // Skip if toDatabase() returns null
    if (data == null) {
      return;
    }

    // Database notifications are created server-side.
    // This channel exists for API parity with Laravel's notification system.
    // Client-side notification creation should use Http.post() directly
    // to the backend's notification endpoint.
    //
    // The data is validated but not sent - use this pattern:
    // await Http.post('/notifications', data: notification.toDatabase(user));
  }
}
