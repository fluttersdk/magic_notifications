import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

void main() {
  group('Notify', () {
    test('manager returns NotificationManager singleton', () {
      final manager = Notify.manager;
      expect(manager, isA<NotificationManager>());
      // Verify it's the same singleton
      expect(identical(manager, NotificationManager()), isTrue);
    });

    test('send() delegates to manager', () async {
      final notification = TestNotification();
      final notifiable = TestNotifiable('1');

      // Reset and register mock channel
      Notify.manager.forgetChannels();
      final mockChannel = MockChannel('test');
      Notify.manager.registerChannel(mockChannel);

      await Notify.send(notifiable, notification);

      expect(mockChannel.sentCount, 1);
    });
  });
}

// Test notification
class TestNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['test'];
}

// Test notifiable entity
class TestNotifiable with Notifiable {
  final String _id;

  TestNotifiable(this._id);

  @override
  String get notifiableId => _id;
}

// Mock channel for testing
class MockChannel extends NotificationChannel {
  final String _name;
  int sentCount = 0;

  MockChannel(this._name);

  @override
  String get name => _name;

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    sentCount++;
  }
}
