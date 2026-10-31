import 'package:flutter/widgets.dart';

/// Builds the page header of a shipped notification screen from what that
/// screen would have drawn itself.
///
/// Passed as `headerBuilder` to [NotificationsListView] and
/// [NotificationPreferencesView]. The returned widget takes the header's place
/// inside the screen's own scroll view and content column, so a host draws its
/// own page header there (one that hands the title and back control to an app
/// bar, say) without rebuilding the screen around it.
typedef NotificationsPageHeaderBuilder = Widget Function(
  BuildContext context,
  NotificationsPageHeader header,
);

/// What a shipped notification screen puts in its page header, handed to a
/// [NotificationsPageHeaderBuilder] instead of being drawn.
///
/// Every string is already translated.
@immutable
class NotificationsPageHeader {
  /// The page title.
  final String title;

  /// The line under the title, or `null` for none.
  final String? subtitle;

  /// The header's action widgets, already wired to the screen, in order.
  ///
  /// Empty when the screen has nothing to offer right now: the inbox hands
  /// over its mark-all-as-read button only while something is unread, exactly
  /// as it draws it.
  final List<Widget> actions;

  /// The back control's accessible name, or `null` when there is no back
  /// control. Set exactly when [backRoute] is.
  final String? backLabel;

  /// The route the back control returns to, or `null` for no back control.
  final String? backRoute;

  /// Creates a [NotificationsPageHeader].
  const NotificationsPageHeader({
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.backLabel,
    this.backRoute,
  });
}
