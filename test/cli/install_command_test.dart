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
const String _pbxproj = r'''// !$*UTF8*$!
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
        97C147061CF9000F007C117D /* Debug */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
            };
            name = Debug;
        };
        97C147071CF9000F007C117D /* Release */ = {
            isa = XCBuildConfiguration;
            buildSettings = {
                PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
            };
            name = Release;
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
                97C147061CF9000F007C117D /* Debug */,
                97C147071CF9000F007C117D /* Release */,
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
    {List<String> backgroundModes = const []}) {
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
      .writeAsStringSync(_pbxproj);
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

      final pbxproj =
          File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
              .readAsStringSync();
      expect(
        'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
            .allMatches(pbxproj)
            .length,
        2,
        reason: 'both Runner configurations, and neither RunnerTests one',
      );
      expect(
        pbxproj,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.app.RunnerTests;\n'
            '            };'),
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
