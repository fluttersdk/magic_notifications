import 'dart:io';
import 'package:fluttersdk_magic_notifications/src/cli/cli.dart';

/// Project type detection
enum ProjectType {
  flutter,
  dart,
  unknown,
}

/// Platform type for installation
enum PlatformType {
  ios,
  android,
  web,
}

/// Installation command for Magic Notifications
class InstallCommand {
  final String projectRoot;

  InstallCommand({required this.projectRoot});

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

  /// Get required platform files for setup verification
  List<String> getRequiredPlatformFiles(PlatformType platform) {
    switch (platform) {
      case PlatformType.ios:
        return [
          'ios/Runner/Info.plist',
          'ios/Runner.xcodeproj/project.pbxproj',
        ];
      case PlatformType.android:
        return [
          'android/app/build.gradle',
          'android/app/src/main/AndroidManifest.xml',
        ];
      case PlatformType.web:
        return [
          'web/index.html',
          'web/manifest.json',
        ];
    }
  }

  /// Execute installation in non-interactive mode (for testing)
  ///
  /// Parameters:
  /// - [oneSignalAppId]: Your OneSignal App ID (UUID format)
  /// - [platforms]: List of platforms to configure ('android', 'ios', 'web')
  /// - [enableSoftPrompt]: Show a soft prompt before requesting push permission
  /// - [safariWebId]: Safari Web ID for web push on Safari (optional)
  /// - [notifyButtonEnabled]: Show the OneSignal notify button widget on web
  Future<void> executeNonInteractive({
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
    final manifestPath =
        '$projectRoot/android/app/src/main/AndroidManifest.xml';

    if (!FileHelper.fileExists(manifestPath)) {
      return;
    }

    var manifest = File(manifestPath).readAsStringSync();

    // Add POST_NOTIFICATIONS permission if not present
    if (!manifest.contains('POST_NOTIFICATIONS')) {
      final permissionTag =
          '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>';

      // Handle both self-closing and regular manifest tags
      if (manifest.contains('</manifest>')) {
        manifest =
            manifest.replaceFirst('</manifest>', '$permissionTag\n</manifest>');
      } else if (manifest.contains('<manifest/>')) {
        manifest = manifest.replaceFirst(
            '<manifest/>', '<manifest>\n$permissionTag\n</manifest>');
      }

      File(manifestPath).writeAsStringSync(manifest);
    }
  }

  /// Setup iOS platform
  Future<void> _setupIOS(String appId) async {
    final infoPlistPath = '$projectRoot/ios/Runner/Info.plist';

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
    final webDir = '$projectRoot/web';

    if (!Directory(webDir).existsSync()) {
      return;
    }

    // Create OneSignal service worker
    // IMPORTANT: Use OneSignalSDK.sw.js (Service Worker version), NOT .page.js
    // The .page.js is for the main HTML page, .sw.js is for the Service Worker
    final workerPath = '$webDir/OneSignalSDKWorker.js';
    final workerContent =
        'importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");\n';
    File(workerPath).writeAsStringSync(workerContent);

    // Update index.html if needed
    final indexPath = '$webDir/index.html';
    if (FileHelper.fileExists(indexPath)) {
      var html = File(indexPath).readAsStringSync();
      // Check if already has OneSignal SDK loaded (case-insensitive check)
      if (!html.toLowerCase().contains('onesignalsdk')) {
        // Add OneSignal SDK script to head (init handled by Dart config)
        const scriptTag = '''
  <!-- OneSignal Web SDK - Init handled by Dart config -->
  <script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
  <script>
    window.OneSignalDeferred = window.OneSignalDeferred || [];
  </script>''';
        html = html.replaceFirst('</head>', '$scriptTag\n</head>');
        File(indexPath).writeAsStringSync(html);
      }
    }
  }
}
