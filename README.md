<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Magic Logo" />
</p>

<h1 align="center">Magic Notifications</h1>

<p align="center">
  <strong>Multi-channel notifications for the Magic Framework.</strong><br/>
  Database, Push & Mail — one unified API.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_notifications"><img src="https://img.shields.io/pub/v/magic_notifications.svg" alt="pub.dev version" /></a>
  <a href="https://github.com/fluttersdk/magic_notifications/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/magic_notifications/ci.yml?branch=master&label=CI" alt="CI Status" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
  <a href="https://pub.dev/packages/magic_notifications/score"><img src="https://img.shields.io/pub/points/magic_notifications" alt="pub points" /></a>
  <a href="https://github.com/fluttersdk/magic_notifications/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/magic_notifications?style=flat" alt="GitHub Stars" /></a>
</p>

<p align="center">
  <a href="https://magic.fluttersdk.com/notifications">Website</a> ·
  <a href="https://magic.fluttersdk.com/packages/notifications/getting-started/installation">Docs</a> ·
  <a href="https://pub.dev/packages/magic_notifications">pub.dev</a> ·
  <a href="https://github.com/fluttersdk/magic_notifications/issues">Issues</a> ·
  <a href="https://github.com/fluttersdk/magic_notifications/discussions">Discussions</a>
</p>

---

> **Alpha** — `magic_notifications` is under active development. APIs may change between minor versions until `1.0.0`.

---

## Why Magic Notifications?

Managing notifications in Flutter means juggling multiple channels — database polling, platform-specific push setup for iOS/Android/Web, email delivery, and user preference logic scattered across your codebase. Every project reinvents the same boilerplate.

**Magic Notifications** gives you a single, unified API for every channel. One config file drives everything. One CLI command sets up your project. Channels and drivers are swappable — switch from OneSignal to another push provider without touching application code.

> **Config-driven notifications.** Define your channels, drivers, and preferences once. Magic Notifications handles the rest.

---

## Features

| | Feature | Description |
|---|---------|-------------|
| :bell: | **Multi-channel** | Database, Push, and Mail channels through one API |
| :iphone: | **OneSignal Push** | iOS, Android, and Web push via `onesignal_flutter` |
| :arrows_counterclockwise: | **Real-time Polling** | Background polling with pause/resume/stop lifecycle |
| :dart: | **User Preferences** | Global and per-type channel preference management |
| :hammer_and_wrench: | **CLI Tools** | Interactive install, configure, doctor, test, and more |
| :gear: | **Config-Driven** | All settings in one Dart config file via `ConfigRepository` |
| :speech_balloon: | **Soft Prompt** | Custom permission dialog before OS prompt |
| :globe_with_meridians: | **Web Support** | Full web push via conditional JS interop |

---

## Quick Start

### 1. Add the dependency

```yaml
dependencies:
  magic_notifications: ^0.0.1
```

### 2. Install configuration

```bash
dart run magic_notifications:install
```

This generates `lib/config/notifications.dart`, injects `NotificationServiceProvider` into `lib/config/app.dart`, wires the `notificationConfig` factory into `lib/main.dart`, and configures platform-specific setup for your selected platforms.

### 3. Boot the provider

The `NotificationServiceProvider` is automatically registered during install. On app boot, it:

- Creates the configured channels (database, push, mail)
- Initializes the push driver with your config
- Sets up background polling for database notifications
- Registers notification preferences

That's it — notifications now work across all configured channels.

---

## Configuration

After running the install command, edit `lib/config/notifications.dart`:

```dart
/// Notification configuration
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': const String.fromEnvironment('ONESIGNAL_APP_ID'),
      // Optional: Safari Web ID for Safari browser support
      // Get this from OneSignal Dashboard -> Settings -> Platforms -> Safari
      // 'safari_web_id': 'web.onesignal.auto.xxx',
      // Optional: Show floating notification button on web (default: false)
      'notify_button_enabled': false,
    },
    'database': {
      'enabled': true,
      'polling_interval': 30, // seconds
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

Add to `.env`:

```
ONESIGNAL_APP_ID=your-onesignal-app-id-here
```

All values are read at runtime via `ConfigRepository` — no hardcoded strings scattered across your codebase.

---

## Platform Setup

### iOS Setup

iOS push notifications require three parts: Xcode project configuration, APNs key from Apple, and OneSignal dashboard setup.

**1. Install CocoaPods Dependencies**

```bash
cd ios && pod install --repo-update && cd ..
```

This installs the OneSignal iOS SDK (`OneSignalXCFramework`).

**2. Configure Xcode Project**

Open the workspace (**not** the `.xcodeproj`):

```bash
open ios/Runner.xcworkspace
```

In Xcode:

1. **Select Runner project** -> Click on **Runner** target
2. Go to **Signing & Capabilities** tab
3. Select your **Team** (Apple Developer account)
4. Ensure **"Automatically manage signing"** is checked
5. Click **"+ Capability"** -> Add **"Push Notifications"**
6. Click **"+ Capability"** -> Add **"Background Modes"**
7. Under Background Modes, check **Remote notifications**

> Xcode will automatically register the App ID with Push Notifications capability in Apple Developer Portal when you build.

**3. Create APNs Key in Apple Developer Portal**

Go to [Apple Developer Portal - Keys](https://developer.apple.com/account/resources/authkeys/list):

1. Click **"+"** to create a new key
2. Enter a name (e.g., `YourApp Push Key`)
3. Check **Apple Push Notifications service (APNs)**
4. Click **Continue** -> **Register**
5. **Download the .p8 file** (you can only download it once!)
6. Note the **Key ID** shown on the confirmation page

**4. Find Your Team ID**

Go to [Apple Developer Account - Membership](https://developer.apple.com/account#MembershipDetailsCard):

- Your **Team ID** is displayed on this page (10-character alphanumeric)

**5. Configure OneSignal Dashboard**

Go to [OneSignal Dashboard](https://onesignal.com):

1. Select your app -> **Settings** -> **Platforms**
2. Click **Apple iOS (APNs)**
3. Select **".p8 Authentication Token"** method
4. Fill in:
   - **Team ID**: From Apple Developer Membership page
   - **Key ID**: Shown when you created the APNs key
   - **Bundle ID**: Your app's bundle identifier (e.g., `com.yourcompany.app`)
   - **p8 file**: Upload the `.p8` file you downloaded
5. Click **Save**

**6. Info.plist (Optional)**

The Background Modes capability in Xcode automatically adds this, but you can verify it exists in `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

**7. Test on Physical Device**

Push notifications do NOT work on iOS Simulator. You must test on a real device.

```bash
flutter run -d <your-iphone-device-id>
```

To find your device ID:
```bash
flutter devices
```

### Android Setup

**1. Update `android/app/build.gradle`**

```gradle
android {
    defaultConfig {
        minSdkVersion 21  // OneSignal requires min SDK 21
    }
}
```

**2. Add Permissions to `android/app/src/main/AndroidManifest.xml`**

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required for push notifications -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.VIBRATE"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
</manifest>
```

### Web Setup

**1. Download Service Worker from OneSignal**

Go to [OneSignal Dashboard](https://onesignal.com/) -> Settings -> Platforms -> Web Push -> Download Service Worker Files

Or create `web/OneSignalSDKWorker.js` with this content:

```javascript
importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");
```

> **Important**: Use `OneSignalSDK.sw.js` (Service Worker version), NOT `OneSignalSDK.page.js`. The `.page.js` is for the main HTML page `<script>` tag, while `.sw.js` is for the Service Worker file.

**2. Update `web/index.html`**

Add OneSignal SDK before closing `</head>` tag:

```html
<head>
  <!-- ... existing tags ... -->
  <!-- OneSignal Web SDK -->
  <script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
  <script>
    window.OneSignalDeferred = window.OneSignalDeferred || [];
    OneSignalDeferred.push(async function(OneSignal) {
      await OneSignal.init({
        appId: "YOUR_APP_ID",
        // Optional: Safari Web ID for Safari browser push support
        // Get from OneSignal Dashboard -> Settings -> Platforms -> Safari
        safari_web_id: "web.onesignal.auto.xxx",
        // Optional: Floating notification bell widget (disabled by default)
        notifyButton: {
          enable: false,
        },
      });
    });
  </script>
</head>
```

**Web Configuration Options**:

| Option | Description | Required |
|--------|-------------|----------|
| `appId` | Your OneSignal App ID | Yes |
| `safari_web_id` | Safari Web ID for Safari browser support | No |
| `notifyButton.enable` | Show floating bell widget for users to manage subscriptions | No (default: false) |

Get your Safari Web ID from: OneSignal Dashboard -> Settings -> Platforms -> Safari

Or use the CLI to generate this automatically:

```bash
dart run magic_notifications install \
  --non-interactive \
  --app-id YOUR_APP_ID \
  --platforms web \
  --safari-web-id web.onesignal.auto.xxx \
  --notify-button
```

**3. Update `web/manifest.json`**

Add GCM sender ID:

```json
{
  "gcm_sender_id": "482941778795",
  "gcm_sender_id_comment": "Do not change. Required for OneSignal Web Push."
}
```

**4. Configure OneSignal Dashboard for Web**

1. Go to OneSignal Dashboard -> Settings -> Platforms -> Web Push
2. Add your website URL (e.g., `http://localhost:8080` for testing)
3. Save configuration

---

## CLI Tools

All commands use the single entry point `dart run magic_notifications [command]`:

### `install`

Interactive wizard to set up notifications:

```bash
# Interactive mode
dart run magic_notifications install

# Non-interactive mode
dart run magic_notifications install \
  --non-interactive \
  --app-id YOUR_APP_ID \
  --platforms android,ios,web \
  --no-soft-prompt
```

| Option | Description |
|--------|-------------|
| `--app-id` | OneSignal App ID (required for non-interactive) |
| `--platforms` | Comma-separated platforms: android,ios,web |
| `--soft-prompt` / `--no-soft-prompt` | Show soft prompt before permission request |
| `--safari-web-id` | Safari Web ID for Safari browser support |
| `--notify-button` | Enable floating notification button on web (default: disabled) |

### `configure`

Update notification configuration:

```bash
# Show current configuration
dart run magic_notifications configure --show

# Update OneSignal App ID
dart run magic_notifications configure --app-id NEW_APP_ID

# Update polling interval (5-600 seconds)
dart run magic_notifications configure --polling-interval 60

# Enable/disable soft prompt
dart run magic_notifications configure --soft-prompt
dart run magic_notifications configure --no-soft-prompt
```

### `doctor`

Check installation and configuration health:

```bash
# Run health check
dart run magic_notifications doctor

# Verbose output
dart run magic_notifications doctor --verbose
```

Verifies:
- Plugin installed in `pubspec.yaml`
- Configuration file exists at `lib/config/notifications.dart`
- Config validation: App ID format, polling interval range
- Platform setup (Android, iOS, Web)

Exits with code `0` if all checks pass, `1` if any check fails.

### `test`

Send test notifications to verify setup:

```bash
# Preview notification (dry run)
dart run magic_notifications test --dry-run

# Send test database notification
dart run magic_notifications test

# Send custom notification
dart run magic_notifications test \
  --title "Hello" \
  --body "World"

# Send push notification
dart run magic_notifications test \
  --channel push \
  --api-url http://localhost:8000

# Test different channels
dart run magic_notifications test --channel database
dart run magic_notifications test --channel push
dart run magic_notifications test --channel mail
```

### `uninstall`

Remove plugin integration from your project:

```bash
# Interactive uninstall (asks for confirmation)
dart run magic_notifications uninstall

# Skip confirmation prompt
dart run magic_notifications uninstall --force
```

Removes:
- `lib/config/notifications.dart`
- `magic_notifications` dependency from `pubspec.yaml`
- `NotificationServiceProvider` injection from `lib/config/app.dart`
- `notificationConfig` factory from `lib/main.dart`

> **Warning**: Platform files (`android/app/src/main/AndroidManifest.xml`, `web/index.html`, `web/OneSignalSDKWorker.js`) are NOT reverted automatically — manual cleanup required.

### `publish`

Laravel vendor:publish style — copies the notification config stub to your project:

```bash
# Publish config stub (skips if already exists)
dart run magic_notifications publish

# Overwrite existing config
dart run magic_notifications publish --force
```

Copies the default `notifications.dart` config to `lib/config/notifications.dart`.
After publishing, update `YOUR_ONESIGNAL_APP_ID` with your actual OneSignal App ID.

### `channels`

List all notification channels and their current status:

```bash
dart run magic_notifications channels
```

Shows each channel (database, push, mail) with:
- Enabled / disabled status
- Polling interval (database channel)
- App ID presence (masked, push channel)

---

## Usage

### Display Notifications in UI

Use the `NotificationDropdownWithStream` widget:

```dart
import 'package:magic_notifications/magic_notifications.dart';

AppBar(
  actions: [
    NotificationDropdownWithStream(
      notificationStream: Notify.notifications(),
      onMarkAsRead: (id) => Notify.markAsRead(id),
      onMarkAllAsRead: () => Notify.markAllAsRead(),
      onNavigate: (path) => MagicRoute.to(path),
    ),
  ],
)
```

### Send Notifications from Backend

#### Database Notification (Laravel Example)

```php
use App\Models\User;
use App\Notifications\MonitorDownNotification;

$user = User::find(1);
$user->notify(new MonitorDownNotification($monitor));
```

#### Push Notification via API

```php
use Illuminate\Support\Facades\Http;

// IMPORTANT: Use 'user_' prefix to match the Flutter external_id format
Http::post('/api/v1/notifications/push', [
    'external_id' => 'user_' . $user->id,  // Must match Flutter's format
    'heading' => 'Important Update',
    'content' => 'Your monitor is down',
    'data' => ['monitor_id' => $monitor->id],
]);
```

Or configure it in your User model (Laravel):

```php
// app/Models/User.php
public function routeNotificationForOneSignal(): array
{
    // Use 'user_' prefix to avoid OneSignal blocked values
    return ['include_external_user_ids' => ['user_' . $this->id]];
}
```

### Create Custom Notifications

```dart
import 'package:magic_notifications/magic_notifications.dart';

class CustomNotification extends Notification {
  final String title;
  final String message;

  CustomNotification(this.title, this.message);

  @override
  List<String> via(Notifiable notifiable) => ['database', 'push'];

  @override
  Map<String, dynamic>? toDatabase(Notifiable notifiable) {
    return {
      'title': title,
      'body': message,
      'action_url': '/details',
    };
  }

  @override
  PushMessage? toPush(Notifiable notifiable) {
    return PushMessage()
      ..heading(title)
      ..content(message);
  }
}
```

### Handle Notification Preferences

```dart
// Get user preferences
final prefs = await Notify.getPreferences();

// Update preferences
await Notify.updatePreferences(NotificationPreference(
  pushEnabled: true,
  emailEnabled: false,
  inAppEnabled: true,
  typePreferences: {
    'alert': ChannelPreference(
      push: true,
      email: true,
      inApp: true,
    ),
  },
));
```

### Initialize Push After Login

In your `AuthController` or login handler:

```dart
import 'package:magic_notifications/magic_notifications.dart';

Future<void> onLoginSuccess(User user) async {
  // 1. Request push notification permission
  // This shows the browser/OS permission prompt if not already granted
  final permissionGranted = await Notify.requestPushPermission();

  // 2. Initialize push with user ID (using 'user_' prefix)
  // IMPORTANT: Use 'user_' prefix to avoid OneSignal blocked values
  // OneSignal blocks simple values like '0', '1', '-1', 'null', etc.
  final userId = user.id.toString();
  await Notify.initializePush('user_$userId');

  // 3. Start polling for database notifications
  Notify.startPolling();
}
```

> **External ID Format**: Always use a prefix like `user_` before the user ID. OneSignal blocks simple numeric values (`0`, `1`, `-1`) as external_id. The same format must be used in your backend when sending targeted notifications.

### Clean Up on Logout

```dart
Future<void> onLogout() async {
  // Stop polling
  Notify.stopPolling();

  // Logout from push
  await Notify.logoutPush();
}
```

---

## Backend API Contract

This plugin works with any backend that provides REST API endpoints. Your backend must implement the following endpoints:

### Required Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/notifications` | GET | List user notifications (paginated) |
| `/notifications/unread-count` | GET | Get unread notification count |
| `/notifications/{id}/read` | POST | Mark single notification as read |
| `/notifications/read-all` | POST | Mark all notifications as read |
| `/notifications/{id}` | DELETE | Delete a notification |
| `/notification-preferences` | GET | Get user notification preferences |
| `/notification-preferences` | PUT | Update user preferences |

### Response Formats

#### GET /notifications

```json
{
  "data": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "type": "monitor_down",
      "data": {
        "title": "Monitor Alert",
        "body": "Your monitor 'API Server' is down",
        "action_url": "/monitors/1"
      },
      "read_at": null,
      "created_at": "2024-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "current_page": 1,
    "last_page": 3,
    "per_page": 15,
    "total": 42
  }
}
```

#### GET /notifications/unread-count

```json
{
  "count": 5
}
```

#### GET /notification-preferences

```json
{
  "data": {
    "push_enabled": true,
    "email_enabled": false,
    "in_app_enabled": true,
    "type_preferences": {
      "monitor_down": { "push": true, "email": true, "in_app": true },
      "monitor_up": { "push": false, "email": false, "in_app": true }
    }
  }
}
```

### Backend Implementation Guides

For framework-specific setup instructions, see:

- **Laravel**: [docs/laravel-backend-setup.md](docs/laravel-backend-setup.md)

---

## Architecture

```
┌─────────────────────────────────────────┐
│         Flutter Application             │
│  ┌───────────────────────────────────┐  │
│  │   NotificationDropdownWidget     │  │
│  └──────────────┬────────────────────┘  │
│                 │                        │
│  ┌──────────────▼────────────────────┐  │
│  │      Notify Facade               │  │
│  └──────────────┬────────────────────┘  │
│                 │                        │
│  ┌──────────────▼────────────────────┐  │
│  │   NotificationManager            │  │
│  │  ┌────────────────────────────┐  │  │
│  │  │  DatabaseChannel           │  │  │
│  │  │  - Stream notifications    │  │  │
│  │  │  - Mark as read/delete     │  │  │
│  │  └────────────────────────────┘  │  │
│  │  ┌────────────────────────────┐  │  │
│  │  │  PushChannel               │  │  │
│  │  │  - OneSignalDriver         │  │  │
│  │  │  - Permission handling     │  │  │
│  │  └────────────────────────────┘  │  │
│  └─────────────────────────────────┘  │
└─────────────────────────────────────────┘
                  │
                  │ HTTP API
                  │
┌─────────────────▼─────────────────────┐
│      Backend (REST API)               │
│  ┌─────────────────────────────────┐  │
│  │  API Endpoints                  │  │
│  │  - GET /notifications           │  │
│  │  - POST /notifications/{id}/read│  │
│  │  - POST /notifications/push     │  │
│  └─────────────────────────────────┘  │
└───────────────────────────────────────┘
```

**Key patterns:**

| Pattern | Implementation |
|---------|---------------|
| Singleton Manager | `NotificationManager` — central orchestrator |
| Strategy (Driver) | `OneSignalDriver` implements push driver contract |
| Facade | `Notify` — static API over `NotificationManager` |
| Service Provider | Two-phase bootstrap: `register()` (sync) -> `boot()` (async) |
| IoC Container | All bindings via `app.singleton()` / `app.make()` |

---

## Testing

### Run Plugin Tests

```bash
cd plugins/magic_notifications
flutter test
```

### Platform Testing

- **iOS**: Run on a **physical device** (push does not work on simulator). Accept permission, send test notification from OneSignal dashboard.
- **Android**: Run on emulator or physical device. Accept permission, send test notification.
- **Web**: Run `flutter run -d chrome`. Accept permission, check DevTools Console for OneSignal logs, send test notification.

### Debugging

Enable debug logging in your `lib/config/notifications.dart`:

```dart
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'debug': true,  // Enable debug logging
    'push': {...},
    'database': {...},
  },
};
```

Check OneSignal subscription:

```dart
final subscription = await Notify.getPushSubscription();
print('Subscribed: ${subscription.optedIn}');
print('Permission: ${subscription.permissionState}');
```

---

## Troubleshooting

### iOS Push Not Working

- Test on **physical device** (not simulator)
- Verify Push Notifications capability enabled in Xcode
- Check provisioning profile includes push entitlements
- Verify OneSignal App ID is correct

### Android Push Not Working

- Check `minSdkVersion >= 21` in build.gradle
- Ensure POST_NOTIFICATIONS permission in AndroidManifest.xml
- Verify Google Play Services installed
- Check OneSignal App ID is correct

### Web Push Not Working

- Use HTTPS (or localhost for testing)
- Check service worker registered in DevTools
- Verify `gcm_sender_id` is `"482941778795"` in manifest.json
- Confirm website URL added to OneSignal dashboard
- Check browser console for errors

### Notifications Not Appearing

- Verify polling started: `Notify.poller.isActive`
- Check network requests in DevTools
- Ensure user authenticated
- Verify backend API returning notifications

---

## API Reference

### Notify Facade

```dart
// Database Channel
static Stream<List<DatabaseNotification>> notifications()
static Future<void> fetchNotifications()
static Future<int> unreadCount()
static Future<void> markAsRead(String id)
static Future<void> markAllAsRead()
static Future<void> delete(String id)

// Push Channel
static Future<bool> requestPushPermission()  // Request permission first!
static Future<void> initializePush(String externalId)  // Use 'user_' + userId
static Future<void> logoutPush()  // Call on logout to unlink device

// Preferences
static Future<NotificationPreference> getPreferences()
static Future<void> updatePreferences(NotificationPreference prefs)

// Polling
static NotificationPoller get poller
```

### Polling Methods (via Notify facade)

```dart
static void startPolling()   // Begin polling (idempotent)
static void stopPolling()    // Stop polling completely
static void pausePolling()   // Pause temporarily (e.g., app backgrounded)
static void resumePolling()  // Resume after pause (e.g., app foregrounded)
```

### NotificationPoller (internal)

```dart
void start()           // Begin polling
void stop()            // Stop polling completely
void pause()           // Pause temporarily
void resume()          // Resume after pause
Future<void> refresh() // Fetch immediately
bool get isActive      // Check if polling
bool get isPaused      // Check if paused
```

---

## Documentation

| Document | Description |
|----------|-------------|
| [Installation](https://magic.fluttersdk.com/packages/notifications/getting-started/installation) | Adding the package and running the installer |
| [Configuration](https://magic.fluttersdk.com/packages/notifications/getting-started/configuration) | Config file reference and options |
| [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels) | Database, Push, and Mail channel details |
| [Drivers](https://magic.fluttersdk.com/packages/notifications/basics/drivers) | Push driver contract and OneSignal implementation |
| [Preferences](https://magic.fluttersdk.com/packages/notifications/basics/preferences) | User notification preference management |
| [CLI Tools](https://magic.fluttersdk.com/packages/notifications/basics/cli) | All CLI commands and flags |
| [Notification Manager](https://magic.fluttersdk.com/packages/notifications/architecture/notification-manager) | Manager singleton and dispatch flow |
| [Service Provider](https://magic.fluttersdk.com/packages/notifications/architecture/service-provider) | Bootstrap lifecycle and IoC bindings |

---

## Contributing

Contributions are welcome! Please see the [issues page](https://github.com/fluttersdk/magic_notifications/issues) for open tasks or to report bugs.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests following the [TDD flow](#) — red, green, refactor
4. Ensure all checks pass: `flutter test`, `dart analyze`, `dart format .`
5. Submit a pull request

---

## License

Magic Notifications is open-sourced software licensed under the [MIT License](LICENSE).

---

<p align="center">
  Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a><br/>
  <sub>If Magic Notifications helps your project, consider giving it a <a href="https://github.com/fluttersdk/magic_notifications">star on GitHub</a>.</sub>
</p>
