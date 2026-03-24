import 'package:test/test.dart';
import 'package:magic_notifications/src/cli/commands/test_command.dart';

void main() {
  late TestCommand command;

  setUp(() {
    command = TestCommand();
  });

  group('TestCommand', () {
    test('getAvailableChannels returns correct channels', () {
      final channels = command.getAvailableChannels();
      expect(channels, containsAll(['database', 'push', 'mail']));
      expect(channels.length, equals(3));
    });

    test('validateApiUrl validates correctly', () {
      expect(command.validateApiUrl('https://api.example.com'), isTrue);
      expect(command.validateApiUrl('http://localhost:8000'), isTrue);
      expect(command.validateApiUrl('api.example.com'), isFalse);
      expect(command.validateApiUrl('ftp://example.com'), isFalse);
      expect(command.validateApiUrl(''), isFalse);
    });

    test('buildTestNotification returns correct payload', () {
      final notification = command.buildTestNotification(
        title: 'Test Title',
        body: 'Test Body',
        channel: 'database',
      );

      expect(notification['title'], equals('Test Title'));
      expect(notification['body'], equals('Test Body'));
      expect(notification['channel'], equals('database'));
      expect(notification['type'], equals('test'));
      expect(notification['created_at'], isNotNull);
      expect(notification['data'], isA<Map>());
      expect(notification['data']['test'], isTrue);
      expect(notification['data']['source'], equals('cli'));
    });

    test('formatNotificationPreview includes required headers', () {
      final notification = {
        'title': 'Test Title',
        'body': 'Test Body',
        'channel': 'database',
        'type': 'test',
      };

      final preview = command.formatNotificationPreview(notification);
      expect(preview, contains('Notification Preview'));
      expect(preview, contains('Title: Test Title'));
      expect(preview, contains('Body: Test Body'));
      expect(preview, contains('Channel: database'));
    });

    test('getProjectRoot returns a path from FileHelper', () {
      expect(command.getProjectRoot(), isNotNull);
    });
  });
}
