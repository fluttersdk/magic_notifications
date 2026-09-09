// The agent-facing reference for this package lives in ANOTHER repository.
//
// `.pubignore` excludes `CLAUDE.md` and `.claude/`, so an agent adopting this
// package from pub.dev never sees them. What it lands on is
// `magic/skills/magic-framework/references/plugin-notifications.md`, which is
// versioned by `magic`'s releases rather than by this package's, and therefore
// drifts silently. Measured once: the reference was stamped v0.0.3 against a
// shipped 0.2.0, with six breaking entries in the CHANGELOG in between.
//
// This test is the cheapest gate that exists for a cross-repository document.
// It cannot run in CI, which clones no siblings, so it SKIPS there rather than
// failing. Releases are cut locally, which is where it fires, and
// `.claude/commands/release.md` carries the same requirement in prose for the
// case where somebody runs the suite somewhere else entirely.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The reference this package owns, in the sibling `magic` checkout.
const String _referencePath =
    '../magic/skills/magic-framework/references/plugin-notifications.md';

/// Reads `version:` out of this package's own manifest.
String _shippedVersion() {
  final RegExp pattern = RegExp(r'^version:\s*(\S+)', multiLine: true);
  final RegExpMatch? match = pattern.firstMatch(
    File('pubspec.yaml').readAsStringSync(),
  );

  expect(match, isNotNull, reason: 'pubspec.yaml declares no version');

  return match!.group(1)!;
}

void main() {
  test('the magic skill reference is stamped with the shipped version', () {
    final File reference = File(_referencePath);

    if (!reference.existsSync()) {
      // No sibling checkout. CI is the normal case here, and a hard failure
      // would make every merge depend on a repository this one does not
      // declare.
      markTestSkipped(
        'no sibling magic checkout at $_referencePath, so the reference '
        'stamp cannot be compared here',
      );

      return;
    }

    final String version = _shippedVersion();
    final String firstLine = reference.readAsLinesSync().first;

    expect(
      firstLine,
      contains('magic_notifications v$version'),
      reason: 'the reference an agent reads is stamped for a different version '
          'than this package ships, which is how it came to document a '
          'contract that no longer compiles. Update $_referencePath against '
          'the current source, then move its stamp to v$version.',
    );
  });
}
