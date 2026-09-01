import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('NotificationException', () {
    test('stores message', () {
      final e = NotificationException('Test error');
      expect(e.message, 'Test error');
    });

    test('stores optional code', () {
      final e = NotificationException('Error', code: 'ERR_001');
      expect(e.code, 'ERR_001');
    });

    test('toString() includes message', () {
      final e = NotificationException('Test error');
      expect(e.toString(), contains('Test error'));
    });
  });

  group('UnsupportedPlatformException', () {
    test('extends NotificationException', () {
      const e = UnsupportedPlatformException('Push is not supported here');
      expect(e, isA<NotificationException>());
    });

    test('carries the message it was given', () {
      const e = UnsupportedPlatformException('Push is not supported here');
      expect(e.message, 'Push is not supported here');
    });
  });
}
