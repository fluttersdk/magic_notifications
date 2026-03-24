import 'dart:io';
import 'package:test/test.dart';
import 'package:magic_notifications/src/cli/commands/channels_command.dart';

class _TestChannelsCommand extends ChannelsCommand {
  final String _root;

  _TestChannelsCommand(this._root);

  @override
  String getProjectRoot() => _root;
}

void main() {
  late Directory tempDir;
  late String projectRoot;

  setUp(() async {
    tempDir =
        await Directory.systemTemp.createTemp('magic_notifications_test_');
    projectRoot = tempDir.path;
    await Directory('${tempDir.path}/lib/config').create(recursive: true);
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('parseChannelConfig correctly parses valid config', () {
    final configFile = File('${tempDir.path}/lib/config/notifications.dart');
    configFile.writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': '12345678-1234-1234-1234-123456789012',
      'notify_button_enabled': false,
    },
    'database': {
      'enabled': true,
      'polling_interval': 45,
    },
    'mail': {
      'enabled': false,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');

    final command = _TestChannelsCommand(projectRoot);
    final config = command.parseChannelConfig(configFile.path);

    expect(config['push']['app_id'], '12345678-1234-1234-1234-123456789012');
    expect(config['push']['notify_button_enabled'], false);
    expect(config['database']['enabled'], true);
    expect(config['database']['polling_interval'], 45);
    expect(config['mail']['enabled'], false);
    expect(config['soft_prompt']['enabled'], true);
  });

  test('parseChannelConfig uses defaults for missing values', () {
    final configFile = File('${tempDir.path}/lib/config/notifications.dart');
    configFile.writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
    },
    'database': {
    },
  },
};
''');

    final command = _TestChannelsCommand(projectRoot);
    final config = command.parseChannelConfig(configFile.path);

    expect(config['push']['app_id'], 'NOT SET');
    expect(config['database']['polling_interval'], 30);
    expect(config['database']['enabled'], false);
    expect(config['mail']['enabled'], false);
  });
}
