import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('PushUserAttributes', () {
    test('describes nobody by default', () {
      const PushUserAttributes attributes = PushUserAttributes();

      expect(attributes.email, isNull);
      expect(attributes.tags, isEmpty);
      expect(attributes.isEmpty, isTrue);
      expect(attributes.isNotEmpty, isFalse);
      expect(attributes, PushUserAttributes.none);
    });

    test('an email alone, or a tag alone, is something to send', () {
      expect(
        const PushUserAttributes(email: 'ada@example.com').isNotEmpty,
        isTrue,
      );
      expect(
        const PushUserAttributes(tags: <String, String>{'plan': 'pro'})
            .isNotEmpty,
        isTrue,
      );
    });

    test('two descriptions of the same person are equal', () {
      // The manager compares what it wrote against what the host describes to
      // decide whether there is anything to send at all, so value equality is
      // what stops a team switch re-writing the same three fields.
      const PushUserAttributes first = PushUserAttributes(
        email: 'ada@example.com',
        tags: <String, String>{'first_name': 'Ada', 'last_name': 'Lovelace'},
      );
      const PushUserAttributes second = PushUserAttributes(
        email: 'ada@example.com',
        tags: <String, String>{'last_name': 'Lovelace', 'first_name': 'Ada'},
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('a changed value, a changed key set and a changed email all differ',
        () {
      const PushUserAttributes base = PushUserAttributes(
        email: 'ada@example.com',
        tags: <String, String>{'first_name': 'Ada'},
      );

      expect(
        base,
        isNot(const PushUserAttributes(
          email: 'ada@example.com',
          tags: <String, String>{'first_name': 'Grace'},
        )),
      );
      expect(
        base,
        isNot(const PushUserAttributes(
          email: 'ada@example.com',
          tags: <String, String>{'first_name': 'Ada', 'locale': 'en'},
        )),
      );
      expect(
        base,
        isNot(const PushUserAttributes(
          email: 'grace@example.com',
          tags: <String, String>{'first_name': 'Ada'},
        )),
      );
    });
  });
}
