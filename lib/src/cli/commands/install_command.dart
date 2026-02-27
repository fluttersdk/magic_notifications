import 'dart:io';
import 'package:magic_notifications/src/cli/cli.dart';

/// Project type detection
enum ProjectType {
  flutter,
  dart,
  unknown,
}

/// Installation command for Magic Notifications
class InstallCommand extends Command {
  @override
  final String name = 'install';

  @override
  final String description = 'Install and configure Magic Notifications';

  final String projectRoot;

  InstallCommand({required this.projectRoot});

  @override
  void configure(ArgParser parser) {
    parser
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
  }

  /// Detect the project type by inspecting pubspec.yaml
  ProjectType detectProjectType() {
    final pubspecPath = '$projectRoot/pubspec.yaml';

    if (!FileHelper.fileExists(pubspecPath)) {
      return ProjectType.unknown;
    }

    try {
      final yaml = FileHelper.readYamlFile(pubspecPath);
      final dependencies = yaml['dependencies'];

      if (dependencies is Map && dependencies.containsKey('flutter')) {
        return ProjectType.flutter;
      }

      return ProjectType.dart;
    } catch (e) {
      return ProjectType.unknown;
    }
  }

  /// Validate OneSignal App ID format (UUID-like format)
  bool validateOneSignalAppId(String appId) {
    // UUID format: 8-4-4-4-12 characters
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(appId);
  }

  @override
  Future<void> handle() async {
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // Check project type
    final projectType = detectProjectType();
    if (projectType == ProjectType.unknown) {
      error('Could not detect project type');
      exit(1);
    }

    info('Detected ${projectType.name} project\n');

    // Non-interactive mode
    if (hasOption('non-interactive') && arguments['non-interactive'] as bool) {
      await _runNonInteractive();
      return;
    }

    // Interactive mode
    await _runInteractive();
  }

  /// Run installation in non-interactive mode (for CI/CD)
  Future<void> _runNonInteractive() async {
    final appId = option('app-id') as String?;
    if (appId == null || appId.isEmpty) {
      error('--app-id is required in non-interactive mode');
      exit(1);
    }

    if (!validateOneSignalAppId(appId)) {
      error('Invalid OneSignal App ID format');
      exit(1);
    }

    final platformsStr = option('platforms') as String? ?? 'android,ios,web';
    final platforms = platformsStr.split(',').map((p) => p.trim()).toList();
    final enableSoftPrompt = arguments['soft-prompt'] as bool;
    final safariWebId = option('safari-web-id') as String?;
    final notifyButtonEnabled = arguments['notify-button'] as bool;

    info(ConsoleStyle.step(1, 3, 'Creating configuration files...'));
    await _executeInstallation(
      oneSignalAppId: appId,
      platforms: platforms,
      enableSoftPrompt: enableSoftPrompt,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
    );

    _showSuccessMessage();
  }

  /// Run installation in interactive mode
  Future<void> _runInteractive() async {
    info('Starting interactive installation wizard...\n');

    // Step 1: Get OneSignal App ID
    info(ConsoleStyle.step(1, 4, 'OneSignal Configuration'));
    comment('Get your App ID from https://onesignal.com/\n');

    String? appId;
    while (appId == null || appId.isEmpty) {
      final input = ask('Enter your OneSignal App ID');

      if (input == null || input.isEmpty) {
        error('App ID is required');
        continue;
      }

      if (!validateOneSignalAppId(input)) {
        error('Invalid App ID format (expected UUID format)');
        comment('Example: 12345678-1234-1234-1234-123456789012');
        continue;
      }

      appId = input;
    }
    success('App ID configured\n');

    // Step 2: Select platforms
    info(ConsoleStyle.step(2, 4, 'Platform Selection'));
    final availablePlatforms = PlatformHelper.detectPlatforms(projectRoot);

    if (availablePlatforms.isEmpty) {
      warn('No platform directories found');
      info('Defaulting to: android, ios, web');
      availablePlatforms.addAll(['android', 'ios', 'web']);
    } else {
      info('Detected platforms: ${availablePlatforms.join(', ')}');
    }

    final selectedPlatforms = <String>[];
    for (final platform in availablePlatforms) {
      if (confirm('Enable $platform?', defaultValue: true)) {
        selectedPlatforms.add(platform);
        success('  $platform enabled');
      } else {
        comment('  $platform skipped');
      }
    }

    if (selectedPlatforms.isEmpty) {
      warn('No platforms selected, using all detected');
      selectedPlatforms.addAll(availablePlatforms);
    }
    newLine();

    // Step 3: Web-specific configuration
    String? safariWebId;
    bool notifyButtonEnabled = false;

    if (selectedPlatforms.contains('web')) {
      info(ConsoleStyle.step(3, 5, 'Web Configuration'));
      comment('Safari Web ID is required for Safari push notifications');

      final safariInput = ask('Enter Safari Web ID (or press Enter to skip)');
      if (safariInput != null && safariInput.isNotEmpty) {
        safariWebId = safariInput;
        success('Safari Web ID configured');
      } else {
        comment('Safari Web ID skipped');
      }

      notifyButtonEnabled =
          confirm('Enable OneSignal notify button?', defaultValue: false);

      if (notifyButtonEnabled) {
        success('Notify button enabled');
      } else {
        comment('Notify button disabled');
      }
      newLine();
    }

    // Step 4: Soft prompt configuration
    info(ConsoleStyle.step(
        selectedPlatforms.contains('web') ? 4 : 3,
        selectedPlatforms.contains('web') ? 5 : 4,
        'Soft Prompt Configuration'));
    comment('Soft prompt asks users before requesting push permissions');

    final enableSoftPrompt = confirm('Enable soft prompt?', defaultValue: true);

    if (enableSoftPrompt) {
      success('Soft prompt enabled');
    } else {
      comment('Soft prompt disabled');
    }
    newLine();

    // Step 5: Execute installation
    info(ConsoleStyle.step(selectedPlatforms.contains('web') ? 5 : 4,
        selectedPlatforms.contains('web') ? 5 : 4, 'Installing...'));

    await _executeInstallation(
      oneSignalAppId: appId,
      platforms: selectedPlatforms,
      enableSoftPrompt: enableSoftPrompt,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
    );

    _showSuccessMessage();
  }

  /// Execute installation core logic
  Future<void> _executeInstallation({
    required String oneSignalAppId,
    required List<String> platforms,
    required bool enableSoftPrompt,
    String? safariWebId,
    bool notifyButtonEnabled = false,
  }) async {
    // 1. Create notification config file
    final configPath = '$projectRoot/lib/config/notifications.dart';
    NotificationConfigHelper.createNotificationConfig(
      configPath: configPath,
      oneSignalAppId: oneSignalAppId,
      softPromptEnabled: enableSoftPrompt,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
    );

    // 2. Update pubspec.yaml with dependency (path-based for local plugin)
    final pubspecPath = '$projectRoot/pubspec.yaml';
    try {
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'fluttersdk_magic_notifications',
        path: './plugins/fluttersdk_magic_notifications',
      );
    } catch (e) {
      // Dependency might already exist
    }

    // 3. Generate platform-specific files
    for (final platform in platforms) {
      switch (platform) {
        case 'android':
          await _setupAndroid(oneSignalAppId);
          break;
        case 'ios':
          await _setupIOS(oneSignalAppId);
          break;
        case 'web':
          await _setupWeb(
            oneSignalAppId,
            safariWebId: safariWebId,
            notifyButtonEnabled: notifyButtonEnabled,
          );
          break;
      }
    }

    // 4. Update main.dart (optional - can be done manually)
    final mainPath = '$projectRoot/lib/main.dart';
    if (FileHelper.fileExists(mainPath)) {
      try {
        NotificationConfigHelper.updateMainDart(
          mainPath: mainPath,
          addImports: ["import 'config/notifications.dart';"],
          configFactoryEntry: '() => notificationConfig',
        );
      } catch (e) {
        // main.dart might already be configured
      }
    }
  }

  /// Setup Android platform
  Future<void> _setupAndroid(String appId) async {
    if (!PlatformHelper.hasPlatform(projectRoot, 'android')) {
      return;
    }

    final manifestPath = PlatformHelper.androidManifestPath(projectRoot);

    if (!FileHelper.fileExists(manifestPath)) {
      return;
    }

    XmlEditor.addAndroidPermission(
      manifestPath,
      'android.permission.POST_NOTIFICATIONS',
    );
  }

  /// Setup iOS platform
  Future<void> _setupIOS(String appId) async {
    final infoPlistPath = PlatformHelper.infoPlistPath(projectRoot);

    if (!FileHelper.fileExists(infoPlistPath)) {
      return;
    }

    // iOS setup typically requires manual steps
    // We can add comments or instructions here
  }

  /// Setup Web platform
  ///
  /// Only loads the SDK script - init is handled by Dart config via service provider.
  Future<void> _setupWeb(
    String appId, {
    String? safariWebId,
    bool notifyButtonEnabled = false,
  }) async {
    if (!PlatformHelper.hasPlatform(projectRoot, 'web')) {
      return;
    }

    final webDir = '$projectRoot/web';

    // Create OneSignal service worker
    // IMPORTANT: Use OneSignalSDK.sw.js (Service Worker version), NOT .page.js
    // The .page.js is for the main HTML page, .sw.js is for the Service Worker
    final workerPath = '$webDir/OneSignalSDKWorker.js';
    final workerContent =
        'importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");\n';
    File(workerPath).writeAsStringSync(workerContent);

    // Update index.html if needed
    final indexPath = PlatformHelper.webIndexPath(projectRoot);
    if (FileHelper.fileExists(indexPath)) {
      if (!HtmlEditor.hasContent(indexPath, 'onesignalsdk')) {
        // Add OneSignal SDK script to head (init handled by Dart config)
        const scriptTag = '''
  <!-- OneSignal Web SDK - Init handled by Dart config -->
  <script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
  <script>
    window.OneSignalDeferred = window.OneSignalDeferred || [];
  </script>''';
        HtmlEditor.injectBeforeClose(indexPath, '</head>', scriptTag);
      }
    }
  }

  /// Show success message after installation
  void _showSuccessMessage() {
    newLine();
    success('Installation complete!\n');
    info('Next steps:');
    info('  1. Run: ${ConsoleStyle.cyan}flutter pub get${ConsoleStyle.reset}');
    info('  2. Configure your OneSignal dashboard');
    info(
        '  3. Test: ${ConsoleStyle.cyan}dart run fluttersdk_magic_notifications:test --dry-run${ConsoleStyle.reset}');
    info(
        '  4. Check status: ${ConsoleStyle.cyan}dart run fluttersdk_magic_notifications:status${ConsoleStyle.reset}');
  }
}
