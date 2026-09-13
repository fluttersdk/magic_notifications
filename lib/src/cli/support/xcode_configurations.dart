import 'package:fluttersdk_artisan/artisan.dart';

/// One build configuration of the Flutter application target, and the
/// entitlements file it signs against when it names one.
typedef XcodeConfiguration = ({String name, String? entitlements});

/// Reads the Runner target's build configurations out of a `project.pbxproj`.
///
/// Two commands need this and they need different halves of it, which is why
/// it answers with every configuration rather than only the interesting ones.
/// `notifications:doctor` wants the ones that already name an entitlements
/// file, so it can judge the APNs environment each one carries.
/// `notifications:install` wants the NAMES, including of configurations that
/// name no file yet, because that is the state of a project it has not
/// touched and it has to address them to write the split.
///
/// Walked structurally, target to configuration list to configuration, rather
/// than searched: the project holds a second target (`RunnerTests`) whose
/// configurations are also called Debug and Release and which signs nothing,
/// so a global match reads the wrong ones.
///
/// Returns empty rather than throwing when the shape is not the one this walk
/// knows. Both callers treat that as "not recognised" and decline to act,
/// which is the only honest answer about a project this cannot read.
abstract final class XcodeConfigurations {
  /// The build setting naming a configuration's entitlements file.
  static const String entitlementsSetting = 'CODE_SIGN_ENTITLEMENTS';

  /// Every build configuration of the Runner target, in project order.
  static List<XcodeConfiguration> read(String pbxprojPath) {
    if (!FileHelper.fileExists(pbxprojPath)) return const [];

    final String source = FileHelper.readFile(pbxprojPath);

    // One object inside `objects = { ... }`: a 24-hex id, an optional
    // /* comment */, then a brace-delimited body at Xcode's two tabs of
    // indent. Measured before pinning it: all 723 `project.pbxproj` files on
    // this machine indent that way, so the strict anchor costs nothing real.
    //
    // The comment is confined to ONE line, which matters whatever the anchor.
    // The hazard is not a nested `buildSettings = {`, which carries no id: it
    // is an array item like `<24hex> /* Localizable.xcstrings */,` inside an
    // object whose OWN id is not 24 hex, so nothing has consumed it. With a
    // `.*?` comment a match starting there runs forward to some later `*/ = {`
    // and swallows every object in between. Measured on a real project that
    // does exactly that: 39 objects found where there are 45, the application
    // target among the missing.
    final Map<String, String> objects = {
      for (final RegExpMatch match in RegExp(
        r'^\t\t([0-9A-Fa-f]{24})(?: /\* [^\n]*? \*/)? = \{(.*?)^\t\t\};$',
        dotAll: true,
        multiLine: true,
      ).allMatches(source))
        match.group(1)!: match.group(2)!,
    };

    String? setting(String body, String key) =>
        RegExp('^\\s*${RegExp.escape(key)} = (.+?);\$', multiLine: true)
            .firstMatch(body)
            ?.group(1)
            ?.trim()
            .replaceAll('"', '');

    final Iterable<String> targets = objects.values.where(
      (String body) =>
          setting(body, 'isa') == 'PBXNativeTarget' &&
          setting(body, 'name') == 'Runner',
    );
    if (targets.length != 1) return const [];

    // `buildConfigurationList = <id> /* Build configuration list for ... */;`
    final String? reference = setting(targets.first, 'buildConfigurationList');
    final String? listId = reference?.split(' ').first;
    if (listId == null || !objects.containsKey(listId)) return const [];

    // Only the ids inside `buildConfigurations = ( ... );`, because the list
    // object also carries `defaultConfigurationName` and its own isa.
    final String? references = RegExp(
      r'buildConfigurations = \((.*?)\);',
      dotAll: true,
    ).firstMatch(objects[listId]!)?.group(1);
    if (references == null) return const [];

    final configurations = <XcodeConfiguration>[];
    for (final RegExpMatch match
        in RegExp(r'[0-9A-Fa-f]{24}').allMatches(references)) {
      final String body = objects[match.group(0)!] ?? '';

      // The name comes from the configuration's OWN `name = ...;`, not from
      // the `/* Release */` comment beside its id in the list above. The
      // comment version matched `\w+`, which excludes a hyphen, so every
      // configuration of a flavoured project (`Release-production` and its
      // siblings, the shape Flutter's own docs prescribe) failed to match at
      // all and dropped out. The comment is cosmetic and Xcode is free to omit
      // it; the `name` is the record.
      final String? name = setting(body, 'name');
      if (name == null) continue;

      configurations.add((
        name: name,
        entitlements: setting(body, entitlementsSetting),
      ));
    }

    return configurations;
  }

  /// The base build type [configuration] belongs to, or null when its name
  /// says nothing about which one that is.
  ///
  /// Flutter flavours append the flavour to the base name, so a project with
  /// staging and production builds carries `Release-production`,
  /// `Debug-staging` and their siblings rather than the three bare names.
  /// Flutter's own documentation prescribes that shape
  /// (https://docs.flutter.dev/deployment/flavors-ios), and the `-` is what
  /// keeps the match tight: a configuration called `ReleaseCandidate` is not a
  /// Release and is declined rather than treated as one.
  static String? baseNameOf(String configuration) {
    for (final String base in const ['Debug', 'Profile', 'Release']) {
      if (configuration == base) return base;
      if (configuration.startsWith('$base-')) return base;
    }

    return null;
  }
}
