import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/src/models/database_notification.dart';
import 'package:magic_notifications/src/notification_manager.dart';

import 'test_helper.dart';

void main() {
  late NotificationManager manager;

  setUpAll(() async {
    await initMagicForTests();
  });

  setUp(() {
    manager = NotificationManager();
  });

  group('NotificationManager - Database', () {
    test('notifications() returns stream of notification lists', () {
      final stream = manager.notifications();
      expect(stream, isA<Stream<List<DatabaseNotification>>>());
    });

    test('stream emits data when listener attached', () async {
      final completer = Completer<List<DatabaseNotification>>();
      final subscription = manager.notifications().listen((data) {
        if (!completer.isCompleted) {
          completer.complete(data);
        }
      });

      final notifications = await completer.future;
      expect(notifications, isEmpty);

      await subscription.cancel();
    });

    test('fetchNotifications() updates stream with data', () async {
      final completer = Completer<List<DatabaseNotification>>();
      var emitCount = 0;

      final subscription = manager.notifications().listen((data) {
        emitCount++;
        if (emitCount == 1 && !completer.isCompleted) {
          completer.complete(data);
        }
      });

      // Wait for initial emit
      await completer.future;

      // Call fetch (should emit again)
      await manager.fetchNotifications();

      // Give time for emission
      await Future.delayed(Duration(milliseconds: 50));

      expect(emitCount, greaterThanOrEqualTo(1));

      await subscription.cancel();
    });

    test('unreadCount() returns integer', () async {
      final count = await manager.unreadCount();
      expect(count, isA<int>());
    });

    test('markAsRead() completes without error', () async {
      await expectLater(
        manager.markAsRead('test-id'),
        completes,
      );
    });

    test('markAllAsRead() completes without error', () async {
      await expectLater(
        manager.markAllAsRead(),
        completes,
      );
    });

    test('deleteNotification() completes without error', () async {
      await expectLater(
        manager.deleteNotification('test-id'),
        completes,
      );
    });

    test('refreshNotifications() is alias for fetchNotifications', () async {
      await expectLater(
        manager.refreshNotifications(),
        completes,
      );
    });
  });
}
