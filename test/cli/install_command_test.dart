import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_notifications/src/cli/commands/install_command.dart'
    as mn;
// Prefixed: fluttersdk_artisan exports its own DoctorCommand from the barrel
// imported above.
import 'package:magic_notifications/src/cli/commands/doctor_command.dart'
    as doctor;
import 'package:magic_notifications/src/cli/notifications_artisan_provider.dart';
import 'package:test/test.dart';

/// Test subclass pinning the project root + stub search paths so install ops
/// land on a real temp directory.
///
/// The install command is hybrid: the manifest-injected provider write and the
/// android / web / app.dart / main.dart mutations are helper-backed ops that
/// write through `dart:io` directly, so the install context MUST point at a
/// real temp directory (an in-memory fs would not observe those writes). The
/// command keeps [getProjectRoot] / [getStubSearchPaths] overridable for that
/// reason.
class _TestInstallCommand extends mn.InstallCommand {
  _TestInstallCommand(this._root);

  final String _root;

  @override
  String getProjectRoot() => _root;

  @override
  List<String> getStubSearchPaths() => <String>[
        '${Directory.current.path}/assets/stubs',
      ];

  @override
  String resolveManifestPath() => '${Directory.current.path}/install.yaml';
}

/// Doctor double pinned to the same temp root, so one test can prove the
/// installer moves the doctor's iOS row from red to green.
class _TestDoctorCommand extends doctor.DoctorCommand {
  _TestDoctorCommand(this._root);

  final String _root;

  @override
  String getProjectRoot() => _root;
}

/// A hand-written `project.pbxproj` holding one application target with two
/// build configurations plus a test bundle with one.
///
/// Small on purpose: this test proves the installer REACHES the Xcode editor,
/// while the editor's own parser, round-trip guard and application-target
/// scoping are covered against a real Flutter project in
/// `fluttersdk_artisan`'s own suite. The RunnerTests configuration is here so
/// the integration still shows an entitlement never landing on the test bundle.

/// A configuration name as the pbxproj spells it: Xcode quotes anything a
/// bare OpenStep word cannot hold, which a flavour's hyphen is.
String _name(String base, String suffix) =>
    suffix.isEmpty ? base : '"$base$suffix"';

String _pbxproj(String suffix) => '''// !\$*UTF8*\$!
{
	archiveVersion = 1;
	objectVersion = 54;
	objects = {
		97C146ED1CF9000F007C117D /* Runner */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget "Runner" */;
			name = Runner;
			productType = "com.apple.product-type.application";
		};
		331C8080294A63A400263BE5 /* RunnerTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 331C8087294A63A400263BE5 /* Build configuration list for PBXNativeTarget "RunnerTests" */;
			name = RunnerTests;
			productType = "com.apple.product-type.bundle.unit-test";
		};
		97C147061CF9000F007C117D /* Debug$suffix */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
			};
			name = ${_name('Debug', suffix)};
		};
		97C147071CF9000F007C117D /* Release$suffix */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
			};
			name = ${_name('Release', suffix)};
		};
		331C8088294A63A400263BE5 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app.RunnerTests;
			};
			name = Debug;
		};
		97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget "Runner" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				97C147061CF9000F007C117D /* Debug$suffix */,
				97C147071CF9000F007C117D /* Release$suffix */,
			);
		};
		331C8087294A63A400263BE5 /* Build configuration list for PBXNativeTarget "RunnerTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				331C8088294A63A400263BE5 /* Debug */,
			);
		};
	};
}
''';

/// Creates `ios/Runner/Info.plist` and `ios/Runner.xcodeproj/project.pbxproj`
/// under [tempDir], with no entitlements file: the state every Flutter project
/// is in until somebody opens Xcode.
void _writeIosProject(Directory tempDir,
    {List<String> backgroundModes = const [],
    String configurationSuffix = ''}) {
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

  File('${tempDir.path}/ios/Runner/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>test_app</string>
$modes</dict>
</plist>
''');

  File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
      .writeAsStringSync(_pbxproj(configurationSuffix));
}

/// Writes a HAND-WRITTEN `lib/config/notifications.dart` declaring [getter].
///
/// Modelled on a real adopter's config: the getter is named after the
/// `notifications.*` config root (so it is NOT the stub's `notificationConfig`)
/// and the app id is resolved from the environment rather than inlined.
void _writeHandWrittenConfig(Directory tempDir, String getter) {
  Directory('${tempDir.path}/lib/config').createSync(recursive: true);
  File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync('''
import '../app/support/env_strings.dart' show envString;

/// Notifications configuration.
Map<String, dynamic> get $getter => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': envString('ONESIGNAL_APP_ID', ''),
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

/// Writes a `lib/main.dart` already wired to a config declaring [getter].
void _writeWiredMain(Directory tempDir, String getter) {
  File('${tempDir.path}/lib/main.dart').writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';
import 'config/notifications.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => $getter,
    ],
  );
}
''');
}

/// Asserts the install invariant directly off disk: whatever getter
/// `lib/config/notifications.dart` declares after the run is the one
/// `lib/main.dart` names in its notifications configFactory.
///
/// Written as a set comparison rather than a substring check so a main.dart
/// left naming BOTH the old and the new getter still fails: one of the two
/// does not exist, and the project would not compile.
void _expectMainNamesTheDeclaredGetter(Directory tempDir) {
  final config = File('${tempDir.path}/lib/config/notifications.dart');
  expect(config.existsSync(), isTrue);
  final declared = RegExp(r'Map<\s*String\s*,\s*dynamic\s*>\s+get\s+(\w+)\s*=>')
      .firstMatch(config.readAsStringSync())
      ?.group(1);
  expect(declared, isNotNull, reason: 'the config on disk declares a getter');

  final main = File('${tempDir.path}/lib/main.dart').readAsStringSync();
  final named = RegExp(r'\(\)\s*=>\s*(\w+),')
      .allMatches(main)
      .map((match) => match.group(1)!)
      .where((name) => name != 'appConfig')
      .toSet();
  expect(
    named,
    <String>{declared!},
    reason: 'main.dart must name the getter the config file actually declares',
  );
}

/// Default option map mirroring the parsed CLI surface for non-interactive runs.
Map<String, dynamic> _options(Map<String, dynamic> overrides) =>
    <String, dynamic>{
      'force': false,
      'dry-run': false,
      'non-interactive': true,
      'no-bootstrap': false,
      'app-id': null,
      'platforms': null,
      'no-soft-prompt': false,
      'safari-web-id': null,
      'notify-button': false,
      ...overrides,
    };

/// Builds an [ArtisanContext] backed by a [MapInput] + [BufferedOutput].
ArtisanContext _ctx(_TestInstallCommand cmd, Map<String, dynamic> overrides) =>
    ArtisanContext.bare(
      MapInput(_options(overrides), signature: cmd.parsedSignature),
      BufferedOutput(),
    );

void main() {
  late Directory tempDir;
  late _TestInstallCommand command;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('magic_notifications_test_');
    command = _TestInstallCommand(tempDir.path);

    File('${tempDir.path}/pubspec.yaml').writeAsStringSync('''
name: test_app
dependencies:
  flutter:
    sdk: flutter
''');

    Directory('${tempDir.path}/lib/config').createSync(recursive: true);

    File('${tempDir.path}/lib/config/app.dart').writeAsStringSync('''
import 'package:magic/magic.dart';

final appConfig = {
  'providers': [
    (app) => RouteServiceProvider(app),
  ],
};
''');

    File('${tempDir.path}/lib/main.dart').writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
}
''');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('InstallCommand metadata', () {
    test('extends ArtisanInstallCommand and carries the base flags', () {
      expect(command, isA<ArtisanInstallCommand>());
      expect(command.signature, contains('--force'));
      expect(command.signature, contains('--dry-run'));
      expect(command.signature, contains('--non-interactive'));
      expect(
          command.pluginName(_ctx(command, const {})), 'magic_notifications');
    });

    test('validateOneSignalAppId accepts valid UUID, rejects garbage', () {
      expect(
        command.validateOneSignalAppId('12345678-1234-1234-1234-123456789012'),
        isTrue,
      );
      expect(command.validateOneSignalAppId('invalid-uuid'), isFalse);
    });
  });

  group('InstallCommand non-interactive', () {
    test('fails fast on missing app-id', () async {
      final exit = await command.handle(_ctx(command, const {}));
      expect(exit, 1);
    });

    test('fails fast on malformed app-id BEFORE staging any op', () async {
      final exit = await command.handle(
        _ctx(command, const {'app-id': 'not-a-uuid'}),
      );
      expect(exit, 1);
      // No config file written, no provider injected: the UUID guard short
      // circuits before the installer stages anything.
      expect(
        File('${tempDir.path}/lib/config/notifications.dart').existsSync(),
        isFalse,
      );
      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      expect(appContent, isNot(contains('NotificationServiceProvider')));
    });

    test('creates config + injects provider + configFactory on fresh install',
        () async {
      final exit = await command.handle(
        _ctx(command, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
          'platforms': 'android,ios',
          'force': true,
        }),
      );
      expect(exit, 0);

      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      expect(File(configPath).existsSync(), isTrue);
      final configContent = File(configPath).readAsStringSync();
      expect(configContent, contains('12345678-1234-1234-1234-123456789012'));
      expect(configContent, contains("'notify_button_enabled': false"));
      expect(configContent, contains("'enabled': true")); // soft prompt

      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      expect(
        appContent,
        contains(
          "import 'package:magic_notifications/magic_notifications.dart';",
        ),
      );
      expect(
          appContent, contains('(app) => NotificationServiceProvider(app),'));

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainContent, contains("import 'config/notifications.dart';"));
      expect(mainContent, contains('() => notificationConfig,'));
    });

    test('does not overwrite existing config without force', () async {
      final configPath = '${tempDir.path}/lib/config/notifications.dart';
      File(configPath).writeAsStringSync('existing-content');

      final exit = await command.handle(
        _ctx(command, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
        }),
      );
      expect(exit, 0);
      expect(File(configPath).readAsStringSync(), 'existing-content');
    });

    test('adds POST_NOTIFICATIONS permission when android selected', () async {
      Directory('${tempDir.path}/android/app/src/main')
          .createSync(recursive: true);
      File('${tempDir.path}/android/app/src/main/AndroidManifest.xml')
          .writeAsStringSync('''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:label="test_app"></application>
</manifest>
''');

      final exit = await command.handle(
        _ctx(command, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
          'platforms': 'android',
          'force': true,
        }),
      );
      expect(exit, 0);

      final manifest =
          File('${tempDir.path}/android/app/src/main/AndroidManifest.xml')
              .readAsStringSync();
      expect(manifest, contains('android.permission.POST_NOTIFICATIONS'));
    });

    test('creates web worker + injects SDK script when web selected', () async {
      Directory('${tempDir.path}/web').createSync();
      File('${tempDir.path}/web/index.html')
          .writeAsStringSync('<html><head></head><body></body></html>');

      final exit = await command.handle(
        _ctx(command, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
          'platforms': 'web',
          'safari-web-id': 'web.onesignal.auto.123',
          'force': true,
        }),
      );
      expect(exit, 0);

      final workerPath = '${tempDir.path}/web/OneSignalSDKWorker.js';
      expect(File(workerPath).existsSync(), isTrue);
      expect(
        File(workerPath).readAsStringSync(),
        contains(
          'importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");',
        ),
      );

      final indexContent =
          File('${tempDir.path}/web/index.html').readAsStringSync();
      expect(indexContent, contains('OneSignalSDK.page.js'));

      final configContent =
          File('${tempDir.path}/lib/config/notifications.dart')
              .readAsStringSync();
      expect(
        configContent,
        contains("'safari_web_id': 'web.onesignal.auto.123'"),
      );
    });

    test('does not inject web script when web is NOT selected', () async {
      Directory('${tempDir.path}/web').createSync();
      File('${tempDir.path}/web/index.html')
          .writeAsStringSync('<html><head></head><body></body></html>');

      final exit = await command.handle(
        _ctx(command, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
          'platforms': 'android',
          'force': true,
        }),
      );
      expect(exit, 0);

      // Web deselected: no worker, no head script (manifest prompts would have
      // run unconditionally; the override gates web setup on platform choice).
      expect(
        File('${tempDir.path}/web/OneSignalSDKWorker.js').existsSync(),
        isFalse,
      );
      final indexContent =
          File('${tempDir.path}/web/index.html').readAsStringSync();
      expect(indexContent, isNot(contains('OneSignalSDK.page.js')));
    });

    test('re-running web install is idempotent (no double script)', () async {
      Directory('${tempDir.path}/web').createSync();
      File('${tempDir.path}/web/index.html')
          .writeAsStringSync('<html><head></head><body></body></html>');

      const opts = {
        'app-id': '12345678-1234-1234-1234-123456789012',
        'platforms': 'web',
        'force': true,
      };

      expect(await command.handle(_ctx(command, opts)), 0);
      // A fresh command instance: installers are one-shot.
      final second = _TestInstallCommand(tempDir.path);
      expect(await second.handle(_ctx(second, opts)), 0);

      final indexContent =
          File('${tempDir.path}/web/index.html').readAsStringSync();
      final scriptCount =
          'OneSignalSDK.page.js'.allMatches(indexContent).length;
      expect(scriptCount, 1, reason: 'head script must be injected only once');
    });

    test('re-running provider inject is idempotent (no double provider)',
        () async {
      const opts = {
        'app-id': '12345678-1234-1234-1234-123456789012',
        'platforms': 'android',
        'force': true,
      };

      expect(await command.handle(_ctx(command, opts)), 0);
      final second = _TestInstallCommand(tempDir.path);
      expect(await second.handle(_ctx(second, opts)), 0);

      final appContent =
          File('${tempDir.path}/lib/config/app.dart').readAsStringSync();
      final providerCount =
          'NotificationServiceProvider(app)'.allMatches(appContent).length;
      expect(providerCount, 1, reason: 'provider must be injected only once');
    });
  });

  group('InstallCommand main.dart wiring', () {
    /// Runs a fresh non-interactive android install (no --force, so an existing
    /// config file is left exactly as the project wrote it).
    Future<ArtisanContext> installAndroid() async {
      final fresh = _TestInstallCommand(tempDir.path);
      final ctx = _ctx(fresh, const {
        'app-id': '12345678-1234-1234-1234-123456789012',
        'platforms': 'android',
      });
      expect(await fresh.handle(ctx), 0);
      return ctx;
    }

    test('appends the getter the existing config declares, not the stub name',
        () async {
      _writeHandWrittenConfig(tempDir, 'notificationsConfig');

      await installAndroid();

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(mainContent, contains("import 'config/notifications.dart';"));
      expect(
        mainContent,
        contains('() => notificationsConfig,'),
        reason: 'the factory must name the getter the config actually declares',
      );
      expect(
        mainContent,
        isNot(contains('() => notificationConfig,')),
        reason: 'the stub getter name does not exist in this project',
      );
    });

    test('a project already wired is untouched whatever the getter is called',
        () async {
      _writeHandWrittenConfig(tempDir, 'notificationsConfig');
      final mainPath = '${tempDir.path}/lib/main.dart';
      File(mainPath).writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';
import 'config/notifications.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationsConfig,
    ],
  );
}
''');
      final before = File(mainPath).readAsStringSync();

      await installAndroid();

      expect(File(mainPath).readAsStringSync(), before);
    });

    test('a config declaring no getter is skipped rather than guessed at',
        () async {
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync(
        '// Hand-rolled: this file declares nothing the installer can name.\n'
        'const int placeholder = 1;\n',
      );

      final ctx = await installAndroid();

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(
        mainContent,
        isNot(contains('config/notifications.dart')),
        reason: 'a wrong symbol is worse than a missing one',
      );
      expect(
        (ctx.output as BufferedOutput).content,
        contains('lib/config/notifications.dart'),
        reason: 'the operator has to be told main.dart was left alone',
      );
    });

    test('a commented-out import does not read as already wired', () async {
      _writeHandWrittenConfig(tempDir, 'notificationsConfig');
      final mainPath = '${tempDir.path}/lib/main.dart';
      File(mainPath).writeAsStringSync('''
import 'package:magic/magic.dart';
import 'config/app.dart';
// import 'config/notifications.dart';

void main() async {
  await Magic.init(
    configFactories: [
      () => appConfig,
    ],
  );
}
''');

      await installAndroid();

      expect(
        File(mainPath).readAsStringSync(),
        contains('() => notificationsConfig,'),
      );
    });
  });

  group('InstallCommand --force config regeneration', () {
    /// Runs a fresh non-interactive android install with `--force`, which
    /// rewrites `lib/config/notifications.dart` from the stub.
    Future<ArtisanContext> forceInstall() async {
      final fresh = _TestInstallCommand(tempDir.path);
      final ctx = _ctx(fresh, const {
        'app-id': '12345678-1234-1234-1234-123456789012',
        'platforms': 'android',
        'force': true,
      });
      expect(await fresh.handle(ctx), 0);
      return ctx;
    }

    test('re-points an already-wired main.dart at the regenerated getter',
        () async {
      _writeHandWrittenConfig(tempDir, 'notificationsConfig');
      _writeWiredMain(tempDir, 'notificationsConfig');

      await forceInstall();

      final mainContent =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      expect(
        mainContent,
        contains('() => notificationConfig,'),
        reason: '--force regenerated the config, so the wiring follows it',
      );
      expect(
        mainContent,
        isNot(contains('() => notificationsConfig,')),
        reason: 'the old getter no longer exists anywhere in the project',
      );
      _expectMainNamesTheDeclaredGetter(tempDir);
    });

    test('holds the invariant when main.dart was never wired', () async {
      _writeHandWrittenConfig(tempDir, 'notificationsConfig');

      await forceInstall();

      _expectMainNamesTheDeclaredGetter(tempDir);
    });

    test('holds the invariant on a fresh project', () async {
      await forceInstall();

      _expectMainNamesTheDeclaredGetter(tempDir);
    });

    test('re-running --force changes nothing once the names agree', () async {
      _writeHandWrittenConfig(tempDir, 'notificationsConfig');
      _writeWiredMain(tempDir, 'notificationsConfig');

      await forceInstall();
      final afterFirst =
          File('${tempDir.path}/lib/main.dart').readAsStringSync();
      await forceInstall();

      expect(
          File('${tempDir.path}/lib/main.dart').readAsStringSync(), afterFirst);
      _expectMainNamesTheDeclaredGetter(tempDir);
    });

    test('leaves a wired main.dart alone when the old getter is unreadable',
        () async {
      Directory('${tempDir.path}/lib/config').createSync(recursive: true);
      File('${tempDir.path}/lib/config/notifications.dart').writeAsStringSync(
        '// Hand-rolled: this file declares nothing the installer can name.\n'
        'const int placeholder = 1;\n',
      );
      _writeWiredMain(tempDir, 'somethingElse');
      final before = File('${tempDir.path}/lib/main.dart').readAsStringSync();

      final ctx = await forceInstall();

      expect(
        File('${tempDir.path}/lib/main.dart').readAsStringSync(),
        before,
        reason: 'the name to replace is unknowable, and guessing is what '
            'broke the project in the first place',
      );
      expect(
        (ctx.output as BufferedOutput).content,
        contains('lib/main.dart'),
        reason: 'the operator has to be told the wiring needs a hand fix',
      );
    });

    test('does not touch main.dart when the config was left in place',
        () async {
      _writeHandWrittenConfig(tempDir, 'notificationsConfig');
      _writeWiredMain(tempDir, 'notificationsConfig');
      final before = File('${tempDir.path}/lib/main.dart').readAsStringSync();

      final fresh = _TestInstallCommand(tempDir.path);
      expect(
        await fresh.handle(_ctx(fresh, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
          'platforms': 'android',
        })),
        0,
      );

      expect(File('${tempDir.path}/lib/main.dart').readAsStringSync(), before);
      _expectMainNamesTheDeclaredGetter(tempDir);
    });
  });

  group('InstallCommand iOS', () {
    /// Runs a fresh non-interactive install for the ios platform.
    Future<int> installIos() {
      final fresh = _TestInstallCommand(tempDir.path);
      return fresh.handle(_ctx(fresh, const {
        'app-id': '12345678-1234-1234-1234-123456789012',
        'platforms': 'ios',
        'force': true,
      }));
    }

    test('writes the background mode, the entitlement and the build setting',
        () async {
      _writeIosProject(tempDir);

      expect(await installIos(), 0);

      final plist =
          File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<key>UIBackgroundModes</key>'));
      expect(plist, contains('<string>remote-notification</string>'));

      final entitlements =
          File('${tempDir.path}/ios/Runner/Runner.entitlements');
      expect(entitlements.existsSync(), isTrue,
          reason: 'the entitlements file is created when absent');
      expect(entitlements.readAsStringSync(),
          contains('<key>aps-environment</key>'));
      expect(entitlements.readAsStringSync(),
          contains('<string>development</string>'));

      final release =
          File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements');
      expect(release.existsSync(), isTrue,
          reason: 'the Release twin is created alongside the development one');
      expect(
          release.readAsStringSync(), contains('<string>production</string>'),
          reason: 'a distribution profile carries only production');

      final pbxproj =
          File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
              .readAsStringSync();
      expect(
        'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
            .allMatches(pbxproj)
            .length,
        1,
        reason: 'Debug only: Release moved to the twin, and RunnerTests signs '
            'nothing',
      );
      expect(
        'CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements;'
            .allMatches(pbxproj)
            .length,
        1,
        reason: 'the one configuration that ships',
      );
      expect(
        pbxproj,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.app.RunnerTests;\n'
            '\t\t\t};'),
        reason: 'the test bundle keeps its single build setting',
      );
    });

    test('keeps background modes the app already declares', () async {
      _writeIosProject(tempDir, backgroundModes: const ['fetch']);

      expect(await installIos(), 0);

      final plist =
          File('${tempDir.path}/ios/Runner/Info.plist').readAsStringSync();
      expect(plist, contains('<string>fetch</string>'),
          reason: 'replacing the array would drop an unrelated mode');
      expect(plist, contains('<string>remote-notification</string>'));
    });

    test('re-running the iOS install changes nothing', () async {
      _writeIosProject(tempDir);
      expect(await installIos(), 0);

      final plistPath = '${tempDir.path}/ios/Runner/Info.plist';
      final pbxprojPath =
          '${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj';
      final plistAfterFirst = File(plistPath).readAsStringSync();
      final pbxprojAfterFirst = File(pbxprojPath).readAsStringSync();

      expect(await installIos(), 0);

      expect(File(plistPath).readAsStringSync(), plistAfterFirst);
      expect(File(pbxprojPath).readAsStringSync(), pbxprojAfterFirst);
    });

    test('turns the doctor iOS row from red to green', () async {
      _writeIosProject(tempDir);
      final health = _TestDoctorCommand(tempDir.path);

      final before = health.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(before['configured'], isFalse,
          reason: 'a project nobody installed into must read red');
      expect(before['issues'], hasLength(3));

      expect(await installIos(), 0);

      final after = health.checkPlatformSetup()['ios'] as Map<String, dynamic>;
      expect(after['issues'], isEmpty);
      expect(after['configured'], isTrue);
    });

    test('leaves the doctor with nothing to say about the APNs environment',
        () async {
      // The acceptance criterion for the split, and the one the red-to-green
      // test above cannot carry: the APNs check reports through the WARNING
      // channel by design, so a project with the wrong Release entitlement has
      // no ISSUES and reads as configured. Before this command wrote the
      // split, this was the state every install left behind, and the doctor
      // has named it on every project since 0.3.0.
      _writeIosProject(tempDir);
      final health = _TestDoctorCommand(tempDir.path);

      expect(await installIos(), 0);

      expect(health.apsEnvironmentWarnings(), isEmpty);

      // And the instrument is reading THIS project rather than answering
      // empty because it understood nothing: an unreadable pbxproj returns
      // the same empty list, so silence alone proves nothing. Breaking the
      // value the install just wrote has to bring the warning back.
      final twin =
          File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements');
      twin.writeAsStringSync(
        twin.readAsStringSync().replaceFirst('production', 'development'),
      );

      expect(
        health.apsEnvironmentWarnings(),
        contains(contains('Release')),
        reason: 'the check can see this project, so the silence above counts',
      );
    });

    test('writes the split for a flavoured project', () async {
      // Flutter flavours append the flavour to the base name, so the
      // configurations are `Release-production` and siblings and a map keyed
      // on a bare `Release` matches nothing. `setEntitlementsPaths` THROWS on
      // that rather than reporting success, so addressing them by base name is
      // what keeps the command from declining the project outright.
      _writeIosProject(tempDir, configurationSuffix: '-production');

      expect(await installIos(), 0);

      final pbxproj =
          File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
              .readAsStringSync();
      expect(
        'CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements;'
            .allMatches(pbxproj)
            .length,
        1,
        reason: 'Release-production signs with a distribution profile too',
      );
      expect(
        File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements')
            .readAsStringSync(),
        contains('<string>production</string>'),
      );
    });

    test('carries every other entitlement into the Release twin', () async {
      // The twin is a copy rather than a fresh minimal plist. A project that
      // already carries associated domains would otherwise lose them on the
      // one build that ships, which is the same silent class of failure the
      // aps-environment split exists to close.
      _writeIosProject(tempDir);
      File('${tempDir.path}/ios/Runner/Runner.entitlements').writeAsStringSync(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0">\n'
        '<dict>\n'
        '\t<key>com.apple.developer.associated-domains</key>\n'
        '\t<array>\n'
        '\t\t<string>applinks:example.com</string>\n'
        '\t</array>\n'
        '</dict>\n'
        '</plist>\n',
      );

      expect(await installIos(), 0);

      final twin = File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements')
          .readAsStringSync();
      expect(twin, contains('applinks:example.com'),
          reason: 'every other key is identical between the two');
      expect(twin, contains('<string>production</string>'));
    });

    test('never overwrites a Release twin somebody already wrote', () async {
      // An adopter who split the file by hand is the person this is helping,
      // and their file may carry more than this command knows about.
      _writeIosProject(tempDir);
      final twin =
          File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements');
      twin.writeAsStringSync(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
        '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0">\n'
        '<dict>\n'
        '\t<key>keychain-access-groups</key>\n'
        '\t<array>\n'
        '\t\t<string>\$(AppIdentifierPrefix)com.example.app</string>\n'
        '\t</array>\n'
        '</dict>\n'
        '</plist>\n',
      );

      expect(await installIos(), 0);

      final after = twin.readAsStringSync();
      expect(after, contains('keychain-access-groups'),
          reason: 'the file is kept, not replaced');
      expect(after, contains('<string>production</string>'),
          reason: 'and only the one key is ensured');
    });

    test('reports rather than dies on a pbxproj the parser refuses', () async {
      // The transaction has already committed by the time the entitlements
      // are pointed, so an exception escaping here turns a project that
      // installed correctly into a stack trace and a non-zero exit, with the
      // post-install steps never printed. The editor's round-trip guard is
      // one `\U00e7` escape away on any project with a non-ASCII product
      // name, which is not an exotic shape in this codebase's own language.
      _writeIosProject(tempDir);
      final pbxproj =
          File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj');
      pbxproj.writeAsStringSync(pbxproj.readAsStringSync().replaceFirst(
          'productType = "com.apple.product-type.application";',
          'productName = "\\U00e7ekirdek";\n\t\t\tproductType = "com.apple.product-type.application";'));

      expect(await installIos(), 0, reason: 'the install itself succeeded');

      expect(
        File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements')
            .existsSync(),
        isTrue,
        reason: 'both files are still written, so the remedy is one setting',
      );
    });

    test('reports rather than dies on an entitlements file it cannot read',
        () async {
      // The same post-commit hazard as the pbxproj one, a step earlier and
      // missed by two reviews before this. `PlistWriter` throws `StateError`
      // on a plist with no root <dict> and an XmlParserException (a
      // FormatException) on one that does not parse, and a hand-edited
      // entitlements file is both of those shapes away from ordinary. The
      // staged op this replaced got this guarantee for free from the
      // transaction dispatcher.
      _writeIosProject(tempDir);
      File('${tempDir.path}/ios/Runner/Runner.entitlements')
          .writeAsStringSync('<?xml version="1.0" encoding="UTF-8"?>\n'
              '<plist version="1.0">\n<array/>\n</plist>\n');

      expect(await installIos(), 0, reason: 'the install itself succeeded');
    });

    test('leaves a project that already points elsewhere alone', () async {
      // The state of EVERY project a previous version of this installer
      // touched, and the population the doctor has been flagging since 0.3.0.
      // `setEntitlementsPaths` is all-or-nothing across the configurations it
      // is asked about, so nothing moves and the command has to say so.
      _writeIosProject(tempDir);
      final pbxproj =
          File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj');
      pbxproj.writeAsStringSync(pbxproj.readAsStringSync().replaceAll(
          'PRODUCT_BUNDLE_IDENTIFIER = com.example.app;',
          'CODE_SIGN_ENTITLEMENTS = Runner/Custom.entitlements;\n'
              '\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.example.app;'));
      final before = pbxproj.readAsStringSync();

      expect(await installIos(), 0);

      expect(pbxproj.readAsStringSync(), before,
          reason: 'not one build setting moved');
      expect(
        File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements')
            .readAsStringSync(),
        contains('<string>production</string>'),
        reason: 'the file is still written, so pointing it is one edit',
      );
    });

    test('an absent ios/ directory is skipped rather than failing', () async {
      expect(await installIos(), 0);
      expect(
        File('${tempDir.path}/ios/Runner/Runner.entitlements').existsSync(),
        isFalse,
      );
    });
  });

  group('InstallCommand banner', () {
    test('prints the version pubspec.yaml declares', () async {
      final pubspec =
          File('${Directory.current.path}/pubspec.yaml').readAsStringSync();
      final declared =
          RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec);
      expect(declared, isNotNull, reason: 'pubspec.yaml declares a version');
      expect(magicNotificationsVersion, declared!.group(1));

      final ctx = _ctx(command, const {
        'app-id': '12345678-1234-1234-1234-123456789012',
        'platforms': 'android',
        'force': true,
      });
      await command.handle(ctx);
      expect(
        (ctx.output as BufferedOutput).content,
        contains('Magic Notifications v$magicNotificationsVersion'),
      );
    });
  });

  group('InstallCommand web service worker', () {
    test('scopes the OneSignal worker away from the Flutter root worker',
        () async {
      Directory('${tempDir.path}/web').createSync();
      File('${tempDir.path}/web/index.html')
          .writeAsStringSync('<html><head></head><body></body></html>');

      final exit = await command.handle(
        _ctx(command, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
          'platforms': 'web',
          'force': true,
        }),
      );
      expect(exit, 0);

      final config = File('${tempDir.path}/lib/config/notifications.dart')
          .readAsStringSync();
      expect(
          config, contains("'service_worker_path': 'OneSignalSDKWorker.js'"));
      expect(config, contains("'service_worker_scope': '/onesignal/'"));
    });
  });

  group('InstallCommand dry-run', () {
    test('dry-run writes nothing to disk', () async {
      Directory('${tempDir.path}/web').createSync();
      File('${tempDir.path}/web/index.html')
          .writeAsStringSync('<html><head></head><body></body></html>');

      final exit = await command.handle(
        _ctx(command, const {
          'app-id': '12345678-1234-1234-1234-123456789012',
          'platforms': 'web',
          'dry-run': true,
        }),
      );
      expect(exit, 0);

      // No transactional write landed: config + worker absent.
      expect(
        File('${tempDir.path}/lib/config/notifications.dart').existsSync(),
        isFalse,
      );
      expect(
        File('${tempDir.path}/web/OneSignalSDKWorker.js').existsSync(),
        isFalse,
      );
    });
  });
}
