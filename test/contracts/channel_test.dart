import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('NotificationChannel', () {
    test('has name property', () {
      final channel = TestChannel();
      expect(channel.name, 'test');
    });

    test('has isAvailable property', () {
      final channel = TestChannel();
      expect(channel.isAvailable, isTrue);
    });

    test('send() is callable', () async {
      final channel = TestChannel();
      await expectLater(
        channel.send(MockNotifiable(), TestNotification()),
        completes,
      );
    });
  });
}

class TestChannel extends NotificationChannel {
  @override
  String get name => 'test';

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {}
}

class MockNotifiable with Notifiable {
  @override
  String get notifiableId => '1';
}

class TestNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['test'];
}
