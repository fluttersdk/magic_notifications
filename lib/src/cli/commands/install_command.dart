import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

/// Project type detection
enum ProjectType { flutter, dart, unknown }

/// Installation command for Magic Notifications
class InstallCommand extends ArtisanCommand {
  @override
  String get signature => 'notifications:install '
      '{--non-interactive : Run in non-interactive mode (for CI/CD)} '
      '{--app-id= : OneSignal App ID} '
      '{--platforms= : Comma-separated list of platforms (android,ios,web)} '
      '{--no-soft-prompt : Disable soft prompt (enabled by default)} '
      '{--safari-web-id= : Safari Web ID for web push (optional)} '
      '{--notify-button : Enable OneSignal notify button on web (default: disabled)} '
      '{--force : Overwrite existing configuration file.}';

  @override
  String get description => 'Install and configure Magic Notifications';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Absolute path to the Flutter project root, resolved on first access.
  String get projectRoot => getProjectRoot();

  /// Resolve the Flutter project root — may be overridden in tests.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Returns the paths to search for stubs.
  ///
  /// Overridable in tests.
  List<String> getStubSearchPaths() {
    return [_resolvePluginStubsDir(), '${Directory.current.path}/assets/stubs'];
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
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    // Check project type
    final projectType = detectProjectType();
    if (projectType == ProjectType.unknown) {
      ctx.output.error('Could not detect project type');
      return 1;
    }

    ctx.output.info('Detected ${projectType.name} project\n');

    // Non-interactive mode
    if (ctx.input.hasOption('non-interactive') &&
        ctx.input.option('non-interactive') as bool) {
      return _runNonInteractive(ctx);
    }

    // Interactive mode
    return _runInteractive(ctx);
  }

  /// Run installation in non-interactive mode (for CI/CD)
  Future<int> _runNonInteractive(ArtisanContext ctx) async {
    final appId = ctx.input.option('app-id') as String?;
    if (appId == null || appId.isEmpty) {
      ctx.output.error('--app-id is required in non-interactive mode');
      return 1;
    }

    if (!validateOneSignalAppId(appId)) {
      ctx.output.error('Invalid OneSignal App ID format');
      return 1;
    }

    final platformsStr =
        ctx.input.option('platforms') as String? ?? 'android,ios,web';
    final platforms = platformsStr.split(',').map((p) => p.trim()).toList();
    final enableSoftPrompt = !(ctx.input.option('no-soft-prompt') as bool);
    final safariWebId = ctx.input.option('safari-web-id') as String?;
    final notifyButtonEnabled = ctx.input.option('notify-button') as bool;

    ctx.output.info(ConsoleStyle.step(1, 3, 'Creating configuration files...'));
    await _executeInstallation(
      ctx,
      oneSignalAppId: appId,
      platforms: platforms,
      enableSoftPrompt: enableSoftPrompt,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
    );

    _showSuccessMessage(ctx);
    return 0;
  }

  /// Run installation in interactive mode
  Future<int> _runInteractive(ArtisanContext ctx) async {
    ctx.output.info('Starting interactive installation wizard...\n');

    // Step 1: Get OneSignal App ID
    ctx.output.info(ConsoleStyle.step(1, 4, 'OneSignal Configuration'));
    ctx.output.comment('Get your App ID from https://onesignal.com/\n');

    String? appId;
    while (appId == null || appId.isEmpty) {
      final input = Prompt.ask('Enter your OneSignal App ID');

      if (input.isEmpty) {
        ctx.output.error('App ID is required');
        continue;
      }

      if (!validateOneSignalAppId(input)) {
        ctx.output.error('Invalid App ID format (expected UUID format)');
        ctx.output.comment('Example: 12345678-1234-1234-1234-123456789012');
        continue;
      }

      appId = input;
    }
    ctx.output.success('App ID configured\n');

    // Step 2: Select platforms
    ctx.output.info(ConsoleStyle.step(2, 4, 'Platform Selection'));
    final availablePlatforms = PlatformHelper.detectPlatforms(projectRoot);

    if (availablePlatforms.isEmpty) {
      ctx.output.warning('No platform directories found');
      ctx.output.info('Defaulting to: android, ios, web');
      availablePlatforms.addAll(['android', 'ios', 'web']);
    } else {
      ctx.output.info('Detected platforms: ${availablePlatforms.join(', ')}');
    }

    final selectedPlatforms = <String>[];
    for (final platform in availablePlatforms) {
      if (Prompt.confirm('Enable $platform?', defaultValue: true)) {
        selectedPlatforms.add(platform);
        ctx.output.success('  $platform enabled');
      } else {
        ctx.output.comment('  $platform skipped');
      }
    }

    if (selectedPlatforms.isEmpty) {
      ctx.output.warning('No platforms selected, using all detected');
      selectedPlatforms.addAll(availablePlatforms);
    }
    ctx.output.writeln('');

    // Step 3: Web-specific configuration
    String? safariWebId;
    bool notifyButtonEnabled = false;

    if (selectedPlatforms.contains('web')) {
      ctx.output.info(ConsoleStyle.step(3, 5, 'Web Configuration'));
      ctx.output.comment(
        'Safari Web ID is required for Safari push notifications',
      );

      final safariInput = Prompt.ask(
        'Enter Safari Web ID (or press Enter to skip)',
      );
      if (safariInput.isNotEmpty) {
        safariWebId = safariInput;
        ctx.output.success('Safari Web ID configured');
      } else {
        ctx.output.comment('Safari Web ID skipped');
      }

      notifyButtonEnabled = Prompt.confirm(
        'Enable OneSignal notify button?',
        defaultValue: false,
      );

      if (notifyButtonEnabled) {
        ctx.output.success('Notify button enabled');
      } else {
        ctx.output.comment('Notify button disabled');
      }
      ctx.output.writeln('');
    }

    // Step 4: Soft prompt configuration
    ctx.output.info(
      ConsoleStyle.step(
        selectedPlatforms.contains('web') ? 4 : 3,
        selectedPlatforms.contains('web') ? 5 : 4,
        'Soft Prompt Configuration',
      ),
    );
    ctx.output.comment(
      'Soft prompt asks users before requesting push permissions',
    );

    final enableSoftPrompt = Prompt.confirm(
      'Enable soft prompt?',
      defaultValue: true,
    );

    if (enableSoftPrompt) {
      ctx.output.success('Soft prompt enabled');
    } else {
      ctx.output.comment('Soft prompt disabled');
    }
    ctx.output.writeln('');

    // Step 5: Execute installation
    ctx.output.info(
      ConsoleStyle.step(
        selectedPlatforms.contains('web') ? 5 : 4,
        selectedPlatforms.contains('web') ? 5 : 4,
        'Installing...',
      ),
    );

    await _executeInstallation(
      ctx,
      oneSignalAppId: appId,
      platforms: selectedPlatforms,
      enableSoftPrompt: enableSoftPrompt,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
    );

    _showSuccessMessage(ctx);
    return 0;
  }

  /// Execute installation core logic
  Future<void> _executeInstallation(
    ArtisanContext ctx, {
    required String oneSignalAppId,
    required List<String> platforms,
    required bool enableSoftPrompt,
    String? safariWebId,
    bool notifyButtonEnabled = false,
  }) async {
    final force = ctx.input.option('force') as bool? ?? false;

    // 1. Create notification config file
    final configPath = '$projectRoot/lib/config/notifications.dart';

    if (FileHelper.fileExists(configPath) && !force) {
      ctx.output.warning(
        'Configuration file already exists. Use --force to overwrite.',
      );
    } else {
      final stub = StubLoader.load(
        'install/notification_config',
        searchPaths: getStubSearchPaths(),
      );
      final content = StubLoader.replace(stub, {
        'oneSignalAppId': oneSignalAppId,
        'safariWebIdLine': safariWebId != null
            ? "\n      'safari_web_id': '$safariWebId',"
            : '',
        'notifyButtonEnabled': notifyButtonEnabled.toString(),
        'softPromptEnabled': enableSoftPrompt.toString(),
      });
      FileHelper.writeFile(configPath, content);
      ctx.output.success('Created lib/config/notifications.dart');
    }

    // 2. Update pubspec.yaml with dependency (path-based for local plugin)
    final pubspecPath = '$projectRoot/pubspec.yaml';
    try {
      ConfigEditor.addPathDependencyToPubspec(
        pubspecPath: pubspecPath,
        name: 'magic_notifications',
        path: './plugins/magic_notifications',
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

    // 4. Update app.dart
    final appPath = '$projectRoot/lib/config/app.dart';
    if (FileHelper.fileExists(appPath)) {
      _injectIntoApp(ctx, appPath);
    }

    // 5. Update main.dart
    final mainPath = '$projectRoot/lib/main.dart';
    if (FileHelper.fileExists(mainPath)) {
      _injectIntoMain(ctx, mainPath);
    }
  }

  /// Injects provider and imports into lib/config/app.dart
  void _injectIntoApp(ArtisanContext ctx, String appPath) {
    ConfigEditor.addImportToFile(
      filePath: appPath,
      importStatement:
          "import 'package:magic_notifications/magic_notifications.dart';",
    );
    final content = FileHelper.readFile(appPath);
    if (!content.contains('NotificationServiceProvider')) {
      ConfigEditor.insertCodeBeforePattern(
        filePath: appPath,
        pattern: RegExp(r'^\s+\],', multiLine: true),
        code: '      (app) => NotificationServiceProvider(app),\n',
      );
      ctx.output.success(
        'Injected NotificationServiceProvider into lib/config/app.dart',
      );
    }
  }

  /// Injects configFactory and imports into lib/main.dart
  void _injectIntoMain(ArtisanContext ctx, String mainPath) {
    if (!FileHelper.fileExists(mainPath)) return;
    ConfigEditor.addImportToFile(
      filePath: mainPath,
      importStatement: "import 'config/notifications.dart';",
    );
    final content = FileHelper.readFile(mainPath);
    if (!content.contains('notificationConfig')) {
      ConfigEditor.insertCodeBeforePattern(
        filePath: mainPath,
        pattern: RegExp(r'^\s+\],', multiLine: true),
        code: '      () => notificationConfig,\n',
      );
      ctx.output.success('Injected notificationConfig into lib/main.dart');
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
    final workerContent = StubLoader.load(
      'install/onesignal_worker',
      searchPaths: getStubSearchPaths(),
    );
    FileHelper.writeFile(workerPath, workerContent);

    // Update index.html if needed
    final indexPath = PlatformHelper.webIndexPath(projectRoot);
    if (FileHelper.fileExists(indexPath)) {
      if (!HtmlEditor.hasContent(indexPath, 'onesignalsdk')) {
        // Add OneSignal SDK script to head (init handled by Dart config)
        final scriptContent = StubLoader.load(
          'install/onesignal_script',
          searchPaths: getStubSearchPaths(),
        );
        HtmlEditor.injectBeforeClose(indexPath, '</head>', scriptContent);
      }
    }
  }

  /// Tries to resolve the package assets directory dynamically using package_config.json
  String _resolvePluginStubsDir() {
    final packageConfigPath =
        '${Directory.current.path}/.dart_tool/package_config.json';
    if (File(packageConfigPath).existsSync()) {
      final content = File(packageConfigPath).readAsStringSync();
      try {
        final map = jsonDecode(content) as Map<String, dynamic>;
        final packages = map['packages'] as List<dynamic>? ?? [];
        for (final package in packages) {
          if (package['name'] == 'magic_notifications') {
            final rootUri = package['rootUri'] as String;
            String parsedPath;
            if (rootUri.startsWith('file://')) {
              parsedPath = Uri.parse(rootUri).toFilePath();
            } else if (rootUri.startsWith('../')) {
              parsedPath = File(
                packageConfigPath,
              ).parent.uri.resolve(rootUri).toFilePath();
            } else {
              parsedPath = rootUri;
            }
            return '$parsedPath/assets/stubs'.replaceAll('//', '/');
          }
        }
      } catch (_) {
        // Fallback below
      }
    }
    return '${Directory.current.path}/assets/stubs';
  }

  /// Show success message after installation
  void _showSuccessMessage(ArtisanContext ctx) {
    ctx.output.writeln('');
    ctx.output.success('Installation complete!\n');
    ctx.output.info('Next steps:');
    ctx.output.info(
      '  1. Run: ${ConsoleStyle.cyan}flutter pub get${ConsoleStyle.reset}',
    );
    ctx.output.info('  2. Configure your OneSignal dashboard');
    ctx.output.info(
      '  3. Test: ${ConsoleStyle.cyan}artisan notifications:test --dry-run${ConsoleStyle.reset}',
    );
    ctx.output.info(
      '  4. Check status: ${ConsoleStyle.cyan}artisan notifications:doctor${ConsoleStyle.reset}',
    );
  }
}
