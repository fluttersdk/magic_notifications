import 'package:test/test.dart';
import 'package:fluttersdk_magic_notifications/src/cli/commands/test_command.dart';

void main() {
  group('TestCommand', () {
    late TestCommand command;

    setUp(() {
      command = TestCommand();
    });

    test('buildTestNotification creates valid structure', () {
      final notification = command.buildTestNotification(
        title: 'Test Title',
        body: 'Test Body',
        channel: 'database',
      );

      expect(notification['title'], equals('Test Title'));
      expect(notification['body'], equals('Test Body'));
      expect(notification['type'], equals('test'));
      expect(notification['channel'], equals('database'));
    });

    test('buildTestNotification includes timestamp', () {
      final notification = command.buildTestNotification(
        title: 'Test',
        body: 'Message',
        channel: 'push',
      );

      expect(notification['created_at'], isNotNull);
    });

    test('getAvailableChannels returns supported channels', () {
      final channels = command.getAvailableChannels();
      expect(channels, contains('database'));
      expect(channels, contains('push'));
      expect(channels, isA<List<String>>());
    });

    test('validateApiUrl accepts valid URLs', () {
      expect(command.validateApiUrl('http://localhost:8000'), isTrue);
      expect(command.validateApiUrl('https://api.example.com'), isTrue);
      expect(command.validateApiUrl('http://192.168.1.1:3000'), isTrue);
    });

    test('validateApiUrl rejects invalid URLs', () {
      expect(command.validateApiUrl('invalid'), isFalse);
      expect(command.validateApiUrl('ftp://wrong'), isFalse);
      expect(command.validateApiUrl(''), isFalse);
    });

    test('formatNotificationPreview shows readable format', () {
      final preview = command.formatNotificationPreview({
        'title': 'Alert',
        'body': 'Test message',
        'channel': 'push',
      });

      expect(preview, contains('Alert'));
      expect(preview, contains('Test message'));
      expect(preview, contains('push'));
    });

    test('formatNotificationPreview handles missing fields', () {
      final preview = command.formatNotificationPreview({
        'title': 'Alert',
      });

      expect(preview, contains('Alert'));
      expect(preview, isNot(contains('null')));
    });
  });
}
