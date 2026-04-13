---
path: "lib/**/*.dart"
---

# Flutter / Dart Stack

- Dart >=3.6.0, Flutter >=3.27.0 — use modern patterns (records, switch expressions, strict null safety)
- Import order: dart/flutter stdlib → third-party packages → `package:magic/magic.dart` → `package:magic_notifications/...` → relative imports
- Naming: `{Concept}Manager` (singleton), `{Concept}Channel` (delivery), `{Concept}Driver` (push impl), `Notification` (base), `Notifiable` (mixin), `{Concept}ServiceProvider` (bootstrap), `{Concept}Exception`
- Singleton pattern: `static final _instance = Class._internal(); factory Class() => _instance;`
- Contract-first: abstract class defines API (`NotificationChannel`, `Notification`, `Notifiable`, `PushDriver`). Implementations in subdirectories
- Two-phase bootstrap: `register()` binds singletons to IoC (sync), `boot()` configures them (`Future<void>`)
- IoC binding: `app.singleton('key', () => Service())` in register, `app.make<T>('key')` in boot
- Config access: static type-safe call — `Config.get<String>('notifications.push.driver')`, never hardcode or use instance
- Safe logging: wrap `Log.error()` / `Log.info()` in try/catch — Log service may not be bound in tests
- Channel contract: `name`, `isAvailable`, `send(Notifiable, Notification)`
- Driver contract: `name`, `isSupported`, `initialize(Map config)`, `dispose()`, stream events
- Streams: `StreamController<T>.broadcast()` for multi-listener events
- Conditional imports for web (onesignal_factory.dart pattern)
- Barrel export: `lib/magic_notifications.dart` groups by concern (Core, Channels, Drivers, Providers, Exceptions)
- Optimistic updates with rollback on API failure
- `analysis_options.yaml` uses `package:flutter_lints/flutter.yaml` — zero warnings required
