import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/facades/notify.dart';
import 'package:magic_notifications/src/http/notifications_list_controller.dart';
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
        'common.page_of': 'Page :current of :total',
      }),
    );

    await Translator.instance.load(const Locale('en'));
  });

  setUp(() {
    // The controller behind this screen is a Magic singleton, so the page a
    // previous case paged to would otherwise survive into the next one.
    Magic.delete<NotificationsListController>();
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

  /// Fakes the endpoint with [lastPage] pages, answering the page the request
  /// actually asked for, so paging forward changes what the screen reads back.
  void fakePages({required int lastPage}) {
    Http.fake((request) {
      final int page =
          int.tryParse('${request.queryParameters?['page'] ?? '1'}') ?? 1;

      return MagicResponse(
        data: <String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'page-$page',
              'type': 'monitor_down',
              'data': {'title': 'Item on page $page', 'body': 'Body'},
              'read_at': null,
              'created_at': DateTime.now().toIso8601String(),
            },
          ],
          'meta': <String, dynamic>{
            'current_page': page,
            'last_page': lastPage,
            'per_page': 15,
            'total': lastPage,
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

  testWidgets('renders the error state, not the empty state, on a failure', (
    tester,
  ) async {
    Http.fake((request) {
      return MagicResponse(data: <String, dynamic>{}, statusCode: 500);
    });

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // "Nothing here yet" on a backend that never answered is the worst
    // possible wording for the failure it hides: it is what sends an on-call
    // engineer back to sleep past an alert nobody could fetch.
    expect(find.text('Could not load notifications'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('renders the error state when the transport fails', (
    tester,
  ) async {
    Http.fake((request) {
      throw StateError('connection closed');
    });

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Could not load notifications'), findsOneWidget);
    expect(find.text('Nothing here yet'), findsNothing);
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

  testWidgets('publishes its state through the container', (tester) async {
    fakePages(lastPage: 1);

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The seam the screen was missing: a host wrapping this view, or a test
    // asserting what it fetched, reaches the state through the container
    // instead of through a private widget state nothing can address.
    final NotificationsListController controller =
        Magic.find<NotificationsListController>();

    expect(controller.isSuccess, isTrue);
    expect(controller.currentPage, 1);
    expect(controller.pageNotifier.value?.data, hasLength(1));
  });

  testWidgets('keeps the page the user paged to across a remount', (
    tester,
  ) async {
    fakePages(lastPage: 2);

    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Page 1 of 2'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Item on page 2'), findsOneWidget);

    // A host shell rebuilds this screen on every navigation back to it, and a
    // screen holding its page in widget state forgets it: the user lands back
    // on page 1 with no way to tell why. The page belongs to the controller.
    await tester.pumpWidget(wrap(const SizedBox.shrink()));
    await tester.pumpWidget(wrap(const NotificationsListView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Item on page 2'), findsOneWidget);
    expect(find.text('Page 2 of 2'), findsOneWidget);
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
