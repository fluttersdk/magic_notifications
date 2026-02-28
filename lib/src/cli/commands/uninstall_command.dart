import 'package:magic_cli/magic_cli.dart';

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
/// dart run magic_notifications uninstall
/// dart run magic_notifications uninstall --force
/// ```
class UninstallCommand extends Command {
  @override
  String get name => 'uninstall';

  @override
  String get description => 'Remove Magic Notifications from the project';

  /// Returns the Flutter project root path.
  ///
  /// Overridable in tests via subclassing.
  String getProjectRoot() => FileHelper.findProjectRoot();

  /// Resolved project root — delegates to [getProjectRoot].
  String get projectRoot => getProjectRoot();

  @override
  void configure(ArgParser parser) {
    parser.addFlag(
      'force',
      abbr: 'f',
      help: 'Skip confirmation prompt',
      defaultsTo: false,
      negatable: false,
    );
  }

  @override
  Future<void> handle() async {
    info(ConsoleStyle.banner('Magic Notifications', '0.0.1'));

    final force = arguments['force'] as bool? ?? false;

    // 1. Show what will be removed so the user knows exactly what happens.
    _showRemovalSummary();

    // 2. Confirm unless --force is provided.
    if (!force) {
      final confirmed = confirm(
        'Are you sure you want to uninstall Magic Notifications?',
        defaultValue: false,
      );
      if (!confirmed) {
        info('Uninstall cancelled.');
        return;
      }
    }

    // 3. Execute all removals.
    await _executeUninstall();

    // 4. Remind the user about the platform files they need to clean manually.
    _showPlatformCleanupInstructions();

    success('Magic Notifications uninstalled successfully!');
  }

  /// Print a summary of what will be removed before asking for confirmation.
  void _showRemovalSummary() {
    info('The following will be removed:');
    info('  • lib/config/notifications.dart');
    info('  • magic_notifications dependency from pubspec.yaml');
    info('  • NotificationServiceProvider from lib/config/app.dart');
    info('  • notificationConfig factory from lib/main.dart');
    newLine();
    warn('Platform files will NOT be reverted (manual cleanup required):');
    info('  • android/app/src/main/AndroidManifest.xml');
    info('  • web/index.html');
    info('  • web/OneSignalSDKWorker.js');
    newLine();
  }

  /// Perform all removal steps sequentially.
  ///
  /// Each step is guarded — a missing file emits a warning instead of
  /// throwing, so partial uninstalls are handled gracefully.
  Future<void> _executeUninstall() async {
    // 1. Delete notifications config file.
    _deleteConfigFile();

    // 2. Remove pubspec.yaml dependency.
    _removePubspecDependency();

    // 3. Clean app.dart.
    _removeFromApp();

    // 4. Clean main.dart.
    _removeFromMain();
  }

  /// Delete `lib/config/notifications.dart`.
  void _deleteConfigFile() {
    final configPath = '$projectRoot/lib/config/notifications.dart';
    if (FileHelper.fileExists(configPath)) {
      FileHelper.deleteFile(configPath);
      success('Deleted lib/config/notifications.dart');
    } else {
      warn('Config file not found (already removed?)');
    }
  }

  /// Remove `magic_notifications` from `pubspec.yaml`.
  void _removePubspecDependency() {
    final pubspecPath = '$projectRoot/pubspec.yaml';
    if (!FileHelper.fileExists(pubspecPath)) {
      return;
    }

    try {
      ConfigEditor.removeDependencyFromPubspec(
        pubspecPath: pubspecPath,
        name: 'magic_notifications',
      );
      success('Removed magic_notifications from pubspec.yaml');
    } catch (e) {
      warn('Could not remove dependency from pubspec.yaml: $e');
    }
  }

  /// Remove import and `NotificationServiceProvider` from `lib/config/app.dart`.
  void _removeFromApp() {
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
    success('Removed NotificationServiceProvider from lib/config/app.dart');
  }

  /// Remove import and `notificationConfig` factory from `lib/main.dart`.
  void _removeFromMain() {
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
    success('Removed notificationConfig from lib/main.dart');
  }

  /// Print manual cleanup instructions for platform-specific files.
  void _showPlatformCleanupInstructions() {
    newLine();
    warn('Manual cleanup required for platform files:');
    info('');
    info('Android (android/app/src/main/AndroidManifest.xml):');
    info(
      '  Remove: <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    );
    info('');
    info('Web (web/index.html):');
    info('  Remove the OneSignal SDK script tags');
    info('');
    info('Web (web/OneSignalSDKWorker.js):');
    info('  Delete this file if no longer needed');
    newLine();
  }
}
