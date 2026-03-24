import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/src/models/notification_preference.dart';

void main() {
  group('NotificationPreference', () {
    test('fromMap() parses API response', () {
      final map = {
        'push_enabled': true,
        'email_enabled': false,
        'in_app_enabled': true,
        'type_preferences': {
          'monitor_down': {'push': true, 'email': false, 'in_app': true},
        },
      };

      final pref = NotificationPreference.fromMap(map);

      expect(pref.pushEnabled, isTrue);
      expect(pref.emailEnabled, isFalse);
      expect(pref.inAppEnabled, isTrue);
      expect(pref.typePreferences['monitor_down']?.push, isTrue);
      expect(pref.typePreferences['monitor_down']?.email, isFalse);
      expect(pref.typePreferences['monitor_down']?.inApp, isTrue);
    });

    test('isEnabled() checks global and type settings', () {
      final pref = NotificationPreference(
        pushEnabled: true,
        emailEnabled: false,
        inAppEnabled: true,
        typePreferences: {
          'monitor_down':
              ChannelPreference(push: true, email: true, inApp: true),
        },
      );

      expect(pref.isEnabled('monitor_down', 'push'), isTrue);
      expect(
          pref.isEnabled('monitor_down', 'mail'), isFalse); // Global disabled
      expect(pref.isEnabled('unknown_type', 'push'),
          isTrue); // No type pref = default
    });

    test('isEnabled() returns false if both type and global are disabled', () {
      final pref = NotificationPreference(
        pushEnabled: true,
        emailEnabled: true,
        typePreferences: {
          'monitor_down':
              ChannelPreference(push: false, email: false, inApp: true),
        },
      );

      expect(pref.isEnabled('monitor_down', 'push'), isFalse);
      expect(pref.isEnabled('monitor_down', 'mail'), isFalse);
    });

    test('toMap() serializes correctly', () {
      final pref = NotificationPreference(
        pushEnabled: false,
        emailEnabled: true,
        inAppEnabled: true,
        typePreferences: {
          'monitor_down':
              ChannelPreference(push: false, email: true, inApp: true),
        },
      );
      final map = pref.toMap();

      expect(map['push_enabled'], isFalse);
      expect(map['email_enabled'], isTrue);
      expect(map['in_app_enabled'], isTrue);
      expect(map['type_preferences'], isA<Map>());
      expect(map['type_preferences']['monitor_down']['push'], isFalse);
      expect(map['type_preferences']['monitor_down']['email'], isTrue);
    });

    test('copyWith() creates modified copy', () {
      final original = NotificationPreference(
        pushEnabled: true,
        emailEnabled: false,
      );

      final modified = original.copyWith(emailEnabled: true);

      expect(original.pushEnabled, isTrue);
      expect(original.emailEnabled, isFalse);
      expect(modified.pushEnabled, isTrue);
      expect(modified.emailEnabled, isTrue);
    });

    test('copyWith() preserves null values', () {
      final original = NotificationPreference(
        pushEnabled: true,
        emailEnabled: false,
      );

      final modified = original.copyWith();

      expect(modified.pushEnabled, original.pushEnabled);
      expect(modified.emailEnabled, original.emailEnabled);
    });
  });

  group('ChannelPreference', () {
    test('fromMap() parses correctly', () {
      final map = {
        'push': true,
        'email': false,
        'in_app': true,
      };

      final pref = ChannelPreference.fromMap(map);

      expect(pref.push, isTrue);
      expect(pref.email, isFalse);
      expect(pref.inApp, isTrue);
    });

    test('toMap() serializes correctly', () {
      final pref = ChannelPreference(push: true, email: false, inApp: true);
      final map = pref.toMap();

      expect(map['push'], isTrue);
      expect(map['email'], isFalse);
      expect(map['in_app'], isTrue);
    });

    test('defaults to true for all channels', () {
      final pref = ChannelPreference();

      expect(pref.push, isTrue);
      expect(pref.email, isTrue);
      expect(pref.inApp, isTrue);
    });
  });
}
