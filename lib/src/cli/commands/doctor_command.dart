// cli.dart re-exports fluttersdk_artisan/artisan.dart (hiding only the builtin
// DoctorCommand that collides with this class), so a direct artisan.dart import
// is redundant here.
import 'package:magic_notifications/src/cli/cli.dart';

/// Diagnostic command for checking Magic Notifications health.
///
/// Performs a comprehensive health check across plugin installation, config
/// validity, and platform-specific setup. Replaces the [StatusCommand] with
/// richer validation including UUID format and polling_interval range checks.
///
/// Exits with code 0 when all checks pass, code 1 when any check fails.
///
/// A third answer sits between those two: a WARNING, for a setting that is
/// configured correctly and not provisioned yet (see [getWarnings]). It does
/// not fail the command, because working before provisioning is a normal state
/// and a doctor that always fails gets ignored, but it never prints a tick and
/// it keeps the summary from claiming every requirement is met.
///
/// ## Usage
/// ```bash
/// dart run <app>:artisan notifications:doctor
/// dart run <app>:artisan notifications:doctor --verbose
/// ```
class DoctorCommand extends ArtisanCommand {
  /// Background mode iOS requires before APNs will wake the app.
  static const String _remoteNotificationMode = 'remote-notification';

  /// Entitlement naming the APNs environment the app registers against.
  static const String _apsEnvironmentKey = 'aps-environment';

  /// Build setting through which Xcode learns the entitlements file exists.
  static const String _entitlementsSetting = 'CODE_SIGN_ENTITLEMENTS';

  /// The env file a project keeps its per-deployment values in.
  ///
  /// The doctor runs from a shell that is not the app's runtime, so it can
  /// never read the environment a build will see. This file it CAN read, and
  /// it is the one a Flutter app bundles as an asset, which is the whole
  /// reason "configured but not provisioned" is a checkable state at all.
  static const String envFileName = '.env';

  /// Matches an `app_id` whose value is a quoted string LITERAL.
  static final RegExp _literalAppId = RegExp(r"'app_id':\s*'([^']*)'");

  /// Matches an `app_id` READ FROM THE ENVIRONMENT, capturing the env key.
  ///
  /// A value that differs between deployments cannot be a literal, so an app
  /// resolves it at runtime instead; this scan happens at file level and can
  /// only ever see the call. Three shapes are recognised: magic's `env('KEY')`
  /// and `env<String>('KEY')`, plus the `envString('KEY', fallback)` wrapper an
  /// app writes when a present-but-blank key has to fall back. The key capture
  /// demands at least one character, so `envString('', '')` names no key and
  /// still reads as an absent App ID rather than a configured one.
  static final RegExp _envResolvedAppId = RegExp(
    r"'app_id':\s*(?:envString|env)\s*(?:<[^>]*>)?\s*\(\s*'([^']+)'",
  );

  @override
  String get signature =>
      'notifications:doctor {--verbose : Show detailed diagnostic information}';

  @override
  String get description =>
      'Check Magic Notifications installation and configuration health';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Absolute path to the Flutter project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolve the Flutter project root — may be overridden in tests.
  String getProjectRoot() => FileHelper.findProjectRoot();

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(
        ConsoleStyle.banner('Magic Notifications', magicNotificationsVersion));

    // 1. Collect missing requirements before printing — we need both for output.
    final verbose = ctx.input.option('verbose') as bool;
    final missing = getMissingRequirements();
    final warnings = getWarnings();

    // 2. Print human-readable report.
    ctx.output.writeln(generateReport(verbose: verbose));

    // 3. Exit with appropriate code.
    if (missing.isEmpty && warnings.isEmpty) {
      ctx.output.success('All checks passed!');
      ctx.output.writeln('');
      return 0;
    }

    // A warning alone exits 0: a developer working before provisioning is a
    // normal state, and a doctor that fails on it stops being read. What it
    // must not do is claim everything passed.
    if (missing.isEmpty) {
      ctx.output.warning(
        'Nothing failed, but push cannot send yet: see the warnings above.',
      );
      ctx.output.writeln('');
      return 0;
    } else {
      ctx.output.writeln('');
      ctx.output.warning('Issues detected. Run the following to fix:');
      ctx.output
          .writeln('  • Install: dart run <app>:artisan notifications:install');
      ctx.output.writeln(
          '  • Configure: dart run <app>:artisan notifications:configure');
      return 1;
    }
  }

  // ---------------------------------------------------------------------------
  // Checks
  // ---------------------------------------------------------------------------

  /// Check if the plugin is listed under `dependencies` in pubspec.yaml.
  ///
  /// Looks specifically for `magic_notifications` — NOT the legacy package name.
  bool checkPluginInstalled() {
    final pubspecPath = '$projectRoot/pubspec.yaml';

    if (!FileHelper.fileExists(pubspecPath)) {
      return false;
    }

    try {
      final yaml = FileHelper.readYamlFile(pubspecPath);
      final dependencies = yaml['dependencies'];

      if (dependencies is Map) {
        return dependencies.containsKey('magic_notifications');
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check if `lib/config/notifications.dart` exists in the project root.
  bool checkConfigExists() {
    final configPath = '$projectRoot/lib/config/notifications.dart';
    return FileHelper.fileExists(configPath);
  }

  /// Validate that the `app_id` is a proper UUID and that `polling_interval`
  /// falls within the accepted range of 5–600 seconds.
  ///
  /// Returns a list of human-readable issue strings; empty means valid.
  List<String> validateConfig() {
    final configPath = '$projectRoot/lib/config/notifications.dart';

    if (!FileHelper.fileExists(configPath)) {
      return ['Config file not found at lib/config/notifications.dart'];
    }

    final content = FileHelper.readFile(configPath);
    final issues = <String>[];

    // 1. Validate app_id presence and UUID format. A literal is validated here
    //    and now; an env-resolved one has no value at file-scan time, so its
    //    presence IS the check and the report names the key instead. Only a
    //    config carrying neither is missing an App ID.
    final appIdMatch = _literalAppId.firstMatch(content);
    if (appIdMatch == null) {
      if (!_envResolvedAppId.hasMatch(content)) {
        issues.add('App ID not found in config');
      }
    } else {
      final appId = appIdMatch.group(1)!;
      if (appId.isEmpty || appId == 'YOUR_APP_ID') {
        issues.add('App ID is placeholder/empty — set a real OneSignal App ID');
      } else if (!validateAppIdFormat(appId)) {
        issues.add(
          'App ID "$appId" is not valid UUID format '
          '(expected: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)',
        );
      }
    }

    // 2. Validate polling_interval range (5–600 seconds).
    final pollingMatch = RegExp(
      r"'polling_interval':\s*(\d+)",
    ).firstMatch(content);
    if (pollingMatch != null) {
      final interval = int.tryParse(pollingMatch.group(1)!);
      if (interval != null && (interval < 5 || interval > 600)) {
        issues.add(
          'polling_interval ($interval) is out of valid range (5–600 seconds)',
        );
      }
    }

    // 3. Ensure soft_prompt section is present.
    if (!content.contains("'soft_prompt'")) {
      issues.add(
        'soft_prompt section missing from config — '
        'add a soft_prompt block to notifications.dart',
      );
    }

    return issues;
  }

  /// The environment key an env-resolved `app_id` reads at runtime, or `null`
  /// when the config declares a literal (or no `app_id` at all).
  ///
  /// Reported rather than validated: the doctor reads files, so it can name the
  /// key the value comes from but never the value itself. A literal wins when
  /// both shapes somehow appear, because the literal is the one this command
  /// can actually check.
  String? envResolvedAppIdKey() {
    final configPath = '$projectRoot/lib/config/notifications.dart';

    if (!FileHelper.fileExists(configPath)) {
      return null;
    }

    final content = FileHelper.readFile(configPath);
    if (_literalAppId.hasMatch(content)) {
      return null;
    }

    return _envResolvedAppId.firstMatch(content)?.group(1);
  }

  /// Whether the project has an env file at all.
  bool hasEnvFile() => FileHelper.fileExists('$projectRoot/$envFileName');

  /// The value [key] carries in the project's env file, or `null` when the file
  /// is absent, the key is missing from it, or the key carries nothing.
  ///
  /// A blank value reads as absent deliberately: `ONESIGNAL_APP_ID=` is a key
  /// nobody provisioned, and it initialises the SDK with an empty App ID just
  /// as surely as a missing line does.
  String? envFileValue(String key) {
    final envPath = '$projectRoot/$envFileName';

    if (!FileHelper.fileExists(envPath)) {
      return null;
    }

    for (final rawLine in FileHelper.readFile(envPath).split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      final separator = line.indexOf('=');
      if (separator == -1) continue;

      final name = line
          .substring(0, separator)
          .trim()
          .replaceFirst(RegExp(r'^export\s+'), '');
      if (name != key) continue;

      final value = _unquoted(line.substring(separator + 1).trim());

      return value.isEmpty ? null : value;
    }

    return null;
  }

  /// [value] with one layer of matching surrounding quotes removed.
  String _unquoted(String value) {
    if (value.length < 2) return value;

    final quote = value[0];
    if (quote != "'" && quote != '"') return value;
    if (!value.endsWith(quote)) return value;

    return value.substring(1, value.length - 1);
  }

  /// Everything that is configured correctly and still cannot work yet.
  ///
  /// Separate from [getMissingRequirements] because the two earn different
  /// answers: a requirement is missing and the command fails, a warning is a
  /// value nobody has provisioned yet and the command still exits 0. What a
  /// warning must never do is print as a tick, which is how an env-resolved App
  /// ID with a blank `.env` entry once certified a build that could not send a
  /// single push.
  List<String> getWarnings() {
    final warnings = <String>[];

    if (!checkConfigExists()) {
      return warnings;
    }

    // A literal App ID is validated by [validateConfig] and has no env half.
    final envKey = envResolvedAppIdKey();
    if (envKey == null) {
      return warnings;
    }

    if (envFileValue(envKey) != null) {
      return warnings;
    }

    warnings.add(
      hasEnvFile()
          ? 'App ID is read from the $envKey environment variable, and '
              '$envFileName carries no value for it, so push initialises with '
              'an empty App ID'
          : 'App ID is read from the $envKey environment variable, and there '
              'is no $envFileName at the project root to confirm it is '
              'provisioned',
    );

    return warnings;
  }

  /// Validate that [appId] matches the OneSignal UUID format (8-4-4-4-12 hex).
  ///
  /// Reuses the same regex as [InstallCommand.validateOneSignalAppId].
  bool validateAppIdFormat(String appId) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(appId);
  }

  /// Check platform-specific setup for all detected platforms.
  ///
  /// Uses [PlatformHelper.detectPlatforms] to find which platforms exist, then
  /// inspects each platform's configuration files for required entries.
  Map<String, dynamic> checkPlatformSetup() {
    final platforms = PlatformHelper.detectPlatforms(projectRoot);
    final result = <String, dynamic>{};

    if (platforms.contains('android')) {
      result['android'] = _checkAndroidSetup();
    }

    if (platforms.contains('ios')) {
      result['ios'] = _checkIOSSetup();
    }

    if (platforms.contains('web')) {
      result['web'] = _checkWebSetup();
    }

    return result;
  }

  // ---------------------------------------------------------------------------
  // Platform checks (private)
  // ---------------------------------------------------------------------------

  /// Inspect AndroidManifest.xml for the POST_NOTIFICATIONS permission.
  Map<String, dynamic> _checkAndroidSetup() {
    final manifestPath = PlatformHelper.androidManifestPath(projectRoot);

    if (!FileHelper.fileExists(manifestPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['AndroidManifest.xml not found'],
      };
    }

    final manifest = FileHelper.readFile(manifestPath);
    final hasPermission = manifest.contains('POST_NOTIFICATIONS');

    return {
      'configured': hasPermission,
      'exists': true,
      'issues': hasPermission
          ? <String>[]
          : ['Missing POST_NOTIFICATIONS permission in AndroidManifest.xml'],
    };
  }

  /// Inspect the three markers an iOS project needs before a push arrives.
  ///
  /// Existence of `Info.plist` proves nothing: every Flutter iOS project ever
  /// generated has one, so a check built on it can only ever pass. These three
  /// can each fail on their own, and each one alone is enough to stop a
  /// notification:
  ///
  /// 1. `UIBackgroundModes` listing `remote-notification`, without which iOS
  ///    never wakes the app for a data payload.
  /// 2. `aps-environment` in `Runner.entitlements`, without which the app has
  ///    no APNs environment to register against.
  /// 3. `CODE_SIGN_ENTITLEMENTS` in `project.pbxproj`, without which Xcode
  ///    never reads that entitlements file at all and the second check passes
  ///    while signing ignores it.
  Map<String, dynamic> _checkIOSSetup() {
    final infoPlistPath = PlatformHelper.infoPlistPath(projectRoot);

    if (!FileHelper.fileExists(infoPlistPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['Info.plist not found'],
      };
    }

    final issues = <String>[];

    if (!_declaresBackgroundMode(infoPlistPath, _remoteNotificationMode)) {
      issues.add(
        'UIBackgroundModes in ios/Runner/Info.plist does not list '
        '$_remoteNotificationMode',
      );
    }

    if (!_fileDeclares(_entitlementsPath, '<key>$_apsEnvironmentKey</key>')) {
      issues.add(
        '$_apsEnvironmentKey is missing from ios/Runner/Runner.entitlements',
      );
    }

    if (!_fileDeclares(_pbxprojPath, _entitlementsSetting)) {
      issues.add(
        '$_entitlementsSetting is not set in '
        'ios/Runner.xcodeproj/project.pbxproj, so Xcode never reads the '
        'entitlements file',
      );
    }

    return {
      'configured': issues.isEmpty,
      'exists': true,
      'issues': issues,
    };
  }

  /// Path to the iOS entitlements file the installer writes.
  String get _entitlementsPath => '$projectRoot/ios/Runner/Runner.entitlements';

  /// Path to the Xcode project file that has to name that entitlements file.
  String get _pbxprojPath =>
      '$projectRoot/ios/Runner.xcodeproj/project.pbxproj';

  /// Whether [path] exists and mentions [marker] outside of a comment.
  bool _fileDeclares(String path, String marker) {
    if (!FileHelper.fileExists(path)) {
      return false;
    }
    return _withoutComments(FileHelper.readFile(path)).contains(marker);
  }

  /// Whether the `UIBackgroundModes` array in [infoPlistPath] lists [mode].
  ///
  /// Scoped to that array rather than the whole file: `remote-notification`
  /// appearing anywhere else in a plist (a string value, a bundle name) is not
  /// the declaration iOS reads.
  bool _declaresBackgroundMode(String infoPlistPath, String mode) {
    final array = RegExp(
      r'<key>\s*UIBackgroundModes\s*</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(_withoutComments(FileHelper.readFile(infoPlistPath)));

    return array != null && array.group(1)!.contains('<string>$mode</string>');
  }

  /// Strip XML and OpenStep comments before a marker is looked for.
  ///
  /// Without this a commented-out reminder counts as configuration: the
  /// Flutter iOS template ships `<!-- ... -->` blocks, a `.pbxproj` is dense
  /// with `/* Debug */` annotations, and a developer who commented a key out
  /// while debugging would still read as green.
  String _withoutComments(String source) => source
      .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

  /// Check for the OneSignal service worker file in the web directory.
  Map<String, dynamic> _checkWebSetup() {
    final workerPath = '$projectRoot/web/OneSignalSDKWorker.js';

    if (!FileHelper.fileExists(workerPath)) {
      return {
        'configured': false,
        'exists': false,
        'issues': ['OneSignalSDKWorker.js not found in web/'],
      };
    }

    return {'configured': true, 'exists': true, 'issues': <String>[]};
  }

  // ---------------------------------------------------------------------------
  // Report
  // ---------------------------------------------------------------------------

  /// Return every unmet requirement across plugin, config, validation, and
  /// platform checks.
  List<String> getMissingRequirements() {
    final missing = <String>[];

    // 1. Plugin installation.
    if (!checkPluginInstalled()) {
      missing.add('Magic notifications plugin not installed in pubspec.yaml');
    }

    // 2. Config file existence.
    if (!checkConfigExists()) {
      missing.add(
        'Configuration file not found (lib/config/notifications.dart)',
      );
    }

    // 3. Config content validation (only when the file exists).
    if (checkConfigExists()) {
      missing.addAll(validateConfig());
    }

    // 4. Platform setup.
    final platformStatus = checkPlatformSetup();
    for (final entry in platformStatus.entries) {
      final platform = entry.key;
      final status = entry.value as Map<String, dynamic>;
      final issues = status['issues'] as List;

      for (final issue in issues) {
        missing.add('[$platform] $issue');
      }
    }

    return missing;
  }

  /// Generate a human-readable diagnostic report.
  ///
  /// When [verbose] is `true`, additional detail lines are shown for each
  /// check (paths, required keys, etc.).
  String generateReport({bool verbose = false}) {
    final buffer = StringBuffer();
    buffer.writeln('Magic Notifications — Doctor Report');
    buffer.writeln('=' * 50);
    buffer.writeln();

    // 1. Plugin installation.
    final pluginInstalled = checkPluginInstalled();
    buffer.writeln('Plugin Installed: ${pluginInstalled ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Location: pubspec.yaml → dependencies');
      buffer.writeln('    Package: magic_notifications');
    }

    // 2. Config file.
    final configExists = checkConfigExists();
    buffer.writeln('Configuration File: ${configExists ? '✓' : '✗'}');
    if (verbose) {
      buffer.writeln('    Path: lib/config/notifications.dart');
    }
    buffer.writeln();

    // 3. Config validation (only when config exists).
    buffer.writeln('Config Validation:');
    if (!configExists) {
      buffer.writeln('  ✗ Skipped — config file missing');
    } else {
      // An env-resolved App ID is configured, but only the runtime environment
      // knows its value. The tick is earned by the env FILE carrying one; when
      // it does not, [getWarnings] says so below and no tick is printed.
      final envKey = envResolvedAppIdKey();
      if (envKey != null && envFileValue(envKey) != null) {
        buffer.writeln(
          '  ✓ App ID is resolved at runtime from the $envKey '
          'environment variable, which $envFileName carries a value for',
        );
      }

      final configIssues = validateConfig();
      final configWarnings = getWarnings();

      if (configIssues.isEmpty && configWarnings.isEmpty) {
        buffer.writeln('  ✓ All config checks passed');
      } else {
        for (final issue in configIssues) {
          buffer.writeln('  ✗ $issue');
        }
        for (final warning in configWarnings) {
          buffer.writeln('  ⚠ $warning');
        }
      }
    }
    buffer.writeln();

    // 4. Platform setup.
    buffer.writeln('Platform Setup:');
    final platformStatus = checkPlatformSetup();

    if (platformStatus.isEmpty) {
      buffer.writeln('  No platforms detected');
    } else {
      for (final entry in platformStatus.entries) {
        final platform = entry.key;
        final status = entry.value as Map<String, dynamic>;
        final configured = status['configured'] as bool;
        final exists = status['exists'] as bool;
        final issues = status['issues'] as List;

        buffer.write('  ${platform.toUpperCase()}: ');
        if (configured) {
          buffer.writeln('✓ Configured');
        } else if (exists) {
          buffer.writeln('⚠ Needs configuration');
        } else {
          buffer.writeln('✗ Not found');
        }

        if (verbose) {
          switch (platform) {
            case 'android':
              buffer.writeln(
                '      Manifest: android/app/src/main/AndroidManifest.xml',
              );
              buffer.writeln('      Required: POST_NOTIFICATIONS permission');
            case 'ios':
              buffer.writeln('      Info.plist: ios/Runner/Info.plist');
              buffer.writeln('      Entitlements: '
                  'ios/Runner/Runner.entitlements');
              buffer.writeln('      Project: '
                  'ios/Runner.xcodeproj/project.pbxproj');
              buffer.writeln(
                '      Required: UIBackgroundModes/$_remoteNotificationMode, '
                '$_apsEnvironmentKey, $_entitlementsSetting',
              );
            case 'web':
              buffer.writeln('      Service Worker: web/OneSignalSDKWorker.js');
              buffer.writeln('      Required: OneSignal SDK in index.html');
          }
          for (final issue in issues) {
            buffer.writeln('      Issue: $issue');
          }
        }
      }
    }

    buffer.writeln();

    // 5. Summary. A warning is not a failure, but it is also not a met
    //    requirement, so it withholds the claim rather than the exit code.
    final missing = getMissingRequirements();
    final warnings = getWarnings();

    if (missing.isEmpty && warnings.isEmpty) {
      buffer.writeln('✓ All requirements met!');
    }

    if (missing.isNotEmpty) {
      buffer.writeln('Missing Requirements:');
      for (final issue in missing) {
        buffer.writeln('  ✗ $issue');
      }
    }

    if (warnings.isNotEmpty) {
      buffer.writeln('Warnings:');
      for (final warning in warnings) {
        buffer.writeln('  ⚠ $warning');
      }
    }

    return buffer.toString();
  }
}
