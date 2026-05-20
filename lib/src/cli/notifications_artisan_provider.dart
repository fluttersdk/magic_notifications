import 'package:fluttersdk_artisan/artisan.dart';

import 'commands/channels_command.dart';
import 'commands/configure_command.dart';
// Aliased: fluttersdk_artisan exports its own toolchain `DoctorCommand` from
// its barrel; this is the notification-specific health check.
import 'commands/doctor_command.dart' as notifications_doctor;
import 'commands/install_command.dart';
import 'commands/publish_command.dart';
import 'commands/test_command.dart';
import 'commands/uninstall_command.dart';

/// ArtisanServiceProvider for Magic Notifications.
///
/// Contributes the seven `notifications:*` commands (install, configure, test,
/// doctor, uninstall, publish, channels) to the host application's
/// [ArtisanApplication]. Consumers wire this into their `artisan.providers`
/// config alongside other plugin providers (e.g. [MagicArtisanProvider],
/// [StarterArtisanProvider]).
class NotificationsArtisanProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() {
    return [
      InstallCommand(),
      ConfigureCommand(),
      TestCommand(),
      notifications_doctor.DoctorCommand(),
      UninstallCommand(),
      PublishCommand(),
      ChannelsCommand(),
    ];
  }
}
