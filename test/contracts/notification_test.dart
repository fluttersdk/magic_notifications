import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('Notification', () {
    test('type defaults to class name', () {
      final notification = TestNotification();
      expect(notification.type, 'TestNotification');
    });

    test('via() returns channels for notifiable', () {
      final notification = TestNotification();
      final notifiable = MockNotifiable();
      expect(notification.via(notifiable), ['database']);
    });

    test('toDatabase() returns null by default', () {
      final notification = TestNotification();
      expect(notification.toDatabase(MockNotifiable()), isNull);
    });

    test('toPush() returns null by default', () {
      final notification = TestNotification();
      expect(notification.toPush(MockNotifiable()), isNull);
    });

    test('toMail() returns null by default', () {
      final notification = TestNotification();
      expect(notification.toMail(MockNotifiable()), isNull);
    });
  });
}

class TestNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['database'];
}

class MockNotifiable with Notifiable {
  @override
  String get notifiableId => '1';
}
