import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_notifications/src/cli/notifications_artisan_provider.dart';
import 'package:test/test.dart';

void main() {
  group('MagicNotificationsArtisanProvider e2e surface', () {
    late MagicNotificationsArtisanProvider provider;

    setUp(() {
      provider = MagicNotificationsArtisanProvider();
    });

    test('provider name is "notifications"', () {
      expect(provider.providerName, equals('notifications'));
    });

    test('commands list is non-empty', () {
      expect(provider.commands(), isNotEmpty);
    });

    test('all seven notifications commands are present', () {
      final commands = [
        'install',
        'configure',
        'test',
        'doctor',
        'uninstall',
        'publish',
        'channels',
      ];

      final registeredNames = provider.commands().map((c) => c.name).toList();

      for (final cmd in commands) {
        expect(
          registeredNames,
          contains('notifications:$cmd'),
          reason: 'notifications:$cmd must be registered by the provider',
        );
      }
    });

    test('mcpTools exposes exactly 2 read-only tools', () {
      // Commands surface via ArtisanApplication registered in the host app;
      // the provider exposes only read-only diagnostics as MCP tools.
      expect(provider.mcpTools(), hasLength(2));
    });

    test('mcpTools tool names follow snake_case service-prefix convention', () {
      for (final tool in provider.mcpTools()) {
        expect(
          tool.name,
          matches(RegExp(r'^notifications_[a-z_]+$')),
          reason:
              '${tool.name} must follow the notifications_ prefix convention',
        );
      }
    });

    test('all commands are ArtisanCommand instances', () {
      for (final command in provider.commands()) {
        expect(command, isA<ArtisanCommand>());
      }
    });

    test('all commands have boot mode CommandBoot.none', () {
      for (final command in provider.commands()) {
        expect(
          command.boot,
          equals(CommandBoot.none),
          reason: '${command.name} should boot without a connected Flutter app',
        );
      }
    });
  });
}
