# Notification Manager

## Table of Contents

- <a name="toc-singleton"></a>[Singleton Lifecycle](#singleton)
- <a name="toc-channels"></a>[Channel Registration](#channels)
- <a name="toc-push-driver"></a>[Push Driver Setup](#push-driver)
- <a name="toc-send-flow"></a>[Send Dispatch Flow](#send-flow)
- <a name="toc-polling"></a>[Polling Orchestration](#polling)
- <a name="toc-realtime"></a>[Realtime Delivery](#realtime)
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
> For testing, use `forgetDrivers()` to reset the singleton's internal state between tests. It clears every channel, every registered push driver factory, and every resolved push driver instance in one call; there is a single method for this now, not a pair split by concern.

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

The push driver resolves lazily through a name-keyed factory registry, not a
single nullable field the provider must fill before anything else runs:

```dart
void extend(String name, PushDriver Function() factory) {
  _pushFactories[name] = factory;
  _resolvedPushDriver = null;
  if (_pushDriver == null) _detachPushDriver();
}

PushDriver? get pushDriverOrNull {
  if (_pushDriver != null) return _pushDriver;
  if (_resolvedPushDriver != null) return _resolvedPushDriver;

  final factory = _pushFactory();
  if (factory == null) return null;

  final created = factory();
  _resolvedPushDriver = created;
  _attachPushDriver(created);
  return created;
}

PushDriver get pushDriver {
  final driver = pushDriverOrNull;
  if (driver == null) {
    throw NotificationException(
      'Push driver not configured. Register one with Notify.extend(name, '
      'factory), or set one explicitly with setPushDriver().',
      code: 'PUSH_DRIVER_NOT_CONFIGURED',
    );
  }
  return driver;
}
```

Resolution order for `pushDriver` / `pushDriverOrNull`: the instance
`setPushDriver()` was given (the escape hatch for a consumer holding an
already-built driver), then a previously-resolved registry instance, then a
fresh build from the registry. `_pushFactory()` resolves the factory named by
`notifications.push.driver` when more than one is registered, and falls back
to the single registered factory when there is exactly one and no config says
otherwise — with two or more and no matching name, there is no unambiguous
answer and the call site that only wants "is push configured at all" gets
`pushDriverOrNull == null` instead of a throw.

`NotificationServiceProvider.boot()` registers the built-in OneSignal factory
via `extend()`, then reads `pushDriver` (or `pushDriverOrNull` where absence
is a supported state) to call `driver.initialize(config)`. After
initialization, the `PushChannel` constructor receives the same driver
reference — `PushChannel.isAvailable` delegates to `driver.isSupported`.

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

## <a name="realtime"></a>Realtime Delivery

Polling is the fallback, not the only path. When the app has a broadcast driver,
the manager can take notification state off the socket instead:

```dart
final bool live = await Notify.startRealtime(
  channel: 'App.Models.User.$userId',
);
```

`startRealtime()` does five things in order, and each one answers a specific
failure:

1. **Refuses when there is no driver.** It reads `broadcasting.default` and
   returns `false` for `null`, empty, or the literal `'null'` driver. It does NOT
   try to subscribe and see what happens: the null driver accepts a subscription
   and silently delivers nothing, so an attempt-based probe would report success
   on the one configuration that cannot work, silence the poller, and leave the
   bell permanently empty.
2. **Connects only if nothing is connected.** `Echo.connect()` is not idempotent
   in magic's Reverb driver: it assigns a fresh channel without closing the
   previous one, so a redundant call opens a second WebSocket and leaks the first.
   This is why `magic ^0.0.6` is the floor; `Echo.connection` is the accessor that
   makes the check possible.
3. **Listens for `notification.created` exactly once.** A second `listen()` for
   one event name REPLACES the earlier handler rather than adding to it, so
   registering the same event anywhere else would silently drop this one.
4. **Stops the poller.** The socket now covers it.
5. **Fetches the existing list once.** A socket carries only what happens next.

### The frame is the state

A `notification.created` frame carries the whole row in the same shape
`GET /notifications` returns, so it is decoded and applied rather than treated as
a signal to fetch:

```dart
void _applyRealtimeFrame(BroadcastEvent event) {
  final incoming = DatabaseNotification.fromMap(event.data);
  _notifications = [
    incoming,
    ..._notifications.where((n) => n.id != incoming.id),
  ];
  _notificationController.add(_notifications);
}
```

Newest first, keyed by id, so a redelivery replaces the held row instead of
appending a duplicate the bell would count twice. A payload the decoder cannot
read is logged and dropped: it must not throw into the driver's listener, and it
must not clear what is already held, because a backend one version ahead is a
reason to miss one row and not to empty the list.

### Both directions of degradation

`connectionState` is watched (and `onReconnect` deliberately is not, since a
reconnect necessarily transitions the state to `connected` and listening to both
would fetch the same list twice for one event):

| Transition | What happens |
|------------|--------------|
| anything but `connected` | the poller is armed as a stand-in; the subscription stays, because realtime is still the intent |
| `connected` | the poller is dropped and the list is refetched once, because Reverb has no replay |

Without the first row, a socket that never comes back is a bell that never
updates again.

### Lifecycle hooks

| App Event | Call |
|-----------|------|
| User logged in | `Notify.startRealtime(channel: ...)` then `Notify.startPolling()` |
| User switched account | `Notify.startRealtime(channel: ...)` with the new channel |
| User logged out | `Notify.stopRealtime()` then `Notify.stopPolling()` |

Both calls on the login row are safe in either order and are idempotent per
channel, so wiring them to an auth-state listener that fires on every login,
logout and restore is the intended shape. `startPolling()` is a no-op while
realtime is live, so a consumer never has to branch on whether a socket is up.

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

Read-mutate operations apply changes locally before the HTTP request completes, then revert on failure. Whether the caller is TOLD about that failure differs per operation, and the note below the `deleteNotification` snippet says which is which:

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

The same pattern applies to `markAllAsRead()`. Rollback always calls `fetchNotifications()` to restore authoritative server state rather than trying to undo the local mutation, which avoids edge cases from concurrent updates.

`deleteNotification` preserves the removed items for rollback, and then **rethrows**:

```dart
Future<void> deleteNotification(String id) async {
  final removed = _notifications.where((n) => n.id == id).toList();
  _notifications.removeWhere((n) => n.id == id);
  _notificationController.add(_notifications);

  try {
    await Http.delete('/notifications/$id');
  } catch (e) {
    NotificationLog.error('Failed to delete notification: $e');
    _notifications.addAll(removed);
    _notificationController.add(_notifications);

    rethrow;
  }
}
```

> [!IMPORTANT]
> `deleteNotification` is the one mutation here that does NOT swallow, and that is deliberate. It used to complete normally on failure, which left a caller no way to tell a delete that worked from one that did not: the only thing a person saw was the row leaving the list and coming back, with nothing said. The rollback is unchanged; the future now carries the failure.
>
> `markAsRead` and `markAllAsRead` still swallow. Their failure is recoverable by looking again and costs a person nothing, while a delete that silently did not happen is the case where the screen and the server disagree about something destructive.
>
> A caller that wants the old silence adds a `catch`. `NotificationsListView` catches it and reports `notifications.delete_failed` through `Magic.error`, which is a key the HOST must supply: this package ships no translation catalogue, and a missing key renders as itself.

> [!TIP]
> The `Notify` facade exposes all these operations as static methods (`Notify.markAsRead`, `Notify.deleteNotification`, etc.), which simply delegate to the same manager instance.

---

**Related**

- [Service Provider](https://magic.fluttersdk.com/packages/notifications/architecture/service-provider)
- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
- [Drivers](https://magic.fluttersdk.com/packages/notifications/basics/drivers)
