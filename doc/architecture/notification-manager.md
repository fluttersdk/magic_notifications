# Notification Manager

## Table of Contents

- <a name="toc-singleton"></a>[Singleton Lifecycle](#singleton)
- <a name="toc-channels"></a>[Channel Registration](#channels)
- <a name="toc-push-driver"></a>[Push Driver Setup](#push-driver)
- <a name="toc-send-flow"></a>[Send Dispatch Flow](#send-flow)
- <a name="toc-polling"></a>[Polling Orchestration](#polling)
- <a name="toc-streams"></a>[Stream Management](#streams)
- <a name="toc-optimistic"></a>[Optimistic Updates with Rollback](#optimistic)

---

## <a name="singleton"></a>Singleton Lifecycle

`NotificationManager` is a process-level singleton implemented via a Dart factory constructor:

```dart
class NotificationManager {
  static final NotificationManager _instance = NotificationManager._internal();

  factory NotificationManager() {
    return _instance;
  }

  NotificationManager._internal();
}
```

Every call to `NotificationManager()` returns the same `_instance`. There is no `dispose` method — the instance lives for the application's lifetime. The `Notify` facade delegates to the same instance:

```dart
class Notify {
  static NotificationManager get manager => NotificationManager();
}
```

This means `NotificationManager()` and `Notify.manager` are identical references, and state set through one is visible through the other.

> [!NOTE]
> For testing, use `forgetChannels()` and `forgetPushDriver()` to reset the singleton's internal state between tests.

---

## <a name="channels"></a>Channel Registration

Channels are stored in a `Map<String, NotificationChannel>` keyed by `channel.name`:

```dart
final Map<String, NotificationChannel> _channels = {};

void registerChannel(NotificationChannel channel) {
  _channels[channel.name] = channel;
}

bool hasChannel(String name) {
  return _channels.containsKey(name);
}
```

Registering a channel with an existing name replaces the previous instance — this is intentional for driver swapping in tests. The standard channels registered by `NotificationServiceProvider`:

| Name | Class | Registered By |
|------|-------|--------------|
| `'database'` | `DatabaseChannel` | You, in service provider |
| `'push'` | `PushChannel(driver)` | You, after driver setup |

---

## <a name="push-driver"></a>Push Driver Setup

The push driver is stored as a nullable field:

```dart
PushDriver? _pushDriver;

PushDriver get pushDriver {
  if (_pushDriver == null) {
    throw NotificationException(
      'Push driver not configured. Call setPushDriver() first.',
      code: 'PUSH_DRIVER_NOT_CONFIGURED',
    );
  }
  return _pushDriver!;
}

void setPushDriver(PushDriver driver) {
  _pushDriver = driver;
}
```

`NotificationServiceProvider.boot()` calls `setPushDriver` then `driver.initialize(config)`. After initialization, the `PushChannel` constructor receives the same driver reference — `PushChannel.isAvailable` delegates to `driver.isSupported`.

---

## <a name="send-flow"></a>Send Dispatch Flow

```dart
Future<void> send(Notifiable notifiable, Notification notification) async {
  final channels = notification.via(notifiable);

  for (final channelName in channels) {
    final channel = _channels[channelName];

    if (channel == null) {
      print('Warning: Unknown notification channel: $channelName');
      continue;
    }

    if (!channel.isAvailable) {
      continue;
    }

    await channel.send(notifiable, notification);
  }
}
```

The dispatch flow:

1. Call `notification.via(notifiable)` — returns `List<String>` of channel names
2. For each name: look up in `_channels` map
3. Skip unknown names (warning only, no throw)
4. Skip channels where `isAvailable == false`
5. Await `channel.send(notifiable, notification)` — channels run sequentially

> [!NOTE]
> Channels execute sequentially, not in parallel. If `DatabaseChannel.send` throws, `PushChannel.send` will not run. Design channel implementations to be fault-tolerant.

---

## <a name="polling"></a>Polling Orchestration

The manager owns the `NotificationPoller` lifecycle but delegates all timer logic to the poller:

```dart
NotificationPoller? _poller;

void startPolling() {
  _poller ??= NotificationPoller(this);
  _poller!.start();
}

void stopPolling() {
  _poller?.stop();
  _poller = null;
}

void pausePolling() {
  _poller?.pause();
}

void resumePolling() {
  _poller?.resume();
}
```

`startPolling()` is idempotent — if the poller already exists and is running, `start()` returns immediately. The recommended lifecycle hooks:

| App Event | Call |
|-----------|------|
| User logged in | `Notify.startPolling()` |
| App backgrounded | `Notify.pausePolling()` |
| App foregrounded | `Notify.resumePolling()` |
| User logged out | `Notify.stopPolling()` |

`NotificationPoller` fetches immediately on `start()` and `resume()`, then fires every 30 seconds (default). The interval can be changed by constructing the poller directly:

```dart
final poller = NotificationPoller(manager, interval: Duration(seconds: 60));
poller.start();
```

---

## <a name="streams"></a>Stream Management

Database notifications are distributed via a broadcast `StreamController`:

```dart
final StreamController<List<DatabaseNotification>> _notificationController =
    StreamController<List<DatabaseNotification>>.broadcast();

List<DatabaseNotification> _notifications = [];

Stream<List<DatabaseNotification>> notifications() async* {
  yield _notifications;          // emit cached state immediately
  yield* _notificationController.stream;  // then stream all future updates
}
```

The `notifications()` method is an async generator that yields the current cached list to new listeners immediately, then forwards all future events from the broadcast controller. This means a widget that subscribes mid-session receives the current notification list without waiting for the next poll interval.

Events are emitted to the stream in four situations:

1. `fetchNotifications()` — full refresh from API
2. `markAsRead(id)` — optimistic update
3. `markAllAsRead()` — optimistic bulk update
4. `deleteNotification(id)` — optimistic removal

---

## <a name="optimistic"></a>Optimistic Updates with Rollback

Read-mutate operations apply changes locally before the HTTP request completes, then revert on failure:

```dart
Future<void> markAsRead(String id) async {
  // 1. Optimistic update
  final index = _notifications.indexWhere((n) => n.id == id);
  if (index != -1) {
    _notifications[index] = _notifications[index].copyWith(
      readAt: DateTime.now(),
    );
    _notificationController.add(_notifications);
  }

  // 2. Sync with backend
  try {
    await Http.post('/notifications/$id/read');
  } catch (e) {
    _safeLogError('Failed to mark notification as read: $e');
    // 3. Rollback on failure
    await fetchNotifications();
  }
}
```

The same pattern applies to `markAllAsRead()` and `deleteNotification()`. Rollback always calls `fetchNotifications()` to restore authoritative server state rather than trying to undo the local mutation, which avoids edge cases from concurrent updates.

`deleteNotification` preserves the removed items for rollback:

```dart
Future<void> deleteNotification(String id) async {
  final removed = _notifications.where((n) => n.id == id).toList();
  _notifications.removeWhere((n) => n.id == id);
  _notificationController.add(_notifications);

  try {
    await Http.delete('/notifications/$id');
  } catch (e) {
    _safeLogError('Failed to delete notification: $e');
    _notifications.addAll(removed);
    _notificationController.add(_notifications);
  }
}
```

> [!TIP]
> The `Notify` facade exposes all these operations as static methods (`Notify.markAsRead`, `Notify.deleteNotification`, etc.), which simply delegate to the same manager instance.

---

**Related**

- [Service Provider](https://magic.fluttersdk.com/packages/notifications/architecture/service-provider)
- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
- [Drivers](https://magic.fluttersdk.com/packages/notifications/basics/drivers)
