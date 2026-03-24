# magic_notifications CLI Refactor

## TL;DR

> **Quick Summary**: Refactor magic_notifications CLI to match magic_cli framework conventions (deeplink pattern). Migrate hardcoded templates to stubs, standardize entry point, add 4 new commands (uninstall, publish, doctor, channels), remove status command (merged into doctor). TDD throughout.
> 
> **Deliverables**:
> - Renamed entry point: `bin/magic_notifications.dart` → `dart run magic_notifications install`
> - 7 CLI commands: install, configure, test, doctor, uninstall, publish, channels
> - Stub files in `assets/stubs/install/`
> - Comprehensive test suite for all commands
> - Removed: `NotificationConfigHelper` (replaced by stubs), `StatusCommand` (replaced by doctor)
> 
> **Estimated Effort**: Medium
> **Parallel Execution**: YES - 4 waves
> **Critical Path**: Task 1 → Task 2 → Task 4 → Task 5 → Task 11 → F1-F4

---

## Context

### Original Request
Refactor magic_notifications CLI commands using magic_deeplink as the reference implementation. Match magic_cli framework's latest conventions. Use stubs, reuse helpers, Laravel artisan-style CLI. Usage: `dart run magic_notifications install`.

### Interview Summary
**Key Discussions**:
- Package name: `magic_notifications` (standardized, old prefix dropped)
- Entry point: `bin/magic_notifications.dart` (matches deeplink pattern)
- Install wizard: Keep both interactive + non-interactive modes
- Status command removed, doctor replaces it with config validation
- Uninstall: full cleanup except platform files (AndroidManifest, index.html) — fragile to revert
- Publish: copies stub files to user's project for customization (Laravel vendor:publish style)
- All 4 extra commands approved: uninstall, publish, doctor, channels
- TDD approach for all commands

**Research Findings**:
- magic_cli provides: Kernel, Command, GeneratorCommand, StubLoader, FileHelper, ConfigEditor, ConsoleStyle, PlatformHelper, XmlEditor, HtmlEditor, JsonEditor, StringHelper
- magic_deeplink pattern: StubLoader.load() with _resolvePluginStubsDir(), ConfigEditor for injection, clean _injectIntoApp/_injectIntoMain separation
- Current NotificationConfigHelper has hardcoded template as multiline Dart string
- Web setup has inline JS content for OneSignal worker

### Metis Review
**Identified Gaps** (addressed):
- Interactive wizard decision: keeping both modes (wizard + stub drop)
- Publish command scope: stub files to project for customization
- Uninstall platform safety: skip platform files, only clean Dart/config
- Re-installation safety: `--force` flag (deeplink pattern) — auto-resolved
- Missing platforms: graceful skip — already in existing code
- NotificationConfigHelper: removed entirely, logic moves to install + stubs

---

## Work Objectives

### Core Objective
Refactor all CLI commands to match magic_cli/magic_deeplink framework conventions. Extract hardcoded templates to stubs, standardize naming, add 4 new commands.

### Concrete Deliverables
- `bin/magic_notifications.dart` — new entry point
- `assets/stubs/install/notification_config.stub` — config template
- `assets/stubs/install/onesignal_worker.stub` — OneSignal worker JS
- `assets/stubs/install/onesignal_script.stub` — OneSignal script injection
- 7 command files in `lib/src/cli/commands/`
- Test files in `test/cli/` for each command
- Updated `pubspec.yaml` (executable, no other changes)

### Definition of Done
- [ ] `dart run magic_notifications install` works from a host project
- [ ] `dart run magic_notifications doctor` passes on a correctly configured project
- [ ] All tests pass: `dart test test/cli/`
- [ ] Zero hardcoded templates in command files — all use StubLoader
- [ ] No `magic_notifications` references remain

### Must Have
- Entry point: `bin/magic_notifications.dart`
- Stub-based templates via StubLoader
- All 7 commands working
- `--force` flag on install (deeplink pattern)
- magic_cli helpers used for ALL file mutations
- Tests for every command
- `getProjectRoot()` and `getStubSearchPaths()` overridable in every command

### Must NOT Have (Guardrails)
- **NO changes to files outside** `bin/`, `lib/src/cli/`, `assets/stubs/`, `test/cli/`, `pubspec.yaml`
- **NO runtime notification code changes** — core library is off-limits
- **NO manual File().writeAsStringSync()** — use FileHelper/ConfigEditor/StubLoader
- **NO AST parser** for ConfigureCommand — keep regex, clean it up
- **NO OneSignal API calls** in doctor — file checks and regex only
- **NO platform file reversion** in uninstall — skip AndroidManifest, index.html, OneSignalWorker.js
- **NO new dependencies** — only existing magic_cli helpers
- **NO over-engineering E2E tests** — unit test commands with injected temp dirs

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: YES (flutter_test + test in dev_dependencies)
- **Automated tests**: TDD (RED → GREEN → REFACTOR)
- **Framework**: `dart test` (test package already in dev_dependencies)
- **Each task follows**: Write failing test → Implement → Refactor

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **CLI commands**: Use Bash — run `dart run magic_notifications [command]`, assert output/files
- **Tests**: Use Bash — run `dart test test/cli/`, assert pass count

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — foundation):
├── Task 1: Entry point + pubspec + stub files [quick]
├── Task 2: Install command rewrite (TDD) [deep]
├── Task 3: CLI barrel file update [quick]

Wave 2 (After Wave 1 — existing command refactors):
├── Task 4: Configure command refactor (TDD) [unspecified-high]
├── Task 5: Test command refactor (TDD) [quick]
├── Task 6: Doctor command — new (TDD) [unspecified-high]

Wave 3 (After Wave 1 — new commands, parallel with Wave 2):
├── Task 7: Uninstall command — new (TDD) [unspecified-high]
├── Task 8: Publish command — new (TDD) [unspecified-high]
├── Task 9: Channels command — new (TDD) [quick]

Wave 4 (After ALL — cleanup + verification):
├── Task 10: Delete obsolete files + final cleanup [quick]
├── Task 11: Integration test run + README CLI section update [unspecified-high]

Wave FINAL (After ALL tasks — independent review, 4 parallel):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real manual QA (unspecified-high)
├── Task F4: Scope fidelity check (deep)

Critical Path: Task 1 → Task 2 → Task 4 → Task 5 → Task 11 → F1-F4
Parallel Speedup: ~55% faster than sequential
Max Concurrent: 3 (Waves 2+3)
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|-----------|--------|
| 1 | — | 2, 3, 4, 5, 6, 7, 8, 9 |
| 2 | 1 | 7, 10, 11 |
| 3 | 1 | — |
| 4 | 1 | 10, 11 |
| 5 | 1 | 10, 11 |
| 6 | 1 | 10, 11 |
| 7 | 1, 2 | 10, 11 |
| 8 | 1 | 10, 11 |
| 9 | 1 | 10, 11 |
| 10 | 2, 4, 5, 6, 7, 8, 9 | 11 |
| 11 | 10 | F1-F4 |

### Agent Dispatch Summary

- **Wave 1**: 3 tasks — T1 → `quick`, T2 → `deep`, T3 → `quick`
- **Wave 2**: 3 tasks — T4 → `unspecified-high`, T5 → `quick`, T6 → `unspecified-high`
- **Wave 3**: 3 tasks — T7 → `unspecified-high`, T8 → `unspecified-high`, T9 → `quick`
- **Wave 4**: 2 tasks — T10 → `quick`, T11 → `unspecified-high`
- **FINAL**: 4 tasks — F1 → `oracle`, F2 → `unspecified-high`, F3 → `unspecified-high`, F4 → `deep`

---

## TODOs

- [ ] 1. Entry Point + Pubspec + Stub Files

  **What to do**:
  - Rename `bin/notifications.dart` → `bin/magic_notifications.dart`
  - Update `pubspec.yaml` executables: `magic_notifications: magic_notifications`
  - Create `assets/stubs/install/notification_config.stub` — extract the template from `NotificationConfigHelper.createNotificationConfig()` using `{{ placeholder }}` syntax for: `oneSignalAppId`, `safariWebIdLine`, `notifyButtonEnabled`, `softPromptEnabled`
  - Create `assets/stubs/install/onesignal_worker.stub` — extract from `InstallCommand._setupWeb()` the worker JS content
  - Create `assets/stubs/install/onesignal_script.stub` — extract from `InstallCommand._setupWeb()` the HTML script injection block
  - Delete old `bin/notifications.dart`

  **Must NOT do**:
  - Do NOT modify any lib/ runtime code
  - Do NOT change any dependency versions

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: File creation and renaming, no complex logic
  - **Skills**: [`anilcan-coding`]
    - `anilcan-coding`: Enforce coding standards for stub content formatting

  **Parallelization**:
  - **Can Run In Parallel**: NO (other tasks depend on this)
  - **Parallel Group**: Wave 1 — start first
  - **Blocks**: Tasks 2, 3, 4, 5, 6, 7, 8, 9
  - **Blocked By**: None

  **References**:

  **Pattern References**:
  - `bin/notifications.dart` — current entry point structure to replicate
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic_deeplink/bin/magic_deeplink.dart` — exact pattern: Kernel + registerMany + handle
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic_deeplink/pubspec.yaml` — executable registration format

  **Source References**:
  - `lib/src/cli/helpers/notification_config_helper.dart:24-47` — hardcoded config template → extract to `notification_config.stub`
  - `lib/src/cli/commands/install_command.dart:366-381` — hardcoded OneSignal worker JS + script HTML → extract to stubs

  **External References**:
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/stubs/stub_loader.dart` — placeholder syntax `{{ variableName }}`

  **WHY Each Reference Matters**:
  - notification_config_helper.dart has the EXACT template to extract — replace dynamic values with `{{ placeholder }}`
  - deeplink entry point is the canonical pattern — copy its Kernel structure
  - StubLoader docs show `{{ }}` syntax stubs MUST use

  **Acceptance Criteria**:
  - [ ] `bin/magic_notifications.dart` exists with Kernel + registerMany pattern
  - [ ] `bin/notifications.dart` deleted
  - [ ] `pubspec.yaml` executables: `magic_notifications: magic_notifications`
  - [ ] `assets/stubs/install/notification_config.stub` has `{{ oneSignalAppId }}`, `{{ softPromptEnabled }}` placeholders
  - [ ] `assets/stubs/install/onesignal_worker.stub` has worker JS content
  - [ ] `assets/stubs/install/onesignal_script.stub` has HTML script block

  **QA Scenarios:**
  ```
  Scenario: Stub files contain correct placeholders
    Tool: Bash
    Steps:
      1. Run: cat assets/stubs/install/notification_config.stub
      2. Assert: contains '{{ oneSignalAppId }}' and '{{ softPromptEnabled }}'
      3. Run: cat assets/stubs/install/onesignal_worker.stub
      4. Assert: contains 'importScripts'
    Expected Result: All stubs valid
    Evidence: .sisyphus/evidence/task-1-stubs.txt

  Scenario: Entry point follows Kernel pattern
    Tool: Bash
    Steps:
      1. Run: cat bin/magic_notifications.dart
      2. Assert: contains 'Kernel()' and 'kernel.handle(args)'
      3. Verify bin/notifications.dart no longer exists
    Expected Result: Correct entry point, old deleted
    Evidence: .sisyphus/evidence/task-1-entry-point.txt
  ```

  **Commit**: YES
  - Message: `refactor(cli): rename entry point and create stub files`
  - Files: `bin/magic_notifications.dart`, `assets/stubs/install/*.stub`, `pubspec.yaml`
  - Pre-commit: `dart analyze bin/`

- [ ] 2. Install Command Rewrite (TDD)

  **What to do**:
  - Write tests FIRST in `test/cli/install_command_test.dart`
  - Rewrite `InstallCommand` following magic_deeplink pattern:
    - Add `getStubSearchPaths()` method (overridable) with `_resolvePluginStubsDir()` — copy from deeplink's install_command.dart:37-42 and :130-163
    - Replace `NotificationConfigHelper.createNotificationConfig()` with `StubLoader.load('install/notification_config', searchPaths: getStubSearchPaths())` + `StubLoader.replace()` for placeholders
    - Extract `_injectIntoApp()` — add import + inject `NotificationServiceProvider` using `ConfigEditor.addImportToFile()` + `ConfigEditor.insertCodeBeforePattern()`
    - Extract `_injectIntoMain()` — add import + inject `notificationConfig` using `ConfigEditor.addImportToFile()` + `ConfigEditor.insertCodeBeforePattern()`
    - Add `--force` flag: skip config write if exists unless --force
    - Keep interactive wizard flow (ask App ID, platforms, soft prompt)
    - Keep non-interactive mode with --non-interactive flag
    - Platform setup: use stubs for OneSignal worker + script
    - Standardize to `magic_notifications` (not `magic_notifications`)
  - Delete `NotificationConfigHelper` class and its file

  **Must NOT do**:
  - Do NOT build an AST parser
  - Do NOT modify the wizard’s UX flow or question order
  - Do NOT add new dependencies

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Complex TDD refactoring, multiple integration points
  - **Skills**: [`anilcan-coding`, `magic-framework`]
    - `anilcan-coding`: TDD methodology, coding standards
    - `magic-framework`: Magic service providers, config injection

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 3, after Task 1)
  - **Parallel Group**: Wave 1
  - **Blocks**: Tasks 7, 10, 11
  - **Blocked By**: Task 1

  **References**:

  **Pattern References**:
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic_deeplink/lib/src/cli/commands/install_command.dart` — THE reference. Follow for: `getProjectRoot()`, `getStubSearchPaths()`, `_resolvePluginStubsDir()`, `_injectIntoApp()`, `_injectIntoMain()`
  - `lib/src/cli/commands/install_command.dart` — CURRENT impl. Keep wizard from `_runInteractive()` (lines 143-253) and `_runNonInteractive()` (lines 112-140)

  **API References**:
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/stubs/stub_loader.dart` — `StubLoader.load(name, searchPaths)`, `StubLoader.replace(stub, replacements)`, `StubLoader.make(name, replacements)`
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/helpers/config_editor.dart` — `ConfigEditor.addImportToFile()`, `ConfigEditor.insertCodeBeforePattern()`, `ConfigEditor.addPathDependencyToPubspec()`

  **WHY Each Reference Matters**:
  - deeplink install is the CANONICAL pattern to replicate
  - Current install has wizard flow that MUST be preserved verbatim
  - StubLoader + ConfigEditor APIs are exact signatures to call

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/install_command_test.dart` → PASS
  - [ ] `InstallCommand` has `getStubSearchPaths()` and `_resolvePluginStubsDir()`
  - [ ] Config created via `StubLoader.load()` + `StubLoader.replace()` — no hardcoded template
  - [ ] `_injectIntoApp()` uses ConfigEditor
  - [ ] `_injectIntoMain()` uses ConfigEditor
  - [ ] `--force` flag works correctly
  - [ ] Interactive wizard preserved
  - [ ] No `magic_notifications` string remains
  - [ ] `lib/src/cli/helpers/notification_config_helper.dart` deleted

  **QA Scenarios:**
  ```
  Scenario: Install creates config from stub with --force
    Tool: Bash
    Steps:
      1. Set up temp project with pubspec.yaml + app.dart + main.dart
      2. Run install with overridden projectRoot and --force
      3. Assert: lib/config/notifications.dart created from stub
      4. Assert: app.dart contains 'NotificationServiceProvider'
      5. Assert: main.dart contains 'notificationConfig'
    Expected Result: Config created, injections applied
    Evidence: .sisyphus/evidence/task-2-install-force.txt

  Scenario: Install aborts without --force when config exists
    Tool: Bash
    Steps:
      1. Create temp project with existing config file
      2. Run install without --force
      3. Assert: warning about existing config displayed
    Expected Result: Graceful abort with warning
    Evidence: .sisyphus/evidence/task-2-install-no-force.txt
  ```

  **Commit**: YES
  - Message: `refactor(cli): rewrite install command with StubLoader pattern`
  - Files: `lib/src/cli/commands/install_command.dart`, `lib/src/cli/helpers/` (deleted), `test/cli/install_command_test.dart`
  - Pre-commit: `dart test test/cli/install_command_test.dart`

- [ ] 3. CLI Barrel File Update

  **What to do**:
  - Update `lib/src/cli/cli.dart`: remove `NotificationConfigHelper` export
  - Keep magic_cli re-export

  **Must NOT do**:
  - Do NOT export command classes from barrel

  **Recommended Agent Profile**:
  - **Category**: `quick`
  - **Skills**: [`anilcan-coding`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 2)
  - **Parallel Group**: Wave 1
  - **Blocks**: None
  - **Blocked By**: Task 1

  **References**:
  - `lib/src/cli/cli.dart` — current 7-line barrel file

  **Acceptance Criteria**:
  - [ ] `lib/src/cli/cli.dart` does NOT contain 'notification_config_helper'
  - [ ] `dart analyze lib/src/cli/cli.dart` → no issues

  **QA Scenarios:**
  ```
  Scenario: Barrel is clean
    Tool: Bash
    Steps:
      1. Run: grep 'notification_config_helper' lib/src/cli/cli.dart
      2. Assert: no matches (exit code 1)
    Expected Result: Helper export removed
    Evidence: .sisyphus/evidence/task-3-barrel.txt
  ```

  **Commit**: YES (groups with Task 1)
  - Message: `refactor(cli): rename entry point and create stub files`

- [ ] 4. Configure Command Refactor (TDD)

  **What to do**:
  - Write tests FIRST in `test/cli/configure_command_test.dart`
  - Add `getProjectRoot()` method (overridable) — currently exists but standardize
  - Clean up regex parsing: add defensive error handling, improve comments explaining each regex
  - Replace `File(_configPath).readAsStringSync()` calls with `FileHelper.readFile()`
  - Replace `File(_configPath).writeAsStringSync()` with `FileHelper.writeFile()`
  - Standardize `magic_notifications` → `magic_notifications` references in messages
  - Keep the existing regex-based config reading/updating approach (do NOT build AST parser)

  **Must NOT do**:
  - Do NOT replace regex with AST parser
  - Do NOT change the config file format

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: TDD with regex cleanup, moderate complexity
  - **Skills**: [`anilcan-coding`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 5, 6)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 10, 11
  - **Blocked By**: Task 1

  **References**:
  - `lib/src/cli/commands/configure_command.dart` — current implementation (278 lines). Regex at lines 174-201 for reading, 207-261 for updating
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/helpers/file_helper.dart` — `FileHelper.readFile()`, `FileHelper.writeFile()` to replace raw `File()` calls

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/configure_command_test.dart` → PASS
  - [ ] No direct `File().readAsStringSync()` or `File().writeAsStringSync()` in configure_command.dart
  - [ ] All regex patterns have explanatory comments
  - [ ] No `magic_notifications` strings

  **QA Scenarios:**
  ```
  Scenario: Configure --show displays current config
    Tool: Bash
    Steps:
      1. Create temp project with notification_config.dart stub
      2. Run configure --show
      3. Assert: output contains 'Push Notifications' and 'Database Notifications'
    Expected Result: Config values displayed
    Evidence: .sisyphus/evidence/task-4-configure-show.txt

  Scenario: Configure updates polling interval
    Tool: Bash
    Steps:
      1. Create temp project with notification_config.dart
      2. Run configure --polling-interval 60
      3. Read config file, assert: 'polling_interval': 60
    Expected Result: Value updated in file
    Evidence: .sisyphus/evidence/task-4-configure-interval.txt
  ```

  **Commit**: YES
  - Message: `refactor(cli): clean up configure command with FileHelper`
  - Files: `lib/src/cli/commands/configure_command.dart`, `test/cli/configure_command_test.dart`
  - Pre-commit: `dart test test/cli/configure_command_test.dart`

- [ ] 5. Test Command Refactor (TDD)

  **What to do**:
  - Write tests FIRST in `test/cli/test_command_test.dart`
  - Add `getProjectRoot()` method if not present (overridable)
  - Replace any `File()` calls with `FileHelper` equivalents
  - Standardize naming references to `magic_notifications`
  - Cosmetic: clean up formatting, add dartdoc to all public methods
  - Keep the simulate/dry-run functionality as-is

  **Must NOT do**:
  - Do NOT add actual push sending capability — keep simulation only

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Mostly cosmetic refactor, straightforward tests
  - **Skills**: [`anilcan-coding`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 4, 6)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 10, 11
  - **Blocked By**: Task 1

  **References**:
  - `lib/src/cli/commands/test_command.dart` — current implementation (231 lines)

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/test_command_test.dart` → PASS
  - [ ] No direct `File()` calls
  - [ ] All public methods have dartdoc

  **QA Scenarios:**
  ```
  Scenario: Test --dry-run shows preview without sending
    Tool: Bash
    Steps:
      1. Run test command with --dry-run
      2. Assert: output contains 'Notification Preview' and 'Dry run mode'
    Expected Result: Preview displayed, nothing sent
    Evidence: .sisyphus/evidence/task-5-test-dryrun.txt
  ```

  **Commit**: YES
  - Message: `refactor(cli): clean up test command`
  - Files: `lib/src/cli/commands/test_command.dart`, `test/cli/test_command_test.dart`
  - Pre-commit: `dart test test/cli/test_command_test.dart`

- [ ] 6. Doctor Command — New (TDD, Replaces Status)

  **What to do**:
  - Write tests FIRST in `test/cli/doctor_command_test.dart`
  - Create `lib/src/cli/commands/doctor_command.dart`
  - Migrate ALL functionality from `StatusCommand` (file checks, platform checks, report generation)
  - ADD config validation on top:
    - Check if OneSignal App ID in config is valid UUID format
    - Check if App ID is placeholder/empty
    - Check polling_interval is in valid range (5-600)
    - Check soft_prompt section exists
  - Use `ConsoleStyle.table()` for structured output
  - Use `ConsoleStyle.keyValue()` for key-value pairs
  - Exit code 0 if all checks pass, exit code 1 if any fail
  - Support `--verbose` flag like StatusCommand
  - Register in `bin/magic_notifications.dart` (replace StatusCommand)

  **Must NOT do**:
  - Do NOT make HTTP calls to OneSignal or backend APIs
  - Do NOT parse Dart AST — regex checks only for config validation

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: New command with merged functionality + new config validation
  - **Skills**: [`anilcan-coding`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 4, 5)
  - **Parallel Group**: Wave 2
  - **Blocks**: Tasks 10, 11
  - **Blocked By**: Task 1

  **References**:
  - `lib/src/cli/commands/status_command.dart` — ALL functionality to migrate: `checkPluginInstalled()`, `checkConfigExists()`, `checkPlatformSetup()`, `getMissingRequirements()`, `generateReport()`
  - `lib/src/cli/commands/install_command.dart:80-86` — `validateOneSignalAppId()` regex to reuse for doctor validation
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/helpers/console_style.dart` — `ConsoleStyle.table()`, `ConsoleStyle.keyValue()` for formatted output

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/doctor_command_test.dart` → PASS
  - [ ] `DoctorCommand` has `name => 'doctor'`
  - [ ] Checks: plugin installed, config exists, platform setup (from StatusCommand)
  - [ ] Checks: App ID format, polling interval range, soft prompt section
  - [ ] Exit code 0 on all pass, 1 on any fail
  - [ ] `--verbose` flag works
  - [ ] Registered in `bin/magic_notifications.dart`

  **QA Scenarios:**
  ```
  Scenario: Doctor reports all checks passing
    Tool: Bash
    Steps:
      1. Create temp project with valid config, pubspec dep, platform files
      2. Run doctor command
      3. Assert: output contains '✓' marks for each check
      4. Assert: exit code 0
    Expected Result: All checks pass
    Evidence: .sisyphus/evidence/task-6-doctor-pass.txt

  Scenario: Doctor detects invalid App ID
    Tool: Bash
    Steps:
      1. Create temp project with config containing 'invalid-app-id'
      2. Run doctor command
      3. Assert: output contains warning about invalid App ID format
      4. Assert: exit code 1
    Expected Result: Invalid config detected
    Evidence: .sisyphus/evidence/task-6-doctor-invalid.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): add doctor command replacing status`
  - Files: `lib/src/cli/commands/doctor_command.dart`, `test/cli/doctor_command_test.dart`
  - Pre-commit: `dart test test/cli/doctor_command_test.dart`

- [ ] 7. Uninstall Command — New (TDD)

  **What to do**:
  - Write tests FIRST in `test/cli/uninstall_command_test.dart`
  - Create `lib/src/cli/commands/uninstall_command.dart`
  - Implement reverse-install logic:
    - Delete `lib/config/notifications.dart`
    - Remove `magic_notifications` dependency from `pubspec.yaml` using `ConfigEditor.removeDependencyFromPubspec()`
    - Remove `NotificationServiceProvider` injection from `lib/config/app.dart`:
      - Remove import line: find and delete line containing `magic_notifications`
      - Remove provider line: find and delete line containing `NotificationServiceProvider`
    - Remove `notificationConfig` injection from `lib/main.dart`:
      - Remove import line: find and delete line containing `config/notifications.dart`
      - Remove config factory line: find and delete line containing `notificationConfig`
  - Do NOT touch platform files (AndroidManifest, index.html, OneSignalWorker.js) — warn user they need manual cleanup
  - Add `--force` flag to skip confirmation prompt
  - Add confirmation: `confirm('Are you sure you want to uninstall Magic Notifications?')`
  - Show summary of what will be removed before confirming
  - After removal, show what remains (platform files) and manual cleanup instructions

  **Must NOT do**:
  - Do NOT revert AndroidManifest.xml changes
  - Do NOT revert index.html changes
  - Do NOT delete OneSignalSDKWorker.js
  - Do NOT modify any runtime code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: New command with file deletion + code removal logic, needs careful handling
  - **Skills**: [`anilcan-coding`, `magic-framework`]
    - `anilcan-coding`: TDD, coding standards
    - `magic-framework`: Understanding of injection patterns to reverse them

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 8, 9)
  - **Parallel Group**: Wave 3
  - **Blocks**: Tasks 10, 11
  - **Blocked By**: Tasks 1, 2 (needs to understand install's injection patterns to reverse them)

  **References**:
  - `lib/src/cli/commands/install_command.dart` — the EXACT injection patterns to reverse: `_injectIntoApp()` and `_injectIntoMain()` — uninstall must undo these
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/helpers/config_editor.dart` — `ConfigEditor.removeDependencyFromPubspec()` method
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/helpers/file_helper.dart` — `FileHelper.deleteFile()` if it exists, otherwise `File().deleteSync()`

  **WHY Each Reference Matters**:
  - install_command shows exactly what was injected — uninstall must find and remove those exact strings
  - ConfigEditor has `removeDependencyFromPubspec()` — use it instead of manual yaml editing

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/uninstall_command_test.dart` → PASS
  - [ ] `UninstallCommand` has `name => 'uninstall'`
  - [ ] Deletes `lib/config/notifications.dart`
  - [ ] Removes dependency from pubspec.yaml via ConfigEditor
  - [ ] Removes import + provider from app.dart
  - [ ] Removes import + configFactory from main.dart
  - [ ] Does NOT touch platform files
  - [ ] Warns user about manual platform cleanup
  - [ ] Confirmation prompt before destructive action
  - [ ] `--force` skips confirmation

  **QA Scenarios:**
  ```
  Scenario: Uninstall removes config and injections
    Tool: Bash
    Steps:
      1. Create temp project with full install (config, deps, injections)
      2. Run uninstall with --force (skip prompt)
      3. Assert: lib/config/notifications.dart deleted
      4. Assert: pubspec.yaml does NOT contain 'magic_notifications' dependency
      5. Assert: app.dart does NOT contain 'NotificationServiceProvider'
      6. Assert: main.dart does NOT contain 'notificationConfig'
    Expected Result: Clean removal of all CLI-managed artifacts
    Evidence: .sisyphus/evidence/task-7-uninstall.txt

  Scenario: Uninstall does NOT touch platform files
    Tool: Bash
    Steps:
      1. Create temp project with OneSignalSDKWorker.js and AndroidManifest with permission
      2. Run uninstall with --force
      3. Assert: web/OneSignalSDKWorker.js still exists
      4. Assert: AndroidManifest still has POST_NOTIFICATIONS
    Expected Result: Platform files untouched
    Evidence: .sisyphus/evidence/task-7-uninstall-platform-safe.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): add uninstall command`
  - Files: `lib/src/cli/commands/uninstall_command.dart`, `test/cli/uninstall_command_test.dart`
  - Pre-commit: `dart test test/cli/uninstall_command_test.dart`

- [ ] 8. Publish Command — New (TDD)

  **What to do**:
  - Write tests FIRST in `test/cli/publish_command_test.dart`
  - Create `lib/src/cli/commands/publish_command.dart`
  - Laravel `vendor:publish` pattern: copy stub files from package assets to user's project
  - Publishes stub files as real Dart files to the user's project (like deeplink's install, but specifically for customization)
  - Behavior:
    - List available publishable assets (notification_config stub)
    - Copy `assets/stubs/install/notification_config.stub` → `lib/config/notifications.dart` with default placeholder values filled in
    - Add `--force` flag to overwrite existing files
    - Use `getStubSearchPaths()` pattern for stub resolution
    - Show what was published on success
  - Use StubLoader for loading stubs, StubLoader.replace() with sensible defaults

  **Must NOT do**:
  - Do NOT publish runtime library files
  - Do NOT modify pubspec.yaml

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: New command with stub resolution and file publishing
  - **Skills**: [`anilcan-coding`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 7, 9)
  - **Parallel Group**: Wave 3
  - **Blocks**: Tasks 10, 11
  - **Blocked By**: Task 1

  **References**:
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic_deeplink/lib/src/cli/commands/install_command.dart` — `getStubSearchPaths()` and `_resolvePluginStubsDir()` pattern to copy
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/stubs/stub_loader.dart` — `StubLoader.load()`, `StubLoader.replace()`

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/publish_command_test.dart` → PASS
  - [ ] `PublishCommand` has `name => 'publish'`
  - [ ] Publishes notification_config stub to `lib/config/notifications.dart`
  - [ ] `--force` overwrites existing
  - [ ] Without --force, warns if file exists

  **QA Scenarios:**
  ```
  Scenario: Publish creates config file from stub with defaults
    Tool: Bash
    Steps:
      1. Create temp project without config file
      2. Run publish command
      3. Assert: lib/config/notifications.dart created
      4. Assert: file contains valid Dart map with default values
    Expected Result: Config published with defaults
    Evidence: .sisyphus/evidence/task-8-publish.txt

  Scenario: Publish warns when file exists
    Tool: Bash
    Steps:
      1. Create temp project with existing config
      2. Run publish without --force
      3. Assert: warning about existing file
    Expected Result: No overwrite, user warned
    Evidence: .sisyphus/evidence/task-8-publish-exists.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): add publish command`
  - Files: `lib/src/cli/commands/publish_command.dart`, `test/cli/publish_command_test.dart`
  - Pre-commit: `dart test test/cli/publish_command_test.dart`

- [ ] 9. Channels Command — New (TDD)

  **What to do**:
  - Write tests FIRST in `test/cli/channels_command_test.dart`
  - Create `lib/src/cli/commands/channels_command.dart`
  - List all notification channels and their config status:
    - **database**: enabled/disabled, polling interval
    - **push**: driver name, app_id presence (masked), soft prompt status
    - **mail**: enabled/disabled
  - Read config file and parse values (reuse regex patterns from ConfigureCommand)
  - Use `ConsoleStyle.table()` for structured output
  - If config file doesn't exist, show error and suggest `dart run magic_notifications install`

  **Must NOT do**:
  - Do NOT make API calls
  - Do NOT modify config

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Simple read-only command, table display
  - **Skills**: [`anilcan-coding`]

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 7, 8)
  - **Parallel Group**: Wave 3
  - **Blocks**: Tasks 10, 11
  - **Blocked By**: Task 1

  **References**:
  - `lib/src/cli/commands/configure_command.dart:162-204` — `readCurrentConfig()` regex patterns to reuse for parsing channel status
  - `/Users/anilcan/StudioProjects/uptizm/plugins/magic/plugins/magic_cli/lib/src/helpers/console_style.dart` — `ConsoleStyle.table()` for formatted output

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/channels_command_test.dart` → PASS
  - [ ] `ChannelsCommand` has `name => 'channels'`
  - [ ] Shows database, push, mail channels with status
  - [ ] Shows error if config missing

  **QA Scenarios:**
  ```
  Scenario: Channels shows all three channels
    Tool: Bash
    Steps:
      1. Create temp project with notification config
      2. Run channels command
      3. Assert: output contains 'database', 'push', 'mail'
      4. Assert: output shows enabled/disabled status for each
    Expected Result: Table with all channels
    Evidence: .sisyphus/evidence/task-9-channels.txt

  Scenario: Channels errors when no config
    Tool: Bash
    Steps:
      1. Create temp project without config file
      2. Run channels command
      3. Assert: error message about missing config
    Expected Result: Error with install suggestion
    Evidence: .sisyphus/evidence/task-9-channels-no-config.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): add channels command`
  - Files: `lib/src/cli/commands/channels_command.dart`, `test/cli/channels_command_test.dart`
  - Pre-commit: `dart test test/cli/channels_command_test.dart`

- [ ] 10. Delete Obsolete Files + Final Cleanup

  **What to do**:
  - Delete `lib/src/cli/commands/status_command.dart` (replaced by doctor)
  - Delete `lib/src/cli/helpers/` directory entirely (NotificationConfigHelper deleted in Task 2)
  - Update `bin/magic_notifications.dart`:
    - Remove `StatusCommand` import and registration
    - Add imports for all new commands: `DoctorCommand`, `UninstallCommand`, `PublishCommand`, `ChannelsCommand`
    - Register all 7 commands in `kernel.registerMany([])`
  - Verify no broken imports across all CLI files
  - Run `dart analyze lib/src/cli/` to confirm zero issues

  **Must NOT do**:
  - Do NOT modify any command logic — this is cleanup only
  - Do NOT delete test files

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: File deletion and import cleanup
  - **Skills**: [`anilcan-coding`]

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (sequential)
  - **Blocks**: Task 11
  - **Blocked By**: Tasks 2, 4, 5, 6, 7, 8, 9

  **References**:
  - `bin/magic_notifications.dart` — entry point to update with all 7 command registrations
  - `lib/src/cli/commands/status_command.dart` — file to delete

  **Acceptance Criteria**:
  - [ ] `status_command.dart` deleted
  - [ ] `lib/src/cli/helpers/` directory deleted
  - [ ] `bin/magic_notifications.dart` registers exactly 7 commands
  - [ ] `dart analyze lib/src/cli/` → no issues
  - [ ] `dart analyze bin/` → no issues

  **QA Scenarios:**
  ```
  Scenario: No obsolete files remain
    Tool: Bash
    Steps:
      1. Run: test ! -f lib/src/cli/commands/status_command.dart && echo 'DELETED'
      2. Assert: 'DELETED'
      3. Run: test ! -d lib/src/cli/helpers && echo 'DELETED'
      4. Assert: 'DELETED'
      5. Run: dart analyze lib/src/cli/ bin/
      6. Assert: 'No issues found'
    Expected Result: Clean codebase
    Evidence: .sisyphus/evidence/task-10-cleanup.txt
  ```

  **Commit**: YES
  - Message: `chore(cli): remove obsolete files and update command registry`
  - Files: deleted files, `bin/magic_notifications.dart`
  - Pre-commit: `dart analyze lib/src/cli/ bin/`

- [ ] 11. Full Test Run + README CLI Section Update

  **What to do**:
  - Run full test suite: `dart test test/cli/`
  - Fix any failing tests
  - Update README.md CLI Commands section:
    - Replace `dart run magic_notifications:install` → `dart run magic_notifications install`
    - Replace `dart run magic_notifications:configure` → `dart run magic_notifications configure`
    - Replace `dart run magic_notifications:status` → `dart run magic_notifications doctor`
    - Replace `dart run magic_notifications:test` → `dart run magic_notifications test`
    - Add sections for new commands: uninstall, publish, channels, doctor
    - Remove status command section
  - Run `dart analyze` on entire project to verify no regressions

  **Must NOT do**:
  - Do NOT rewrite the entire README — only update CLI sections

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Integration testing + documentation update
  - **Skills**: [`anilcan-coding`, `anilcan-doc-writer`]
    - `anilcan-coding`: Verify all tests pass
    - `anilcan-doc-writer`: Update CLI docs in README following doc standards

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 4 (after Task 10)
  - **Blocks**: F1-F4
  - **Blocked By**: Task 10

  **References**:
  - `README.md` — current CLI documentation section
  - All `test/cli/*.dart` files

  **Acceptance Criteria**:
  - [ ] `dart test test/cli/` → ALL PASS
  - [ ] `dart analyze` → no issues
  - [ ] README has updated command examples with `dart run magic_notifications [cmd]`
  - [ ] README has sections for: install, configure, test, doctor, uninstall, publish, channels
  - [ ] README does NOT mention `status` command or `magic_notifications`

  **QA Scenarios:**
  ```
  Scenario: All tests pass
    Tool: Bash
    Steps:
      1. Run: dart test test/cli/
      2. Assert: exit code 0, all tests pass
    Expected Result: Zero failures
    Evidence: .sisyphus/evidence/task-11-tests.txt

  Scenario: README is updated
    Tool: Bash
    Steps:
      1. Run: grep 'dart run magic_notifications install' README.md
      2. Assert: matches found
      3. Run: grep 'magic_notifications' README.md
      4. Assert: no matches (exit code 1)
      5. Run: grep 'dart run magic_notifications doctor' README.md
      6. Assert: matches found
    Expected Result: All CLI references updated
    Evidence: .sisyphus/evidence/task-11-readme.txt
  ```

  **Commit**: YES
  - Message: `docs(cli): update README with new CLI command reference`
  - Files: `README.md`
  - Pre-commit: `dart test test/cli/ && dart analyze`

---
## Final Verification Wave

> 4 review agents run in PARALLEL. ALL must APPROVE. Rejection → fix → re-run.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists (read file, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in .sisyphus/evidence/. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `dart analyze` + `dart test`. Review all changed files for: `as dynamic`, empty catches, print() in prod, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic names. Verify all public methods have dartdoc. Verify 120-char line limit, 4-space indent, trailing commas, multi-line collections.
  Output: `Analyze [PASS/FAIL] | Tests [N pass/N fail] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real Manual QA** — `unspecified-high` + `anilcan-coding` skill
  Create a temp Flutter project. Run every CLI command end-to-end:
  - `dart run magic_notifications install --force`
  - `dart run magic_notifications configure --show`
  - `dart run magic_notifications doctor`
  - `dart run magic_notifications test --dry-run`
  - `dart run magic_notifications channels`
  - `dart run magic_notifications publish`
  - `dart run magic_notifications uninstall`
  Capture all output. Verify files created/modified/deleted correctly.
  Output: `Commands [N/N pass] | Files [N correct] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual diff. Verify 1:1 — everything in spec was built, nothing beyond spec. Check "Must NOT do" compliance: no runtime code changes, no files outside allowed directories. Detect cross-task contamination. Flag unaccounted changes.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | VERDICT`

---

## Commit Strategy

| Wave | Commit | Files |
|------|--------|-------|
| 1 | `refactor(cli): rename entry point and create stub files` | bin/, assets/stubs/, pubspec.yaml |
| 1 | `refactor(cli): rewrite install command with StubLoader pattern` | lib/src/cli/commands/install_command.dart, test/ |
| 2 | `refactor(cli): clean up configure and test commands` | lib/src/cli/commands/configure_command.dart, test_command.dart, test/ |
| 2 | `feat(cli): add doctor command replacing status` | lib/src/cli/commands/doctor_command.dart, test/ |
| 3 | `feat(cli): add uninstall, publish, channels commands` | lib/src/cli/commands/*.dart, test/ |
| 4 | `chore(cli): remove obsolete files and update barrel exports` | lib/src/cli/, bin/ |

---

## Success Criteria

### Verification Commands
```bash
dart test test/cli/                    # Expected: All tests pass
dart analyze lib/src/cli/              # Expected: No issues found
dart run magic_notifications install --help  # Expected: Shows help with options
dart run magic_notifications doctor    # Expected: Shows diagnostic output
```

### Final Checklist
- [ ] All "Must Have" present
- [ ] All "Must NOT Have" absent
- [ ] All 7 commands registered and working
- [ ] Zero hardcoded templates
- [ ] All tests pass
- [ ] No `magic_notifications` references in CLI code
