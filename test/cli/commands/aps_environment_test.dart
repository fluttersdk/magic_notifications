import 'dart:io';

import 'package:magic_notifications/src/cli/commands/doctor_command.dart';
import 'package:test/test.dart';

/// Test double that overrides [getProjectRoot] to use a temp directory,
/// mirroring `doctor_command_test.dart`'s.
class _TestDoctorCommand extends DoctorCommand {
  final String _root;

  _TestDoctorCommand(this._root);

  @override
  String getProjectRoot() => _root;
}

/// A pbxproj with the shape Xcode actually writes: a `PBXNativeTarget` named
/// Runner pointing at an `XCConfigurationList`, which names the three
/// configurations, each with its own build settings.
///
/// Spelled out rather than trimmed to the fields under test, because the walk
/// this exercises navigates target to list to configuration precisely so it
/// cannot be fooled by the `RunnerTests` target, whose configurations are also
/// called Debug and Release. That target is here for the same reason.
String _pbxproj({
  required String debugEntitlements,
  required String releaseEntitlements,
  String profileEntitlements = 'Runner/Runner.entitlements',
}) =>
    '''
// !\$*UTF8*\$!
{
	objects = {

		97C146ED1CF9000F007C117D /* Runner */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget "Runner" */;
			name = Runner;
			productName = Runner;
		};
		331C8080294A63A400263BE5 /* RunnerTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 331C8087294A63A400263BE5 /* Build configuration list for PBXNativeTarget "RunnerTests" */;
			name = RunnerTests;
			productName = RunnerTests;
		};
		97C147051CF9000F007C117D /* Build configuration list for PBXNativeTarget "Runner" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				97C147061CF9000F007C117D /* Debug */,
				97C147071CF9000F007C117D /* Release */,
				249021D4217E4FDB00AE95B9 /* Profile */,
			);
		};
		331C8087294A63A400263BE5 /* Build configuration list for PBXNativeTarget "RunnerTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				331C8088294A63A400263BE5 /* Debug */,
			);
		};
		97C147061CF9000F007C117D /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = $debugEntitlements;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
			};
			name = Debug;
		};
		97C147071CF9000F007C117D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = $releaseEntitlements;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
			};
			name = Release;
		};
		249021D4217E4FDB00AE95B9 /* Profile */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = $profileEntitlements;
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app;
			};
			name = Profile;
		};
		331C8088294A63A400263BE5 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				PRODUCT_BUNDLE_IDENTIFIER = com.example.app.RunnerTests;
			};
			name = Debug;
		};
	};
}
''';

String _entitlements(String apsEnvironment) => '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>aps-environment</key>
	<string>$apsEnvironment</string>
</dict>
</plist>
''';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('aps_env_test_');
    Directory('${tempDir.path}/ios/Runner').createSync(recursive: true);
    Directory('${tempDir.path}/ios/Runner.xcodeproj')
        .createSync(recursive: true);
    File('${tempDir.path}/ios/Runner/Info.plist').writeAsStringSync('''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>UIBackgroundModes</key>
	<array>
		<string>remote-notification</string>
	</array>
</dict>
</plist>
''');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// The `[ios]` prefixed entries of the doctor's missing-requirement list,
  /// reached the way `doctor_command_test.dart` reaches them.
  List<String> iosIssues() => _TestDoctorCommand(tempDir.path)
      .getMissingRequirements()
      .where((issue) => issue.startsWith('[ios]'))
      .toList();

  group('the APNs environment each configuration signs against', () {
    test('names Release when one entitlements file serves every build', () {
      // What `notifications:install` produces today, and what every adopter has
      // until somebody splits it by hand. Debug and Profile are right; Release
      // is the one that ships and it is wrong.
      File('${tempDir.path}/ios/Runner/Runner.entitlements')
          .writeAsStringSync(_entitlements('development'));
      File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
          .writeAsStringSync(_pbxproj(
        debugEntitlements: 'Runner/Runner.entitlements',
        releaseEntitlements: 'Runner/Runner.entitlements',
      ));

      final issues = iosIssues();

      expect(issues, hasLength(1));
      expect(issues.single, contains('Release configuration'));
      expect(issues.single, contains('development'));
      expect(issues.single, contains('production'));
    });

    test('is silent on a project that has split the file', () {
      File('${tempDir.path}/ios/Runner/Runner.entitlements')
          .writeAsStringSync(_entitlements('development'));
      File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements')
          .writeAsStringSync(_entitlements('production'));
      File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
          .writeAsStringSync(_pbxproj(
        debugEntitlements: 'Runner/Runner.entitlements',
        releaseEntitlements: 'Runner/RunnerRelease.entitlements',
      ));

      expect(iosIssues(), isEmpty);
    });

    test('names Debug when the split is wired the wrong way round', () {
      // The mirror image, and the one that breaks a device build rather than a
      // release: a development profile does not carry the production value
      // either.
      File('${tempDir.path}/ios/Runner/Runner.entitlements')
          .writeAsStringSync(_entitlements('production'));
      File('${tempDir.path}/ios/Runner/RunnerRelease.entitlements')
          .writeAsStringSync(_entitlements('development'));
      File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
          .writeAsStringSync(_pbxproj(
        debugEntitlements: 'Runner/Runner.entitlements',
        releaseEntitlements: 'Runner/RunnerRelease.entitlements',
        profileEntitlements: 'Runner/Runner.entitlements',
      ));

      final issues = iosIssues();

      expect(issues, hasLength(3));
      expect(issues.where((i) => i.contains('Debug')), hasLength(1));
      expect(issues.where((i) => i.contains('Profile')), hasLength(1));
      expect(issues.where((i) => i.contains('Release')), hasLength(1));
    });

    test('reports an entitlements file a configuration names and does not have',
        () {
      File('${tempDir.path}/ios/Runner/Runner.entitlements')
          .writeAsStringSync(_entitlements('development'));
      File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
          .writeAsStringSync(_pbxproj(
        debugEntitlements: 'Runner/Runner.entitlements',
        releaseEntitlements: 'Runner/RunnerRelease.entitlements',
      ));

      expect(
        iosIssues().single,
        allOf(
            contains('RunnerRelease.entitlements'), contains('does not exist')),
      );
    });

    test('stays silent on a pbxproj whose shape it does not recognise', () {
      // A doctor that guesses at an unfamiliar project reports a fault that is
      // not there. The two older checks already cover the file being missing.
      File('${tempDir.path}/ios/Runner/Runner.entitlements')
          .writeAsStringSync(_entitlements('development'));
      File('${tempDir.path}/ios/Runner.xcodeproj/project.pbxproj')
          .writeAsStringSync('{ objects = { }; }');

      expect(
        iosIssues().where((i) => i.contains('configuration signs against')),
        isEmpty,
      );
    });
  });
}
