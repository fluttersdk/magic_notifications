# Configuration

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-config-map"></a>[Full Config Map Reference](#config-map)
- <a name="toc-push"></a>[notifications.push](#push)
- <a name="toc-permission"></a>[Asking for permission](#permission)
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
      'service_worker_path': 'OneSignalSDKWorker.js',
      'service_worker_scope': '/onesignal/',
      'notify_button_enabled': false,
      'self_test_enabled': false,
      'auto_request_on_login': false,
      'reprompt_after_hours': 0,
      'fallback_to_settings': true,
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
| `service_worker_path` | `String?` | `'OneSignalSDKWorker.js'` | Web only. Path to the OneSignal service worker script. A Flutter web build already registers `flutter_service_worker.js` at the root scope, so OneSignal needs its own worker rather than sharing that one. |
| `service_worker_scope` | `String?` | `'/onesignal/'` | Web only. The scope OneSignal registers its worker under. Whichever of the two registrations lands second wins the root scope, so pointing OneSignal at a scope of its own (rather than `/`) keeps it from silently losing to Flutter's worker. |
| `notify_button_enabled` | `bool` | `false` | Whether to show the floating OneSignal notification bell widget on web. |
| `auto_request_on_login` | `bool` | `false` | Whether the package may raise the OS permission prompt by itself, once, after an identity is declared through `Notify.initializePush(userId)`. Ships off, and an absent key is off: an app that upgrades without touching its config keeps asking on its own terms. See [Asking for permission](#permission) below for when it actually fires and why web needs care. |
| `reprompt_after_hours` | `int` | `0` | How long before the app's OWN reminder may be shown again to somebody who turned it down. `0` (and an absent key) means never. Read by `NotificationManager.pushPromptAdvice()`; this package never stores the decline timestamp. |
| `fallback_to_settings` | `bool` | `true` | Mobile only. Whether `requestPermission()` on an already-denied device opens the app's settings page instead of resolving silently. On by default, which is what the OneSignal driver always did; turn it off for an app that would rather ask once and drop it. Inert on web, which has no such API. |
| `self_test_enabled` | `bool` | `false` | Gates `PushChannel.send()`, the client-triggered surface that asks the backend to push a test notification to the caller's own devices. Ships off: it is a new authenticated capability whose only effect is making the platform emit a real push, and that is worth switching on deliberately once an app actually calls for it, not something worth having live from day one. Turning it on takes both halves: the backend carries the matching `magic-starter.onesignal.self_test_enabled` switch, also off by default, and answers `501` while it is off, so setting only this key changes which side refuses. |

> [!NOTE]
> `NotificationServiceProvider.boot()` reads `notifications.push.driver` first. If it equals `'onesignal'`, it calls `createOneSignalDriver()` (which returns `OneSignalWebDriver` on web, `OneSignalDriver` on iOS/Android) and initializes it with `app_id`, `safari_web_id`, `service_worker_path`, `service_worker_scope`, and `notify_button_enabled`.

> [!TIP]
> Pass `app_id` via `String.fromEnvironment('ONESIGNAL_APP_ID')` so the value is injected at compile time from your `.env` file, keeping the App ID out of source control.

---

## <a name="permission"></a>Asking for permission

There are two separate cadences here, and conflating them is the mistake this
section exists to prevent.

**The OS prompt is a one-shot.** Once a person has answered it, no code can
raise it again: on the web `Notification.requestPermission()` against a denied
origin resolves immediately with `denied` and shows nothing, and iOS and
Android behave the same way. The only route back is the browser's site
settings or the OS Settings app. So an automatic request is worth exactly one
shot, on a device that has never been asked.

**The app's own reminder is not a one-shot.** It is your UI, and it may appear
on whatever cadence you configure, including on a device whose OS permission
is denied: on mobile its button opens the app's settings page (see
`fallback_to_settings`), which is a real route back.

### The automatic request

With `auto_request_on_login: true`, the package raises the platform request
once, from `want()` (which `Notify.initializePush(userId)` calls), and only
when:

- the OS has never asked on this device (`PushDriver.canRaisePermissionRequest()`),
- the device is not already subscribed,
- and it has not already been raised in this launch.

It is never raised from `reconcilePushIdentity()`, which runs on every
auth-state change and on a signed-out boot: a dialog from there arrives with
nothing in front of it explaining what it is for.

> [!WARNING]
> On web, browsers require a user gesture for a permission request and a login
> is not one, so this key can spend the ask without rendering it. Prefer the
> reminder below, whose button is a tap.

### The reminder, and what its button can do

Ask the package rather than deriving it:

```dart
final advice = await Notify.manager.pushPromptAdvice(
  declinedAt: await myOwnStorage.readPushPromptDeclinedAt(),
);

if (!advice.show) return const SizedBox.shrink();

return switch (advice.action) {
  // A real dialog will appear: Notify.requestPushPermission().
  PushPromptAction.request => MyEnableRow(),
  // The prompt is spent, but this platform routes the same call to Settings.
  PushPromptAction.openSettings => MyOpenSettingsRow(),
  // Nowhere to send the tap. Say where the switch lives instead.
  PushPromptAction.instructions => MyBlockedInstructionsRow(),
  PushPromptAction.none => const SizedBox.shrink(),
};
```

`advice.show` already accounts for `reachability()`, `reprompt_after_hours`,
`soft_prompt.enabled`, and the timestamp you passed in. `advice.reachability`
is the same four-state read, carried so a status row does not need a second
platform call.

The decline timestamp stays yours. A decline is your UI's event, recorded
wherever you already keep device state; a copy inside this package would be a
second answer to drift out of sync with the first.

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

The package does not ship a soft-prompt dialog. It ships the reachability
read the dialog would need to decide whether to show itself at all:
`PushDriver.reachability()` on the resolved driver (see
[Drivers](../basics/drivers.md#abstract)) answers `unavailable`, `blocked`,
`off`, or `on` without triggering the OS permission dialog. Build the actual
prompt UI in the host app, gated on that read, using these config values for
its copy:

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `enabled` | `bool` | `true` | Whether the host app's own soft prompt should show before `Notify.requestPushPermission()`. `NotificationManager.pushPromptAdvice()` honours it (a `false` here answers `show: false`), so a call site using that API does not have to check it a second time. |
| `title` | `String` | `'Stay Updated'` | Suggested dialog title text. |
| `message` | `String` | `'Get notified about important events.'` | Suggested dialog body text. |

A call site that needs the raw state still reads `reachability()` directly, but
one deciding whether to interrupt somebody should ask
`NotificationManager.pushPromptAdvice()` instead: it folds this key, the
re-prompt interval and the platform's route back into one answer. See
[Asking for permission](#permission).

```dart
final reachability = await NotificationManager().pushDriver.reachability();

if (reachability == PushReachability.blocked) {
  // The OS will not re-prompt. Point at the platform setting instead.
}
```

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
