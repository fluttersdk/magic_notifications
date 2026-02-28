import 'package:magic_cli/magic_cli.dart' hide InstallCommand;

import 'package:magic_notifications/src/cli/commands/install_command.dart';
import 'package:magic_notifications/src/cli/commands/configure_command.dart';
import 'package:magic_notifications/src/cli/commands/test_command.dart';
import 'package:magic_notifications/src/cli/commands/doctor_command.dart';
import 'package:magic_notifications/src/cli/commands/uninstall_command.dart';
import 'package:magic_notifications/src/cli/commands/publish_command.dart';
import 'package:magic_notifications/src/cli/commands/channels_command.dart';



/// Magic Notifications CLI entry point.
void main(List<String> args) async {
  final kernel = Kernel();

  // 1. Register all notification commands.
  kernel.registerMany([
    InstallCommand(),
    ConfigureCommand(),
    TestCommand(),
    DoctorCommand(),
    UninstallCommand(),
    PublishCommand(),
    ChannelsCommand(),
  ]);

  // 2. Execute requested command.
  await kernel.handle(args);
}
