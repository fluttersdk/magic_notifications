# Installation

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-pubdev"></a>[pub.dev Dependency Setup](#pubdev)
- <a name="toc-cli-wizard"></a>[CLI Installation Wizard](#cli-wizard)
- <a name="toc-service-provider"></a>[Service Provider Registration](#service-provider)
- <a name="toc-main-dart"></a>[Config Factory in main.dart](#main-dart)
- <a name="toc-platform-setup"></a>[Platform Setup Summary](#platform-setup)
- <a name="toc-next-steps"></a>[Next Steps](#next-steps)

---

## <a name="overview"></a>Overview

Magic Notifications is a multi-channel notification plugin for Flutter apps built on the Magic Framework. It ships with a built-in CLI that automates the entire setup process — dependency declaration, config file creation, platform-specific files, and provider injection.

> [!NOTE]
> The CLI wizard is the recommended installation path. Manual setup requires you to replicate every step the CLI performs; use it only when your CI/CD pipeline demands fully scripted control.

---

## <a name="pubdev"></a>pub.dev Dependency Setup

Add the package to your `pubspec.yaml`:

```yaml
dependencies:
  magic_notifications: ^0.1.0
```

Then fetch dependencies:

```bash
flutter pub get
```

For local development within a monorepo (e.g., `plugins/magic_notifications`):

```yaml
dependencies:
  magic_notifications:
    path: ./plugins/magic_notifications
```

---

## <a name="cli-wizard"></a>CLI Installation Wizard

Run the interactive wizard from your Flutter project root:

```bash
dart run magic_notifications install
```

The wizard guides you through four steps:

1. **OneSignal App ID** — prompts for your UUID-format App ID (get it from the [OneSignal Dashboard](https://onesignal.com/))
2. **Platform selection** — detects existing platform directories; confirm each one
3. **Web configuration** (web only) — optional Safari Web ID, optional notify button
4. **Soft prompt** — whether to show a custom dialog before the OS permission prompt

### Non-Interactive Mode (CI/CD)

```bash
dart run magic_notifications install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012 \
  --platforms android,ios,web
```

```bash
# With web extras
dart run magic_notifications install \
  --non-interactive \
  --app-id YOUR_APP_ID \
  --platforms web \
  --safari-web-id web.onesignal.auto.xxx \
  --notify-button
```

```bash
# Disable soft prompt and overwrite any existing config
dart run magic_notifications install \
  --non-interactive \
  --app-id YOUR_APP_ID \
  --no-soft-prompt \
  --force
```

### What the CLI Produces

| Artifact | Path |
|----------|------|
| Notification config | `lib/config/notifications.dart` |
| Android permission | `android/app/src/main/AndroidManifest.xml` |
| Web service worker | `web/OneSignalSDKWorker.js` |
| Web SDK script | `web/index.html` (injected) |
| Provider injection | `lib/config/app.dart` (injected) |
| Config factory | `lib/main.dart` (injected) |

> [!TIP]
> Run `dart run magic_notifications doctor` immediately after installation to verify every required artifact is in place.

---

## <a name="service-provider"></a>Service Provider Registration

If you ran the CLI, `lib/config/app.dart` is already updated. For manual setup, add the import and provider entry:

```dart
import 'package:magic_notifications/magic_notifications.dart';

final providers = [
  // ... other providers
  (app) => NotificationServiceProvider(app),
];
```

The `NotificationServiceProvider` runs two phases during framework boot:

- `register()` — binds `NotificationManager` as a singleton under the `'notifications'` key
- `boot()` — reads config, initializes the OneSignal push driver, starts no polling on its own

See [Service Provider Architecture](../architecture/service-provider.md) for the full boot sequence.

---

## <a name="main-dart"></a>Config Factory in main.dart

The notification config must be passed to `Magic.init` as a config factory:

```dart
import 'config/notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationConfig,  // add this
    ],
  );

  runApp(MyApp());
}
```

The `notificationConfig` getter is defined in `lib/config/notifications.dart` (created by the CLI or `publish` command). Its shape:

```dart
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': const String.fromEnvironment('ONESIGNAL_APP_ID'),
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

Add the App ID to your `.env`:

```
ONESIGNAL_APP_ID=your-onesignal-app-id-here
```

---

## <a name="platform-setup"></a>Platform Setup Summary

### iOS

iOS push requires manual steps in Xcode — the CLI cannot automate them.

1. Open `ios/Runner.xcworkspace` (not `.xcodeproj`)
2. Select the **Runner** target → **Signing & Capabilities**
3. Add capability **Push Notifications**
4. Add capability **Background Modes** → check **Remote notifications**
5. Run `cd ios && pod install --repo-update && cd ..`
6. Create an APNs key in [Apple Developer Portal](https://developer.apple.com/account/resources/authkeys/list) (.p8 file + Key ID + Team ID)
7. Upload the .p8 key to OneSignal Dashboard → Settings → Platforms → Apple iOS (APNs)

> [!NOTE]
> Push notifications do not work on iOS Simulator. A physical device is required for testing.

### Android

**`android/app/build.gradle`** — set minimum SDK:

```gradle
android {
    defaultConfig {
        minSdkVersion 21
    }
}
```

**`android/app/src/main/AndroidManifest.xml`** — add permissions (the CLI injects `POST_NOTIFICATIONS` automatically):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

### Web

The CLI creates the service worker and injects the SDK script. Manually:

**`web/OneSignalSDKWorker.js`**:

```javascript
importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");
```

> [!NOTE]
> Use `OneSignalSDK.sw.js` for the service worker file and `OneSignalSDK.page.js` for the `<script>` tag in `index.html`. They are different build targets.

**`web/manifest.json`** — add GCM sender ID:

```json
{
  "gcm_sender_id": "482941778795",
  "gcm_sender_id_comment": "Do not change. Required for OneSignal Web Push."
}
```

For the full platform guides, see [README.md](../../README.md).

---

## <a name="next-steps"></a>Next Steps

1. Run `dart run magic_notifications doctor` to confirm setup health
2. Read [Configuration](./configuration.md) for all config key details
3. Add polling and push login to your auth flow — see [README.md](../../README.md)
4. Explore [Channels](../basics/channels.md) and [Drivers](../basics/drivers.md)

---

**Related**

- [Configuration](https://magic.fluttersdk.com/packages/notifications/getting-started/configuration)
- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
- [CLI Reference](https://magic.fluttersdk.com/packages/notifications/basics/cli)
