# Magic Notifications Plugin

Multi-channel notification system for Flutter Magic Framework applications.

## Features

- 📱 **Database Channel**: In-app notifications with real-time updates
- 🔔 **Push Channel**: OneSignal integration for iOS, Android, and Web
- 🎯 **User Preferences**: Granular control over notification channels and types
- 🔄 **Real-time Polling**: Background polling with pause/resume support
- 🌐 **Multi-platform**: iOS, Android, Web support with platform-specific optimizations

## Installation

### ⚡ Quick Start with CLI (Recommended)

The fastest way to set up notifications in your Flutter Magic project:

```bash
# Run interactive installation wizard
dart run fluttersdk_magic_notifications:install
```

The CLI will:
- ✅ Create configuration file (`lib/config/notifications.dart`)
- ✅ Add plugin dependency to `pubspec.yaml`
- ✅ Generate platform-specific setup (Android, iOS, Web)
- ✅ Update `lib/main.dart` with initialization code
- ✅ Configure OneSignal integration

#### CLI Options

```bash
# Non-interactive mode (for CI/CD)
dart run fluttersdk_magic_notifications:install \
  --non-interactive \
  --app-id YOUR_ONESIGNAL_APP_ID \
  --platforms android,ios,web

# Disable soft prompt
dart run fluttersdk_magic_notifications:install \
  --no-soft-prompt

# Web options: Safari Web ID and Notify Button
dart run fluttersdk_magic_notifications:install \
  --non-interactive \
  --app-id YOUR_APP_ID \
  --platforms web \
  --safari-web-id web.onesignal.auto.xxx \
  --notify-button
```

| Option | Description |
|--------|-------------|
| `--app-id` | OneSignal App ID (required for non-interactive) |
| `--platforms` | Comma-separated platforms: android,ios,web |
| `--soft-prompt` / `--no-soft-prompt` | Show soft prompt before permission request |
| `--safari-web-id` | Safari Web ID for Safari browser support |
| `--notify-button` | Enable floating notification button on web (default: disabled) |

### 📦 Manual Installation

If you prefer manual setup:

#### 1. Add Dependency

Add to your `pubspec.yaml`:

```yaml
dependencies:
  fluttersdk_magic_notifications:
    path: ./plugins/fluttersdk_magic_notifications
```

Then run:

```bash
flutter pub get
```

#### 2. Configure OneSignal

##### Get OneSignal App ID

1. Sign up at [OneSignal](https://onesignal.com/)
2. Create a new app
3. Copy your App ID from Settings

##### Create Configuration File

Create `lib/config/notifications.dart`:

```dart
/// Notification configuration
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': const String.fromEnvironment('ONESIGNAL_APP_ID'),
      // Optional: Safari Web ID for Safari browser support
      // Get this from OneSignal Dashboard → Settings → Platforms → Safari
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

#### 3. Platform-Specific Setup

##### iOS Setup

**1. Enable Push Notifications Capability**

Open `ios/Runner.xcworkspace` in Xcode:
1. Select your project → Runner target
2. Go to "Signing & Capabilities"
3. Click "+ Capability" and add "Push Notifications"
4. Add "Background Modes" capability
5. Check "Remote notifications"

**2. Configure Info.plist**

Add to `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

##### Android Setup

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

##### Web Setup

**1. Download Service Worker from OneSignal**

Go to [OneSignal Dashboard](https://onesignal.com/) → Settings → Platforms → Web Push → Download Service Worker Files

Or create `web/OneSignalSDKWorker.js` with this content:

```javascript
importScripts("https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.sw.js");
```

> ⚠️ **Important**: Use `OneSignalSDK.sw.js` (Service Worker version), NOT `OneSignalSDK.page.js`. The `.page.js` is for the main HTML page `<script>` tag, while `.sw.js` is for the Service Worker file.

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
        // Get from OneSignal Dashboard → Settings → Platforms → Safari
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

Get your Safari Web ID from: OneSignal Dashboard → Settings → Platforms → Safari

Or use the CLI to generate this automatically:

```bash
dart run fluttersdk_magic_notifications:install \
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

1. Go to OneSignal Dashboard → Settings → Platforms → Web Push
2. Add your website URL (e.g., `http://localhost:8080` for testing)
3. Save configuration

#### 4. Register Service Provider

In your app's `lib/config/app.dart`:

```dart
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

final appConfig = {
  'name': 'Your App',
  'providers': [
    // ... other providers
    NotificationServiceProvider,
  ],
};
```

#### 5. Initialize in Your App

In `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:fluttersdk_magic/fluttersdk_magic.dart';
import 'config/app.dart';
import 'config/notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Magic Framework with all configs
  await Magic.init(
    configFactories: [
      () => appConfig,
      () => notificationConfig,  // Add notification config here
    ],
  );

  runApp(MyApp());
}
```

#### 6. Start Polling in App Layout

The recommended approach is to start polling when the authenticated layout mounts:

```dart
// In your AppLayout or AuthenticatedLayout widget:
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

class _AppLayoutState extends State<AppLayout> {
  @override
  void initState() {
    super.initState();
    // Start notification polling when user is authenticated
    // This is safe to call multiple times (idempotent)
    try {
      Notify.startPolling();
    } catch (_) {
      // Silently fail if Magic not initialized (e.g., in tests)
    }
  }
}
```

#### 7. Initialize Push After Login

In your `AuthController` or login handler:

```dart
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

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

> ⚠️ **External ID Format**: Always use a prefix like `user_` before the user ID. OneSignal blocks simple numeric values (`0`, `1`, `-1`) as external_id. The same format must be used in your backend when sending targeted notifications.

#### 8. Clean Up on Logout

```dart
Future<void> onLogout() async {
  // Stop polling
  Notify.stopPolling();

  // Logout from push
  await Notify.logoutPush();
}
```

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

## CLI Commands

### Install

Interactive wizard to set up notifications:

```bash
# Interactive mode
dart run fluttersdk_magic_notifications:install

# Non-interactive mode
dart run fluttersdk_magic_notifications:install \
  --non-interactive \
  --app-id YOUR_APP_ID \
  --platforms android,ios,web \
  --no-soft-prompt
```

### Configure

Update notification configuration:

```bash
# Show current configuration
dart run fluttersdk_magic_notifications:configure --show

# Update OneSignal App ID
dart run fluttersdk_magic_notifications:configure --app-id NEW_APP_ID

# Update polling interval (5-600 seconds)
dart run fluttersdk_magic_notifications:configure --polling-interval 60

# Enable/disable soft prompt
dart run fluttersdk_magic_notifications:configure --soft-prompt
dart run fluttersdk_magic_notifications:configure --no-soft-prompt
```

### Status

Check installation and configuration status:

```bash
# Check status
dart run fluttersdk_magic_notifications:status

# Verbose output
dart run fluttersdk_magic_notifications:status --verbose
```

Verifies:
- Plugin installed in `pubspec.yaml`
- Configuration file exists
- Platform-specific setup (Android, iOS, Web)
- Lists any missing requirements

### Test

Send test notifications to verify setup:

```bash
# Preview notification (dry run)
dart run fluttersdk_magic_notifications:test --dry-run

# Send test database notification
dart run fluttersdk_magic_notifications:test

# Send custom notification
dart run fluttersdk_magic_notifications:test \
  --title "Hello" \
  --body "World"

# Send push notification
dart run fluttersdk_magic_notifications:test \
  --channel push \
  --api-url http://localhost:8000

# Test different channels
dart run fluttersdk_magic_notifications:test --channel database
dart run fluttersdk_magic_notifications:test --channel push
dart run fluttersdk_magic_notifications:test --channel mail
```

## Usage

### Display Notifications in UI

Use the `NotificationDropdownWithStream` widget:

```dart
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

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
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

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

## Testing

### Run Plugin Tests

```bash
cd plugins/fluttersdk_magic_notifications
flutter test
```

### Test Push Notifications

#### iOS
1. Run on **physical device** (push doesn't work on simulator)
2. Accept notification permission when prompted
3. Send test notification from OneSignal dashboard
4. Verify notification appears

#### Android
1. Run on emulator or physical device
2. Accept notification permission
3. Send test notification
4. Verify notification appears

#### Web
1. Run `flutter run -d chrome`
2. Accept notification permission
3. Check DevTools Console for OneSignal logs
4. Send test notification from OneSignal dashboard
5. Verify notification appears in browser

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

## License

This plugin is part of the Magic Framework ecosystem.

## Support

For issues and questions:
- Check existing tests for usage examples
- Review this README for setup instructions
- Open an issue in the project repository
