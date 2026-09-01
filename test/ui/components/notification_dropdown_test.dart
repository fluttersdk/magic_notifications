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

  Widget wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
    return MaterialApp(
      home: WindTheme(
        data: WindThemeData(),
        child: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child,
            ),
          ),
        ),
      ),
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

  testWidgets(
    'the unread badge stays inside its pill at an accessibility text scale',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          NotificationDropdown(notificationStream: streamController.stream),
          textScaler: const TextScaler.linear(3.0),
        ),
      );

      streamController.add([makeNotification(), makeNotification()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final Finder count = find.text('2');

      // The pill is a fixed-height box, so the digit's own render box is
      // CONSTRAINT-clamped to that height whether or not the glyph fits: at a
      // 3.0 scale the box still measures 14.0 while the line paints at 39.0.
      // The intrinsic height is the only honest reading of what the text
      // actually needs, so the assertion goes against that, not against
      // `digit.size.height`, which would pass vacuously.
      final Size pill = tester.getSize(
        find.ancestor(of: count, matching: find.byType(WDiv)).first,
      );
      final RenderBox digit = tester.renderObject<RenderBox>(count);
      final double needed = digit.getMaxIntrinsicHeight(digit.size.width);

      expect(needed, lessThanOrEqualTo(pill.height));
    },
  );

  testWidgets('the styling seam reaches the trigger, badge and panel', (
    tester,
  ) async {
    const String triggerClassName = 'p-2 rounded-lg bg-transparent';
    const String triggerIconClassName = 'text-[18px] text-primary';
    const String badgeClassName = '''
      min-w-[14px] h-[14px] px-1 rounded-full
      bg-primary
      flex items-center justify-center
    ''';
    const String badgeTextClassName = 'text-[9px] font-bold text-black';
    const String panelClassName = 'w-96 bg-primary rounded-md';

    await tester.pumpWidget(
      wrap(
        NotificationDropdown(
          notificationStream: streamController.stream,
          triggerClassName: triggerClassName,
          triggerIconClassName: triggerIconClassName,
          badgeClassName: badgeClassName,
          badgeTextClassName: badgeTextClassName,
          panelClassName: panelClassName,
        ),
      ),
    );

    streamController.add([makeNotification()]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byWidgetPredicate(
        (w) => w is WPopover && w.className == panelClassName,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is WDiv && w.className == triggerClassName,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is WIcon && w.className == triggerIconClassName,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) => w is WDiv && w.className == badgeClassName),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is WText && w.className == badgeTextClassName,
      ),
      findsOneWidget,
    );
  });

  testWidgets('the dropdown preview renders without error', (tester) async {
    await tester.pumpWidget(wrap(const NotificationDropdownPreview()));
    await tester.pump();

    expect(find.byType(NotificationDropdownPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
