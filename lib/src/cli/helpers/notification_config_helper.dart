import 'package:magic_cli/magic_cli.dart';

/// Notification-specific configuration helpers
class NotificationConfigHelper {
  /// Create notification config file
  ///
  /// Parameters:
  /// - [configPath]: Path to write the config file
  /// - [oneSignalAppId]: Your OneSignal App ID (UUID format)
  /// - [softPromptEnabled]: Show a soft prompt before requesting push permission
  /// - [safariWebId]: Safari Web ID for web push on Safari (optional)
  /// - [notifyButtonEnabled]: Show the OneSignal notify button widget on web (default: false)
  static void createNotificationConfig({
    required String configPath,
    required String oneSignalAppId,
    required bool softPromptEnabled,
    String? safariWebId,
    bool notifyButtonEnabled = false,
  }) {
    // Build optional safari_web_id line
    final safariWebIdLine =
        safariWebId != null ? "\n      'safari_web_id': '$safariWebId'," : '';

    final content = '''
/// Magic Notifications Configuration
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': '$oneSignalAppId',$safariWebIdLine
      'notify_button_enabled': $notifyButtonEnabled,
    },
    'database': {
      'enabled': true,
      'polling_interval': 30, // seconds
    },
    'mail': {
      'enabled': false,
    },
    'soft_prompt': {
      'enabled': $softPromptEnabled,
      'title': 'Enable Notifications',
      'message': 'Stay updated with important alerts and updates',
    },
  },
};
''';

    FileHelper.writeFile(configPath, content);
  }

  /// Update main.dart with imports and add to configFactories
  static void updateMainDart({
    required String mainPath,
    required List<String> addImports,
    required String configFactoryEntry,
  }) {
    // Add imports using ConfigEditor
    for (final import in addImports) {
      ConfigEditor.addImportToFile(
        filePath: mainPath,
        importStatement: import,
      );
    }

    // Add to configFactories list
    var content = FileHelper.readFile(mainPath);

    // Check if already added
    if (content.contains(configFactoryEntry)) {
      return;
    }

    // Find the configFactories list and add the entry before the closing bracket
    final configFactoriesPattern = RegExp(
      r'configFactories:\s*\[\s*([^\]]*)\s*\]',
      multiLine: true,
      dotAll: true,
    );

    final match = configFactoriesPattern.firstMatch(content);
    if (match != null) {
      final existingEntries = match.group(1) ?? '';
      final trimmed = existingEntries.trimRight();

      // Add comma if there are existing entries and doesn't end with comma
      final needsComma = trimmed.isNotEmpty && !trimmed.endsWith(',');
      final comma = needsComma ? ',' : '';

      final newContent = content.replaceFirst(
        configFactoriesPattern,
        'configFactories: [$existingEntries$comma\n      $configFactoryEntry,\n    ]',
      );

      FileHelper.writeFile(mainPath, newContent);
    }
  }
}
