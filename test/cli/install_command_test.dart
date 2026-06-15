import 'dart:io';

import 'package:fluttersdk_artisan/artisan.dart';
import 'package:magic_notifications/src/cli/commands/install_command.dart'
    as mn;
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
