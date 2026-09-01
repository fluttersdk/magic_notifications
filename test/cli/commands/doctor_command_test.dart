import 'dart:io';

// Import artisan without DoctorCommand to avoid collision with the
// notifications-specific DoctorCommand below.
import 'package:fluttersdk_artisan/artisan.dart' hide DoctorCommand;
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

/// Write a minimal iOS project into [tempDir].
///
/// The three markers the doctor reads are independently switchable so each one
/// can be removed on its own: an `Info.plist` whose `UIBackgroundModes` array
/// holds [backgroundModes], a `Runner.entitlements` carrying `aps-environment`
/// when [entitlement] is set, and a `project.pbxproj` naming that file in
/// `CODE_SIGN_ENTITLEMENTS` when [codeSignEntitlements] is set.
void _writeIosProject(
  Directory tempDir, {
  List<String> backgroundModes = const <String>[],
  bool entitlement = false,
  bool codeSignEntitlements = false,
  String? infoPlistOverride,
}) {
  Directory('${tempDir.path}/ios/Runner').createSync(recursive: true);
  Directory('${tempDir.path}/ios/Runner.xcodeproj').createSync(recursive: true);

  final modes = backgroundModes.isEmpty
      ? ''
      : '''
	<key>UIBackgroundModes</key>
	<array>
${backgroundModes.map((mode) => '\t\t<string>$mode</string>').join('\n')}
	</array>
''';

  File('${tempDir.path}/ios/Runner/Info.plist').writeAsStringSync(
    infoPlistOverride ??
        '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>test_app</string>
$modes</dict>
</plist>
''',
  );

  if (entitlement) {
    File('${tempDir.path}/ios/Runner/Runner.entitlements').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>development</string>
</dict>
</plist>
''');
  }

  final entitlementsSetting = codeSignEntitlements
      ? '                CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;\n'
      : '';
  File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
      .writeAsStringSync('''
// !\$*UTF8*\$!
{
    objects = {
        97C147061CF9000F007C117D /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
$entitlementsSetting                PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
            };
            name = Debug;
        };
    };
}
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
    test('name is "notifications:doctor"', () {
      expect(command.name, equals('notifications:doctor'));
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

    test('returns false when unrelated dependency is present', () {
      File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  some_other_package:
    path: ./plugins/some_other_package
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
  // iOS platform setup
  // ---------------------------------------------------------------------------

  group('iOS setup', () {
    /// The `[ios]` prefixed entries of the doctor's missing-requirement list.
    List<String> iosIssues() => command
        .getMissingRequirements()
        .where((issue) => issue.startsWith('[ios]'))
        .toList();

    test('reports all three markers missing on a stock Flutter iOS project',
        () {
      _writeIosProject(tempDir);

      final issues = iosIssues();
      expect(issues.any((i) => i.contains('UIBackgroundModes')), isTrue,
          reason: 'a project without remote-notification must fail');
      expect(issues.any((i) => i.contains('aps-environment')), isTrue,
          reason: 'a project without an entitlements file must fail');
      expect(issues.any((i) => i.contains('CODE_SIGN_ENTITLEMENTS')), isTrue,
          reason: 'an entitlements file Xcode does not read must fail');
    });

    test('reports configured when all three markers are present', () {
      _writeIosProject(
        tempDir,
        backgroundModes: const ['remote-notification'],
        entitlement: true,
        codeSignEntitlements: true,
      );

      final status =
          command.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(status['configured'], isTrue);
      expect(status['issues'], isEmpty);
      expect(iosIssues(), isEmpty);
    });

    test('fails when UIBackgroundModes omits remote-notification', () {
      _writeIosProject(
        tempDir,
        backgroundModes: const ['fetch'],
        entitlement: true,
        codeSignEntitlements: true,
      );

      final status =
          command.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(status['configured'], isFalse);
      expect(
        (status['issues'] as List).single,
        contains('UIBackgroundModes'),
      );
    });

    test('fails when the entitlements file has no aps-environment', () {
      _writeIosProject(
        tempDir,
        backgroundModes: const ['remote-notification'],
        codeSignEntitlements: true,
      );

      final status =
          command.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(status['configured'], isFalse);
      expect((status['issues'] as List).single, contains('aps-environment'));
    });

    test('fails when the pbxproj does not name the entitlements file', () {
      _writeIosProject(
        tempDir,
        backgroundModes: const ['remote-notification'],
        entitlement: true,
      );

      final status =
          command.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(status['configured'], isFalse);
      expect(
        (status['issues'] as List).single,
        contains('CODE_SIGN_ENTITLEMENTS'),
      );
    });

    test('a commented-out background mode does not count as configured', () {
      _writeIosProject(
        tempDir,
        entitlement: true,
        codeSignEntitlements: true,
        infoPlistOverride: '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
	<!-- <key>UIBackgroundModes</key>
	<array>
		<string>remote-notification</string>
	</array> -->
</dict>
</plist>
''',
      );

      final status =
          command.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(status['configured'], isFalse);
      expect(
        (status['issues'] as List).single,
        contains('UIBackgroundModes'),
      );
    });

    test('reports the iOS row as configured in the report', () {
      _writeIosProject(
        tempDir,
        backgroundModes: const ['remote-notification'],
        entitlement: true,
        codeSignEntitlements: true,
      );

      expect(command.generateReport(), contains('IOS: ✓ Configured'));
    });

    test('reports Info.plist absence as not found', () {
      Directory('${tempDir.path}/ios').createSync(recursive: true);

      final status =
          command.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(status['exists'], isFalse);
      expect(status['configured'], isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // --verbose flag via ArtisanContext
  // ---------------------------------------------------------------------------

  group('--verbose flag', () {
    test('verbose flag produces a longer report than non-verbose', () async {
      // Drive the command directly through an ArtisanContext so there is no
      // stdin/stdout dependency. The verbose report includes per-check detail
      // lines (file paths, package names); the default report omits them.
      final verboseCtx = ArtisanContext.bare(
        MapInput({'verbose': true}, signature: command.parsedSignature),
        BufferedOutput(),
      );
      final defaultCtx = ArtisanContext.bare(
        MapInput({'verbose': false}, signature: command.parsedSignature),
        BufferedOutput(),
      );

      await command.handle(verboseCtx);
      await command.handle(defaultCtx);

      final verboseOut = (verboseCtx.output as BufferedOutput).content;
      final defaultOut = (defaultCtx.output as BufferedOutput).content;
      expect(verboseOut.length, greaterThan(defaultOut.length));
    });
  });
}
