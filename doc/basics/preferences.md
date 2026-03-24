# Preferences

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-model"></a>[NotificationPreference Model](#model)
- <a name="toc-channel-preference"></a>[ChannelPreference Model](#channel-preference)
- <a name="toc-global-vs-type"></a>[Global Toggles vs Per-Type Preferences](#global-vs-type)
- <a name="toc-api"></a>[API Endpoints](#api)
- <a name="toc-ui"></a>[UI Integration Example](#ui)

---

## <a name="overview"></a>Overview

`NotificationPreference` represents a user's opt-in/opt-out decisions across all notification channels. The model has two layers: global channel toggles (push, email, in-app), and per-notification-type overrides (`typePreferences`). The `isEnabled` method combines both layers to answer "should this notification be delivered via this channel?"

---

## <a name="model"></a>NotificationPreference Model

```dart
class NotificationPreference {
  final bool pushEnabled;
  final bool emailEnabled;
  final bool inAppEnabled;
  final Map<String, ChannelPreference> typePreferences;

  const NotificationPreference({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.inAppEnabled = true,
    this.typePreferences = const {},
  });
}
```

### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `pushEnabled` | `bool` | `true` | Global push notifications toggle |
| `emailEnabled` | `bool` | `true` | Global email notifications toggle |
| `inAppEnabled` | `bool` | `true` | Global in-app (database) notifications toggle |
| `typePreferences` | `Map<String, ChannelPreference>` | `{}` | Per-notification-type channel overrides |

### Deserialization

```dart
// From API response
final pref = NotificationPreference.fromMap({
  'push_enabled': true,
  'email_enabled': false,
  'in_app_enabled': true,
  'type_preferences': {
    'monitor_down': {'push': true, 'email': true, 'in_app': true},
    'monitor_up': {'push': false, 'email': false, 'in_app': true},
  },
});
```

### Serialization

```dart
// For PUT /notification-preferences
final map = pref.toMap();
// {
//   'push_enabled': true,
//   'email_enabled': false,
//   'in_app_enabled': true,
//   'type_preferences': {...},
// }
```

### copyWith

```dart
final updated = pref.copyWith(emailEnabled: true);
```

---

## <a name="channel-preference"></a>ChannelPreference Model

```dart
class ChannelPreference {
  final bool push;
  final bool email;
  final bool inApp;

  const ChannelPreference({
    this.push = true,
    this.email = true,
    this.inApp = true,
  });
}
```

`ChannelPreference` holds the per-type override for each channel. It deserializes from the `type_preferences` sub-map:

```dart
final monitorDown = ChannelPreference.fromMap({
  'push': true,
  'email': true,
  'in_app': false,
});
```

---

## <a name="global-vs-type"></a>Global Toggles vs Per-Type Preferences

`isEnabled(notificationType, channel)` applies a two-stage gate:

```dart
bool isEnabled(String notificationType, String channel) {
  // Stage 1: global toggle
  final globalEnabled = _isGlobalChannelEnabled(channel);
  if (!globalEnabled) return false;

  // Stage 2: type-specific override
  final typePref = typePreferences[notificationType];
  if (typePref == null) return true; // default: enabled

  return _isTypeChannelEnabled(typePref, channel);
}
```

**Channel alias resolution:**

| Argument | Maps to property |
|----------|-----------------|
| `'push'` | `pushEnabled` / `ChannelPreference.push` |
| `'mail'` or `'email'` | `emailEnabled` / `ChannelPreference.email` |
| `'database'` or `'in_app'` | `inAppEnabled` / `ChannelPreference.inApp` |

**Example**: global push is `true`, but `monitor_up.push` is `false` → `isEnabled('monitor_up', 'push')` returns `false`. PushChannel will skip delivery.

`PushChannel.send` runs this check automatically when the `Notifiable` has a non-null `notificationPreference`:

```dart
final preference = notifiable.notificationPreference;
if (preference != null) {
  if (!preference.isEnabled(notification.type, 'push')) return;
}
```

---

## <a name="api"></a>API Endpoints

The backend must implement two endpoints:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/notification-preferences` | Fetch current user preferences |
| `PUT` | `/notification-preferences` | Update preferences |

### GET /notification-preferences Response

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

### PUT /notification-preferences Request Body

```json
{
  "push_enabled": true,
  "email_enabled": true,
  "in_app_enabled": true,
  "type_preferences": {
    "monitor_down": { "push": true, "email": true, "in_app": true }
  }
}
```

---

## <a name="ui"></a>UI Integration Example

A typical preferences screen fetches, renders, and persists the preference model:

```dart
import 'package:magic_notifications/magic_notifications.dart';

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  NotificationPreference? _pref;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final response = await Http.get('/notification-preferences');
    if (response.successful) {
      setState(() {
        _pref = NotificationPreference.fromMap(
          response.data['data'] as Map<String, dynamic>,
        );
      });
    }
  }

  Future<void> _save(NotificationPreference updated) async {
    await Http.put('/notification-preferences', data: updated.toMap());
    setState(() => _pref = updated);
  }

  @override
  Widget build(BuildContext context) {
    final pref = _pref;
    if (pref == null) return const CircularProgressIndicator();

    return ListView(
      children: [
        SwitchListTile(
          title: const Text('Push Notifications'),
          value: pref.pushEnabled,
          onChanged: (v) => _save(pref.copyWith(pushEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('Email Notifications'),
          value: pref.emailEnabled,
          onChanged: (v) => _save(pref.copyWith(emailEnabled: v)),
        ),
        SwitchListTile(
          title: const Text('In-App Notifications'),
          value: pref.inAppEnabled,
          onChanged: (v) => _save(pref.copyWith(inAppEnabled: v)),
        ),
      ],
    );
  }
}
```

> [!TIP]
> Attach the loaded `NotificationPreference` to your `User` model by overriding `Notifiable.notificationPreference`. This allows `PushChannel.send` to automatically respect per-type preferences without extra plumbing.

```dart
class User extends Model with Notifiable {
  NotificationPreference? _cachedPreference;

  @override
  String get notifiableId => id.toString();

  @override
  dynamic get notificationPreference => _cachedPreference;

  void setPreference(NotificationPreference pref) {
    _cachedPreference = pref;
  }
}
```

---

**Related**

- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
- [Notification Manager](https://magic.fluttersdk.com/packages/notifications/architecture/notification-manager)
