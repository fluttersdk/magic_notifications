# CLI Refactor Issues

## [2026-02-28] Session: ses_35af40e63ffeeaaBal377J8Los — Initial

### Known Gotchas
1. install_command.dart line 278: uses `magic_notifications` as dependency name in ConfigEditor.addPathDependencyToPubspec — must change to `magic_notifications`
2. install_command.dart line 2: imports from `magic_notifications/src/cli/cli.dart` (relative import of barrel file)
3. bin/notifications.dart line 1: has `hide InstallCommand` — deeplink does this too (magic_cli exports its own InstallCommand, we override it)
4. The worker content in install_command.dart line 369 uses `File(workerPath).writeAsStringSync()` — MUST migrate to FileHelper
5. pubspec.yaml current executable is at TOP (lines 7-8), deeplink puts it at BOTTOM — follow the task spec which says match deeplink pattern

### Watch Out
- Task 1 agent must read `notification_config_helper.dart` to extract the EXACT template for the stub file
- Task 1 agent must read install_command.dart lines 366-384 for the exact worker JS and script HTML
- Task 2 references deeplink's `_injectIntoApp` and `_injectIntoMain` — the import for notifications should be `magic_notifications` not `magic_notifications`
