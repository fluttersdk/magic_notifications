import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('Notifiable', () {
    test('notifiableId is required', () {
      final entity = TestNotifiable('123');
      expect(entity.notifiableId, '123');
    });

    test('notifiableEmail defaults to null', () {
      final entity = TestNotifiable('123');
      expect(entity.notifiableEmail, isNull);
    });

    test('pushExternalId defaults to notifiableId', () {
      final entity = TestNotifiable('123');
      expect(entity.pushExternalId, '123');
    });

    test('notificationPreference defaults to null', () {
      final entity = TestNotifiable('123');
      expect(entity.notificationPreference, isNull);
    });
  });
}

class TestNotifiable with Notifiable {
  final String _id;

  TestNotifiable(this._id);

  @override
  String get notifiableId => _id;
}
