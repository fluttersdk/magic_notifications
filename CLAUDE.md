# Magic Notifications Plugin

Flutter push and database notification plugin for the Magic Framework. In-app polling + OneSignal (mobile/web) via `onesignal_flutter` package.

**Version:** 0.0.1-alpha.1 · **Dart:** >=3.6.0 · **Flutter:** >=3.27.0

## Commands

| Command | Description |
|---------|-------------|
| `flutter test --coverage` | Run all tests with coverage |
| `flutter analyze --no-fatal-infos` | Static analysis |
| `dart format .` | Format all code |
| `dart run magic_notifications install` | Interactive setup wizard |
| `dart run magic_notifications configure` | Update notification config |
| `dart run magic_notifications doctor` | Health check |
| `dart run magic_notifications test` | Send test notification |
| `dart run magic_notifications channels` | List channel status |
| `dart run magic_notifications uninstall` | Remove plugin integration |
| `dart run magic_notifications publish` | Copy config stub to project |

## Architecture

**Pattern**: ServiceProvider + Singleton Manager + Channel/Driver chain

```
lib/
├── magic_notifications.dart       # Barrel export (Channels, Contracts, Drivers, Facades, Models, Providers, Widgets, Exceptions)
└── src/
    ├── notification_manager.dart  # Singleton — channel + driver orchestration
    ├── notification_poller.dart   # Timer-based polling with pause/resume
    ├── channels/                  # DatabaseChannel, PushChannel
    ├── contracts/                 # Notification, NotificationChannel, Notifiable
    ├── drivers/push/             # OneSignalDriver (mobile), OneSignalWebDriver (web)
    ├── drivers/push_web/         # Web JS interop (conditional import)
    ├── facades/                   # Notify (static API)
    ├── models/                    # DatabaseNotification, PushMessage, NotificationPreference, etc.
    ├── providers/                 # NotificationServiceProvider (register + boot)
    ├── widgets/                   # PushPromptDialog
    ├── exceptions/               # NotificationException
    └── cli/commands/             # install, configure, doctor, test, channels, uninstall, publish
bin/
└── magic_notifications.dart       # CLI entry point
assets/stubs/                      # Stub templates for code generation
```

**Data flow:** App boot → `NotificationServiceProvider.boot()` → registers channels + push driver → `Notify.startPolling()` → `NotificationPoller` fetches via HTTP → emits to broadcast stream. Push: `Notify.initializePush()` → OneSignalDriver → platform-specific (mobile vs web JS interop)

**Pure Dart** — no android/, ios/, or native platform code. Platform support via `onesignal_flutter` package.

## Post-Change Checklist

After ANY source code change, sync **before committing**:

1. **`CHANGELOG.md`** — Add entry under `[Unreleased]` section
2. **`README.md`** — Update if features, API, or usage changes
3. **`doc/`** — Update relevant documentation files

## Development Flow (TDD)

Every feature, fix, or refactor must go through the red-green-refactor cycle:

1. **Red** — Write a failing test that describes the expected behavior
2. **Green** — Write the minimum code to make the test pass
3. **Refactor** — Clean up while keeping tests green

**Rules:**
- No production code without a failing test first
- Run `flutter test` after every change — all tests must stay green
- Run `dart analyze` after every change — zero warnings, zero errors
- Run `dart format .` before committing — zero formatting issues

**Verification cycle:** Edit → `flutter test` → `dart analyze` → repeat until green

## Testing

- Mock via contract inheritance (no mockito): `class MockNotificationChannel extends NotificationChannel`
- Reset state in setUp: singleton state reset
- Tests mirror `lib/src/` structure in `test/`
- CLI tests in `test/cli/commands/`

## Key Gotchas

| Mistake | Fix |
|---------|-----|
| OneSignal blocks bare numeric IDs | Always use `user_` prefix: `Notify.initializePush('user_$userId')` |
| Hardcoded config values | Read from `ConfigRepository`: `config.get('notifications.push.app_id')` |
| Direct manager instantiation | Use singleton factory: `NotificationManager()` |
| Timer leak in poller | Ensure `stop()` on dispose |
| Direct web push imports | Use conditional imports via `onesignal_factory.dart` |
| Optimistic updates without rollback | Always rollback on API failure in markAsRead/delete |
| Missing stream disposal | `StreamController` must be disposed in provider teardown |

## Skills & Extensions

- `fluttersdk:magic-framework` — Magic Framework patterns: facades, service providers, IoC, Eloquent ORM, controllers, routing. Use for ANY code touching Magic APIs.

## CI

- `ci.yml`: push/PR → `flutter pub get` → `flutter analyze --no-fatal-infos` → `dart format --set-exit-if-changed` → `flutter test --coverage` → codecov upload
- `publish.yml`: tag-triggered → validate → publish to pub.dev via OIDC
