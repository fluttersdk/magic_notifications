import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

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

  group('PushNotSupportedException', () {
    test('extends NotificationException', () {
      final e = PushNotSupportedException();
      expect(e, isA<NotificationException>());
    });

    test('has default message', () {
      final e = PushNotSupportedException();
      expect(e.message, contains('not supported'));
    });
  });
}
