/// CLI barrel for Magic Notifications.
///
/// Exposes ONLY the artisan-CLI surface ([MagicNotificationsArtisanProvider]).
/// Does NOT export the Magic Notifications runtime (no Flutter, dart:ui, or
/// package:magic runtime imports), so this barrel is safe for consumption from
/// pure-Dart artisan dispatchers.
///
/// Consumers register the provider in their `bin/artisan.dart`:
///
/// ```dart
/// import 'package:fluttersdk_artisan/artisan.dart';
/// import 'package:magic_notifications/cli.dart' show MagicNotificationsArtisanProvider;
///
/// Future<void> main(List<String> args) async {
///   final registry = ArtisanRegistry()
///     ..registerProvider(MagicNotificationsArtisanProvider());
///   exit(await ArtisanApplication(registry: registry).dispatch(args));
/// }
/// ```
///
/// Runtime consumers (lib/main.dart of a Magic-based app) continue to
/// import `package:magic_notifications/magic_notifications.dart` for facades
/// and the full notification surface.
library;

export 'src/cli/notifications_artisan_provider.dart';
