import 'package:fluttersdk_artisan/artisan.dart';

/// CLI command to uninstall Magic Notifications from the project.
///
/// Reverses the changes made by `install`:
/// - Deletes `lib/config/notifications.dart`
/// - Removes the `magic_notifications` dependency from `pubspec.yaml`
/// - Removes import and provider line from `lib/config/app.dart`
/// - Removes import and configFactory line from `lib/main.dart`
///
/// Platform files are NOT reverted (AndroidManifest.xml, index.html,
/// OneSignalSDKWorker.js) — the user must clean those manually.
///
/// ## Usage
/// ```bash
/// artisan notifications:uninstall
/// artisan notifications:uninstall --force
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

  @override
  Future<int> handle(ArtisanContext ctx) async {
    ctx.output.info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    final force = ctx.input.option('force') as bool? ?? false;

    // 1. Show what will be removed so the user knows exactly what happens.
    _showRemovalSummary(ctx);

    // 2. Confirm unless --force is provided.
    if (!force) {
      final confirmed = Prompt.confirm(
        'Are you sure you want to uninstall Magic Notifications?',
        defaultValue: false,
      );
      if (!confirmed) {
        ctx.output.info('Uninstall cancelled.');
        return 0;
      }
    }

    // 3. Execute all removals.
    await _executeUninstall(ctx);

    // 4. Remind the user about the platform files they need to clean manually.
    _showPlatformCleanupInstructions(ctx);

    ctx.output.success('Magic Notifications uninstalled successfully!');
    return 0;
  }

  /// Print a summary of what will be removed before asking for confirmation.
  void _showRemovalSummary(ArtisanContext ctx) {
    ctx.output.info('The following will be removed:');
    ctx.output.info('  • lib/config/notifications.dart');
    ctx.output.info('  • magic_notifications dependency from pubspec.yaml');
    ctx.output.info('  • NotificationServiceProvider from lib/config/app.dart');
    ctx.output.info('  • notificationConfig factory from lib/main.dart');
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
  /// Each step is guarded — a missing file emits a warning instead of
  /// throwing, so partial uninstalls are handled gracefully.
  Future<void> _executeUninstall(ArtisanContext ctx) async {
    // 1. Delete notifications config file.
    _deleteConfigFile(ctx);

    // 2. Remove pubspec.yaml dependency.
    _removePubspecDependency(ctx);

    // 3. Clean app.dart.
    _removeFromApp(ctx);

    // 4. Clean main.dart.
    _removeFromMain(ctx);
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

  /// Remove import and `notificationConfig` factory from `lib/main.dart`.
  void _removeFromMain(ArtisanContext ctx) {
    final mainPath = '$projectRoot/lib/main.dart';
    if (!FileHelper.fileExists(mainPath)) {
      return;
    }

    var content = FileHelper.readFile(mainPath);

    // Remove the notifications config import line.
    content = content.replaceAll(
      RegExp(r"import 'config/notifications\.dart';\n?"),
      '',
    );

    // Remove the notificationConfig configFactory entry.
    content = content.replaceAll(
      RegExp(r"[ \t]*\(\) => notificationConfig,\n?"),
      '',
    );

    FileHelper.writeFile(mainPath, content);
    ctx.output.success('Removed notificationConfig from lib/main.dart');
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
