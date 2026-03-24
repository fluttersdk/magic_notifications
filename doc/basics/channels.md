# Channels

## Table of Contents

- <a name="toc-concept"></a>[Channel Concept](#concept)
- <a name="toc-interface"></a>[NotificationChannel Interface](#interface)
- <a name="toc-database-channel"></a>[DatabaseChannel](#database-channel)
- <a name="toc-push-channel"></a>[PushChannel](#push-channel)
- <a name="toc-custom-channels"></a>[Creating Custom Channels](#custom-channels)
- <a name="toc-registration"></a>[Channel Registration](#registration)

---

## <a name="concept"></a>Channel Concept

A channel is a delivery mechanism for notifications. When `NotificationManager.send` is called, it asks the notification which channels it wants via `Notification.via()`, then dispatches to each registered channel in turn.

```dart
class MonitorDownNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['database', 'push'];
}
```

Channels are identified by a string name. The manager skips unknown channel names (logs a warning) and skips channels where `isAvailable` returns `false`. This makes it safe to declare channels in `via()` without knowing whether the device supports them at compile time.

---

## <a name="interface"></a>NotificationChannel Interface

```dart
abstract class NotificationChannel {
  /// Channel identifier (e.g., 'database', 'push', 'mail')
  String get name;

  /// Whether this channel is available and configured
  bool get isAvailable;

  /// Send notification through this channel
  Future<void> send(Notifiable notifiable, Notification notification);
}
```

Every channel must implement these three members:

- `name` — the string key used in `via()` return values and `registerChannel`
- `isAvailable` — a synchronous guard checked before every `send` call; return `false` to silently skip
- `send` — the actual delivery logic; receives the target entity and the notification

---

## <a name="database-channel"></a>DatabaseChannel

```dart
class DatabaseChannel extends NotificationChannel {
  @override
  String get name => 'database';

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    final data = notification.toDatabase(notifiable);
    if (data == null) return;
    // no-op: database notifications are created server-side
  }
}
```

### How It Works

The database channel follows an asymmetric pattern:

1. **Backend creates** — the Laravel backend calls `$user->notify(new SomeNotification())`, which persists a row in the `notifications` table
2. **Frontend polls** — `NotificationPoller` calls `NotificationManager.fetchNotifications()` every 30 seconds (configurable), which hits `GET /notifications`
3. **Stream emits** — results are pushed to the broadcast `StreamController<List<DatabaseNotification>>`
4. **UI reacts** — any widget listening to `Notify.notifications()` receives the updated list

The `send()` method in `DatabaseChannel` is intentionally a no-op. It exists for API parity with Laravel's notification system. When `toDatabase()` returns `null`, `send()` exits immediately; otherwise, the data map is validated but not forwarded (the backend owns persistence).

> [!NOTE]
> `DatabaseChannel.isAvailable` always returns `true`. Availability is controlled server-side by whether the backend is reachable.

**DatabaseNotification model fields:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | `String` | UUID from backend |
| `type` | `String` | Notification class name (e.g., `monitor_down`) |
| `title` | `String` | Display title |
| `body` | `String` | Display body |
| `data` | `Map<String, dynamic>` | Full data payload |
| `actionUrl` | `String?` | Deep-link or route path |
| `createdAt` | `DateTime` | Creation timestamp |
| `readAt` | `DateTime?` | `null` when unread |
| `isRead` | `bool` | `readAt != null` |

---

## <a name="push-channel"></a>PushChannel

```dart
class PushChannel extends NotificationChannel {
  final PushDriver _driver;

  PushChannel(this._driver);

  @override
  String get name => 'push';

  @override
  bool get isAvailable => _driver.isSupported;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    final pushMessage = notification.toPush(notifiable);
    if (pushMessage == null) return;

    final preference = notifiable.notificationPreference;
    if (preference != null) {
      final pushEnabled = preference.isEnabled(notification.type, 'push');
      if (!pushEnabled) return;
    }

    // Dispatches to backend → OneSignal
  }
}
```

### How It Works

1. `toPush()` is called on the notification; a `null` return exits early
2. If the `Notifiable` has a `notificationPreference`, `isEnabled(type, 'push')` is checked against global + per-type preferences
3. `isAvailable` delegates to `_driver.isSupported` — `false` on web for `OneSignalDriver`, `false` on mobile for `OneSignalWebDriver`

> [!TIP]
> Use `PushMessage` with its fluent builder to construct `toPush()` payloads:
> ```dart
> @override
> PushMessage? toPush(Notifiable notifiable) {
>   return PushMessage()
>     ..heading('Monitor Down')
>     ..content('api.example.com is not responding')
>     ..data({'monitor_id': monitor.id})
>     ..url('/monitors/${monitor.id}');
> }
> ```

---

## <a name="custom-channels"></a>Creating Custom Channels

Extend `NotificationChannel` to add any delivery mechanism:

```dart
import 'package:magic_notifications/magic_notifications.dart';

class SlackChannel extends NotificationChannel {
  final String _webhookUrl;

  SlackChannel(this._webhookUrl);

  @override
  String get name => 'slack';

  @override
  bool get isAvailable => _webhookUrl.isNotEmpty;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    final data = notification.toDatabase(notifiable);
    if (data == null) return;

    await Http.post(_webhookUrl, data: {
      'text': '${data['title']}: ${data['body']}',
    });
  }
}
```

Then declare `'slack'` in `via()`:

```dart
@override
List<String> via(Notifiable notifiable) => ['database', 'slack'];
```

---

## <a name="registration"></a>Channel Registration

Channels are registered on `NotificationManager` before any notifications are dispatched. `NotificationServiceProvider.register()` is the conventional place:

```dart
@override
void register() {
  final manager = NotificationManager();
  manager.registerChannel(DatabaseChannel());
  manager.registerChannel(PushChannel(driver));
  // manager.registerChannel(SlackChannel(webhookUrl));
  app.singleton('notifications', () => manager);
}
```

Registration is idempotent per name — registering a channel with an existing name replaces the previous instance.

```dart
// Check registration
final bool exists = NotificationManager().hasChannel('push');
```

---

**Related**

- [Drivers](https://magic.fluttersdk.com/packages/notifications/basics/drivers)
- [Preferences](https://magic.fluttersdk.com/packages/notifications/basics/preferences)
- [Notification Manager](https://magic.fluttersdk.com/packages/notifications/architecture/notification-manager)
