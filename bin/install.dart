import 'dart:io';
import 'package:fluttersdk_magic_notifications/src/cli/commands/install_command.dart';
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
      'non-interactive',
      negatable: false,
      help: 'Run in non-interactive mode (for CI/CD)',
    )
    ..addOption(
      'app-id',
      help: 'OneSignal App ID',
    )
    ..addOption(
      'platforms',
      help: 'Comma-separated list of platforms (android,ios,web)',
    )
    ..addFlag(
      'soft-prompt',
      defaultsTo: true,
      help: 'Enable soft prompt for notifications',
    )
    ..addOption(
      'safari-web-id',
      help: 'Safari Web ID for web push (optional)',
    )
    ..addFlag(
      'notify-button',
      defaultsTo: false,
      help: 'Enable OneSignal notify button on web (default: disabled)',
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

    final command = InstallCommand(projectRoot: projectRoot);

    // Check project type
    final projectType = command.detectProjectType();
    if (projectType == ProjectType.unknown) {
      print(ConsoleStyle.error('Could not detect project type'));
      exit(1);
    }

    print(ConsoleStyle.info('Detected ${projectType.name} project'));
    print('');

    // Non-interactive mode
    if (results['non-interactive'] as bool) {
      await _runNonInteractive(results, command);
      exit(0);
    }

    // Interactive mode
    await _runInteractive(command, projectRoot);
    exit(0);
  } catch (e) {
    print(ConsoleStyle.error('Error: $e'));
    exit(1);
  }
}

/// Run installation in non-interactive mode (for CI/CD)
Future<void> _runNonInteractive(
    ArgResults results, InstallCommand command) async {
  final appId = results['app-id'] as String?;
  if (appId == null || appId.isEmpty) {
    print(ConsoleStyle.error('--app-id is required in non-interactive mode'));
    exit(1);
  }

  if (!command.validateOneSignalAppId(appId)) {
    print(ConsoleStyle.error('Invalid OneSignal App ID format'));
    exit(1);
  }

  final platformsStr = results['platforms'] as String? ?? 'android,ios,web';
  final platforms = platformsStr.split(',').map((p) => p.trim()).toList();
  final enableSoftPrompt = results['soft-prompt'] as bool;
  final safariWebId = results['safari-web-id'] as String?;
  final notifyButtonEnabled = results['notify-button'] as bool;

  print(ConsoleStyle.step(1, 3, 'Creating configuration files...'));
  await command.executeNonInteractive(
    oneSignalAppId: appId,
    platforms: platforms,
    enableSoftPrompt: enableSoftPrompt,
    safariWebId: safariWebId,
    notifyButtonEnabled: notifyButtonEnabled,
  );

  _showSuccessMessage();
}

/// Run installation in interactive mode
Future<void> _runInteractive(InstallCommand command, String projectRoot) async {
  print(ConsoleStyle.info('Starting interactive installation wizard...'));
  print('');

  // Step 1: Get OneSignal App ID
  print(ConsoleStyle.step(1, 4, 'OneSignal Configuration'));
  print(ConsoleStyle.comment('Get your App ID from https://onesignal.com/'));
  print('');

  String? appId;
  while (appId == null || appId.isEmpty) {
    stdout.write('  Enter your OneSignal App ID: ');
    final input = stdin.readLineSync()?.trim();

    if (input == null || input.isEmpty) {
      print(ConsoleStyle.error('  App ID is required'));
      continue;
    }

    if (!command.validateOneSignalAppId(input)) {
      print(
          ConsoleStyle.error('  Invalid App ID format (expected UUID format)'));
      print(ConsoleStyle.comment(
          '  Example: 12345678-1234-1234-1234-123456789012'));
      continue;
    }

    appId = input;
  }
  print(ConsoleStyle.success('  App ID configured'));
  print('');

  // Step 2: Select platforms
  print(ConsoleStyle.step(2, 4, 'Platform Selection'));
  final availablePlatforms = _detectAvailablePlatforms(projectRoot);

  if (availablePlatforms.isEmpty) {
    print(ConsoleStyle.warning('  No platform directories found'));
    print(ConsoleStyle.info('  Defaulting to: android, ios, web'));
    availablePlatforms.addAll(['android', 'ios', 'web']);
  } else {
    print(ConsoleStyle.info(
        '  Detected platforms: ${availablePlatforms.join(', ')}'));
  }

  final selectedPlatforms = <String>[];
  for (final platform in availablePlatforms) {
    stdout.write('  Enable $platform? [Y/n]: ');
    final input = stdin.readLineSync()?.trim().toLowerCase();
    if (input == null || input.isEmpty || input == 'y' || input == 'yes') {
      selectedPlatforms.add(platform);
      print(ConsoleStyle.success('    $platform enabled'));
    } else {
      print(ConsoleStyle.comment('    $platform skipped'));
    }
  }

  if (selectedPlatforms.isEmpty) {
    print(ConsoleStyle.warning('  No platforms selected, using all detected'));
    selectedPlatforms.addAll(availablePlatforms);
  }
  print('');

  // Step 3: Web-specific configuration
  String? safariWebId;
  bool notifyButtonEnabled = false;

  if (selectedPlatforms.contains('web')) {
    print(ConsoleStyle.step(3, 5, 'Web Configuration'));
    print(ConsoleStyle.comment(
        '  Safari Web ID is required for Safari push notifications'));
    stdout.write('  Enter Safari Web ID (or press Enter to skip): ');
    final safariInput = stdin.readLineSync()?.trim();
    if (safariInput != null && safariInput.isNotEmpty) {
      safariWebId = safariInput;
      print(ConsoleStyle.success('  Safari Web ID configured'));
    } else {
      print(ConsoleStyle.comment('  Safari Web ID skipped'));
    }

    stdout.write('  Enable OneSignal notify button? [y/N]: ');
    final notifyInput = stdin.readLineSync()?.trim().toLowerCase();
    notifyButtonEnabled = notifyInput == 'y' || notifyInput == 'yes';

    if (notifyButtonEnabled) {
      print(ConsoleStyle.success('  Notify button enabled'));
    } else {
      print(ConsoleStyle.comment('  Notify button disabled'));
    }
    print('');
  }

  // Step 4: Soft prompt configuration
  print(ConsoleStyle.step(selectedPlatforms.contains('web') ? 4 : 3,
      selectedPlatforms.contains('web') ? 5 : 4, 'Soft Prompt Configuration'));
  print(ConsoleStyle.comment(
      '  Soft prompt asks users before requesting push permissions'));
  stdout.write('  Enable soft prompt? [Y/n]: ');
  final softPromptInput = stdin.readLineSync()?.trim().toLowerCase();
  final enableSoftPrompt = softPromptInput == null ||
      softPromptInput.isEmpty ||
      softPromptInput == 'y' ||
      softPromptInput == 'yes';

  if (enableSoftPrompt) {
    print(ConsoleStyle.success('  Soft prompt enabled'));
  } else {
    print(ConsoleStyle.comment('  Soft prompt disabled'));
  }
  print('');

  // Step 5: Execute installation
  print(ConsoleStyle.step(selectedPlatforms.contains('web') ? 5 : 4,
      selectedPlatforms.contains('web') ? 5 : 4, 'Installing...'));

  await command.executeNonInteractive(
    oneSignalAppId: appId,
    platforms: selectedPlatforms,
    enableSoftPrompt: enableSoftPrompt,
    safariWebId: safariWebId,
    notifyButtonEnabled: notifyButtonEnabled,
  );

  _showSuccessMessage();
}

/// Detect available platforms by checking directory existence
List<String> _detectAvailablePlatforms(String projectRoot) {
  final platforms = <String>[];

  if (Directory('$projectRoot/android').existsSync()) {
    platforms.add('android');
  }
  if (Directory('$projectRoot/ios').existsSync()) {
    platforms.add('ios');
  }
  if (Directory('$projectRoot/web').existsSync()) {
    platforms.add('web');
  }

  return platforms;
}

/// Show success message after installation
void _showSuccessMessage() {
  print('');
  print(ConsoleStyle.success('Installation complete!'));
  print('');
  print(ConsoleStyle.info('Next steps:'));
  print('  1. Run: ${ConsoleStyle.cyan}flutter pub get${ConsoleStyle.reset}');
  print('  2. Configure your OneSignal dashboard');
  print(
      '  3. Test: ${ConsoleStyle.cyan}dart run fluttersdk_magic_notifications:test --dry-run${ConsoleStyle.reset}');
  print(
      '  4. Check status: ${ConsoleStyle.cyan}dart run fluttersdk_magic_notifications:status${ConsoleStyle.reset}');
}

void _showHelp(ArgParser parser) {
  print('''
Magic Notifications - Installation Wizard

Usage: dart run fluttersdk_magic_notifications:install [options]

Options:
${parser.usage}

Examples:
  # Non-interactive installation
  dart run fluttersdk_magic_notifications:install --non-interactive --app-id YOUR_APP_ID

  # Specify platforms
  dart run fluttersdk_magic_notifications:install --non-interactive --app-id YOUR_APP_ID --platforms android,web

  # Web with Safari support and notify button
  dart run fluttersdk_magic_notifications:install --non-interactive --app-id YOUR_APP_ID --platforms web --safari-web-id web.onesignal.auto.xxx --notify-button

  # Disable soft prompt and notify button
  dart run fluttersdk_magic_notifications:install --non-interactive --app-id YOUR_APP_ID --no-soft-prompt --no-notify-button
''');
}
