import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/models/database_notification.dart';
import 'package:magic_notifications/src/ui/components/notification_dropdown/notification_dropdown.dart';
import 'package:magic_notifications/src/ui/components/notification_dropdown/notification_dropdown.preview.dart';

import '../../test_helper.dart';

/// Feeds the translator a literal map so the popover lays out real labels.
class _MapTranslationLoader implements TranslationLoader {
  const _MapTranslationLoader(this.sentences);

  final Map<String, dynamic> sentences;

  @override
  Future<Map<String, dynamic>> load(Locale locale) async => sentences;
}

void main() {
  setUpAll(() async {
    await initMagicForTests();

    Translator.instance.setLoader(
      const _MapTranslationLoader(<String, dynamic>{
        'notifications.title': 'Notifications',
        'notifications.mark_all_read': 'Mark all as read',
        'notifications.empty': 'Nothing here yet',
        'notifications.load_failed': 'Could not load notifications',
        'notifications.badge_overflow': '9+',
        'notifications.view_all': 'View all',
      }),
    );

    await Translator.instance.load(const Locale('en'));
  });

  late StreamController<List<DatabaseNotification>> streamController;

  setUp(() {
    streamController = StreamController<List<DatabaseNotification>>.broadcast();
  });

  tearDown(() async {
    await streamController.close();
  });

  DatabaseNotification makeNotification({bool isRead = false}) {
    final now = DateTime.now();
    return DatabaseNotification.fromMap({
      'id': 'test-id-${now.microsecondsSinceEpoch}',
      'type': 'monitor_down',
      'data': {'title': 'Test Notification', 'body': 'Test body'},
      'read_at': isRead ? now.toIso8601String() : null,
      'created_at': now.toIso8601String(),
    });
  }

  Widget wrap(Widget child) {
    return MaterialApp(
      home: WindTheme(data: WindThemeData(), child: Scaffold(body: child)),
    );
  }

  testWidgets('renders the bell icon', (tester) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

    streamController.add([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('shows the unread badge when unread count is greater than zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([
      makeNotification(),
      makeNotification(),
      makeNotification(isRead: true),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('hides the badge when every notification is read', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([
      makeNotification(isRead: true),
      makeNotification(isRead: true),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('renders the empty state in the popover content', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets('the dropdown preview renders without error', (tester) async {
    await tester.pumpWidget(wrap(const NotificationDropdownPreview()));
    await tester.pump();

    expect(find.byType(NotificationDropdownPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
