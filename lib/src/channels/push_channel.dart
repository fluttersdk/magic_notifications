import 'package:magic/magic.dart';

import '../contracts/channel.dart';
import '../contracts/notifiable.dart';
import '../contracts/notification.dart';
import '../drivers/push/push_driver.dart';
import '../exceptions/notification_exception.dart';

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

    // The endpoint derives the recipient from the authenticated session, so
    // the request body carries no recipient field at all: that omission is
    // the safety property that makes it safe to expose a client-triggered
    // push send in the first place. Sending one, even null, would imply the
    // caller can choose a target, which the server would reject anyway.
    final response = await Http.post(
      '/notifications/push-test',
      data: <String, dynamic>{
        'title': pushMessage.headingValue,
        'body': pushMessage.contentValue,
        if (pushMessage.dataValue != null) 'data': pushMessage.dataValue,
      },
    );

    if (!response.successful) {
      throw NotificationException(
        response.message ?? 'Push test send failed.',
        code: 'HTTP_${response.statusCode}',
      );
    }
  }
}
