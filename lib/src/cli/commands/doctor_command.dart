// Directly, because FileHelper reads a path it is given and this command has to
// WALK one: an NSE's extension point lives in whichever Info.plist its target
// owns, and the target can be named anything.
import 'dart:convert';
import 'dart:io';

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

  /// The entitlement that shares a container between the app and its
  /// Notification Service Extension. See [iosExtensionWarnings].
  static const String _appGroupsKey = 'com.apple.security.application-groups';

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
      // The two kinds of warning mean opposite things about whether push
      // works at all, and saying "cannot send yet" over a missing Xcode
      // extension would send an adopter hunting a provisioning problem that
      // is not there.
      ctx.output.warning(
        configWarnings().isEmpty
            ? 'Nothing failed. Push sends, but some of it is not wired: see '
                'the warnings above.'
            : 'Nothing failed, but push cannot send yet: see the warnings '
                'above.',
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
  List<String> getWarnings() => <String>[
        ...configWarnings(),
        ...iosExtensionWarnings(),
        ...apsEnvironmentWarnings(),
      ];

  /// Warnings about the APNs environment each build configuration signs
  /// against. See [_apsEnvironmentIssues] for what is measured.
  ///
  /// A warning rather than a failure, and the choice is the class's own rule
  /// rather than a softening. `notifications:install` writes one entitlements
  /// file declaring `development` for every configuration, because the
  /// distribution value is a signing decision it cannot make, so EVERY
  /// freshly installed project reports this until somebody splits the file by
  /// hand. A doctor that fails on its own installer's correct output is the
  /// "always fails" state this class warns about at the top, and the
  /// remediation footer a failure prints names `notifications:install` and
  /// `notifications:configure`, neither of which can clear it.
  ///
  /// It is still never a tick, and it still stops the summary claiming every
  /// requirement is met, which is what the warning channel is for. When the
  /// installer learns to write the split, this becomes a failure honestly.
  List<String> apsEnvironmentWarnings() {
    if (!FileHelper.directoryExists('$projectRoot/ios')) return const [];

    return _apsEnvironmentIssues();
  }

  /// Warnings about the CONFIG specifically, which is the only kind the
  /// report's "Config Validation" section may print.
  ///
  /// Split from [getWarnings] when the iOS extension checks landed: rendering
  /// every warning under that heading filed an Xcode target's absence as a
  /// config finding, and printed it twice.
  List<String> configWarnings() {
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

  /// What OneSignal's iOS setup asks for that no Dart package can install.
  ///
  /// Push works without either of these, which is exactly why they need
  /// saying: a build with no Notification Service Extension delivers
  /// notifications normally and quietly reports no confirmed deliveries, no
  /// rich media and no badge counts, so the absence looks like the product
  /// working rather than an install left half done.
  ///
  /// The two halves fail independently and are checked separately. An
  /// extension with no shared App Group gives rich media and still no
  /// confirmed delivery, because the container is how the extension hands what
  /// it saw back to the app.
  ///
  /// Warnings rather than failures: an app that never wants rich notifications
  /// is a legitimate build, and a doctor that fails one stops being read.
  /// Neither can be automated from here, since a pub package cannot add an
  /// Xcode target; `doc/getting-started/installation.md` carries the manual
  /// steps.
  List<String> iosExtensionWarnings() {
    final warnings = <String>[];

    // Nothing to say about iOS on a project that does not ship it.
    if (!FileHelper.directoryExists('$projectRoot/ios')) return warnings;

    if (!_hasNotificationServiceExtension()) {
      warnings.add(
        'No Notification Service Extension target found in '
        'ios/Runner.xcodeproj/project.pbxproj. Push still arrives; confirmed '
        'delivery, rich media and badge counts do not. See '
        'doc/getting-started/installation.md for the Xcode steps.',
      );

      // The group check below would only repeat the same finding.
      return warnings;
    }

    if (!_fileDeclares(_entitlementsPath, _appGroupsKey)) {
      warnings.add(
        'A Notification Service Extension exists but $_appGroupsKey is missing '
        'from ios/Runner/Runner.entitlements. Without the shared App Group the '
        'extension cannot report back, so confirmed delivery and badge counts '
        'stay unavailable even though rich media works.',
      );
    }

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

  /// What each build configuration's entitlements file has to declare.
  ///
  /// Apple decides this, not us: a development provisioning profile carries
  /// `aps-environment: development` and a distribution one carries
  /// `production`, and signing against the other value is refused. So the value
  /// is a property of the CONFIGURATION rather than of the project, and the
  /// installer's single `development` file is correct for two of the three and
  /// wrong for the one that ships.
  static const Map<String, String> _apsEnvironmentByConfiguration = {
    'Debug': 'development',
    'Profile': 'development',
    'Release': 'production',
  };

  /// Whether each configuration signs against an APNs environment it can use.
  ///
  /// This is the check that would have caught a real defect and did not exist:
  /// the existing test above asks only whether `aps-environment` is PRESENT in
  /// `Runner.entitlements`, so a project whose Release build declares
  /// `development` prints a clean bill of health and then either fails at
  /// export or ships an app registering a sandbox token the production app can
  /// never deliver to. Neither symptom appears until TestFlight.
  ///
  /// Read per configuration rather than per file, because the fix is a split:
  /// Release points at its own entitlements twin while Debug and Profile keep
  /// the development one. A project that has not split yet is the ordinary
  /// case here, and it fails on Release with the value it actually carries,
  /// which is the message that tells somebody what to do.
  ///
  /// Silent when the pbxproj cannot be walked. A doctor that guesses at a
  /// project shape it does not recognise reports a fault that is not there,
  /// and the two checks above already cover the file being absent entirely.
  List<String> _apsEnvironmentIssues() {
    final Map<String, String> entitlements = _entitlementsByConfiguration();
    if (entitlements.isEmpty) return const [];

    final issues = <String>[];

    for (final MapEntry<String, String> entry in entitlements.entries) {
      final String? expected = _apsEnvironmentByConfiguration[entry.key];
      if (expected == null) continue;

      final String? relative = _resolveEntitlementsPath(entry.value);
      if (relative == null) continue;

      final String path = '$projectRoot/ios/$relative';
      if (!FileHelper.fileExists(path)) {
        issues.add(
          'the ${entry.key} configuration signs against ios/$relative, '
          'which does not exist',
        );
        continue;
      }

      final String? actual = _declaredApsEnvironment(path);

      // A twin with NO `aps-environment` at all used to pass clean, which is
      // the same silence this check exists to remove: the app registers for no
      // APNs environment and nothing says so. The presence check above only
      // ever reads `Runner.entitlements`, so nothing else looks at a twin.
      // Skipped for that one file precisely because the older check has it,
      // and two lines about one file is noise rather than rigour.
      if (actual == null) {
        if (relative == _defaultEntitlementsRelativePath) continue;

        issues.add(
          'the ${entry.key} configuration signs against ios/$relative, '
          'which declares no $_apsEnvironmentKey at all',
        );
        continue;
      }

      if (actual == expected) continue;

      issues.add(
        'the ${entry.key} configuration signs against ios/$relative, '
        'which declares $_apsEnvironmentKey $actual where a '
        '${entry.key == 'Release' ? 'distribution' : 'development'} '
        'provisioning profile carries $expected',
      );
    }

    return issues;
  }

  /// The entitlements path relative to `ios/`, or null when it cannot be one.
  ///
  /// A build setting may carry Xcode's own variables, and the route this
  /// package's own guide recommends produces one: editing Code Signing
  /// Entitlements in Xcode's Build Settings can write
  /// `"$(SRCROOT)/Runner/RunnerRelease.entitlements"`. Joined verbatim that
  /// names no file, so a correctly split project failed the whole iOS row.
  ///
  /// The two variables that resolve to the directory holding the `.xcodeproj`
  /// are stripped, since that is what the rest of this reads relative to.
  /// Anything else carrying a `$(` is declined rather than guessed at, which
  /// is the same posture as an unrecognised pbxproj: a doctor that resolves a
  /// variable wrongly reports a missing file that is sitting right there.
  String? _resolveEntitlementsPath(String setting) {
    String value = setting;

    for (final String variable in const [r'$(SRCROOT)/', r'$(PROJECT_DIR)/']) {
      if (value.startsWith(variable)) {
        value = value.substring(variable.length);
        break;
      }
    }

    return value.contains(r'$(') ? null : value;
  }

  /// The entitlements path the older presence check above reads, as the
  /// pbxproj spells it.
  static const String _defaultEntitlementsRelativePath =
      'Runner/Runner.entitlements';

  /// The `aps-environment` string in an entitlements plist, or null.
  ///
  /// Matched on the key/value pair rather than on the value alone: an
  /// entitlements file holds other strings, and `development` is a word that
  /// appears in more than one of them.
  String? _declaredApsEnvironment(String path) {
    final RegExpMatch? match = RegExp(
      '<key>$_apsEnvironmentKey</key>\\s*<string>([^<]*)</string>',
    ).firstMatch(FileHelper.readFile(path));

    return match?.group(1);
  }

  /// Maps each Runner build configuration to the entitlements path it signs
  /// against, as the pbxproj spells it (relative to `ios/`).
  ///
  /// Walked structurally, target to configuration list to configuration,
  /// rather than searched: the project holds a second target (`RunnerTests`)
  /// whose configurations are also called Debug and Release and which signs
  /// nothing, so a global match reads the wrong ones. Returns empty rather
  /// than throwing when the shape is not the one this walk knows.
  Map<String, String> _entitlementsByConfiguration() {
    if (!FileHelper.fileExists(_pbxprojPath)) return const {};

    final String source = FileHelper.readFile(_pbxprojPath);

    // One top-level object: a 24-hex id, an optional /* comment */, then a
    // brace-delimited body at two tabs of indent. Xcode writes this format.
    final Map<String, String> objects = {
      for (final RegExpMatch match in RegExp(
        r'^\t\t([0-9A-Fa-f]{24})(?: /\* .*? \*/)? = \{(.*?)^\t\t\};$',
        dotAll: true,
        multiLine: true,
      ).allMatches(source))
        match.group(1)!: match.group(2)!,
    };

    String? setting(String body, String key) =>
        RegExp('^\\s*${RegExp.escape(key)} = (.+?);\$', multiLine: true)
            .firstMatch(body)
            ?.group(1)
            ?.trim()
            .replaceAll('"', '');

    final Iterable<String> targets = objects.values.where(
      (String body) =>
          setting(body, 'isa') == 'PBXNativeTarget' &&
          setting(body, 'name') == 'Runner',
    );
    if (targets.length != 1) return const {};

    // `buildConfigurationList = <id> /* Build configuration list for ... */;`
    final String? reference = setting(targets.first, 'buildConfigurationList');
    final String? listId = reference?.split(' ').first;
    if (listId == null || !objects.containsKey(listId)) return const {};

    final Map<String, String> byConfiguration = {};
    for (final RegExpMatch match in RegExp(r'([0-9A-Fa-f]{24}) /\* (\w+) \*/,')
        .allMatches(objects[listId]!)) {
      final String? path =
          setting(objects[match.group(1)!] ?? '', _entitlementsSetting);
      if (path != null) byConfiguration[match.group(2)!] = path;
    }

    return byConfiguration;
  }

  /// Path to the iOS entitlements file the installer writes.
  String get _entitlementsPath => '$projectRoot/ios/Runner/Runner.entitlements';

  /// Path to the Xcode project file that has to name that entitlements file.
  String get _pbxprojPath =>
      '$projectRoot/ios/Runner.xcodeproj/project.pbxproj';

  /// Whether the project ships a Notification Service Extension target.
  ///
  /// Two conditions, and the second is what makes this worth more than a
  /// substring search. `.appex` in the pbxproj says only that SOME app
  /// extension exists: a widget, a share sheet and a keyboard all end in that
  /// suffix, so a project carrying one of those and no NSE read as configured
  /// and got nothing but the App Group nag. That is a false green on the one
  /// check whose whole justification is that a missing NSE looks exactly like
  /// the product working.
  ///
  /// The extension POINT is what identifies it, and it lives in the target's
  /// own `Info.plist` rather than in the pbxproj, so the plists under `ios/`
  /// are what gets searched.
  ///
  /// Only the app's OWN target directories, which a review had to correct
  /// twice over. The first version walked all of `ios/` recursively and read
  /// each plist as UTF-8, and both halves of that were wrong on a real
  /// project:
  ///
  ///   - `ios/Pods` is full of vendored frameworks whose `Info.plist` is a
  ///     BINARY plist. `readAsStringSync` throws on one, nothing here caught
  ///     it, and `getWarnings()` is called unguarded from `handle()`, so the
  ///     command and the MCP tool crashed instead of reporting. It only bit a
  ///     project whose pbxproj already names a `.appex`, which is exactly this
  ///     check's audience, and OneSignal's own iOS SDK arrives as an
  ///     XCFramework through CocoaPods.
  ///   - `listSync(recursive: true)` follows links, so it descended
  ///     `ios/.symlinks/plugins/*` into the pub cache. A dependency shipping an
  ///     NSE template plist then read as THIS app's extension, which is the
  ///     false green the whole check exists to remove.
  ///
  /// So the walk starts at the immediate children of `ios/`, skips the
  /// directories that are never an app target, and never follows a link. That
  /// also retires a `'/Runner/'` substring test that did nothing on Windows,
  /// where the separator is a backslash: Runner is excluded by NAME now, which
  /// has no separator in it.
  bool _hasNotificationServiceExtension() {
    if (!_fileDeclares(_pbxprojPath, '.appex')) return false;

    final Directory ios = Directory('$projectRoot/ios');
    if (!ios.existsSync()) return false;

    for (final FileSystemEntity entity in ios.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      if (_notAnAppTarget.contains(_basename(entity.path))) continue;

      final bool declares = entity
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((File file) => _basename(file.path) == 'Info.plist')
          .any(_declaresExtensionPoint);

      if (declares) return true;
    }

    return false;
  }

  /// Whether [plist] registers against the notification-service extension
  /// point.
  ///
  /// Bytes and a tolerant decode rather than `readAsStringSync`, because a
  /// vendored framework's plist is binary and the strict decoder throws on it.
  /// A binary plist that happens to contain the identifier still matches, since
  /// the bytes of an ASCII string survive `allowMalformed`.
  bool _declaresExtensionPoint(File plist) => _withoutComments(
        utf8.decode(plist.readAsBytesSync(), allowMalformed: true),
      ).contains(_notificationServiceExtensionPoint);

  /// The last path segment, separator-agnostic.
  String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

  /// Directories under `ios/` that are never one of the app's own targets.
  ///
  /// `Runner` is the app, and an app is not its own notification service.
  /// The rest are tooling: CocoaPods' vendored sources, Flutter's symlinks into
  /// the pub cache, the build output, and the engine's own directory.
  static const Set<String> _notAnAppTarget = <String>{
    'Runner',
    'Pods',
    '.symlinks',
    'build',
    'Flutter',
  };

  /// Apple's identifier for the extension point an NSE registers against.
  static const String _notificationServiceExtensionPoint =
      'com.apple.usernotifications.service';

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
      final warningsAboutConfig = configWarnings();

      if (configIssues.isEmpty && warningsAboutConfig.isEmpty) {
        buffer.writeln('  ✓ All config checks passed');
      } else {
        for (final issue in configIssues) {
          buffer.writeln('  ✗ $issue');
        }
        for (final warning in warningsAboutConfig) {
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
