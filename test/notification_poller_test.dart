import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/src/notification_poller.dart';

/// Mock that tracks fetch calls for testing without calling real implementation.
class MockNotificationManager {
  int fetchCallCount = 0;

  Future<void> fetchNotifications() async {
    fetchCallCount++;
    // Don't call real manager - just track the call
  }
}

void main() {
  late MockNotificationManager mockManager;
  late NotificationPoller poller;

  setUp(() {
    mockManager = MockNotificationManager();
    poller = NotificationPoller(mockManager);
  });

  tearDown(() {
    poller.stop();
  });

  group('NotificationPoller', () {
    test('start() begins polling', () async {
      poller.start();

      // Wait a bit for first fetch
      await Future.delayed(Duration(milliseconds: 100));

      expect(mockManager.fetchCallCount, greaterThanOrEqualTo(1));
      expect(poller.isActive, isTrue);
    });

    test('stop() cancels polling', () {
      poller.start();
      expect(poller.isActive, isTrue);

      poller.stop();
      expect(poller.isActive, isFalse);
    });

    test('pause() temporarily stops without canceling', () {
      poller.start();
      expect(poller.isActive, isTrue);

      poller.pause();
      expect(poller.isActive, isFalse);
      expect(poller.isPaused, isTrue);
    });

    test('resume() continues after pause', () async {
      poller.start();
      poller.pause();
      expect(poller.isActive, isFalse);

      final countBeforeResume = mockManager.fetchCallCount;

      poller.resume();
      expect(poller.isActive, isTrue);
      expect(poller.isPaused, isFalse);

      // Wait for polling to resume
      await Future.delayed(Duration(milliseconds: 100));
      expect(mockManager.fetchCallCount, greaterThan(countBeforeResume));
    });

    test('refresh() fetches immediately without affecting polling state',
        () async {
      final countBefore = mockManager.fetchCallCount;

      await poller.refresh();

      expect(mockManager.fetchCallCount, countBefore + 1);
      expect(poller.isActive, isFalse); // Not started yet
    });

    test('refresh() works when poller is active', () async {
      poller.start();

      await Future.delayed(Duration(milliseconds: 50));
      final countBefore = mockManager.fetchCallCount;

      await poller.refresh();

      expect(mockManager.fetchCallCount, countBefore + 1);
      expect(poller.isActive, isTrue); // Still active
    });

    test('multiple start() calls are idempotent', () {
      poller.start();
      poller.start();
      poller.start();

      expect(poller.isActive, isTrue);
    });

    test('stop() on non-started poller does not throw', () {
      expect(() => poller.stop(), returnsNormally);
    });
  });
}
