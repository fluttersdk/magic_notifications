---
paths:
  - "test/**/*.dart"
---

# Testing Domain

- Mock via contract inheritance (no mockito): `class MockNotificationChannel extends NotificationChannel { ... }`
- Mock drivers: override `name`, `isSupported`, `onReceived` and `onIdentityChanged` (return `Stream.empty()`), `permissionState()` (async), `currentExternalId()`, `currentSubscriptionId()`, `initialize()`, `dispose()`
- Reset singleton state in setUp: `manager.forgetDrivers()` clears channels, the registered factories, the resolved driver and the IN-MEMORY push intent. It deliberately leaves the PERSISTED intent alone, because a test-isolation helper must not sign a real device out. Call it in every `setUp()`.
- Test structure mirrors `lib/src/` exactly: `test/channels/`, `test/contracts/`, `test/drivers/`, `test/facades/`, `test/models/`, `test/providers/`, `test/cli/`
- Call `initMagicForTests()` from `test/test_helper.dart` in `main()` before any test needing Magic bindings
- CLI tests in `test/cli/commands/` — override `getProjectRoot()` and `getStubSearchPaths()` for temp dirs
- Use `group()` for logical grouping by feature/scenario
- Import from `package:magic_notifications/src/...` (internal paths) in tests, not barrel — tests need granular access
- Assertions: `expect()`, `isA<T>()`, `throwsA()`, `isFalse`, `isTrue`, `isNull`, `isNotNull`
- Stream testing: listen to `Notify.notifications()`, trigger fetch, verify emission
- Provider tests: create `MagicApp.instance`, register provider, verify bindings with `app.make<T>('key')`
- Exception tests: verify `NotificationException` message, code, `toString()` output
