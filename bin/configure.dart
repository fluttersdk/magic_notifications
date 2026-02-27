import 'dart:io';
import 'package:magic_cli/magic_cli.dart';
import 'package:magic_notifications/src/cli/commands/configure_command.dart'
    as notifications;

void main(List<String> arguments) async {
  try {
    String projectRoot;
    try {
      projectRoot = FileHelper.findProjectRoot();
    } catch (e) {
      stderr.writeln(ConsoleStyle.error(
          'Could not find pubspec.yaml in current directory or parent directories'));
      stdout.writeln(ConsoleStyle.info(
          'Please run this command from your Flutter/Dart project directory'));
      exit(1);
    }

    final command = notifications.ConfigureCommand(projectRoot: projectRoot);
    await command.runWith(arguments);
  } catch (e) {
    stderr.writeln(ConsoleStyle.error('Error: $e'));
    exit(1);
  }
}
