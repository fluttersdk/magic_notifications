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
///
/// ## This channel is SELF-ADDRESSED
///
/// It POSTs to an endpoint that derives the recipient from the authenticated
/// session, and the request carries no recipient field: a client-triggered send
/// that could choose its target is a harassment vector, and that omission is
/// what makes exposing this at all safe. So the only person this channel can
/// page is the authenticated one.
///
/// The [Notifiable] in [send] therefore selects the preference matrix and the
/// message, never the recipient. A notifiable that is not the authenticated
/// user is refused; it cannot quietly become the caller.
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
    // Refused rather than skipped, and refused first. Skipping is what a
    // preference does, and it reads as "delivered elsewhere"; a caller that
    // named a specific person has to hear that this did not reach them, or the
    // only signal left is the caller's own device buzzing for somebody else's
    // outage.
    _refuseForeignRecipient(notifiable);

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

  /// Throws when [notifiable] is somebody other than the authenticated user.
  ///
  /// A build with no auth bound, and a session with nobody signed in, are both
  /// un-answerable here rather than mismatches: there is no caller identity to
  /// compare against, and the endpoint rejects the request on its own.
  void _refuseForeignRecipient(Notifiable notifiable) {
    if (!Magic.bound('auth')) return;

    final Object? authenticated = Auth.id();
    if (authenticated == null) return;
    if (authenticated.toString() == notifiable.notifiableId) return;

    throw NotificationException(
      'The push channel can only reach the authenticated user: the endpoint '
      'derives the recipient from the session, so a notification addressed to '
      '"${notifiable.notifiableId}" would have paged "$authenticated" '
      'instead. Send it through a channel that carries a recipient, or have '
      'the backend send this push.',
      code: 'PUSH_RECIPIENT_NOT_AUTHENTICATED_USER',
    );
  }
}
