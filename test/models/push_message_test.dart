import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

void main() {
  group('PushMessage', () {
    test('fluent builder sets heading', () {
      final message = PushMessage()..heading('Test Title');
      expect(message.headingValue, 'Test Title');
    });

    test('fluent builder sets content', () {
      final message = PushMessage()..content('Test Body');
      expect(message.contentValue, 'Test Body');
    });

    test('fluent builder sets data', () {
      final message = PushMessage()..data({'key': 'value'});
      expect(message.dataValue, {'key': 'value'});
    });

    test('addData() merges into existing data', () {
      final message = PushMessage()
        ..data({'a': '1'})
        ..addData('b', '2');
      expect(message.dataValue, {'a': '1', 'b': '2'});
    });

    test('toMap() returns complete structure', () {
      final message = PushMessage()
        ..heading('Title')
        ..content('Body')
        ..data({'type': 'test'})
        ..url('/page');

      final map = message.toMap();
      expect(map['heading'], 'Title');
      expect(map['content'], 'Body');
      expect(map['data'], {'type': 'test'});
      expect(map['url'], '/page');
    });

    test('toMap() excludes null values', () {
      final message = PushMessage()..heading('Title');
      final map = message.toMap();
      expect(map.containsKey('content'), isFalse);
      expect(map.containsKey('url'), isFalse);
    });
  });
}
