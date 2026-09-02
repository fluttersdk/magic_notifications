import 'package:flutter/material.dart' show Icons, CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../facades/notify.dart';
import '../../http/notifications_list_controller.dart';
import '../../models/database_notification.dart';
import '../../support/notification_log.dart';

/// The full notification list screen.
///
/// Server-side paginated through [NotificationsListController], with
/// mark-as-read, mark-all-as-read, delete and tap-through to a notification's
/// action URL. Registered as `notifications.list`, so a host replaces or wraps
/// it through `Notify.view`.
class NotificationsListView
    extends MagicStatefulView<NotificationsListController> {
  /// Marks one notification read, or `null` to go through [Notify] directly.
  final Future<void> Function(String id)? onMarkAsRead;

  /// Marks every notification read, or `null` to go through [Notify] directly.
  final Future<void> Function()? onMarkAllAsRead;

  /// Deletes one notification. No delete affordance renders when `null`.
  ///
  /// Answers whether the row is gone: `true` after a delete the server
  /// accepted, `false` when nothing happened because the host decided not to
  /// go ahead. A host that asks for confirmation returns `false` on a decline,
  /// and that is the whole reason this returns a value at all. The list is a
  /// separately paginated fetch, so a real delete has to be followed by a
  /// reload (a row leaving page one pulls one up from page two); with no answer
  /// to read, the row had to reload after EVERY tap, and declining a
  /// confirmation dialog cost a full `GET /notifications` for a list that had
  /// not changed.
  ///
  /// A throw is a third outcome and is not the same as `false`: the manager
  /// removes the row optimistically and puts it back when the request fails,
  /// so what the server still holds is unknown and the list reloads.
  final Future<bool> Function(String id)? onDelete;

  /// Navigates to a notification's action URL, or `null` for [MagicRoute].
  final void Function(String path)? onNavigate;

  /// Rows per page requested from the backend.
  final int perPage;

  /// Creates a [NotificationsListView].
  const NotificationsListView({
    super.key,
    this.onMarkAsRead,
    this.onMarkAllAsRead,
    this.onDelete,
    this.onNavigate,
    this.perPage = 15,
  });

  @override
  State<NotificationsListView> createState() => _NotificationsListViewState();
}

class _NotificationsListViewState extends MagicStatefulViewState<
    NotificationsListController, NotificationsListView> {
  /// The card shell every section renders in.
  ///
  /// Full-bleed (`overflow-hidden`, no body padding) because the rows span edge
  /// to edge and carry their own `px-6`.
  static const String _cardClassName =
      'w-full bg-surface-container border border-color-border '
      'rounded-2xl overflow-hidden flex flex-col';

  /// The neutral leading icon, used for every type the adopter did not answer
  /// for through the `notifications.icon` slot family.
  static const IconData _defaultNotificationIcon =
      Icons.notifications_none_outlined;

  @override
  void initState() {
    // Put the controller before `MagicStatefulViewState.initState` resolves it
    // with `Magic.find`, which throws when nothing has put it. Doing it here
    // rather than at the mount point keeps the view mountable from anywhere:
    // the registry default, a host route, a test.
    NotificationsListController.instance;

    super.initState();
  }

  @override
  void onInit() {
    super.onInit();

    controller.perPage = widget.perPage;
    // Re-read the page the controller is on rather than page 1: the singleton
    // survives a remount, so a host shell rebuilding this screen puts the user
    // back where they were instead of at the top of the list.
    controller.refresh();
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

  @override
  Widget build(BuildContext context) {
    // The rows are published on their own notifier (the mixin's state is
    // cleared by `setLoading()`), so the page rebuild has to listen to both:
    // the state mixin through `MagicStatefulViewState`, the rows through here.
    return ListenableBuilder(
      listenable: controller.pageNotifier,
      builder: (context, _) => _buildPage(context),
    );
  }

  Widget _buildPage(BuildContext context) {
    final page = controller.pageNotifier.value;
    final notifications = page?.data ?? const <DatabaseNotification>[];
    final hasUnread = notifications.any((n) => !n.isRead);
    final totalPages = page?.lastPage ?? 1;

    final headerSlot = Notify.view.buildSlot(
      'notifications.list',
      'header',
      context,
    );
    final footerSlot = Notify.view.buildSlot(
      'notifications.list',
      'footer',
      context,
    );

    // The page surface wraps the scroll view so the surface token paints the
    // whole content viewport rather than only the content height.
    return WDiv(
      className: 'w-full min-h-full bg-surface',
      child: SingleChildScrollView(
        // Own the implicit scroll controller: the host shell may already hold
        // the ambient PrimaryScrollController, and two claimants contend.
        primary: false,
        child: SafeArea(
          top: false,
          bottom: false,
          child: WDiv(
            className: 'w-full flex flex-col p-4 lg:p-6',
            children: [
              _buildHeader(hasUnread: hasUnread),
              WDiv(
                className: 'mt-6 flex flex-col gap-6',
                children: [
                  if (headerSlot != null) headerSlot,
                  _buildBody(context, notifications, totalPages),
                  if (footerSlot != null) footerSlot,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the page header, carrying the mark-all-as-read action.
  ///
  /// The action rides in the page header rather than a bar the list builds for
  /// itself: a page that owns its own action bar ends up owning its geometry
  /// too, which is how this surface drifted off the app's page rhythm.
  Widget _buildHeader({required bool hasUnread}) {
    return WDiv(
      className: 'w-full flex flex-row items-center justify-between gap-3',
      children: [
        WDiv(
          className: 'flex flex-col gap-1 flex-initial min-w-0',
          children: [
            WText(
              trans('notifications.title'),
              className: 'text-2xl font-semibold text-fg',
            ),
            WText(
              trans('notifications.list_subtitle'),
              className: 'text-sm text-fg-muted',
            ),
          ],
        ),
        if (hasUnread)
          WButton(
            onTap: () async {
              final markAllAsRead = widget.onMarkAllAsRead;
              if (markAllAsRead != null) {
                await markAllAsRead();
              } else {
                await Notify.markAllAsRead();
              }
              controller.refresh();
            },
            className: 'px-4 py-2 rounded-lg bg-primary hover:bg-primary/80 '
                'text-white font-medium text-sm',
            child: WText(
              trans('notifications.mark_all_read'),
              className: 'text-white font-medium text-sm',
            ),
          ),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<DatabaseNotification> notifications,
    int totalPages,
  ) {
    if (controller.isLoading && notifications.isEmpty) {
      return const WDiv(
        className: 'w-full bg-surface-container border border-color-border '
            'rounded-2xl p-6 flex items-center justify-center',
        child: CircularProgressIndicator(),
      );
    }

    // Before the rows, and before the empty state: a read that failed leaves
    // whatever it had last on the notifier, and showing that (or, worse, the
    // "nothing here yet" copy) tells an on-call engineer they have no alerts
    // when what happened is that nobody could be asked.
    if (controller.isError) {
      return _buildPlaceholder(
        icon: Icons.error_outline,
        message: trans('notifications.load_failed'),
      );
    }

    if (notifications.isEmpty) {
      return _buildPlaceholder(
        icon: Icons.notifications_off_outlined,
        message: trans('notifications.empty'),
      );
    }

    return WDiv(
      className: 'flex flex-col gap-6',
      children: [
        WDiv(
          className: _cardClassName,
          child: WDiv(
            className: 'flex flex-col',
            children: notifications
                .map((n) => _buildNotificationItem(context, n))
                .toList(),
          ),
        ),
        if (totalPages > 1) _buildPagination(totalPages),
      ],
    );
  }

  /// The centred icon-plus-message card both the empty state and the failure
  /// state render in.
  ///
  /// Named for the shape rather than for "empty": the failure path renders it
  /// too, and calling that one an empty state is how the two got told as one
  /// answer in the first place.
  Widget _buildPlaceholder({required IconData icon, required String message}) {
    return WDiv(
      className: 'w-full bg-surface-container border border-color-border '
          'rounded-2xl p-6 flex flex-col gap-4',
      child: WDiv(
        className: 'flex flex-col items-center justify-center py-20 gap-4',
        children: [
          WIcon(icon, className: 'text-6xl text-fg-disabled'),
          WText(message, className: 'text-fg-muted'),
        ],
      ),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    DatabaseNotification notification,
  ) {
    // What a notification type looks like is the adopter's vocabulary, not this
    // package's, so the leading icon comes from the type-icon slot family and
    // falls back to one neutral bell.
    final Widget leadingIcon =
        Notify.view.buildTypeIcon(notification.type, context) ??
            WIcon(_defaultNotificationIcon, className: 'text-xl text-fg-muted');

    return WAnchor(
      onTap: () async {
        // 1. Mark as read through the callback, or the Notify facade directly.
        final markAsRead = widget.onMarkAsRead;
        if (markAsRead != null) {
          await markAsRead(notification.id);
        } else {
          await Notify.markAsRead(notification.id);
        }

        // 2. Navigate to the action URL, or reload the current page.
        final actionUrl = notification.actionUrl;
        if (actionUrl != null) {
          final navigate = widget.onNavigate;
          if (navigate != null) {
            navigate(actionUrl);
          } else {
            MagicRoute.to(actionUrl);
          }
        } else {
          controller.refresh();
        }
      },
      child: WDiv(
        className: 'px-6 py-4 flex flex-row items-center gap-4 '
            'border-b border-color-border-subtle hover:bg-surface-container',
        children: [
          WDiv(
            className: 'w-10 h-10 rounded-full bg-surface-container-high '
                'flex items-center justify-center flex-shrink-0',
            child: leadingIcon,
          ),
          Expanded(
            child: WDiv(
              className: 'flex flex-col min-w-0',
              children: [
                // One className with a state prefix rather than a ternary, for
                // the reason the dropdown's row carries: an interpolated or
                // branched className is a second parser cache key per row, so a
                // page of twenty notifications parses two strings where it has
                // one shape.
                WText(
                  notification.title,
                  states: {if (!notification.isRead) 'unread'},
                  className: 'text-sm text-fg unread:font-semibold',
                ),
                const WSpacer(className: 'h-0.5'),
                WText(notification.body, className: 'text-sm text-fg-muted'),
                const WSpacer(className: 'h-1'),
                WText(
                  _formatTime(notification.createdAt),
                  className: 'text-xs text-fg-muted',
                ),
              ],
            ),
          ),
          if (!notification.isRead)
            const WDiv(
              className: 'w-2 h-2 rounded-full bg-primary flex-shrink-0',
              child: SizedBox.shrink(),
            ),
          if (widget.onDelete != null)
            WAnchor(
              // The glyph carries no text, so without this a screen reader
              // announced a bare "button" on every row with nothing saying
              // what it does, and an E2E driver had no handle to resolve it by.
              semanticLabel: trans('notifications.delete'),
              onTap: () async {
                // Three outcomes, and only two of them are worth a reload.
                //
                // The callback can throw: `deleteNotification` rethrows a
                // failed request after rolling the row back. Caught here rather
                // than left to escape into the gesture callback, and answered
                // with a message, because the rollback on its own just puts the
                // row back and a person watching it return learns nothing.
                bool reload = true;

                try {
                  // `false` means the host chose not to go ahead, which is what
                  // a declined confirmation dialog looks like from here. The
                  // list is unchanged, so reloading it would spend a request to
                  // re-read what is already on screen.
                  reload = await widget.onDelete!(notification.id);
                } catch (e) {
                  NotificationLog.error('Failed to delete notification: $e');
                  Magic.error(
                    trans('notifications.title'),
                    trans('notifications.delete_failed'),
                  );
                  // A failure leaves the local copy rolled back and the
                  // server's own state unknown, so re-read it rather than
                  // trusting what is in hand.
                  reload = true;
                }

                if (reload) {
                  await controller.refresh();
                }
              },
              child: WDiv(
                className:
                    'p-2 ml-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20',
                child: WIcon(
                  Icons.delete_outline,
                  // The hover tone needs its `dark:` peer like every other
                  // colour token: `red-500` was written alone, so dark mode
                  // hovered to a red tuned for a white background.
                  className:
                      'text-lg text-fg-muted hover:text-red-500 dark:hover:text-red-400',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalPages) {
    final int currentPage = controller.currentPage;

    return WDiv(
      className: 'w-full flex flex-row items-center justify-center gap-2 mt-4',
      children: [
        WButton(
          onTap: currentPage > 1
              ? () => controller.loadPage(currentPage - 1)
              : null,
          disabled: currentPage <= 1,
          className: 'px-3 py-2 rounded-lg bg-surface-container-high '
              'border border-color-border disabled:opacity-50',
          child: WIcon(Icons.chevron_left, className: 'text-fg-muted'),
        ),
        WText(
          trans('common.page_of', {
            'current': currentPage,
            'total': totalPages,
          }),
          className: 'text-sm font-medium text-fg',
        ),
        WButton(
          onTap: currentPage < totalPages
              ? () => controller.loadPage(currentPage + 1)
              : null,
          disabled: currentPage >= totalPages,
          className: 'px-3 py-2 rounded-lg bg-surface-container-high '
              'border border-color-border disabled:opacity-50',
          child: WIcon(Icons.chevron_right, className: 'text-fg-muted'),
        ),
      ],
    );
  }
}
