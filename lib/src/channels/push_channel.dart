import '../contracts/channel.dart';
import '../contracts/notifiable.dart';
import '../contracts/notification.dart';
import '../drivers/push/push_driver.dart';

/// Push notification channel using a configured driver (e.g., OneSignal).
///
/// Sends notifications via push notification service when:
/// - Driver is available/supported
/// - Notification defines toPush() message
/// - User preferences allow push notifications
class PushChannel extends NotificationChannel {
  final PushDriver _driver;

  /// Creates a push channel with the specified driver.
  PushChannel(this._driver);

  @override
  String get name => 'push';

  @override
  bool get isAvailable => _driver.isSupported;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    // Get push message from notification
    final pushMessage = notification.toPush(notifiable);
    if (pushMessage == null) {
      // Notification doesn't support push or chose not to send
      return;
    }

    // Check user preferences if available
    final preference = notifiable.notificationPreference;
    if (preference != null) {
      final pushEnabled = preference.isEnabled(notification.type, 'push');
      if (!pushEnabled) {
        // User has disabled push for this notification type
        return;
      }
    }

    // In a real implementation, this would POST to backend endpoint
    // which then calls OneSignal API. For now, this is a no-op
    // that will be implemented when backend integration is added.
    //
    // Example backend call would be:
    // await Http.post('/notifications/push', data: {
    //   'external_id': notifiable.pushExternalId,
    //   'type': notification.type,
    //   ...pushMessage.toMap(),
    // });
  }
}
