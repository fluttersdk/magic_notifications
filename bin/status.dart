import 'dart:io';
import 'package:fluttersdk_magic_notifications/src/cli/commands/status_command.dart';
import 'package:fluttersdk_magic_cli/fluttersdk_magic_cli.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Display this help message',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Show detailed status information',
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool) {
      _showHelp(parser);
      exit(0);
    }

    print(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // Find project root
    String projectRoot;
    try {
      projectRoot = FileHelper.findProjectRoot();
    } catch (e) {
      print(ConsoleStyle.error(
          'Could not find pubspec.yaml in current directory or parent directories'));
      print(ConsoleStyle.info(
          'Please run this command from your Flutter/Dart project directory'));
      exit(1);
    }

    final command = StatusCommand(projectRoot: projectRoot);
    final verbose = results['verbose'] as bool;

    // Generate and display report
    final report = command.generateReport(verbose: verbose);
    print(report);

    // Check if there are any issues
    final missing = command.getMissingRequirements();

    if (missing.isEmpty) {
      print(ConsoleStyle.success('All checks passed!'));
      print('');
      print(ConsoleStyle.info('Next steps:'));
      print(
          '  • Test notifications: dart run fluttersdk_magic_notifications:test');
      print(
          '  • Update configuration: dart run fluttersdk_magic_notifications:configure');
      exit(0);
    } else {
      print('');
      print(ConsoleStyle.warning('Issues detected. Run the following to fix:'));
      print('  • Install: dart run fluttersdk_magic_notifications:install');
      print('  • Configure: dart run fluttersdk_magic_notifications:configure');
      exit(1);
    }
  } catch (e) {
    print(ConsoleStyle.error('Error: $e'));
    exit(1);
  }
}

void _showHelp(ArgParser parser) {
  print('''
Magic Notifications - Status Checker

Usage: dart run fluttersdk_magic_notifications:status [options]

Options:
${parser.usage}

Description:
  Checks the installation and configuration status of Magic Notifications.
  Verifies:
  • Plugin installation in pubspec.yaml
  • Configuration file existence
  • Platform-specific setup (Android, iOS, Web)

Examples:
  # Check status
  dart run fluttersdk_magic_notifications:status

  # Verbose output
  dart run fluttersdk_magic_notifications:status --verbose
''');
}
