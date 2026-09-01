import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await initMagicForTests();
  });

  late NotificationsListController controller;

  setUp(() {
    // The controller is a Magic singleton, so the page a previous case paged to
    // would otherwise survive into the next one and certify a state nothing in
    // this test set up.
    Magic.delete<NotificationsListController>();
    controller = NotificationsListController.instance;
  });

  tearDown(() {
    Http.unfake();
  });

  /// Fakes the notification endpoint, answering the page the request asked for
  /// so a read can be told apart from the read before it.
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

  group('NotificationsListController', () {
    test('loadPage() publishes the page it read and reports success', () async {
      fakePages(lastPage: 3);

      await controller.loadPage(2);

      expect(controller.currentPage, 2);
      expect(controller.isSuccess, isTrue);
      expect(controller.pageNotifier.value?.lastPage, 3);
      expect(
        controller.pageNotifier.value?.data.single.title,
        'Item on page 2',
      );
    });

    test('loadPage() asks the backend for the page size it was given',
        () async {
      controller.perPage = 30;
      final fake = Http.fake((request) {
        return MagicResponse(
          data: <String, dynamic>{
            'data': <Map<String, dynamic>>[],
            'meta': <String, dynamic>{'current_page': 1, 'last_page': 1},
          },
          statusCode: 200,
        );
      });

      await controller.loadPage(1);

      fake.assertSent(
        (request) =>
            request.url == '/notifications' &&
            request.queryParameters?['perPage'] == '30',
      );
    });

    test('refresh() re-reads the page the controller is on', () async {
      fakePages(lastPage: 3);
      await controller.loadPage(2);

      final fake = Http.fake((request) {
        return MagicResponse(
          data: <String, dynamic>{
            'data': <Map<String, dynamic>>[],
            'meta': <String, dynamic>{'current_page': 2, 'last_page': 3},
          },
          statusCode: 200,
        );
      });

      await controller.refresh();

      // A refresh after a mark-as-read or a delete has to land on the page the
      // user is looking at; re-reading page 1 would throw them back to the top
      // of the list every time they act on a row.
      fake.assertSent((request) => request.queryParameters?['page'] == '2');
      expect(controller.currentPage, 2);
    });

    test('loadPage() reports an error instead of publishing an empty page',
        () async {
      Http.fake((request) {
        return MagicResponse(data: <String, dynamic>{}, statusCode: 500);
      });

      await controller.loadPage(1);

      // A failed read published as an empty page reaches the screen as "no
      // notifications", which is the one thing an on-call engineer must not be
      // told while the backend is down.
      expect(controller.isError, isTrue);
      expect(controller.isSuccess, isFalse);
      expect(controller.pageNotifier.value, isNull);
    });

    test('a failed reload keeps the rows the screen already had', () async {
      fakePages(lastPage: 3);
      await controller.loadPage(2);

      Http.fake((request) {
        throw StateError('connection closed');
      });

      await controller.refresh();

      // The rows are stale, not gone, and the page the user was on is still
      // the page a retry has to re-read.
      expect(controller.isError, isTrue);
      expect(controller.currentPage, 2);
      expect(controller.pageNotifier.value?.data, hasLength(1));
    });

    test('a reload keeps the rows it already has while it is in flight',
        () async {
      fakePages(lastPage: 2);
      await controller.loadPage(1);

      controller.setLoading();

      // The screen shows its spinner only when it has nothing else to show, so
      // the rows have to outlive the loading status: `setLoading()` clears the
      // mixin's own state, which is exactly why the page does not live there.
      expect(controller.isLoading, isTrue);
      expect(controller.pageNotifier.value?.data, hasLength(1));
    });

    test('signing out drops the page the previous person was reading',
        () async {
      fakePages(lastPage: 3);

      // The controller has to exist before the sign-out, the way it does on a
      // device where somebody opened the list and then signed out.
      controller.onInit();
      await controller.loadPage(2);

      expect(controller.pageNotifier.value, isNotNull);
      expect(controller.currentPage, 2);

      await Notify.logoutPush();

      // Read synchronously, because this is exactly what `build` does on the
      // next person's first frame, before any refresh has had a chance to land.
      // This controller is a process-lifetime singleton, so nothing else drops
      // A's incident titles before B's screen paints them.
      expect(controller.pageNotifier.value, isNull);
      expect(controller.currentPage, 1);
    });
  });

  group('NotificationsListController on a host with no log binding', () {
    tearDown(() {
      // The case below flushed the container to drop the `log` binding, and it
      // dropped every other binding with it. Put a log back so the rest of the
      // run resolves one again.
      Log.fake();
    });

    test('loadPage() reaches its error state instead of throwing', () async {
      // A host that registers no logging provider is a legitimate build, not
      // only a test condition, and `Log.error` resolves `log` out of the
      // container and THROWS when nothing bound it. Called unguarded from the
      // catch, it turns a handled read failure into an unhandled one: the
      // screen never reaches its error state and the exception escapes into
      // whatever awaited the load.
      Magic.flush();

      Http.fake((request) {
        throw StateError('connection closed');
      });

      await controller.loadPage(1);

      expect(controller.isError, isTrue);
      expect(controller.isSuccess, isFalse);
    });
  });
}
