/// CLI barrel for Magic Notifications.
///
/// Re-exports the artisan infrastructure plus the notifications provider and
/// all seven notifications:* commands. Consumers register
/// [MagicNotificationsArtisanProvider] in their `artisan.providers` config;
/// the commands surface automatically through the host [ArtisanApplication].
library;

// Hide the artisan-builtin DoctorCommand so the notifications-specific
// DoctorCommand (commands/doctor_command.dart) is the only one visible from
// this barrel.
export 'package:fluttersdk_artisan/artisan.dart' hide DoctorCommand;
export 'commands/channels_command.dart';
export 'commands/configure_command.dart';
export 'commands/doctor_command.dart';
export 'commands/install_command.dart';
export 'commands/publish_command.dart';
export 'commands/test_command.dart';
export 'commands/uninstall_command.dart';
export 'notifications_artisan_provider.dart';
