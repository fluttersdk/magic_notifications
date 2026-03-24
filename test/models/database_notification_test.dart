import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('DatabaseNotification', () {
    test('fromMap() parses API response', () {
      final map = {
        'id': 'uuid-123',
        'type': 'monitor_down',
        'data': {
          'title': 'Monitor Down',
          'body': 'api.example.com is not responding',
          'action_url': '/monitors/1',
        },
        'created_at': '2026-02-03T12:00:00.000Z',
        'read_at': null,
      };

      final notification = DatabaseNotification.fromMap(map);

      expect(notification.id, 'uuid-123');
      expect(notification.type, 'monitor_down');
      expect(notification.title, 'Monitor Down');
      expect(notification.body, 'api.example.com is not responding');
      expect(notification.actionUrl, '/monitors/1');
      expect(notification.isRead, isFalse);
      expect(notification.createdAt, isA<DateTime>());
    });

    test('fromMap() handles read notification', () {
      final map = {
        'id': 'uuid-123',
        'type': 'monitor_up',
        'data': {'title': 'Monitor Up', 'body': 'Back online'},
        'created_at': '2026-02-03T12:00:00.000Z',
        'read_at': '2026-02-03T12:05:00.000Z',
      };

      final notification = DatabaseNotification.fromMap(map);
      expect(notification.isRead, isTrue);
      expect(notification.readAt, isA<DateTime>());
    });

    test('fromMap() handles missing optional fields', () {
      final map = {
        'id': 'uuid-123',
        'type': 'test',
        'data': {'title': 'Test', 'body': 'Body'},
        'created_at': '2026-02-03T12:00:00.000Z',
      };

      final notification = DatabaseNotification.fromMap(map);
      expect(notification.actionUrl, isNull);
      expect(notification.readAt, isNull);
    });

    test('copyWith() creates modified copy', () {
      final original = DatabaseNotification(
        id: '1',
        type: 'test',
        title: 'Test',
        body: 'Body',
        data: {},
        createdAt: DateTime(2026, 2, 3, 12, 0),
      );

      final modified = original.copyWith(readAt: DateTime(2026, 2, 3, 12, 5));

      expect(original.isRead, isFalse);
      expect(original.readAt, isNull);
      expect(modified.isRead, isTrue);
      expect(modified.readAt, isNotNull);
      expect(modified.id, original.id);
      expect(modified.title, original.title);
    });

    test('copyWith() preserves unchanged fields', () {
      final original = DatabaseNotification(
        id: '1',
        type: 'test',
        title: 'Test',
        body: 'Body',
        data: {'key': 'value'},
        actionUrl: '/test',
        createdAt: DateTime(2026, 2, 3),
      );

      final modified = original.copyWith();

      expect(modified.id, original.id);
      expect(modified.type, original.type);
      expect(modified.title, original.title);
      expect(modified.body, original.body);
      expect(modified.actionUrl, original.actionUrl);
    });

    test('toMap() serializes correctly', () {
      final notification = DatabaseNotification(
        id: 'uuid-123',
        type: 'monitor_down',
        title: 'Monitor Down',
        body: 'Error',
        data: {'monitor_id': 1},
        actionUrl: '/monitors/1',
        createdAt: DateTime(2026, 2, 3, 12, 0),
        readAt: DateTime(2026, 2, 3, 12, 5),
      );

      final map = notification.toMap();

      expect(map['id'], 'uuid-123');
      expect(map['type'], 'monitor_down');
      expect(map['data']['title'], 'Monitor Down');
      expect(map['data']['body'], 'Error');
      expect(map['data']['action_url'], '/monitors/1');
      expect(map['data']['monitor_id'], 1);
      expect(map['created_at'], isA<String>());
      expect(map['read_at'], isA<String>());
    });
  });
}
