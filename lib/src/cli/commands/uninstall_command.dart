import 'package:fluttersdk_artisan/artisan.dart';

import '../notifications_artisan_provider.dart';
import 'install_command.dart' show NotificationsConfigWiring;

/// CLI command to uninstall Magic Notifications from the project.
///
/// Reverses the changes made by `install`:
/// - Deletes `lib/config/notifications.dart`
/// - Removes the `magic_notifications` dependency from `pubspec.yaml`
/// - Removes import and provider line from `lib/config/app.dart`
/// - Removes the config import and the configFactory entry naming the getter
///   that config declares from `lib/main.dart`
///
/// ## Why the getter is read before anything is deleted
///
/// The factory entry in `main.dart` names whatever getter the project's config
/// declares, which is `notificationConfig` only when the config came from this
/// package's stub; a hand-written one names its own symbol. Matching on the
/// stub's literal name removed nothing from such a project while reporting
/// success, leaving an import and a factory pointing at a file this command had
/// just deleted. The name can only be read off the config file, so it is read
/// in [handle] BEFORE [_deleteConfigFile] removes the only copy of it.
///
/// When that name cannot be read (the config is already gone, or declares no
/// getter this package can name), `main.dart` is left exactly as it is and the
/// leftovers are reported: a line matched by guessing is a line removed from a
/// project that still needs it.
///
/// Platform files are NOT reverted (AndroidManifest.xml, index.html,
/// OneSignalSDKWorker.js): the user must clean those manually.
///
/// ## Usage
/// ```bash
/// dart run <app>:artisan notifications:uninstall
/// dart run <app>:artisan notifications:uninstall --force
/// ```
class UninstallCommand extends ArtisanCommand {
  @override
  String get signature =>
      'notifications:uninstall {--force : Skip confirmation prompt}';

  @override
  String get description => 'Remove Magic Notifications from the project';

  @override
  CommandBoot get boot => CommandBoot.none;

  /// Returns the Flutter project root path.
  ///
  /// Overridable in tests via subclassing.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Resolved project root — delegates to [getProjectRoot].
  String get projectRoot => getProjectRoot();

  /// Asks the operator to confirm the destructive uninstall.
  ///
  /// Returns `true` to proceed, `false` to cancel. Overridable in tests so the
  /// confirmation can be decided without reading real stdin.
  bool confirmRemoval() => Prompt.confirm(
        'Are you sure you want to uninstall Magic Notifications?',
        defaultValue: false,
      );

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(
        ConsoleStyle.banner('Magic Notifications', magicNotificationsVersion));

    final force = ctx.input.option('force') as bool? ?? false;

    // 1. Read the getter the project's config declares. This has to happen
    //    first: the config file is the only place that name exists, and
    //    _deleteConfigFile is about to remove it.
    final configGetter = _declaredConfigGetter();

    // 2. Show what will be removed so the user knows exactly what happens.
    _showRemovalSummary(ctx, configGetter);

    // 3. Confirm unless --force is provided.
    if (!force) {
      if (!confirmRemoval()) {
        ctx.output.info('Uninstall cancelled.');
        return 0;
      }
    }

    // 4. Execute all removals.
    await _executeUninstall(ctx, configGetter);

    // 5. Remind the user about the platform files they need to clean manually.
    _showPlatformCleanupInstructions(ctx);

    ctx.output.success('Magic Notifications uninstalled successfully!');
    return 0;
  }

  /// The getter `lib/config/notifications.dart` declares its config map under,
  /// or `null` when the file is absent or declares none this package can name.
  String? _declaredConfigGetter() {
    final configPath = '$projectRoot/lib/config/notifications.dart';
    if (!FileHelper.fileExists(configPath)) {
      return null;
    }
    return NotificationsConfigWiring.getterName(
        FileHelper.readFile(configPath));
  }

  /// Print a summary of what will be removed before asking for confirmation.
  ///
  /// [configGetter] is the symbol read off the project's own config, so the
  /// summary promises the line this run can actually remove rather than the one
  /// a stub-generated project would have.
  void _showRemovalSummary(ArtisanContext ctx, String? configGetter) {
    ctx.output.info('The following will be removed:');
    ctx.output.info('  • lib/config/notifications.dart');
    ctx.output.info('  • magic_notifications dependency from pubspec.yaml');
    ctx.output.info('  • NotificationServiceProvider from lib/config/app.dart');
    ctx.output.info(
      configGetter == null
          ? '  • nothing from lib/main.dart: the config getter cannot be read, '
              'so its wiring is reported instead of guessed at'
          : '  • the config import and the "() => $configGetter," factory '
              'from lib/main.dart',
    );
    ctx.output.writeln('');
    ctx.output.warning(
      'Platform files will NOT be reverted (manual cleanup required):',
    );
    ctx.output.info('  • android/app/src/main/AndroidManifest.xml');
    ctx.output.info('  • web/index.html');
    ctx.output.info('  • web/OneSignalSDKWorker.js');
    ctx.output.writeln('');
  }

  /// Perform all removal steps sequentially.
  ///
  /// Each step is guarded: a missing file emits a warning instead of throwing,
  /// so partial uninstalls are handled gracefully. [configGetter] was read in
  /// [handle], before step 1 deleted the file that declared it.
  Future<void> _executeUninstall(
    ArtisanContext ctx,
    String? configGetter,
  ) async {
    // 1. Delete notifications config file.
    _deleteConfigFile(ctx);

    // 2. Remove pubspec.yaml dependency.
    _removePubspecDependency(ctx);

    // 3. Clean app.dart.
    _removeFromApp(ctx);

    // 4. Clean main.dart.
    _removeFromMain(ctx, configGetter);
  }

  /// Delete `lib/config/notifications.dart`.
  void _deleteConfigFile(ArtisanContext ctx) {
    final configPath = '$projectRoot/lib/config/notifications.dart';
    if (FileHelper.fileExists(configPath)) {
      FileHelper.deleteFile(configPath);
      ctx.output.success('Deleted lib/config/notifications.dart');
    } else {
      ctx.output.warning('Config file not found (already removed?)');
    }
  }

  /// Remove `magic_notifications` from `pubspec.yaml`.
  void _removePubspecDependency(ArtisanContext ctx) {
    final pubspecPath = '$projectRoot/pubspec.yaml';
    if (!FileHelper.fileExists(pubspecPath)) {
      return;
    }

    try {
      ConfigEditor.removeDependencyFromPubspec(
        pubspecPath: pubspecPath,
        name: 'magic_notifications',
      );
      ctx.output.success('Removed magic_notifications from pubspec.yaml');
    } catch (e) {
      ctx.output.warning('Could not remove dependency from pubspec.yaml: $e');
    }
  }

  /// Remove import and `NotificationServiceProvider` from `lib/config/app.dart`.
  void _removeFromApp(ArtisanContext ctx) {
    final appPath = '$projectRoot/lib/config/app.dart';
    if (!FileHelper.fileExists(appPath)) {
      return;
    }

    var content = FileHelper.readFile(appPath);

    // Remove the magic_notifications package import line.
    content = content.replaceAll(
      RegExp(r"import 'package:magic_notifications/[^']*';\n?"),
      '',
    );

    // Remove the NotificationServiceProvider provider entry.
    content = content.replaceAll(
      RegExp(r"[ \t]*\(app\) => NotificationServiceProvider\(app\),\n?"),
      '',
    );

    FileHelper.writeFile(appPath, content);
    ctx.output.success(
      'Removed NotificationServiceProvider from lib/config/app.dart',
    );
  }

  /// Remove the config import and the `() => [configGetter],` factory from
  /// `lib/main.dart`.
  ///
  /// The import is matched however it is spelled (relative from `lib/`, or a
  /// `package:` uri) because a project is free to write either; the factory is
  /// matched by the getter the config declared, never by the stub's name.
  ///
  /// A `null` [configGetter] means nothing on disk could tell this command what
  /// the factory is called. Both edits are then skipped together, import
  /// included: removing the import while a factory still names the symbol it
  /// provided leaves a project that compiles less than the one we started with.
  ///
  /// Both edits skip comments, because [NotificationsConfigWiring] strips them
  /// before it decides a project is wired at all: a project whose import is
  /// commented out is correctly judged "not wired", and cutting that text out
  /// of the middle of its comment anyway leaves a dangling `//`.
  void _removeFromMain(ArtisanContext ctx, String? configGetter) {
    final mainPath = '$projectRoot/lib/main.dart';
    if (!FileHelper.fileExists(mainPath)) {
      return;
    }

    if (configGetter == null) {
      ctx.output.warning(
        'lib/main.dart was left untouched: no config getter could be read out '
        'of lib/config/notifications.dart, so the factory to remove cannot be '
        'named without guessing. Remove the config/notifications.dart import '
        'and its "() => <yourConfigGetter>," entry from Magic.init\'s '
        'configFactories by hand.',
      );
      return;
    }

    final content = FileHelper.readFile(mainPath);
    final updated = _removeOutsideComments(
      _removeOutsideComments(
        content,
        NotificationsConfigWiring.configImportLine,
      ),
      NotificationsConfigWiring.configFactoryLine(configGetter),
    );

    if (updated == content) {
      ctx.output.comment(
        'lib/main.dart references no notifications wiring; nothing to remove.',
      );
      return;
    }

    FileHelper.writeFile(mainPath, updated);
    ctx.output.success(
      'Removed the config import and "() => $configGetter," from lib/main.dart',
    );
  }

  /// Dart line and block comments, matched exactly as
  /// [NotificationsConfigWiring.withoutComments] strips them.
  ///
  /// Sharing the notion of "comment" with the DETECTION is the point: a
  /// removal that reads the file differently from the check that authorised it
  /// edits text the check never counted.
  static final RegExp _comment = RegExp(r'/\*.*?\*/|//[^\n]*', dotAll: true);

  /// [source] with every match of [pattern] that lies outside a comment gone.
  String _removeOutsideComments(String source, RegExp pattern) {
    final comments = _comment.allMatches(source).toList(growable: false);

    return source.replaceAllMapped(pattern, (match) {
      final insideComment = comments.any(
        (comment) => match.start >= comment.start && match.start < comment.end,
      );

      return insideComment ? match[0]! : '';
    });
  }

  /// Print manual cleanup instructions for platform-specific files.
  void _showPlatformCleanupInstructions(ArtisanContext ctx) {
    ctx.output.writeln('');
    ctx.output.warning('Manual cleanup required for platform files:');
    ctx.output.info('');
    ctx.output.info('Android (android/app/src/main/AndroidManifest.xml):');
    ctx.output.info(
      '  Remove: <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    );
    ctx.output.info('');
    ctx.output.info('Web (web/index.html):');
    ctx.output.info('  Remove the OneSignal SDK script tags');
    ctx.output.info('');
    ctx.output.info('Web (web/OneSignalSDKWorker.js):');
    ctx.output.info('  Delete this file if no longer needed');
    ctx.output.writeln('');
  }
}
