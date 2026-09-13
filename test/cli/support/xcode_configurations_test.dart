import 'dart:io';

import 'package:magic_notifications/src/cli/support/xcode_configurations.dart';
import 'package:test/test.dart';

/// A pbxproj carrying an object whose id is NOT 24 hex, holding a file
/// reference in a `children = ( ... )` array.
///
/// Modelled on a real project, where that shape is what a widened object
/// scanner over-matches on: it starts a match at the array item, runs forward
/// to the next `*/ ... = {`, and swallows every object in between (39 objects
/// found where there are 45, the application target among the missing).
///
/// **This fixture does not reproduce that**, measured rather than assumed:
/// both the shipped regex and a fully widened one read the same four objects
/// out of it, because reproducing the over-match also needs a closing brace at
/// the array item's own indent further down, which no small fixture has
/// without being built solely to have one. What justifies the shipped anchor
/// is the measurement in `xcode_configurations.dart`, not this test. What this
/// test covers is the walk's contract: which objects are configurations, what
/// each signs against, and the two shapes that answer empty.
const String _pbxprojWithAnArrayItem = '''
// !\$*UTF8*\$!
{
	objects = {
		LOCALIZATIONGRP01A2B3C4D5E6F /* Localization */ = {
			isa = PBXGroup;
			children = (
				6EA189DAD2FC954E2AA5B6B5 /* Localizable.xcstrings */,
			);
		};
		97C146ED1CF9000F007C117D /* Runner */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 97C147051CF9000F007C117D /* list */;
			name = Runner;
		};
		97C147051CF9000F007C117D /* list */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				97C147061CF9000F007C117D /* Debug */,
				97C147071CF9000F007C117D /* Release */,
			);
		};
		97C147061CF9000F007C117D /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;
			};
			name = Debug;
		};
		97C147071CF9000F007C117D /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements;
			};
			name = Release;
		};
	};
}
''';

void main() {
  late Directory tempDir;
  late String pbxproj;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('xcode_configurations_');
    pbxproj = '${tempDir.path}/project.pbxproj';
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('XcodeConfigurations.read', () {
    test('is not derailed by an id-less object holding a file reference', () {
      // The discriminating fixture. A comment pattern that may cross lines
      // starts matching at the `children = (` array item above, runs to the
      // next `*/ ... = {`, and takes the Runner target and its configurations
      // with it. Measured on a real project first: the loose form found 39
      // objects where there are 45.
      File(pbxproj).writeAsStringSync(_pbxprojWithAnArrayItem);

      final configurations = XcodeConfigurations.read(pbxproj);

      expect(configurations.map((c) => c.name), ['Debug', 'Release']);
      expect(
        configurations.firstWhere((c) => c.name == 'Release').entitlements,
        'Runner/RunnerRelease.entitlements',
      );
    });

    test('returns empty for a file it cannot walk', () {
      File(pbxproj).writeAsStringSync('{ objects = { }; }');

      expect(XcodeConfigurations.read(pbxproj), isEmpty);
    });

    test('returns empty for a file that is not there', () {
      expect(
          XcodeConfigurations.read('${tempDir.path}/absent.pbxproj'), isEmpty);
    });
  });

  group('XcodeConfigurations.baseNameOf', () {
    test('reads the three bare names', () {
      expect(XcodeConfigurations.baseNameOf('Debug'), 'Debug');
      expect(XcodeConfigurations.baseNameOf('Profile'), 'Profile');
      expect(XcodeConfigurations.baseNameOf('Release'), 'Release');
    });

    test('reads a flavour by its base name', () {
      // The shape Flutter's own documentation prescribes.
      expect(XcodeConfigurations.baseNameOf('Release-production'), 'Release');
      expect(XcodeConfigurations.baseNameOf('Debug-staging'), 'Debug');
    });

    test('declines a name that merely starts with one', () {
      // The hyphen is what keeps the match tight: a ReleaseCandidate is not a
      // Release, and judging it as one would point a configuration nobody
      // said signs with a distribution profile at the production entitlement.
      expect(XcodeConfigurations.baseNameOf('ReleaseCandidate'), isNull);
      expect(XcodeConfigurations.baseNameOf('Staging'), isNull);
    });
  });
}
