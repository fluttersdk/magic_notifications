# CLI Refactor Decisions

## [2026-02-28] Session: ses_35af40e63ffeeaaBal377J8Los — Initial

### Architecture Decisions
1. Entry point renamed bin/notifications.dart → bin/magic_notifications.dart
2. NotificationConfigHelper removed entirely — logic moves to install command + stubs
3. status_command.dart → replaced by doctor_command.dart
4. Wizard flow in InstallCommand preserved verbatim (keep interactive + non-interactive)
5. Uninstall does NOT touch platform files (AndroidManifest, index.html, OneSignalSDKWorker.js)
6. Publish = Laravel vendor:publish — copies stub to user project for customization
7. Doctor = StatusCommand + config validation (UUID format, polling interval range, soft prompt section)

### Stub File Design
- notification_config.stub: uses `{{ placeholder }}` syntax — NOT Dart string interpolation
- onesignal_worker.stub: static content (no placeholders needed)
- onesignal_script.stub: static HTML block (no placeholders needed)

### Test Strategy
- TDD: write failing test first, then implement
- Tests in test/cli/ directory
- Use injected temp dirs via overridable getProjectRoot()
- No E2E tests — unit test with temp dirs
