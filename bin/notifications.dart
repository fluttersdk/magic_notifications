import 'package:magic_cli/magic_cli.dart' hide InstallCommand;

import 'package:magic_notifications/src/cli/commands/install_command.dart';
import 'package:magic_notifications/src/cli/commands/configure_command.dart';
import 'package:magic_notifications/src/cli/commands/status_command.dart';
import 'package:magic_notifications/src/cli/commands/test_command.dart';

/// Single consolidated entry point for all Magic Notifications CLI commands.
void main(List<String> args) async {
  final kernel = Kernel();
  kernel.registerMany([
    InstallCommand(),
    ConfigureCommand(),
    StatusCommand(),
    TestCommand(),
  ]);
  await kernel.handle(args);
}
