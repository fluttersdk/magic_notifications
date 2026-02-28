import 'dart:io';

import 'package:magic_notifications/src/cli/commands/configure_command.dart';
import 'package:test/test.dart';

/// Test double that overrides [ConfigureCommand.getProjectRoot] to point at a
/// temporary directory, isolating all file I/O from the real file system.
class _TestConfigureCommand extends ConfigureCommand {
  final String _root;

  _TestConfigureCommand(this._root);

  @override
  String getProjectRoot() => _root;
}

/// Builds the canonical test config content used across all test scenarios.
String _buildNotificationsConfig({
  String appId = '12345678-1234-1234-1234-123456789012',
  bool notifyButtonEnabled = false,
  bool databaseEnabled = true,
  int pollingInterval = 30,
  bool mailEnabled = false,
  bool softPromptEnabled = true,
}) {
  return '''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': '$appId',
      'notify_button_enabled': $notifyButtonEnabled,
    },
    'database': {
      'enabled': $databaseEnabled,
      'polling_interval': $pollingInterval,
    },
    'mail': {
      'enabled': $mailEnabled,
    },
    'soft_prompt': {
      'enabled': $softPromptEnabled,
    },
  },
};
''';
}

void main() {
  late Directory tempDir;
  late _TestConfigureCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('configure_cmd_test_');
    command = _TestConfigureCommand(tempDir.path);

    Directory('${tempDir.path}/lib/config').createSync(recursive: true);
    File('${tempDir.path}/lib/config/notifications.dart')
        .writeAsStringSync(_buildNotificationsConfig());
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // configExists
  // ---------------------------------------------------------------------------
  group('configExists', () {
    test('returns true when notifications.dart exists', () {
      expect(command.configExists(), isTrue);
    });

    test('returns false when notifications.dart is missing', () {
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();
      expect(command.configExists(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // validatePollingInterval
  // ---------------------------------------------------------------------------
  group('validatePollingInterval', () {
    test('accepts lower boundary: 5', () {
      expect(command.validatePollingInterval(5), isTrue);
    });

    test('rejects below lower boundary: 4', () {
      expect(command.validatePollingInterval(4), isFalse);
    });

    test('accepts upper boundary: 600', () {
      expect(command.validatePollingInterval(600), isTrue);
    });

    test('rejects above upper boundary: 601', () {
      expect(command.validatePollingInterval(601), isFalse);
    });

    test('accepts mid-range value: 60', () {
      expect(command.validatePollingInterval(60), isTrue);
    });

    test('rejects zero', () {
      expect(command.validatePollingInterval(0), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // readCurrentConfig
  // ---------------------------------------------------------------------------
  group('readCurrentConfig', () {
    test('parses app_id from push section', () {
      final config = command.readCurrentConfig();

      expect(config['push'], isNotNull);
      expect(
        config['push']['app_id'],
        equals('12345678-1234-1234-1234-123456789012'),
      );
    });

    test('parses polling_interval from database section', () {
      final config = command.readCurrentConfig();

      expect(config['database'], isNotNull);
      expect(config['database']['polling_interval'], equals(30));
    });

    test('parses database enabled flag', () {
      final config = command.readCurrentConfig();

      expect(config['database']['enabled'], isTrue);
    });

    test('parses soft_prompt enabled flag', () {
      final config = command.readCurrentConfig();

      expect(config['soft_prompt'], isNotNull);
      expect(config['soft_prompt']['enabled'], isTrue);
    });

    test('throws when config file does not exist', () {
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();

      expect(command.readCurrentConfig, throwsA(isA<FileSystemException>()));
    });
  });

  // ---------------------------------------------------------------------------
  // updateConfig — app_id
  // ---------------------------------------------------------------------------
  group('updateConfig app_id', () {
    test('replaces app_id value in the file', () {
      command.updateConfig({
        'push': {'app_id': 'new-app-id-value'},
      });

      final content = File('${tempDir.path}/lib/config/notifications.dart')
          .readAsStringSync();
      expect(content, contains("'app_id': 'new-app-id-value'"));
      expect(content, isNot(contains('12345678-1234-1234-1234-123456789012')));
    });

    test('updated app_id is readable by readCurrentConfig', () {
      const newId = 'aaaabbbb-cccc-dddd-eeee-ffffffffffff';
      command.updateConfig({
        'push': {'app_id': newId},
      });

      final config = command.readCurrentConfig();
      expect(config['push']['app_id'], equals(newId));
    });
  });

  // ---------------------------------------------------------------------------
  // updateConfig — polling_interval
  // ---------------------------------------------------------------------------
  group('updateConfig polling_interval', () {
    test('replaces polling_interval in the file', () {
      command.updateConfig({
        'database': {'polling_interval': 60},
      });

      final content = File('${tempDir.path}/lib/config/notifications.dart')
          .readAsStringSync();
      expect(content, contains("'polling_interval': 60"));
      expect(content, isNot(contains("'polling_interval': 30")));
    });

    test('updated polling_interval is readable by readCurrentConfig', () {
      command.updateConfig({
        'database': {'polling_interval': 120},
      });

      final config = command.readCurrentConfig();
      expect(config['database']['polling_interval'], equals(120));
    });
  });

  // ---------------------------------------------------------------------------
  // updateConfig — soft_prompt
  // ---------------------------------------------------------------------------
  group('updateConfig soft_prompt', () {
    test('disables soft_prompt enabled flag', () {
      command.updateConfig({
        'soft_prompt': {'enabled': false},
      });

      final config = command.readCurrentConfig();
      expect(config['soft_prompt']['enabled'], isFalse);
    });

    test('re-enables soft_prompt enabled flag', () {
      // Write a config with soft_prompt disabled first.
      File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync(
          _buildNotificationsConfig(softPromptEnabled: false));

      command.updateConfig({
        'soft_prompt': {'enabled': true},
      });

      final config = command.readCurrentConfig();
      expect(config['soft_prompt']['enabled'], isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // getConfigOptions
  // ---------------------------------------------------------------------------
  group('getConfigOptions', () {
    test('returns expected option names', () {
      final options = command.getConfigOptions();

      expect(options, contains('OneSignal App ID'));
      expect(options, contains('Soft Prompt'));
      expect(options, contains('Polling Interval'));
    });
  });
}
