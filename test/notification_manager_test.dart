import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

void main() {
  late NotificationManager manager;

  setUp(() {
    manager = NotificationManager();
    manager.forgetChannels(); // Reset for tests
  });

  group('NotificationManager', () {
    test('is singleton', () {
      final m1 = NotificationManager();
      final m2 = NotificationManager();
      expect(identical(m1, m2), isTrue);
    });

    test('registerChannel() adds channel', () {
      final channel = MockChannel('test');
      manager.registerChannel(channel);
      expect(manager.hasChannel('test'), isTrue);
    });

    test('send() dispatches to correct channels', () async {
      final channel = MockChannel('database');
      manager.registerChannel(channel);

      final notification = TestNotification(via: ['database']);
      final notifiable = TestNotifiable('1');

      await manager.send(notifiable, notification);

      expect(channel.sentCount, 1);
    });

    test('send() skips unavailable channels', () async {
      final channel = MockChannel('database', available: false);
      manager.registerChannel(channel);

      final notification = TestNotification(via: ['database']);
      await manager.send(TestNotifiable('1'), notification);

      expect(channel.sentCount, 0);
    });

    test('send() logs warning for unknown channels', () async {
      final notification = TestNotification(via: ['unknown']);
      // Should not throw, just log
      await expectLater(
        manager.send(TestNotifiable('1'), notification),
        completes,
      );
    });
  });
}

// Mock channel for testing
class MockChannel extends NotificationChannel {
  final String _name;
  final bool _available;
  int sentCount = 0;

  MockChannel(this._name, {bool available = true}) : _available = available;

  @override
  String get name => _name;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    sentCount++;
  }
}

// Test notification
class TestNotification extends Notification {
  final List<String> channels;

  TestNotification({required List<String> via}) : channels = via;

  @override
  List<String> via(Notifiable notifiable) => channels;
}

// Test notifiable entity
class TestNotifiable with Notifiable {
  final String _id;

  TestNotifiable(this._id);

  @override
  String get notifiableId => _id;
}
