---
path: "test/**/*.dart"
---

# Testing Domain

- Mock via contract inheritance (no mockito): `class MockNotificationChannel extends NotificationChannel { ... }`
- Mock drivers: override `name`, `isSupported`, `onReceived` (return `Stream.empty()`), `initialize()`, `dispose()`
- Reset singleton state in setUp: clear channels, clear push driver
- Test structure mirrors `lib/src/` exactly: `test/channels/`, `test/contracts/`, `test/drivers/`, `test/facades/`, `test/models/`, `test/providers/`, `test/cli/`
- CLI tests in `test/cli/commands/` — override `getProjectRoot()` and `getStubSearchPaths()` for temp dirs
- Use `group()` for logical grouping by feature/scenario
- Import from `package:magic_notifications/src/...` (internal paths) in tests, not barrel — tests need granular access
- Assertions: `expect()`, `isA<T>()`, `throwsA()`, `isFalse`, `isTrue`, `isNull`, `isNotNull`
- Stream testing: listen to `Notify.notifications()`, trigger fetch, verify emission
- Provider tests: create `MagicApp.instance`, register provider, verify bindings with `app.make<T>('key')`
- Exception tests: verify `NotificationException` message, code, `toString()` output
