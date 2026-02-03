import '../notification_manager.dart';
import 'notification.dart';

/// Mixin for entities that can receive notifications
///
/// Example:
/// ```dart
/// class User extends Model with Notifiable {
///   @override
///   String get notifiableId => getAttribute('id').toString();
///
///   @override
///   String? get notifiableEmail => getAttribute('email') as String?;
/// }
/// ```
mixin Notifiable {
  /// Unique identifier for this notifiable entity
  String get notifiableId;

  /// Email address for mail notifications (optional)
  String? get notifiableEmail => null;

  /// Push notification external ID (defaults to notifiableId)
  String get pushExternalId => notifiableId;

  /// Notification preferences (optional)
  dynamic get notificationPreference => null;

  /// Send a notification to this entity (convenience method)
  Future<void> notify(Notification notification) async {
    await NotificationManager().send(this, notification);
  }
}
