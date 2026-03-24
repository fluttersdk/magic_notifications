import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('DatabaseChannel', () {
    test('name is "database"', () {
      final channel = DatabaseChannel();
      expect(channel.name, 'database');
    });

    test('isAvailable is always true', () {
      final channel = DatabaseChannel();
      expect(channel.isAvailable, isTrue);
    });

    test('send() skips if toDatabase() returns null', () async {
      final channel = DatabaseChannel();
      final notification = TestNotification(databaseData: null);
      final notifiable = TestNotifiable('1');

      // Should complete without error
      await expectLater(
        channel.send(notifiable, notification),
        completes,
      );
    });
  });
}

// Test notification
class TestNotification extends Notification {
  final Map<String, dynamic>? databaseData;

  TestNotification({this.databaseData});

  @override
  List<String> via(Notifiable notifiable) => ['database'];

  @override
  Map<String, dynamic>? toDatabase(Notifiable notifiable) => databaseData;
}

// Test notifiable entity
class TestNotifiable with Notifiable {
  final String _id;

  TestNotifiable(this._id);

  @override
  String get notifiableId => _id;
}
