import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../models/database_notification.dart';
import 'notification_dropdown.dart';

/// Static preview for [NotificationDropdown].
///
/// Renders the dropdown twice over mock notification streams: once on its
/// defaults (empty state, no badge) and once through the styling seam, so the
/// catalogue shows that the trigger, the glyph, the badge and the panel are all
/// an adopter's to answer for. The restyled one carries two unread
/// notifications because the badge is half of what the seam exists to reach and
/// an empty stream never paints it. One preview class per file.
class NotificationDropdownPreview extends StatefulWidget {
  /// Creates a [NotificationDropdownPreview].
  const NotificationDropdownPreview({super.key});

  @override
  State<NotificationDropdownPreview> createState() =>
      _NotificationDropdownPreviewState();
}

class _NotificationDropdownPreviewState
    extends State<NotificationDropdownPreview> {
  final StreamController<List<DatabaseNotification>> _controller =
      StreamController<List<DatabaseNotification>>.broadcast();

  final StreamController<List<DatabaseNotification>> _restyledController =
      StreamController<List<DatabaseNotification>>.broadcast();

  @override
  void initState() {
    super.initState();
    // Emit an empty list so the preview shows the empty state immediately.
    _controller.add([]);
    _restyledController.add(_unreadSample());
  }

  @override
  void dispose() {
    _controller.close();
    _restyledController.close();
    super.dispose();
  }

  /// Two unread notifications, enough to paint the badge the restyled variant
  /// is there to show off.
  List<DatabaseNotification> _unreadSample() {
    final DateTime now = DateTime.now();

    return [
      DatabaseNotification(
        id: 'preview-1',
        type: 'preview',
        title: 'Deployment finished',
        body: 'The 14:20 release is live.',
        data: const {},
        createdAt: now.subtract(const Duration(minutes: 3)),
      ),
      DatabaseNotification(
        id: 'preview-2',
        type: 'preview',
        title: 'New team member',
        body: 'Dana accepted the invitation.',
        data: const {},
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-row items-start gap-6 p-6',
      children: [
        NotificationDropdown(notificationStream: _controller.stream),
        // Every override replaces its default outright, layout tokens included,
        // which is why each string below restates the geometry it wants rather
        // than only the color it changes.
        NotificationDropdown(
          notificationStream: _restyledController.stream,
          triggerClassName: '''
            w-9 h-9 rounded-md duration-150
            bg-gray-100 dark:bg-gray-800
            hover:bg-gray-200 dark:hover:bg-gray-700
            active:bg-gray-200 dark:active:bg-gray-700
            flex items-center justify-center
          ''',
          triggerIconClassName: 'text-lg text-gray-700 dark:text-gray-200',
          badgeClassName: '''
            min-w-[14px] h-[14px] px-1 rounded-full
            bg-amber-500
            flex items-center justify-center
          ''',
          badgeTextClassName: 'text-[9px] font-bold text-gray-900',
          panelClassName: '''
            w-96
            bg-gray-50 dark:bg-gray-900
            border border-gray-300 dark:border-gray-600
            rounded-md
          ''',
        ),
      ],
    );
  }
}
