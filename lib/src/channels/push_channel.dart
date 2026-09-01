import 'package:magic/magic.dart';

import '../contracts/channel.dart';
import '../contracts/notifiable.dart';
import '../contracts/notification.dart';
import '../drivers/push/push_driver.dart';
import '../exceptions/notification_exception.dart';
import '../support/notification_log.dart';

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
///
/// ## This channel ships SWITCHED OFF
///
/// `notifications.push.self_test_enabled` gates the whole send, and an absent
/// key is off. Making the platform emit a push on a client's say-so is a
/// capability, not a detail, and it stays cold until an app has something that
/// needs it: an endpoint reachable by anything holding a token, whose only
/// effect is an outbound push, should not be live before the first caller
/// exists. The backend half of this package's contract carries the same switch
/// (`magic-starter.onesignal.self_test_enabled`) and refuses on its own; either
/// half alone is a half-measure, since a client that refuses locally leaves the
/// endpoint reachable and a server that refuses leaves the client posting
/// requests that always fail.
class PushChannel extends NotificationChannel {
  /// The config key that has to be `true` before this channel sends anything.
  static const String _switchKey = 'notifications.push.self_test_enabled';

  final PushDriver _driver;

  /// Creates a push channel with the specified driver.
  PushChannel(this._driver);

  @override
  String get name => 'push';

  /// Whether this channel can send: a supported driver AND the switch on.
  ///
  /// The switch belongs in this answer rather than only in [send]. A channel
  /// that reports itself available and then quietly does nothing is the exact
  /// shape this package has been removing, and it is what the manager reads to
  /// decide whether to dispatch at all: with the switch off the push channel is
  /// skipped there, so a notification listing `push` among its channels falls
  /// through to the ones that can still deliver instead of being handed to a
  /// channel that will drop it.
  @override
  bool get isAvailable => _driver.isSupported && _isSwitchedOn;

  /// Whether this deployment has switched the self-addressed send on.
  ///
  /// A value that is not a boolean reads as OFF rather than as truthy: it is a
  /// configuration mistake, and the safe reading of a mistake on a switch that
  /// guards an outbound send is the one that sends nothing.
  bool get _isSwitchedOn => Config.get<bool>(_switchKey) ?? false;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    // SKIPPED rather than refused, and skipped first.
    //
    // An operator who has not switched a feature on has not made an error, so
    // this is the same shape as a disabled preference below and not the same
    // shape as the foreign recipient underneath it: naming somebody else IS an
    // error, and a caller who did that has to hear about it. Reaching here at
    // all means a caller went around `isAvailable`, which the manager consults
    // first, so the skip is worth one debug line and is not worth an error: it
    // is the configured behaviour, not a failure.
    //
    // First, ahead of the recipient guard, because a channel that cannot page
    // anybody has no mis-page to refuse.
    if (!_isSwitchedOn) {
      NotificationLog.debug(
        '[notifications] the push channel is switched off, so a "'
        '${notification.type}" notification was not sent to its device. Set '
        'config $_switchKey to true, and switch the endpoint on at the '
        'backend, to enable the self-addressed test send.',
      );

      return;
    }

    // Refused rather than skipped, and refused before the body is built.
    // Skipping is what a preference does, and it reads as "delivered
    // elsewhere"; a caller that named a specific person has to hear that this
    // did not reach them, or the only signal left is the caller's own device
    // buzzing for somebody else's outage.
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
