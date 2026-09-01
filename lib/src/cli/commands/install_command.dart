import 'dart:convert';
import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';

import '../notifications_artisan_provider.dart';

/// Project type detection result for the install banner.
enum ProjectType { flutter, dart, unknown }

/// Reads how a project has wired `lib/config/notifications.dart` out of the
/// project's OWN source, instead of assuming the names this package generates.
///
/// The getter name is not knowable in advance. The stub `notifications:install`
/// writes calls it `notificationConfig`, but a project that hand-wrote its
/// config names it after its own config root (`notificationsConfig` for a
/// `notifications.*` tree). Every command that has to name that symbol, the
/// installer appending a factory and the uninstaller removing one, reads it
/// through this one place: a command that guesses either stops the app
/// compiling (install appending a factory for a symbol that does not exist) or
/// silently does nothing while reporting success (uninstall matching a line
/// that is not there).
abstract final class NotificationsConfigWiring {
  /// Core of an import of the notifications config, however the path is
  /// spelled (relative from `lib/`, or a `package:` uri).
  static const String _importCore =
      r"""import\s+['"][^'"]*config/notifications\.dart['"]""";

  /// Matches the `Map<String, dynamic> get <name> =>` declaration a
  /// notifications config exposes, capturing the getter name.
  static final RegExp getterDeclaration = RegExp(
    r'Map<\s*String\s*,\s*dynamic\s*>\s+get\s+(\w+)\s*=>',
  );

  /// Matches an import of the notifications config, which is what "this
  /// project is already wired" means.
  static final RegExp configImport = RegExp(_importCore);

  /// Matches that import as a whole LINE (any `show` / `as` combinator, the
  /// semicolon and the line break included), so removing it leaves no residue.
  static final RegExp configImportLine =
      RegExp(r'[ \t]*' + _importCore + r'[^;\n]*;[ \t]*\r?\n?');

  /// The getter name [configSource] declares its config map under, or `null`
  /// when it declares none this package can name.
  static String? getterName(String configSource) =>
      getterDeclaration.firstMatch(withoutComments(configSource))?.group(1);

  /// Whether [mainSource] already imports the notifications config.
  ///
  /// Comments are stripped first: an import somebody commented out is not an
  /// import, and reading one as wiring would leave the project with a config
  /// nothing ever loads.
  static bool wiresConfig(String mainSource) =>
      configImport.hasMatch(withoutComments(mainSource));

  /// Matches the `() => <getterName>,` configFactory entry, for a rename in
  /// place.
  static RegExp configFactory(String getterName) =>
      RegExp(_factoryPattern(getterName));

  /// Matches that entry as a whole LINE, for a removal that leaves no blank
  /// line behind.
  static RegExp configFactoryLine(String getterName) =>
      RegExp(r'[ \t]*' + _factoryPattern(getterName) + r'[ \t]*\r?\n?');

  /// Strips Dart line and block comments from [source].
  ///
  /// Every reader here looks for a declaration, and a declaration inside a
  /// comment (a doc comment quoting the import, a factory line left commented
  /// during debugging) is not one.
  static String withoutComments(String source) => source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp(r'//[^\n]*'), '');

  /// The bare `() => <getterName>,` pattern both matchers above build on.
  static String _factoryPattern(String getterName) =>
      r'\(\)\s*=>\s*' + RegExp.escape(getterName) + r'\s*,';
}

/// Resolved install plan computed from CLI flags or the interactive wizard.
///
/// Carries everything the staging phase needs so [InstallCommand.handle] can
/// validate + collect the full answer set BEFORE touching the installer. The
/// UUID is already validated by the time this is built.
class _InstallPlan {
  const _InstallPlan({
    required this.oneSignalAppId,
    required this.platforms,
    required this.enableSoftPrompt,
    required this.safariWebId,
    required this.notifyButtonEnabled,
  });

  /// Validated OneSignal App ID (UUID format).
  final String oneSignalAppId;

  /// Platforms the operator opted into (subset of android / ios / web).
  final List<String> platforms;

  /// Whether the soft-prompt permission flow is enabled in the config.
  final bool enableSoftPrompt;

  /// Optional Safari Web ID for web push.
  final String? safariWebId;

  /// Whether the OneSignal notify button renders on web.
  final bool notifyButtonEnabled;

  /// `true` when the operator selected the web platform.
  bool get hasWeb => platforms.contains('web');

  /// `true` when the operator selected the android platform.
  bool get hasAndroid => platforms.contains('android');

  /// `true` when the operator selected the ios platform.
  bool get hasIos => platforms.contains('ios');
}

/// `notifications:install`: installs Magic Notifications via the bundled
/// install.yaml manifest layered with a fluent override for the dynamic
/// OneSignal flow the v1 manifest schema cannot express.
///
/// ## Layered architecture
///
/// 1. `install.yaml` declares the STATIC slice: `plugin_name`, the
///    `magic.provider: NotificationServiceProvider` injection, and the
///    `post_install` message. [resolveManifestPath] locates it relative to the
///    plugin package root.
/// 2. [handle] validates `--app-id` as a UUID BEFORE staging anything (fail
///    fast, exit 1), resolves the platform selection (non-interactive flags or
///    the interactive wizard), then drives the fluent override.
/// 3. The override stages TRANSACTIONAL writes first (the placeholder-rendered
///    `lib/config/notifications.dart`, and `web/OneSignalSDKWorker.js` when web
///    is selected) so the atomic `.tmp` swap covers them, then helper-backed
///    mutations LAST (provider inject from the manifest, android permission,
///    the iOS background mode plus push entitlement, main.dart configFactory
///    inject, and the idempotent `<head>` script).
///    Helper-backed ops write synchronously during stage and do NOT roll back
///    (PluginInstaller V1 limitation), so they trail every high-risk write.
/// 4. The head-script injection is gated with [HtmlEditor.hasContent] so a
///    re-install never double-injects.
/// 5. After a successful commit, a `--force` run that replaced an existing
///    config reconciles `main.dart` with the file it just wrote (see
///    [_realignMainFactory]). Regenerating the config must never leave the
///    project naming a getter that no longer exists.
///
/// ## Why a fluent override, not a pure manifest
///
/// Four things the v1 schema cannot do, all handled here in code:
///   - UUID validation of `--app-id` with fail-fast exit.
///   - Web / Safari prompts that fire ONLY when web is selected (manifest
///     `prompts:` run unconditionally during prepare and cannot be skipped).
///   - The arbitrary `web/OneSignalSDKWorker.js` write (`native.web` supports
///     only head_scripts / meta_tags).
///   - The placeholder-substituted config + the idempotent head-script guard.
class InstallCommand extends ArtisanInstallCommand {
  /// Public default constructor. Tests subclass to pin [getProjectRoot],
  /// [getStubSearchPaths], and [resolveManifestPath].
  InstallCommand();

  /// Background mode iOS requires before APNs will wake the app for a silent
  /// or data payload.
  static const String _remoteNotificationMode = 'remote-notification';

  /// Where the OneSignal worker is written, relative to the web root.
  static const String _serviceWorkerPath = 'OneSignalSDKWorker.js';

  /// Scope that worker registers under.
  static const String _serviceWorkerScope = '/onesignal/';

  @override
  String get signature => 'notifications:install '
      '$baseFlags'
      '{--app-id= : OneSignal App ID (UUID format)} '
      '{--platforms= : Comma-separated platforms (android,ios,web)} '
      '{--no-soft-prompt : Disable the soft prompt (enabled by default)} '
      '{--safari-web-id= : Legacy Safari Web ID, optional; modern Safari '
      'uses VAPID and needs none} '
      '{--notify-button : Enable the OneSignal notify button on web}';

  @override
  String get description => 'Install and configure Magic Notifications';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  String pluginName(ArtisanContext ctx) => 'magic_notifications';

  /// Absolute path to the Flutter project root, resolved on access.
  String get projectRoot => getProjectRoot();

  /// Resolve the Flutter project root. Overridable in tests.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Stub search paths, plugin assets first. Overridable in tests.
  List<String> getStubSearchPaths() =>
      [_resolvePluginStubsDir(), '${Directory.current.path}/assets/stubs'];

  /// Resolves the plugin's `install.yaml` path. Overridable in tests.
  ///
  /// Walks the consumer's `.dart_tool/package_config.json` to find the
  /// magic_notifications package root, mirroring [resolveMagicStubsDir]'s
  /// resolution so the `.parent` / `.parent.parent` ambiguity never bites.
  String resolveManifestPath() {
    final pluginRoot = _resolvePluginRoot();
    return pluginRoot == null
        ? '${Directory.current.path}/install.yaml'
        : '$pluginRoot/install.yaml';
  }

  /// Builds the [InstallContext] bound to the resolved project root. Overrides
  /// the base so the installer targets [projectRoot] rather than the cwd.
  @override
  InstallContext buildContext(ArtisanContext ctx) =>
      InstallContext.real(ctx, projectRoot: projectRoot);

  /// Validate an OneSignal App ID against the canonical UUID 8-4-4-4-12 shape.
  bool validateOneSignalAppId(String appId) {
    final uuidRegex = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    return uuidRegex.hasMatch(appId);
  }

  /// Detect the project type by inspecting pubspec.yaml.
  ProjectType detectProjectType() {
    final pubspecPath = '$projectRoot/pubspec.yaml';
    if (!FileHelper.fileExists(pubspecPath)) {
      return ProjectType.unknown;
    }
    final yaml = FileHelper.readYamlFile(pubspecPath);
    final dependencies = yaml['dependencies'];
    if (dependencies is Map && dependencies.containsKey('flutter')) {
      return ProjectType.flutter;
    }
    return ProjectType.dart;
  }

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(
        ConsoleStyle.banner('Magic Notifications', magicNotificationsVersion));

    // 1. Project-type guard. An unrecognised root means there is nothing safe
    //    to scaffold into.
    final projectType = detectProjectType();
    if (projectType == ProjectType.unknown) {
      ctx.output.error('Could not detect project type');
      return 1;
    }
    ctx.output.info('Detected ${projectType.name} project\n');

    // 2. Resolve the install plan (validates --app-id as UUID, fail-fast). The
    //    plan must be fully built BEFORE the installer stages any op so a bad
    //    App ID never leaves a half-written project behind.
    final plan = isNonInteractive(ctx)
        ? _resolveNonInteractivePlan(ctx)
        : _resolveInteractivePlan(ctx);
    if (plan == null) {
      return 1;
    }

    // 3. Parse the manifest for the static slice (provider name + message).
    final InstallManifest manifest;
    try {
      manifest = ManifestParser.parseFile(resolveManifestPath());
    } on FormatException catch (e) {
      ctx.output.error('install.yaml: $e');
      return 1;
    } on ManifestValidationException catch (e) {
      ctx.output.error('install.yaml: ${e.message}');
      return 1;
    }

    // 4. Stage + commit the install via the fluent override.
    final result = await _runInstall(ctx, manifest, plan);

    // 5. Echo the post-install message on Success.
    if (result is Success && manifest.postInstall.message != null) {
      ctx.output.info(manifest.postInstall.message!);
    }

    return _renderResult(ctx, result);
  }

  /// Builds the install plan from CLI flags (CI/CD path). Returns `null` after
  /// emitting an error when `--app-id` is missing or malformed.
  _InstallPlan? _resolveNonInteractivePlan(ArtisanContext ctx) {
    final appId = ctx.input.option('app-id') as String?;
    if (appId == null || appId.isEmpty) {
      ctx.output.error('--app-id is required in non-interactive mode');
      return null;
    }
    if (!validateOneSignalAppId(appId)) {
      ctx.output.error('Invalid OneSignal App ID format');
      return null;
    }

    final platformsStr =
        ctx.input.option('platforms') as String? ?? 'android,ios,web';
    final platforms =
        platformsStr.split(',').map((p) => p.trim()).toList(growable: false);

    return _InstallPlan(
      oneSignalAppId: appId,
      platforms: platforms,
      enableSoftPrompt: !(ctx.input.option('no-soft-prompt') as bool? ?? false),
      safariWebId: ctx.input.option('safari-web-id') as String?,
      notifyButtonEnabled: ctx.input.option('notify-button') as bool? ?? false,
    );
  }

  /// Builds the install plan via the interactive wizard. The web / Safari
  /// prompts are gated on the platform selection IN CODE because manifest
  /// prompts run unconditionally and cannot be skipped when web is deselected.
  _InstallPlan? _resolveInteractivePlan(ArtisanContext ctx) {
    ctx.output.info('Starting interactive installation wizard...\n');

    // 1. OneSignal App ID, re-prompt until a valid UUID is entered.
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

    // 2. Platform selection.
    ctx.output.info(ConsoleStyle.step(2, 4, 'Platform Selection'));
    final available = PlatformHelper.detectPlatforms(projectRoot);
    if (available.isEmpty) {
      ctx.output.warning('No platform directories found');
      ctx.output.info('Defaulting to: android, ios, web');
      available.addAll(['android', 'ios', 'web']);
    } else {
      ctx.output.info('Detected platforms: ${available.join(', ')}');
    }
    final selected = <String>[];
    for (final platform in available) {
      if (Prompt.confirm('Enable $platform?', defaultValue: true)) {
        selected.add(platform);
        ctx.output.success('  $platform enabled');
      } else {
        ctx.output.comment('  $platform skipped');
      }
    }
    if (selected.isEmpty) {
      ctx.output.warning('No platforms selected, using all detected');
      selected.addAll(available);
    }
    ctx.output.writeln('');

    // 3. Web-specific config, only when web was selected.
    String? safariWebId;
    var notifyButtonEnabled = false;
    if (selected.contains('web')) {
      ctx.output.info(ConsoleStyle.step(3, 5, 'Web Configuration'));
      // A Safari Web ID belongs to the LEGACY Safari push path only. Modern
      // Safari (macOS 13+, iOS 16.4+) subscribes over VAPID and needs nothing
      // here, so the answer defaults to skip rather than reading as required.
      ctx.output.comment(
        'Safari Web ID is only for the legacy Safari push path '
        '(pre macOS 13 / iOS 16.4). Modern Safari uses VAPID and needs none.',
      );
      if (Prompt.confirm('Configure a legacy Safari Web ID?',
          defaultValue: false)) {
        final safariInput =
            Prompt.ask('Enter legacy Safari Web ID (or press Enter to skip)');
        if (safariInput.isNotEmpty) {
          safariWebId = safariInput;
          ctx.output.success('Legacy Safari Web ID configured');
        } else {
          ctx.output.comment('Legacy Safari Web ID skipped');
        }
      } else {
        ctx.output.comment('Legacy Safari Web ID skipped');
      }
      notifyButtonEnabled = Prompt.confirm('Enable OneSignal notify button?',
          defaultValue: false);
      ctx.output.writeln('');
    }

    // 4. Soft-prompt config.
    final hasWeb = selected.contains('web');
    ctx.output.info(
      ConsoleStyle.step(hasWeb ? 4 : 3, hasWeb ? 5 : 4, 'Soft Prompt'),
    );
    ctx.output
        .comment('Soft prompt asks users before requesting push permissions');
    final enableSoftPrompt =
        Prompt.confirm('Enable soft prompt?', defaultValue: true);
    ctx.output.writeln('');

    return _InstallPlan(
      oneSignalAppId: appId,
      platforms: selected,
      enableSoftPrompt: enableSoftPrompt,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
    );
  }

  /// Stages the ordered op list onto a fresh [PluginInstaller] and commits.
  ///
  /// Op-order contract (Must Have): transactional `writeFile` ops first so the
  /// atomic `.tmp` swap covers them, helper-backed mutations last (they write
  /// synchronously during stage and do NOT roll back).
  Future<TransactionResult> _runInstall(
    ArtisanContext ctx,
    InstallManifest manifest,
    _InstallPlan plan,
  ) async {
    final installContext = buildContext(ctx);
    final installer = PluginInstaller(
      installContext,
      pluginName: manifest.pluginName,
    );
    final force = isForce(ctx);

    // ---- Transactional writes FIRST (ride the atomic .tmp swap) ----

    // 1. Config file. Skip when it already exists and --force was not passed
    //    (mirrors the legacy behavior; the installer would otherwise overwrite).
    //    The rendered source is kept: op 6 reads the config getter's name out
    //    of whichever source this run leaves on disk.
    //
    //    The getter the project declares TODAY is read here, before anything
    //    can overwrite the only file that carries it, because step 8 needs it
    //    to re-point an already-wired main.dart after a --force regeneration.
    final configPath = '$projectRoot/lib/config/notifications.dart';
    final mainPath = '$projectRoot/lib/main.dart';
    final configExists = FileHelper.fileExists(configPath);
    final previousGetter = configExists
        ? NotificationsConfigWiring.getterName(FileHelper.readFile(configPath))
        : null;
    final mainWiredBefore =
        FileHelper.fileExists(mainPath) && _wiresConfig(mainPath);
    String? stagedConfig;
    if (configExists && !force) {
      ctx.output.warning(
          'Configuration file already exists. Use --force to overwrite.');
    } else {
      stagedConfig = _renderConfig(plan);
      installer.writeFile(
        targetPath: configPath,
        content: stagedConfig,
      );
    }

    // 2. Web service worker (arbitrary file write the manifest cannot express).
    if (plan.hasWeb && PlatformHelper.hasPlatform(projectRoot, 'web')) {
      installer.writeFile(
        targetPath: '$projectRoot/web/OneSignalSDKWorker.js',
        content: StubLoader.load(
          'install/onesignal_worker',
          searchPaths: getStubSearchPaths(),
        ),
      );
    }

    // ---- Helper-backed mutations LAST (synchronous, no rollback) ----

    // 3. Provider injection from the manifest's magic.provider slot. Uses the
    //    PluginInstaller composite (import + providers-list append); idempotent.
    final provider = manifest.magic.provider;
    if (provider != null) {
      installer.injectProvider(provider);
    }

    // 4. Android POST_NOTIFICATIONS permission, gated on platform selection.
    //    The dispatcher additionally skips silently when android/ is absent.
    if (plan.hasAndroid) {
      installer
          .injectAndroidPermission('android.permission.POST_NOTIFICATIONS');
    }

    // 5. iOS push setup, gated on platform selection. The dispatcher skips
    //    both ops silently when ios/ is absent, and PlistWriter creates the
    //    entitlements file when the project has never had one (which is every
    //    Flutter project until somebody opens Xcode). The entitlement op also
    //    points CODE_SIGN_ENTITLEMENTS at that file, without which Xcode never
    //    reads it.
    if (plan.hasIos) {
      final modes = _declaredBackgroundModes(
        PlatformHelper.infoPlistPath(projectRoot),
      );
      if (!modes.contains(_remoteNotificationMode)) {
        installer.injectInfoPlistKey(
          key: 'UIBackgroundModes',
          value: <String>[...modes, _remoteNotificationMode],
        );
      }
      installer.injectEntitlement(
        platform: 'ios',
        key: 'aps-environment',
        // Development is the install-time default. The distribution value is a
        // signing concern, decided when the build is archived, not here.
        value: 'development',
      );
    }

    // 6. main.dart configFactory inject. The import is RELATIVE
    //    (config/notifications.dart, not a package: import) so injectConfigFactory
    //    cannot be used; stage the import + the factory append explicitly.
    //
    //    Prior wiring is detected by THAT IMPORT, never by a symbol name: the
    //    guard used to test for the stub's `notificationConfig`, which misses on
    //    a project whose config declares `notificationsConfig`, so every re-run
    //    appended a factory naming a symbol that does not exist and stopped the
    //    app compiling. And when this run is not the one writing the config, the
    //    getter's name is read out of the project's own file rather than
    //    assumed.
    if (FileHelper.fileExists(mainPath) && !mainWiredBefore) {
      final configSource = stagedConfig ??
          (configExists ? FileHelper.readFile(configPath) : null);
      final getter = configSource == null
          ? null
          : NotificationsConfigWiring.getterName(configSource);
      if (getter == null) {
        // Guessing here is how the app broke in the first place: a factory
        // naming a symbol the config does not declare costs a compile, while a
        // missing one costs a documented manual step.
        ctx.output.warning(
          'No config getter could be read out of lib/config/notifications.dart, '
          'so lib/main.dart was left untouched. Add '
          "\"import 'config/notifications.dart';\" and "
          '"() => <yourConfigGetter>," inside Magic.init\'s configFactories '
          'by hand.',
        );
      } else {
        installer
          ..injectMainDartImport("import 'config/notifications.dart';")
          ..injectAfter(
            targetFile: mainPath,
            pattern: RegExp(r'\(\)\s*=>\s*\w+Config,(?=\s*\n\s*\])'),
            code: '\n      () => $getter,',
          );
      }
    }

    // 7. Web SDK <head> script, gated on web selection AND idempotency. The
    //    head_scripts dispatcher has no hasContent guard, so re-installing
    //    would double-inject without this check; stage the inject only when the
    //    SDK is not already present.
    if (plan.hasWeb && PlatformHelper.hasPlatform(projectRoot, 'web')) {
      final indexPath = PlatformHelper.webIndexPath(projectRoot);
      if (FileHelper.fileExists(indexPath) &&
          !HtmlEditor.hasContent(indexPath, 'onesignalsdk')) {
        installer.injectIntoWebHead(
          StubLoader.load(
            'install/onesignal_script',
            searchPaths: getStubSearchPaths(),
          ),
        );
      }
    }

    final result = await installer.commit(dryRun: isDryRun(ctx), force: force);

    // 8. Post-commit reconcile: a --force run that REPLACED an existing config
    //    leaves an already-wired main.dart naming a getter the new file no
    //    longer declares. This runs after the commit, not as a staged op, so it
    //    reads the config that actually landed and never fires on a dry run or
    //    on a transaction that rolled back.
    if (result is Success &&
        stagedConfig != null &&
        configExists &&
        mainWiredBefore) {
      _realignMainFactory(
        ctx,
        mainPath,
        previousGetter: previousGetter,
        regeneratedGetter: NotificationsConfigWiring.getterName(stagedConfig),
      );
    }

    return result;
  }

  /// Whether the project's `main.dart` at [mainPath] already imports the
  /// notifications config, which is what "already installed" means here.
  bool _wiresConfig(String mainPath) => NotificationsConfigWiring.wiresConfig(
        FileHelper.readFile(mainPath),
      );

  /// Re-points an already-wired `lib/main.dart` at the getter the regenerated
  /// config declares, after a `--force` run overwrote the project's own config.
  ///
  /// Why this exists: `--force` rewrites the config from the stub, whose getter
  /// is `notificationConfig`, while a project that hand-wrote its config named
  /// its own symbol in `Magic.init`. Left alone, the two disagree and the app
  /// stops compiling. The operator asked to REGENERATE THE CONFIG, not to break
  /// the build, and a command whose whole purpose is repair must never hand
  /// back a project that does not compile.
  ///
  /// Why the wiring follows the file, rather than the stub being rendered under
  /// whatever getter the old config declared: `--force` means "give me the
  /// file this installer generates". Rendering it under a foreign name would
  /// leave a config that no fresh install would ever produce, so nobody reading
  /// that project later could tell what the tool actually writes. The symbol
  /// is one line in `main.dart`; the file is the thing being regenerated.
  ///
  /// [previousGetter] is read BEFORE the overwrite (the old file is the only
  /// place that name exists) and [regeneratedGetter] comes from the source this
  /// run wrote. When either is unknown, `main.dart` is left exactly as it is:
  /// a guessed rename is how this package broke a real project once already.
  void _realignMainFactory(
    ArtisanContext ctx,
    String mainPath, {
    required String? previousGetter,
    required String? regeneratedGetter,
  }) {
    if (regeneratedGetter == null || previousGetter == null) {
      ctx.output.warning(
        'lib/config/notifications.dart was regenerated, but the getter it '
        'declared before could not be read, so lib/main.dart was left '
        'untouched. Check that its configFactories entry names '
        '${regeneratedGetter ?? 'the getter the new config declares'}.',
      );
      return;
    }
    if (previousGetter == regeneratedGetter) {
      return;
    }

    final content = FileHelper.readFile(mainPath);
    final updated = content.replaceAll(
      NotificationsConfigWiring.configFactory(previousGetter),
      '() => $regeneratedGetter,',
    );
    if (updated == content) {
      ctx.output.warning(
        'lib/main.dart imports the notifications config but names no '
        '"() => $previousGetter," factory, so nothing was re-pointed. Check '
        'its configFactories entry names $regeneratedGetter.',
      );
      return;
    }

    FileHelper.writeFile(mainPath, updated);
    ctx.output.success(
      'Re-pointed lib/main.dart at $regeneratedGetter '
      '(was $previousGetter, which the regenerated config no longer declares)',
    );
  }

  /// Renders the notification config stub with the plan's placeholder values.
  String _renderConfig(_InstallPlan plan) {
    final stub = StubLoader.load(
      'install/notification_config',
      searchPaths: getStubSearchPaths(),
    );
    final rendered = StubLoader.replace(stub, {
      'oneSignalAppId': plan.oneSignalAppId,
      'safariWebIdLine': plan.safariWebId != null
          ? "\n      'safari_web_id': '${plan.safariWebId}',"
          : '',
      'notifyButtonEnabled': plan.notifyButtonEnabled.toString(),
      'softPromptEnabled': plan.enableSoftPrompt.toString(),
      'serviceWorkerPath': _serviceWorkerPath,
      'serviceWorkerScope': _serviceWorkerScope,
    });
    return rendered;
  }

  /// The `UIBackgroundModes` values [infoPlistPath] already declares.
  ///
  /// [PluginInstaller.injectInfoPlistKey] dispatches a `List<String>` onto
  /// `PlistWriter.setArrayKey`, which REPLACES the array, so staging
  /// `['remote-notification']` blind would drop an app's own `fetch` or
  /// `audio` mode on a helper-backed write the transaction cannot roll back.
  /// Reading the current values first turns that replace into a union.
  List<String> _declaredBackgroundModes(String infoPlistPath) {
    if (!FileHelper.fileExists(infoPlistPath)) {
      return const <String>[];
    }

    // Comments first: a mode somebody commented out is a mode the project does
    // not declare, and carrying it into the union would quietly re-enable it.
    final content = FileHelper.readFile(infoPlistPath)
        .replaceAll(RegExp(r'<!--.*?-->', dotAll: true), '');
    final array = RegExp(
      r'<key>\s*UIBackgroundModes\s*</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(content);
    if (array == null) {
      return const <String>[];
    }

    return RegExp(r'<string>([^<]*)</string>')
        .allMatches(array.group(1)!)
        .map((match) => match.group(1)!.trim())
        .where((mode) => mode.isNotEmpty)
        .toList(growable: false);
  }

  /// Translates a [TransactionResult] into a process exit code and emits the
  /// matching summary line.
  int _renderResult(ArtisanContext ctx, TransactionResult result) {
    switch (result) {
      case Success():
        ctx.output.success('Installation complete!');
        return 0;
      case DryRun(opCount: final n):
        ctx.output.info('Dry-run: $n op(s) staged; no files were written.');
        return 0;
      case Conflict(conflicts: final list):
        ctx.output.error(
          'Conflict on ${list.length} file(s). Re-run with --force to overwrite.',
        );
        return 1;
      case Error(error: final msg, rolledBack: final ok):
        ctx.output.error('Install failed: $msg (rolledBack: $ok)');
        return 1;
    }
  }

  /// Resolves the magic_notifications package root via the consumer's
  /// `.dart_tool/package_config.json`. Returns `null` when the config or the
  /// package entry is absent.
  String? _resolvePluginRoot() {
    final packageConfigPath =
        '${Directory.current.path}/.dart_tool/package_config.json';
    final file = File(packageConfigPath);
    if (!file.existsSync()) {
      return null;
    }
    final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final packages = map['packages'] as List<dynamic>? ?? const [];
    for (final package in packages) {
      if (package['name'] != 'magic_notifications') {
        continue;
      }
      final rootUri = package['rootUri'] as String;
      if (rootUri.startsWith('file://')) {
        return Uri.parse(rootUri).toFilePath();
      }
      return file.parent.uri.resolve(rootUri).toFilePath();
    }
    return null;
  }

  /// Resolves the plugin's `assets/stubs/` directory off [_resolvePluginRoot].
  String _resolvePluginStubsDir() {
    final pluginRoot = _resolvePluginRoot();
    return pluginRoot == null
        ? '${Directory.current.path}/assets/stubs'
        : '$pluginRoot/assets/stubs';
  }
}
