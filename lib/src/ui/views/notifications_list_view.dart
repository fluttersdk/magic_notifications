import 'package:flutter/material.dart' show Icons, CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../facades/notify.dart';
import '../../models/database_notification.dart';
import '../../models/paginated_notifications.dart';

/// The full notification list screen.
///
/// Server-side paginated, with mark-as-read, mark-all-as-read, delete and
/// tap-through to a notification's action URL. Registered as
/// `notifications.list`, so a host replaces or wraps it through `Notify.view`.
class NotificationsListView extends StatefulWidget {
  /// Marks one notification read, or `null` to go through [Notify] directly.
  final Future<void> Function(String id)? onMarkAsRead;

  /// Marks every notification read, or `null` to go through [Notify] directly.
  final Future<void> Function()? onMarkAllAsRead;

  /// Deletes one notification. No delete affordance renders when `null`.
  final Future<void> Function(String id)? onDelete;

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

class _NotificationsListViewState extends State<NotificationsListView> {
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

  PaginatedNotifications? _paginatedData;
  bool _isLoading = true;
  bool _hasError = false;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _loadPage(1);
  }

  Future<void> _loadPage(int page) async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final result = await Notify.fetchPaginatedNotifications(
        page: page,
        perPage: widget.perPage,
      );

      if (!mounted) return;

      setState(() {
        _paginatedData = result;
        _currentPage = page;
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      Log.error('[NotificationsListView._loadPage] $e\n$stackTrace');

      if (!mounted) return;

      setState(() {
        _hasError = true;
        _isLoading = false;
      });
    }
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
    final notifications = _paginatedData?.data ?? [];
    final hasUnread = notifications.any((n) => !n.isRead);
    final totalPages = _paginatedData?.lastPage ?? 1;

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
              _loadPage(_currentPage);
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
    if (_isLoading && notifications.isEmpty) {
      return const WDiv(
        className: 'w-full bg-surface-container border border-color-border '
            'rounded-2xl p-6 flex items-center justify-center',
        child: CircularProgressIndicator(),
      );
    }

    if (_hasError) {
      return _buildEmptyState(
        icon: Icons.error_outline,
        message: trans('notifications.load_failed'),
      );
    }

    if (notifications.isEmpty) {
      return _buildEmptyState(
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

  Widget _buildEmptyState({required IconData icon, required String message}) {
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
          _loadPage(_currentPage);
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
                WText(
                  notification.title,
                  className: notification.isRead
                      ? 'text-sm text-fg'
                      : 'text-sm text-fg font-semibold',
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
              onTap: () async {
                await widget.onDelete?.call(notification.id);
                _loadPage(_currentPage);
              },
              child: WDiv(
                className:
                    'p-2 ml-2 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20',
                child: WIcon(
                  Icons.delete_outline,
                  className: 'text-lg text-fg-muted hover:text-red-500',
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalPages) {
    return WDiv(
      className: 'w-full flex flex-row items-center justify-center gap-2 mt-4',
      children: [
        WButton(
          onTap: _currentPage > 1 ? () => _loadPage(_currentPage - 1) : null,
          disabled: _currentPage <= 1,
          className: 'px-3 py-2 rounded-lg bg-surface-container-high '
              'border border-color-border disabled:opacity-50',
          child: WIcon(Icons.chevron_left, className: 'text-fg-muted'),
        ),
        WText(
          trans('common.page_of', {
            'current': _currentPage,
            'total': totalPages,
          }),
          className: 'text-sm font-medium text-fg',
        ),
        WButton(
          onTap: _currentPage < totalPages
              ? () => _loadPage(_currentPage + 1)
              : null,
          disabled: _currentPage >= totalPages,
          className: 'px-3 py-2 rounded-lg bg-surface-container-high '
              'border border-color-border disabled:opacity-50',
          child: WIcon(Icons.chevron_right, className: 'text-fg-muted'),
        ),
      ],
    );
  }
}
