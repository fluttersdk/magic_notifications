import 'package:flutter/material.dart' show Icons, CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../facades/notify.dart';
import '../../../models/database_notification.dart';
import 'notification_dropdown.recipe.dart';

/// Bell icon dropdown with a real-time unread badge over a notification stream.
///
/// Uses [WPopover] for overlay mechanics and [StreamBuilder] for live unread
/// counts.
///
/// ### Example
/// ```dart
/// NotificationDropdown(
///   notificationStream: Notify.notifications(),
///   onMarkAsRead: (id) => Notify.markAsRead(id),
///   onMarkAllAsRead: () => Notify.markAllAsRead(),
///   onNotificationTap: (n) => MagicRoute.to(n.actionUrl ?? '/'),
///   onViewAll: () => MagicRoute.to('/notifications'),
/// )
/// ```
///
/// ### Restyling it
///
/// The defaults are Wind's own palette (`bg-white`, `text-gray-500`,
/// `bg-red-500`), which reads as a foreign control next to an app whose other
/// controls are written in that app's semantic aliases. Four surfaces take an
/// override so an adopter can answer in its own vocabulary without forking the
/// widget: [triggerClassName], [triggerIconClassName], [badgeClassName] with
/// [badgeTextClassName], and [panelClassName].
///
/// Each override REPLACES its default outright, layout tokens included, rather
/// than appending to it, so a value that changes one token still has to carry
/// the rest:
///
/// ```dart
/// NotificationDropdown(
///   notificationStream: Notify.notifications(),
///   triggerClassName: 'w-9 h-9 rounded-lg flex items-center justify-center '
///       'bg-surface hover:bg-surface-container',
///   triggerIconClassName: 'text-[18px] text-fg-muted',
///   panelClassName: 'w-80 bg-surface border border-color-border rounded-xl',
/// )
/// ```
///
/// Replacement rather than append is deliberate. Wind's last-wins is per
/// family, and `bg-*` and `dark:bg-*` are two families, so an appended
/// light-only override would leave the default's `dark:bg-gray-800` alive and
/// the adopter would be debugging a dark mode it never asked for.
class NotificationDropdown extends StatelessWidget {
  /// The neutral leading icon, used for every type the adopter did not answer
  /// for through the `notifications.icon` slot family.
  static const IconData _defaultTypeIcon = Icons.notifications_none_outlined;

  /// Stream of notifications to display.
  final Stream<List<DatabaseNotification>> notificationStream;

  /// Callback when a notification is marked as read.
  final Future<void> Function(String id)? onMarkAsRead;

  /// Callback when all notifications are marked as read.
  final Future<void> Function()? onMarkAllAsRead;

  /// Callback when a notification is tapped.
  final void Function(DatabaseNotification notification)? onNotificationTap;

  /// Callback when the "View all" link is tapped.
  final VoidCallback? onViewAll;

  /// className of the popover panel, replacing
  /// [kNotificationDropdownPanelClassName].
  ///
  /// The default carries the panel's `w-80` width and `rounded-xl shadow-xl`
  /// alongside its palette, so an override that only means to recolor the
  /// surface still has to restate the width it wants.
  final String panelClassName;

  /// className of the trigger surface, replacing
  /// [kNotificationDropdownTriggerClassName].
  ///
  /// The default's `hover:`/`active:` tones are part of the string; an override
  /// that omits them ships a trigger with no press or hover feedback.
  final String triggerClassName;

  /// className of the trigger glyph, replacing
  /// [kNotificationDropdownTriggerIconClassName].
  ///
  /// This is where the bell's SIZE lives (`text-2xl` by default), so an adopter
  /// fitting the bell into a smaller control box overrides this one rather than
  /// [triggerClassName].
  final String triggerIconClassName;

  /// className of the unread badge pill, replacing
  /// [kNotificationDropdownBadgeClassName].
  ///
  /// The count inside it is clamped to
  /// [kNotificationDropdownBadgeMaxTextScaleFactor] whatever this value is,
  /// because the clamp is derived from the DEFAULT pill's fixed height; an
  /// override that makes the pill taller gets a badge that scales less than it
  /// could, never one that clips.
  final String badgeClassName;

  /// className of the unread count inside the badge pill, replacing
  /// [kNotificationDropdownBadgeTextClassName].
  final String badgeTextClassName;

  /// Creates a [NotificationDropdown].
  const NotificationDropdown({
    super.key,
    required this.notificationStream,
    this.onMarkAsRead,
    this.onMarkAllAsRead,
    this.onNotificationTap,
    this.onViewAll,
    this.panelClassName = kNotificationDropdownPanelClassName,
    this.triggerClassName = kNotificationDropdownTriggerClassName,
    this.triggerIconClassName = kNotificationDropdownTriggerIconClassName,
    this.badgeClassName = kNotificationDropdownBadgeClassName,
    this.badgeTextClassName = kNotificationDropdownBadgeTextClassName,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DatabaseNotification>>(
      stream: notificationStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return _buildLoadingDropdown();
        }

        if (snapshot.hasError) {
          return _buildErrorDropdown();
        }

        final notifications = snapshot.data ?? [];
        final unreadCount = notifications.where((n) => !n.isRead).length;

        return _buildDropdown(notifications, unreadCount);
      },
    );
  }

  Widget _buildDropdown(
    List<DatabaseNotification> notifications,
    int unreadCount,
  ) {
    return WPopover(
      alignment: PopoverAlignment.bottomRight,
      className: panelClassName,
      maxHeight: 400,
      triggerBuilder: (context, isOpen, isHovering) =>
          _buildTrigger(context, isOpen, isHovering, unreadCount: unreadCount),
      contentBuilder: (context, close) =>
          _buildContent(context, close, notifications, unreadCount),
    );
  }

  Widget _buildTrigger(
    BuildContext context,
    bool isOpen,
    bool isHovering, {
    required int unreadCount,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        WDiv(
          states: {if (isOpen) 'active', if (isHovering) 'hover'},
          className: triggerClassName,
          child: WIcon(
            Icons.notifications_outlined,
            className: triggerIconClassName,
          ),
        ),
        if (unreadCount > 0)
          Positioned(
            top: 4,
            right: 4,
            child: WDiv(
              className: badgeClassName,
              // The pill's height is fixed while the digit inside it grows with
              // the OS text scale, so an accessibility scale clips the count.
              // The clamp is the whole guard against that; see the constant for
              // where its value comes from and why it must not be raised alone.
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: kNotificationDropdownBadgeMaxTextScaleFactor,
                child: WText(
                  unreadCount > 9
                      ? trans('notifications.badge_overflow')
                      : unreadCount.toString(),
                  className: badgeTextClassName,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent(
    BuildContext context,
    VoidCallback close,
    List<DatabaseNotification> notifications,
    int unreadCount,
  ) {
    return WDiv(
      className: 'flex flex-col items-stretch',
      children: [
        _buildContentHeader(unreadCount),
        WDiv(
          className: 'flex-1 min-h-0',
          child: _buildNotificationsList(context, close, notifications),
        ),
        if (onViewAll != null) _buildFooter(context, close),
      ],
    );
  }

  Widget _buildContentHeader(int unreadCount) {
    return WDiv(
      className: '''
        px-4 py-3 w-full
        border-b border-gray-200 dark:border-gray-700
        flex flex-row items-center justify-between
      ''',
      children: [
        WText(
          trans('notifications.title'),
          className: 'text-base font-semibold text-gray-900 dark:text-white',
        ),
        if (unreadCount > 0 && onMarkAllAsRead != null)
          WAnchor(
            onTap: onMarkAllAsRead,
            child: WText(
              trans('notifications.mark_all_read'),
              // Brand-relative on both ends: `text-primary` resolves to the
              // ADOPTER's brand, so a hover jumping to a fixed palette green
              // reads as deliberate only while that brand happens to be green.
              className: 'text-xs text-primary hover:text-primary/80',
            ),
          ),
      ],
    );
  }

  Widget _buildNotificationsList(
    BuildContext context,
    VoidCallback close,
    List<DatabaseNotification> notifications,
  ) {
    if (notifications.isEmpty) {
      return WDiv(
        className:
            'w-full py-12 flex flex-col items-center justify-center gap-3',
        children: [
          WIcon(
            Icons.notifications_off_outlined,
            className: 'text-4xl text-gray-300 dark:text-gray-600',
          ),
          WText(
            trans('notifications.empty'),
            className: 'text-sm text-gray-500 dark:text-gray-400',
          ),
        ],
      );
    }

    return WDiv(
      className: 'overflow-y-auto flex flex-col',
      children: notifications
          .map((n) => _buildNotificationItem(context, n, close))
          .toList(),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    DatabaseNotification notification,
    VoidCallback close,
  ) {
    // What a notification type looks like is the adopter's vocabulary, not this
    // package's, so the leading icon comes from the type-icon slot family and
    // falls back to one neutral bell.
    final Widget leadingIcon =
        Notify.view.buildTypeIcon(notification.type, context) ??
            WIcon(
              _defaultTypeIcon,
              className: 'text-lg text-blue-500 dark:text-blue-400',
            );

    // One className for both row shapes, with the difference carried as a
    // state: an interpolated variant is a second parser cache key per row, so a
    // list of twenty notifications parsed two strings where it has one shape.
    // The read row also had the tint ABSENT rather than overridden, which is
    // exactly the case Wind's state prefixes exist to express.
    final Set<String> rowStates = {if (!notification.isRead) 'unread'};

    return WAnchor(
      onTap: () async {
        await onMarkAsRead?.call(notification.id);
        onNotificationTap?.call(notification);
        close();
      },
      child: WDiv(
        states: rowStates,
        className: '''
          flex flex-row items-start gap-3 px-4 py-3 w-full
          border-b border-gray-100 dark:border-gray-700
          hover:bg-gray-50 dark:hover:bg-gray-700
          unread:bg-primary/5 dark:unread:bg-primary/10
        ''',
        children: [
          WDiv(
            className: '''
              w-8 h-8 rounded-full
              bg-gray-100 dark:bg-gray-700
              flex items-center justify-center
            ''',
            child: leadingIcon,
          ),
          WDiv(
            className: 'flex-1 flex flex-col min-w-0',
            children: [
              WText(
                notification.title,
                states: rowStates,
                className: '''
                  text-sm text-gray-900 dark:text-white truncate
                  unread:font-semibold
                ''',
              ),
              const WSpacer(className: 'h-0.5'),
              WText(
                notification.body,
                className: 'text-xs text-gray-500 dark:text-gray-400',
              ),
              const WSpacer(className: 'h-0.5'),
              WText(
                _formatTime(notification.createdAt),
                className: 'text-xs text-gray-400 dark:text-gray-500',
              ),
            ],
          ),
          if (!notification.isRead)
            WDiv(
              className: 'w-2 h-2 rounded-full bg-primary mt-2',
              child: const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, VoidCallback close) {
    return WAnchor(
      onTap: () {
        onViewAll?.call();
        close();
      },
      child: WDiv(
        className: '''
          px-4 py-3 w-full
          border-t border-gray-200 dark:border-gray-700
          hover:bg-gray-50 dark:hover:bg-gray-700
          flex items-center justify-center
        ''',
        child: WText(
          trans('notifications.view_all'),
          className: 'text-sm font-medium text-primary',
        ),
      ),
    );
  }

  Widget _buildLoadingDropdown() {
    return WPopover(
      alignment: PopoverAlignment.bottomRight,
      className: panelClassName,
      maxHeight: 400,
      triggerBuilder: (context, isOpen, isHovering) =>
          _buildTrigger(context, isOpen, isHovering, unreadCount: 0),
      contentBuilder: (context, close) => WDiv(
        className: 'py-12 flex items-center justify-center',
        child: const CircularProgressIndicator(),
      ),
    );
  }

  Widget _buildErrorDropdown() {
    return WPopover(
      alignment: PopoverAlignment.bottomRight,
      className: panelClassName,
      maxHeight: 400,
      triggerBuilder: (context, isOpen, isHovering) =>
          _buildTrigger(context, isOpen, isHovering, unreadCount: 0),
      contentBuilder: (context, close) => WDiv(
        className:
            'w-full py-12 flex flex-col items-center justify-center gap-3',
        children: [
          WIcon(
            Icons.error_outline,
            className: 'text-4xl text-red-500 dark:text-red-400',
          ),
          WText(
            trans('notifications.load_failed'),
            className: 'text-sm text-gray-600 dark:text-gray-400',
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return trans('time.just_now');
    } else if (difference.inHours < 1) {
      return trans('time.minutes_ago', {'minutes': difference.inMinutes});
    } else if (difference.inDays < 1) {
      return trans('time.hours_ago', {'hours': difference.inHours});
    } else if (difference.inDays < 7) {
      return trans('time.days_ago', {'days': difference.inDays});
    } else {
      return trans('time.date_format', {
        'day': dateTime.day,
        'month': dateTime.month,
        'year': dateTime.year,
      });
    }
  }
}
