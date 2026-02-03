import 'notifiable.dart';

/// Base class for notifications
///
/// Example:
/// ```dart
/// class MonitorDownNotification extends Notification {
///   final Monitor monitor;
///
///   MonitorDownNotification(this.monitor);
///
///   @override
///   List<String> via(Notifiable notifiable) => ['database', 'push'];
///
///   @override
///   Map<String, dynamic>? toDatabase(Notifiable notifiable) => {
///     'title': 'Monitor Down',
///     'body': '${monitor.name} is not responding',
///     'action_url': '/monitors/${monitor.id}',
///   };
/// }
/// ```
abstract class Notification {
  /// Returns the notification type (defaults to class name)
  String get type => runtimeType.toString();

  /// Returns the channels this notification should be sent through
  List<String> via(Notifiable notifiable);

  /// Returns the database representation of this notification
  Map<String, dynamic>? toDatabase(Notifiable notifiable) => null;

  /// Returns the push message for this notification
  dynamic toPush(Notifiable notifiable) => null;

  /// Returns the mail message for this notification
  dynamic toMail(Notifiable notifiable) => null;
}
