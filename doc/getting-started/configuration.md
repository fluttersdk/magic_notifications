# Configuration

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-config-map"></a>[Full Config Map Reference](#config-map)
- <a name="toc-push"></a>[notifications.push](#push)
- <a name="toc-database"></a>[notifications.database](#database)
- <a name="toc-mail"></a>[notifications.mail](#mail)
- <a name="toc-soft-prompt"></a>[notifications.soft_prompt](#soft-prompt)
- <a name="toc-env"></a>[Environment Variables](#env)
- <a name="toc-runtime"></a>[Runtime Config Access](#runtime)

---

## <a name="overview"></a>Overview

All configuration lives in a single Dart map returned by `notificationConfig`, typically at `lib/config/notifications.dart`. The Magic Framework's `ConfigRepository` merges this map at boot time so that `Config.get(key)` resolves values at any point in the application lifecycle.

> [!NOTE]
> Create this file with the CLI (`dart run magic_notifications publish` or `dart run magic_notifications install`) rather than writing it by hand, to ensure the structure matches what `NotificationServiceProvider` expects.

---

## <a name="config-map"></a>Full Config Map Reference

```dart
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': const String.fromEnvironment('ONESIGNAL_APP_ID'),
      // 'safari_web_id': 'web.onesignal.auto.xxx',  // web only, optional
      'notify_button_enabled': false,
    },
    'database': {
      'enabled': true,
      'polling_interval': 30,
    },
    'mail': {
      'enabled': false,
    },
    'soft_prompt': {
      'enabled': true,
      'title': 'Stay Updated',
      'message': 'Get notified about important events.',
    },
  },
};
```

---

## <a name="push"></a>notifications.push

Controls the push notification channel and its driver.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `driver` | `String` | `'onesignal'` | Push driver identifier. `'onesignal'` is the only built-in driver. |
| `app_id` | `String` | `''` | OneSignal App ID (UUID format). Must be non-empty for push to function. |
| `safari_web_id` | `String?` | `null` | Safari Web Push ID for Safari browser support. Optional — omit for non-Safari targets. |
| `notify_button_enabled` | `bool` | `false` | Whether to show the floating OneSignal notification bell widget on web. |

> [!NOTE]
> `NotificationServiceProvider.boot()` reads `notifications.push.driver` first. If it equals `'onesignal'`, it calls `createOneSignalDriver()` (which returns `OneSignalWebDriver` on web, `OneSignalDriver` on iOS/Android) and initializes it with `app_id`, `safari_web_id`, and `notify_button_enabled`.

> [!TIP]
> Pass `app_id` via `String.fromEnvironment('ONESIGNAL_APP_ID')` so the value is injected at compile time from your `.env` file, keeping the App ID out of source control.

---

## <a name="database"></a>notifications.database

Controls the in-app (database) notification channel and its polling behavior.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | `bool` | `true` | Whether the database channel is active. |
| `polling_interval` | `int` | `30` | Seconds between `GET /notifications` requests. Valid range: 5–600. |

`NotificationPoller` uses the default interval of 30 seconds when no config override is applied. Change it with:

```bash
dart run magic_notifications configure --polling-interval 60
```

---

## <a name="mail"></a>notifications.mail

Controls the mail notification channel.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | `bool` | `false` | Whether mail notifications are active. Mail dispatch is handled server-side. |

> [!NOTE]
> Mail notifications are sent by the backend. The Flutter client only reads this flag to know whether to render mail preference toggles in the UI.

---

## <a name="soft-prompt"></a>notifications.soft_prompt

Controls the pre-permission soft prompt dialog rendered by `PushPromptDialog`.

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | `bool` | `true` | Whether to show the soft prompt before the OS permission dialog. |
| `title` | `String` | `'Stay Updated'` | Dialog title text. |
| `message` | `String` | `'Get notified about important events.'` | Dialog body text. |

When `enabled` is `true`, show `PushPromptDialog` before calling `Notify.requestPushPermission()`. The dialog gives the user context before the non-dismissable OS prompt appears.

---

## <a name="env"></a>Environment Variables

| Variable | Used In | Description |
|----------|---------|-------------|
| `ONESIGNAL_APP_ID` | `notifications.push.app_id` | OneSignal App ID injected at compile time via `String.fromEnvironment`. |

Set in `.env` (or your CI secrets):

```
ONESIGNAL_APP_ID=12345678-1234-1234-1234-123456789012
```

Build with the variable injected:

```bash
flutter build apk --dart-define-from-file=.env
flutter build web --dart-define-from-file=.env
```

---

## <a name="runtime"></a>Runtime Config Access

After the Magic Framework boots, any config value is accessible via `Config.get`:

```dart
// Read the push App ID
final appId = Config.get<String>('notifications.push.app_id');

// Read the polling interval (returns int)
final interval = Config.get<int>('notifications.database.polling_interval');

// Read soft prompt enabled flag
final softPromptEnabled = Config.get<bool>('notifications.soft_prompt.enabled');
```

`Config.get` returns `null` when the key is absent; use the typed overload with a default:

```dart
final enabled = Config.get<bool>('notifications.database.enabled') ?? true;
```

---

**Related**

- [Installation](https://magic.fluttersdk.com/packages/notifications/getting-started/installation)
- [Service Provider](https://magic.fluttersdk.com/packages/notifications/architecture/service-provider)
- [CLI Reference](https://magic.fluttersdk.com/packages/notifications/basics/cli)
