# CLI Refactor Learnings

## [2026-02-28] Session: ses_35af40e63ffeeaaBal377J8Los — Initial Context Load

### Project Structure
- Package name: `magic_notifications`
- Current entry point: `bin/notifications.dart` → becomes `bin/magic_notifications.dart`
- Executable in pubspec: `notifications: notifications` → becomes `magic_notifications: magic_notifications`
- Current 4 commands: install, configure, status, test
- Target 7 commands: install, configure, test, doctor, uninstall, publish, channels

### Key Files
- `lib/src/cli/cli.dart` — barrel file (7 lines), exports magic_cli + notification_config_helper
- `lib/src/cli/helpers/notification_config_helper.dart` — hardcoded template (98 lines), WILL BE DELETED
- `lib/src/cli/commands/install_command.dart` — 399 lines, has wizard flow + web setup
- `bin/notifications.dart` — 18 lines, Kernel + registerMany pattern

### Patterns to Follow
- deeplink entry point: `import 'package:magic_cli/magic_cli.dart' hide InstallCommand;`
- deeplink pubspec executable: under `executables:` at the bottom (not top)
- deeplink install command: `getProjectRoot()` + `getStubSearchPaths()` + `_resolvePluginStubsDir()`
- Stub placeholder syntax: `{{ variableName }}` (double curly braces)
- ConfigEditor for file mutations, FileHelper for file ops, StubLoader for stubs

### Template Content (from notification_config_helper.dart lines 24-47)
The notification_config.stub should contain the Dart map template with placeholders:
- `{{ oneSignalAppId }}` → replaces `'$oneSignalAppId'`
- `{{ safariWebIdLine }}` → replaces the optional safari web id line
- `{{ notifyButtonEnabled }}` → replaces `$notifyButtonEnabled`
- `{{ softPromptEnabled }}` → replaces `$softPromptEnabled`

### Web Setup Content (from install_command.dart lines 366-384)
- onesignal_worker.stub: `importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");`
- onesignal_script.stub: The HTML script block injected into index.html (lines 376-382)

### Critical Constraints
- NO changes to files outside `bin/`, `lib/src/cli/`, `assets/stubs/`, `test/cli/`, `pubspec.yaml`
- NO manual File().writeAsStringSync() — use FileHelper/ConfigEditor/StubLoader
- NO AST parser for ConfigureCommand — keep regex
- NO OneSignal API calls in doctor
- NO platform file reversion in uninstall
- Canonical bin entry point follows the pattern: Kernel + registerMany + handle.
- pubspec.yaml executables should be placed at the bottom after dev_dependencies for consistency.
- Stubs extracted from hardcoded logic enable easier maintenance and customization.
- Removed `NotificationConfigHelper` export from `lib/src/cli/cli.dart` as part of the CLI refactor to avoid exposing internal helpers in the public barrel.
- The `Kernel` class constructor no longer takes arguments, use `Kernel()..register(command)` instead of `Kernel([command])`.
Task 5: Refactor test_command.dart completed.
- Import fixed to magic_cli/magic_cli.dart
- getProjectRoot() added for testability
- All public methods documented with dartdoc
- Direct File() calls avoided (uses FileHelper)
- TDD tests passed in test/cli/test_command_test.dart


## [2026-02-28] Task 6 — DoctorCommand Created

### Implementation Notes
- `DoctorCommand` lives at `lib/src/cli/commands/doctor_command.dart`
- Imports `package:magic_notifications/src/cli/cli.dart` (NOT magic_cli directly) — this barrel re-exports magic_cli
- `checkPluginInstalled()` checks for `magic_notifications` (NOT `magic_notifications`)
- UUID regex split across two string literals to stay under 120-char line limit
- `_checkAndroidSetup()` uses `FileHelper.readFile(manifestPath)` (NOT `File().readAsStringSync()`)
- `validateConfig()` returns `List<String>` with human-readable issues
- `getMissingRequirements()` only calls `validateConfig()` when config file exists — avoids duplicate "config missing" errors
- `generateReport()` has a dedicated "Config Validation:" section (separate from the config existence check)
- Tests use `_TestDoctorCommand` that overrides `getProjectRoot()` — same pattern as InstallCommand tests
- 35 tests, all green. `dart analyze` clean. No suppressions.

### Confirmed Available ConsoleStyle Methods
- `ConsoleStyle.banner(title, version)` — box banner
- `ConsoleStyle.step(current, total, description)` — progress step
- `ConsoleStyle.cyan` / `ConsoleStyle.reset` — color constants
- `ConsoleStyle.table(headers, rows)` — table (exists but NOT used in DoctorCommand)
- `ConsoleStyle.keyValue(key, value)` — key-value pair (exists but NOT used in DoctorCommand)

## [2026-02-28] Task 4 — configure_command.dart refactor

### Changes Applied
- Import fixed: `package:magic_notifications/src/cli/cli.dart` → `package:magic_cli/magic_cli.dart`
- `File(_configPath).readAsStringSync()` (×2 in readCurrentConfig + updateConfig) → `FileHelper.readFile(_configPath)`
- `File(_configPath).writeAsStringSync(content)` → `FileHelper.writeFile(_configPath, content)`
- `dart:io` kept because `FileSystemException` (thrown in readCurrentConfig/updateConfig) is defined there
- Error message fixed: `dart run magic_notifications:install` → `dart run magic_notifications install`
- All 4 regex patterns got explanatory comments describing what they match

### Test Pattern (for future commands)
- Test double pattern: `class _TestCommand extends RealCommand { @override String getProjectRoot() => _root; }`
- Tests operate entirely in `Directory.systemTemp.createTempSync(...)` — zero real FS side-effects
- Pre-existing test file (`test/cli/commands/configure_command_test.dart`) was already committed by an earlier session; new file replaced it with 20 comprehensive tests using the override pattern

### Gotcha: dart:io and FileSystemException
- Even after removing all `File()` calls, keep `import 'dart:io'` if `FileSystemException` is thrown directly
- `FileHelper.readFile()` also throws `FileSystemException` internally — but callers may catch that type, so the import is load-bearing if you reference the class by name

### Regex Coverage
| Pattern | What it matches |
|---------|----------------|
| `'app_id':\s*'([^']*)'` | push.app_id value |
| `'polling_interval':\s*(\d+)` | database.polling_interval integer |
| `'enabled':\s*(true\|false)` in db substring | database.enabled boolean |
| `'soft_prompt':\s*\{[^}]*'enabled':\s*(true\|false)` | soft_prompt.enabled boolean |

### ChannelsCommand Implementation
- Implemented a read-only command to display notification channels.
- Reused regex patterns from `ConfigureCommand` for consistent config parsing.
- Followed TDD by writing tests first, ensuring robust parsing of `lib/config/notifications.dart`.
- Used `ConsoleStyle` for Laravel-like CLI output formatting.

## [2026-02-28] Task 8 — PublishCommand Created

### Implementation Notes
- `PublishCommand` lives at `lib/src/cli/commands/publish_command.dart`
- Imports: `dart:convert`, `dart:io`, `package:magic_cli/magic_cli.dart`
- `_resolvePluginStubsDir()` copied verbatim from `InstallCommand` — same package_config.json parsing logic
- `StubLoader.replace()` called with Map<String, String>: keys are placeholder names WITHOUT `{{ }}` braces
- Default values: `oneSignalAppId='YOUR_ONESIGNAL_APP_ID'`, `safariWebIdLine=''`, `notifyButtonEnabled='false'`, `softPromptEnabled='true'`
- `--force` / `-f` flag: without it, warns and returns without writing; with it, overwrites

### Test Pattern
- `_TestPublishCommand` overrides `getProjectRoot()` → temp dir, `getStubSearchPaths()` → `assets/stubs`
- 10 tests, all green. `dart analyze` clean. No suppressions.

### Key Distinction from InstallCommand
- `publish` = stub-only, no wizard, no provider injection, no platform files
- `install` = full wizard + provider injection + platform setup
- User workflow: `publish` first (config scaffold), then `install` (wire everything)

## [2026-02-28] Task 7 — UninstallCommand Created

### Implementation Notes
- `UninstallCommand` lives at `lib/src/cli/commands/uninstall_command.dart`
- Imports only `package:magic_cli/magic_cli.dart` — no `dart:io` needed (FileHelper/ConfigEditor handle all FS ops)
- `ConfigEditor.removeDependencyFromPubspec()` EXISTS in magic_cli — confirmed and used directly
- `FileHelper.deleteFile()` EXISTS and is safe (no-op when file missing)
- Regex patterns use `[ \t]*` prefix (NOT `\s+`) to avoid stripping blank lines that contain only spaces/tabs
- `confirm()` returns `defaultValue` (false) in non-interactive test environments — uninstall is safely cancelled without --force
- Platform files (AndroidManifest.xml, index.html, OneSignalSDKWorker.js) are intentionally NOT touched — only warned about

### Test Structure
- 18 tests, all green. `dart analyze` clean. No suppressions.
- `_TestUninstallCommand` overrides `getProjectRoot()` — same test-double pattern used across all commands
- Graceful tests: missing config, app.dart, or main.dart — none throw
- Platform safety tests: create files then verify unchanged after uninstall
- Confirmation bypass test: without `--force`, config file survives (confirm() defaults to false in non-TTY)

### Regex Patterns Used
| Pattern | What it removes |
|---------|-----------------|
| `import 'package:magic_notifications/[^']*';\n?` | magic_notifications import line in app.dart |
| `[ \t]*\(app\) => NotificationServiceProvider\(app\),\n?` | provider entry in app.dart providers list |
| `import 'config/notifications\.dart';\n?` | notifications config import in main.dart |
| `[ \t]*\(\) => notificationConfig,\n?` | configFactory entry in main.dart configFactories list |

## Task 11: Full Test Run + README CLI Section Update (2026-02-28)

- All 85 CLI tests pass after updating `readme_test.dart` to expect new space-separated command format
- `dart analyze lib/ bin/` → clean (no issues). Pre-existing errors in `test/channels/` and `test/providers/` reference old `magic_notifications` package name — not related to CLI refactor
- README update pattern: replace ALL `magic_notifications:[command]` (colon-separated) with `magic_notifications [command]` (space-separated)
- `status` command fully removed from README; replaced with `### Doctor` section
- New sections added: Uninstall, Publish, Channels
- `magic_notifications:` still appears in README once (line 71) inside a `pubspec.yaml` YAML block as the package path reference — acceptable per task spec
- readme_test.dart must be updated alongside README when command format changes — they are tightly coupled
