import 'dart:io';

import 'package:magic_cli/magic_cli.dart';
import 'package:magic_notifications/src/cli/commands/doctor_command.dart';
import 'package:test/test.dart';

/// Test double that overrides [getProjectRoot] to use a temp directory.
class _TestDoctorCommand extends DoctorCommand {
  final String _root;

  _TestDoctorCommand(this._root);

  @override
  String getProjectRoot() => _root;
}

/// Write a fully valid notifications config to the temp project.
void _writeValidConfig(Directory tempDir) {
  Directory('${tempDir.path}/lib/config').createSync(recursive: true);
  File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': '12345678-1234-1234-1234-123456789012',
    },
    'database': {
      'enabled': true,
      'polling_interval': 30,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
}

/// Write a valid pubspec.yaml with `magic_notifications` dependency.
void _writeValidPubspec(Directory tempDir) {
  File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
  magic_notifications:
    path: ./plugins/magic_notifications
''');
}

void main() {
  late Directory tempDir;
  late _TestDoctorCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('doctor_cmd_test_');
    command = _TestDoctorCommand(tempDir.path);
    _writeValidPubspec(tempDir);
    _writeValidConfig(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  // ---------------------------------------------------------------------------
  // Name and description
  // ---------------------------------------------------------------------------

  group('DoctorCommand metadata', () {
    test('name is "doctor"', () {
      expect(command.name, equals('doctor'));
    });

    test('description is not empty', () {
      expect(command.description, isNotEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // checkPluginInstalled
  // ---------------------------------------------------------------------------

  group('checkPluginInstalled', () {
    test('returns true when magic_notifications is in dependencies', () {
      expect(command.checkPluginInstalled(), isTrue);
    });

    test('returns false when dependency is absent', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
      expect(command.checkPluginInstalled(), isFalse);
    });

    test('returns false when only old package name is present', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  fluttersdk_magic_notifications:
    path: ./plugins/fluttersdk_magic_notifications
''');
      expect(command.checkPluginInstalled(), isFalse);
    });

    test('returns false when pubspec.yaml is missing', () {
      File('${tempDir.path}/pubspec.yaml').deleteSync();
      expect(command.checkPluginInstalled(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // checkConfigExists
  // ---------------------------------------------------------------------------

  group('checkConfigExists', () {
    test('returns true when config file exists', () {
      expect(command.checkConfigExists(), isTrue);
    });

    test('returns false when config file is missing', () {
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();
      expect(command.checkConfigExists(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // validateAppIdFormat
  // ---------------------------------------------------------------------------

  group('validateAppIdFormat', () {
    test('accepts a valid UUID v4 string', () {
      expect(
        command.validateAppIdFormat('12345678-1234-1234-1234-123456789012'),
        isTrue,
      );
    });

    test('rejects a short ID', () {
      expect(command.validateAppIdFormat('abc-def'), isFalse);
    });

    test('rejects an empty string', () {
      expect(command.validateAppIdFormat(''), isFalse);
    });

    test('rejects a placeholder value', () {
      expect(command.validateAppIdFormat('YOUR_APP_ID'), isFalse);
    });

    test('rejects an ID with wrong segment lengths', () {
      expect(command.validateAppIdFormat('1234-1234-1234-1234-1234'), isFalse);
    });

    test('accepts uppercase hex UUID', () {
      expect(
        command.validateAppIdFormat('ABCDEF12-ABCD-ABCD-ABCD-ABCDEF123456'),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // validateConfig
  // ---------------------------------------------------------------------------

  group('validateConfig', () {
    test('returns no issues for a valid config', () {
      expect(command.validateConfig(), isEmpty);
    });

    test('returns issue when config file is missing', () {
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();
      final issues = command.validateConfig();
      expect(issues, isNotEmpty);
      expect(issues.first, contains('not found'));
    });

    test('returns issue when app_id is a placeholder', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': 'YOUR_APP_ID',
    },
    'database': {
      'polling_interval': 30,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
      final issues = command.validateConfig();
      expect(issues.any((i) => i.contains('App ID')), isTrue);
    });

    test('returns issue when app_id is not valid UUID format', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': 'not-a-uuid',
    },
    'database': {
      'polling_interval': 30,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
      final issues = command.validateConfig();
      expect(issues.any((i) => i.contains('UUID')), isTrue);
    });

    test('returns issue when polling_interval is above max (999)', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': '12345678-1234-1234-1234-123456789012',
    },
    'database': {
      'polling_interval': 999,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
      final issues = command.validateConfig();
      expect(issues.any((i) => i.contains('polling_interval')), isTrue);
    });

    test('returns issue when polling_interval is below min (3)', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': '12345678-1234-1234-1234-123456789012',
    },
    'database': {
      'polling_interval': 3,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
      final issues = command.validateConfig();
      expect(issues.any((i) => i.contains('polling_interval')), isTrue);
    });

    test('returns issue when soft_prompt section is missing', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': '12345678-1234-1234-1234-123456789012',
    },
    'database': {
      'polling_interval': 30,
    },
  },
};
''');
      final issues = command.validateConfig();
      expect(issues.any((i) => i.contains('soft_prompt')), isTrue);
    });

    test('accepts polling_interval at boundary value 5', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': '12345678-1234-1234-1234-123456789012',
    },
    'database': {
      'polling_interval': 5,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
      final issues = command.validateConfig();
      expect(issues.where((i) => i.contains('polling_interval')), isEmpty);
    });

    test('accepts polling_interval at boundary value 600', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': '12345678-1234-1234-1234-123456789012',
    },
    'database': {
      'polling_interval': 600,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
      final issues = command.validateConfig();
      expect(issues.where((i) => i.contains('polling_interval')), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // getMissingRequirements
  // ---------------------------------------------------------------------------

  group('getMissingRequirements', () {
    test('returns empty list when fully configured project is valid', () {
      final missing = command.getMissingRequirements();
      expect(missing, isEmpty);
    });

    test('includes plugin issue when dependency is missing', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');
      final missing = command.getMissingRequirements();
      expect(missing.any((m) => m.toLowerCase().contains('plugin')), isTrue);
    });

    test('includes config issue when config is missing', () {
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();
      final missing = command.getMissingRequirements();
      expect(
        missing.any((m) => m.toLowerCase().contains('config')),
        isTrue,
      );
    });

    test('includes validation issue when app_id is invalid', () {
      File('${tempDir.path}/lib/config/notifications.dart')
          .writeAsStringSync('''
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'app_id': 'bad-id',
    },
    'database': {
      'polling_interval': 30,
    },
    'soft_prompt': {
      'enabled': true,
    },
  },
};
''');
      final missing = command.getMissingRequirements();
      expect(missing.any((m) => m.contains('App ID')), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // generateReport
  // ---------------------------------------------------------------------------

  group('generateReport', () {
    test('contains plugin installed check', () {
      final report = command.generateReport();
      expect(report, contains('Plugin'));
    });

    test('contains configuration file check', () {
      final report = command.generateReport();
      expect(report, contains('Configuration'));
    });

    test('shows ✓ when everything is valid', () {
      final report = command.generateReport();
      expect(report, contains('✓'));
    });

    test('shows ✗ when config is missing', () {
      File('${tempDir.path}/lib/config/notifications.dart').deleteSync();
      final report = command.generateReport();
      expect(report, contains('✗'));
    });

    test('verbose shows package name detail', () {
      final report = command.generateReport(verbose: true);
      expect(report, contains('magic_notifications'));
    });

    test('verbose shows config path detail', () {
      final report = command.generateReport(verbose: true);
      expect(report, contains('lib/config/notifications.dart'));
    });

    test('non-verbose omits per-check detail lines', () {
      final report = command.generateReport(verbose: false);
      expect(report, isNot(contains('Package: magic_notifications')));
    });

    test('report includes config validation section', () {
      final report = command.generateReport();
      expect(report, contains('Config Validation'));
    });
  });

  // ---------------------------------------------------------------------------
  // --verbose flag via Kernel
  // ---------------------------------------------------------------------------

  group('--verbose flag', () {
    test('verbose flag is registered on the parser', () {
      final kernel = Kernel()..register(command);
      // Runs without throwing an exception — verifies flag is defined
      expect(() => kernel.handle(['doctor', '--verbose']), returnsNormally);
    });
  });
}
