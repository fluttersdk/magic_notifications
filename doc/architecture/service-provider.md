# Service Provider

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-two-phase"></a>[Two-Phase Bootstrap Pattern](#two-phase)
- <a name="toc-register"></a>[register() — IoC Binding](#register)
- <a name="toc-boot"></a>[boot() — Push Driver Initialization](#boot)
- <a name="toc-config-loading"></a>[Config Loading from ConfigRepository](#config-loading)
- <a name="toc-ioc"></a>[IoC Integration](#ioc)
- <a name="toc-registration"></a>[Registering the Provider](#registration)

---

## <a name="overview"></a>Overview

`NotificationServiceProvider` is the bootstrap entry point for the magic_notifications plugin. It extends the Magic Framework's `ServiceProvider` and is responsible for wiring `NotificationManager` into the IoC container and initializing the push driver from config.

```dart
class NotificationServiceProvider extends ServiceProvider {
  NotificationServiceProvider(super.app);

  @override
  void register() { ... }

  @override
  Future<void> boot() async { ... }
}
```

---

## <a name="two-phase"></a>Two-Phase Bootstrap Pattern

The Magic Framework's service provider contract separates bootstrapping into two phases:

| Phase | Method | Timing | Purpose |
|-------|--------|--------|---------|
| 1 | `register()` | Synchronous, early | Bind services into the IoC container |
| 2 | `boot()` | Async, after all providers registered | Initialize services that depend on other bindings |

`register()` is called for all providers before `boot()` is called for any provider. This guarantees that by the time `boot()` runs, every binding registered by all other providers is already available.

---

## <a name="register"></a>register() — IoC Binding

```dart
@override
void register() {
  app.singleton('notifications', () => NotificationManager());
}
```

`register()` does one thing: bind the `NotificationManager` singleton under the `'notifications'` key. Because `NotificationManager` is itself a Dart-level singleton (factory constructor), the IoC binding and the direct constructor call always return the same instance.

After `register()` completes, any code in the app can resolve the manager:

```dart
final manager = app.make<NotificationManager>('notifications');
```

> [!NOTE]
> Channel registration (`DatabaseChannel`, `PushChannel`) is **not** done here. Channels depend on the push driver, which requires async config reading — that belongs in `boot()`.

---

## <a name="boot"></a>boot() — Push Driver Initialization

```dart
@override
Future<void> boot() async {
  final manager = NotificationManager();

  final pushDriver = Config.get<String>('notifications.push.driver');
  if (pushDriver == 'onesignal') {
    final driver = createOneSignalDriver();
    manager.setPushDriver(driver);

    final appId = Config.get<String>('notifications.push.app_id');
    final safariWebId = Config.get<String>('notifications.push.safari_web_id');
    final notifyButtonEnabled =
        Config.get<bool>('notifications.push.notify_button_enabled') ?? false;

    if (appId != null && appId.isNotEmpty) {
      try {
        await driver.initialize({
          'app_id': appId,
          'safari_web_id': safariWebId,
          'notify_button_enabled': notifyButtonEnabled,
        });
      } catch (e) {
        _log('Failed to initialize OneSignal: $e', isError: true);
      }
    }
  }
}
```

The `boot()` sequence:

1. Read `notifications.push.driver` from `ConfigRepository`
2. If `'onesignal'`, call `createOneSignalDriver()` (returns platform-appropriate driver via conditional imports)
3. Call `manager.setPushDriver(driver)` — makes the driver accessible via `NotificationManager().pushDriver`
4. Read `app_id`, `safari_web_id`, `notify_button_enabled` from config
5. Call `driver.initialize(config)` if `app_id` is present and non-empty
6. Catch any initialization errors and log them without rethrowing — a failed push init should not prevent the app from starting

> [!NOTE]
> `boot()` does not start database polling. Polling should be started from your authenticated layout's `initState` via `Notify.startPolling()`, so it only runs when a user is logged in.

---

## <a name="config-loading"></a>Config Loading from ConfigRepository

`Config.get` is the Magic Framework's static accessor for the merged config map. The provider reads values using dot-notation keys:

```dart
// String values
Config.get<String>('notifications.push.driver')    // 'onesignal'
Config.get<String>('notifications.push.app_id')    // '12345678-...'
Config.get<String>('notifications.push.safari_web_id')  // nullable

// Bool values
Config.get<bool>('notifications.push.notify_button_enabled')  // false
Config.get<bool>('notifications.database.enabled')            // true
Config.get<bool>('notifications.soft_prompt.enabled')         // true

// Int values
Config.get<int>('notifications.database.polling_interval')    // 30
```

All keys are null-safe — `Config.get` returns `null` when a key is absent or has the wrong type. The provider uses `?? false` / `?? 0` where a non-null default is required.

The config values originate from the `notificationConfig` getter in `lib/config/notifications.dart`, which is registered as a config factory in `Magic.init`:

```dart
await Magic.init(
  configFactories: [
    () => appConfig,
    () => notificationConfig,
  ],
);
```

---

## <a name="ioc"></a>IoC Integration

### Binding

```dart
app.singleton('notifications', () => NotificationManager());
```

`app.singleton` registers a lazy singleton factory. The factory is called once on first resolution and the result is cached for subsequent `make` calls.

### Resolution

```dart
// Resolve by key
final manager = app.make<NotificationManager>('notifications');

// Or use the direct constructor (same instance)
final manager = NotificationManager();
```

Both resolution paths return identical references because `NotificationManager()` is a Dart-level singleton regardless of the IoC binding.

---

## <a name="registration"></a>Registering the Provider

Add `NotificationServiceProvider` to your app's provider list in `lib/config/app.dart`:

```dart
import 'package:magic_notifications/magic_notifications.dart';

final providers = [
  // ... other framework providers first
  (app) => NotificationServiceProvider(app),
];
```

The provider must be registered **after** any providers it depends on (e.g., `ConfigServiceProvider`, `HttpServiceProvider`). The Magic Framework's `Config` and `Http` services must be available when `boot()` runs.

> [!TIP]
> Run `dart run magic_notifications install` to have the CLI inject the provider and import statement automatically, avoiding manual edits to `app.dart`.

---

**Related**

- [Notification Manager](https://magic.fluttersdk.com/packages/notifications/architecture/notification-manager)
- [Configuration](https://magic.fluttersdk.com/packages/notifications/getting-started/configuration)
- [Drivers](https://magic.fluttersdk.com/packages/notifications/basics/drivers)
