import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/facades/notify.dart';
import 'package:magic_notifications/src/ui/views/notifications_list_view.dart';

import '../../test_helper.dart';

/// Feeds the translator a literal map so the view lays out real labels.
///
/// A widget test that renders a label needs its language keys loaded, or the
/// raw key is what gets measured and a failure says nothing about the widget.
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
        'notifications.list_subtitle': 'Everything we sent you',
        'notifications.mark_all_read': 'Mark all as read',
        'notifications.load_failed': 'Could not load notifications',
        'notifications.empty': 'Nothing here yet',
      }),
    );

    await Translator.instance.load(const Locale('en'));
  });

  tearDown(() {
    Http.unfake();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      home: WindTheme(
        data: WindThemeData(),
        child: Scaffold(
          body: SizedBox(width: 1024, height: 900, child: child),
        ),
      ),
    );
  }

  /// Fakes the paginated notifications endpoint with [data] and one page of
  /// results, so the widget's `initState` fetch resolves deterministically.
  void fakeNotifications(List<Map<String, dynamic>> data) {
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': data,
          'meta': <String, dynamic>{
            'current_page': 1,
            'last_page': 1,
            'per_page': 15,
            'total': data.length,
          },
        },
        statusCode: 200,
      );
    });
  }

  Map<String, dynamic> makeNotificationMap({
    required String id,
    required String title,
    required String body,
    bool isRead = false,
  }) {
    return <String, dynamic>{
      'id': id,
      'type': 'monitor_down',
      'data': {'title': title, 'body': body},
      'read_at': isRead ? DateTime.now().toIso8601String() : null,
      'created_at': DateTime.now().toIso8601String(),
    };
  }

  testWidgets('renders loading state before the first fetch resolves', (
    tester,
  ) async {
    fakeNotifications(const []);

    await tester.pumpWidget(wrap(const NotificationsListView()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders empty state with icon and message', (tester) async {
    fakeNotifications(const []);

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(find.text('Nothing here yet'), findsOneWidget);
  });

  testWidgets('renders notification items with title and body', (
    tester,
  ) async {
    fakeNotifications([
      makeNotificationMap(
        id: '1',
        title: 'Monitor Down',
        body: 'Your monitor is down',
      ),
    ]);

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Monitor Down'), findsOneWidget);
    expect(find.text('Your monitor is down'), findsOneWidget);
  });

  testWidgets('renders the mark-all-as-read button when unread items exist', (
    tester,
  ) async {
    fakeNotifications([
      makeNotificationMap(id: '1', title: 'Unread', body: 'Body'),
    ]);

    await tester.pumpWidget(
      wrap(NotificationsListView(onMarkAllAsRead: () async {})),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Mark all as read'), findsOneWidget);
  });

  testWidgets('renders the header slot when registered', (tester) async {
    Notify.view.slot(
      'notifications.list',
      'header',
      (context) => const Text('Custom Header'),
    );
    addTearDown(() {
      Notify.view.slot(
        'notifications.list',
        'header',
        (context) => const SizedBox.shrink(),
      );
    });

    fakeNotifications(const []);

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Custom Header'), findsOneWidget);
  });

  testWidgets('renders the footer slot when registered', (tester) async {
    Notify.view.slot(
      'notifications.list',
      'footer',
      (context) => const Text('Custom Footer'),
    );
    addTearDown(() {
      Notify.view.slot(
        'notifications.list',
        'footer',
        (context) => const SizedBox.shrink(),
      );
    });

    fakeNotifications(const []);

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Custom Footer'), findsOneWidget);
  });
}
