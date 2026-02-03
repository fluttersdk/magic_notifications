import 'dart:io';
import 'package:test/test.dart';
import 'package:fluttersdk_magic_notifications/src/cli/commands/configure_command.dart';

void main() {
  group('ConfigureCommand', () {
    late Directory tempDir;
    late ConfigureCommand command;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('configure_cmd_test_');
      command = ConfigureCommand(projectRoot: tempDir.path);

      // Create existing config
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
final notificationConfig = {
  'push': {
    'driver': 'onesignal',
    'app_id': 'old-app-id',
  },
  'database': {
    'enabled': true,
    'polling_interval': 30,
  },
  'soft_prompt': {
    'enabled': true,
  },
};
''');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('readCurrentConfig parses existing config', () {
      final config = command.readCurrentConfig();
      expect(config['push']['app_id'], equals('old-app-id'));
      expect(config['database']['polling_interval'], equals(30));
    });

    test('updateConfig changes app_id', () {
      command.updateConfig({
        'push': {'app_id': 'new-app-id'}
      });

      final content = File('${tempDir.path}/lib/config/notifications.dart')
          .readAsStringSync();
      expect(content, contains('new-app-id'));
    });

    test('updateConfig changes polling_interval', () {
      command.updateConfig({
        'database': {'polling_interval': 60}
      });

      final config = command.readCurrentConfig();
      expect(config['database']['polling_interval'], equals(60));
    });

    test('getConfigOptions returns available options', () {
      final options = command.getConfigOptions();
      expect(options, contains('OneSignal App ID'));
      expect(options, contains('Soft Prompt'));
      expect(options, contains('Polling Interval'));
    });

    test('validatePollingInterval accepts valid range', () {
      expect(command.validatePollingInterval(10), isTrue);
      expect(command.validatePollingInterval(300), isTrue);
      expect(command.validatePollingInterval(60), isTrue);
    });

    test('validatePollingInterval rejects invalid range', () {
      expect(command.validatePollingInterval(0), isFalse);
      expect(command.validatePollingInterval(-5), isFalse);
      expect(command.validatePollingInterval(1000), isFalse);
    });

    test('configExists returns true when config file exists', () {
      expect(command.configExists(), isTrue);
    });

    test('configExists returns false when config file missing', () {
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();
      expect(command.configExists(), isFalse);
    });
  });
}
