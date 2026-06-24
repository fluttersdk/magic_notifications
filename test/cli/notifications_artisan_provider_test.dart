import 'package:magic_notifications/src/cli/notifications_artisan_provider.dart';
import 'package:test/test.dart';

void main() {
  group('MagicNotificationsArtisanProvider.mcpTools', () {
    late MagicNotificationsArtisanProvider provider;

    setUp(() {
      provider = MagicNotificationsArtisanProvider();
    });

    test('exposes exactly 2 MCP tools', () {
      expect(provider.mcpTools(), hasLength(2));
    });

    test('exposes notifications_doctor tool', () {
      final names = provider.mcpTools().map((t) => t.name).toList();
      expect(names, contains('notifications_doctor'));
    });

    test('exposes notifications_channels tool', () {
      final names = provider.mcpTools().map((t) => t.name).toList();
      expect(names, contains('notifications_channels'));
    });

    test('does not expose install tool', () {
      final names = provider.mcpTools().map((t) => t.name).toList();
      expect(names, isNot(contains('notifications_install')));
    });

    test('does not expose uninstall tool', () {
      final names = provider.mcpTools().map((t) => t.name).toList();
      expect(names, isNot(contains('notifications_uninstall')));
    });

    test('does not expose configure tool', () {
      final names = provider.mcpTools().map((t) => t.name).toList();
      expect(names, isNot(contains('notifications_configure')));
    });

    test('does not expose test tool', () {
      final names = provider.mcpTools().map((t) => t.name).toList();
      expect(names, isNot(contains('notifications_test')));
    });

    test('does not expose publish tool', () {
      final names = provider.mcpTools().map((t) => t.name).toList();
      expect(names, isNot(contains('notifications_publish')));
    });

    test('each tool has a non-empty description', () {
      for (final tool in provider.mcpTools()) {
        expect(
          tool.description,
          isNotEmpty,
          reason: '${tool.name} must have a description',
        );
      }
    });

    test('each tool has a non-empty extensionMethod', () {
      for (final tool in provider.mcpTools()) {
        expect(
          tool.extensionMethod,
          isNotEmpty,
          reason: '${tool.name} must declare an extensionMethod',
        );
      }
    });
  });
}
