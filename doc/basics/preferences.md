# Preferences

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-model"></a>[NotificationPreference Model](#model)
- <a name="toc-channel-preference"></a>[ChannelPreference Model](#channel-preference)
- <a name="toc-global-vs-type"></a>[Global Toggles vs Per-Type Preferences](#global-vs-type)
- <a name="toc-api"></a>[API Endpoints](#api)
- <a name="toc-ui"></a>[UI Integration Example](#ui)
- <a name="toc-push-prompt"></a>[Push Prompt Component](#push-prompt)

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

A type x channel matrix. Each cell carries `enabled` and `locked`; a locked cell
is one the backend refuses to change (a security mail, an account alert), and the
screen renders its switch disabled rather than letting a tap earn a 422.

```json
{
  "data": {
    "monitor_down": {
      "label": "Monitor down",
      "channels": {
        "mail": { "enabled": true, "locked": false },
        "database": { "enabled": true, "locked": true },
        "push": { "enabled": false, "locked": false }
      }
    }
  },
  "meta": { "push_provisioned": true }
}
```

`meta.push_provisioned` is the backend saying whether it has a push `app_id` at
all. When it is `false` the push row still renders, with a hint under it, because
the preference is a real choice even while nothing can deliver it yet.

### PUT /notification-preferences Request Body

One cell, which is what a switch in the matrix sends:

```json
{ "type": "monitor_down", "channel": "push", "is_enabled": false }
```

Or a batch, which is what the bulk row above the matrix sends:

```json
{
  "preferences": [
    { "type": "monitor_down", "channel": "push", "is_enabled": false },
    { "type": "monitor_up", "channel": "push", "is_enabled": false }
  ]
}
```

> [!IMPORTANT]
> The bulk row needs the batch shape. A backend that accepts only the single
> shape answers 422 and the control is dead, so an adopter running a hand-rolled
> endpoint has to add it. `magic-starter-laravel` has accepted both since 0.0.7.
>
> The batch is one request on purpose. A loop of one-request-per-type has a way
> to half-succeed, and a half-succeeded bulk renders exactly like a complete one:
> the switch reads "off" while the one type that failed keeps delivering.

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

## <a name="push-prompt"></a>Push Prompt Component

`PushPrompt`, `PushPromptHost` and `PushOffNotice`
(`lib/src/ui/components/push_prompt/`) are the package's own push-permission
soft prompt: a row asking for push BEFORE the platform's one-shot prompt is
spent, built on `NotificationManager.pushPromptAdvice()`.

- **`PushPrompt`** is presentational: given `reachability`, `action`,
  `declined` and `busy`, it renders one of four presentations and reports
  `onEnable` / `onDecline`. It touches no platform API itself.
- **`PushPromptHost`** wires it to the live device. It owns nothing about
  WHEN to ask (`pushPromptAdvice` does), but it owns the one thing the package
  refuses to: the moment the user last declined it on this device. That is why
  it takes a `declinedVaultKey` constructor parameter rather than a fixed key:

  ```dart
  const PushPromptHost(declinedVaultKey: 'my_app.push_prompt_declined')
  ```

  It reads that key as an ISO-8601 timestamp and nothing else; a value an
  older build wrote in some other shape is the host's own migration to make,
  once, before ever constructing this widget.

- **`PushOffNotice`** is a quiet shell marker (a sidebar row, or a compact
  glyph for a mobile top bar) that tells a person, on a screen they were
  already looking at, that this device cannot be reached by push. Tapping it
  calls the required `onOpenPreferences` callback, which a host wires to
  wherever `PushPromptHost` and its controls actually live:

  ```dart
  PushOffNotice(
    onOpenPreferences: () => MagicRoute.to('/settings/notifications'),
  )
  ```

### Translation keys

This package ships no catalogue of its own, and `PushPrompt`/`PushOffNotice`
resolve every string through `trans('notifications.push_prompt.*')`. A host
adds all of the following to every locale it ships; a missing key renders as
itself.

| Key | English reference copy |
|-----|-------------------------|
| `notifications.push_prompt.unavailable_body` | This build has no push notifications. |
| `notifications.push_prompt.on_body` | You're all set to receive push notifications. |
| `notifications.push_prompt.blocked_title` | Notifications are blocked |
| `notifications.push_prompt.blocked_body_settings` | Turn notifications back on in your device settings. |
| `notifications.push_prompt.blocked_body_web` | Open the padlock icon in your browser's address bar to allow notifications. |
| `notifications.push_prompt.blocked_body_ios` | Open Settings, then Notifications, to allow notifications for this app. |
| `notifications.push_prompt.blocked_body_android` | Open this app's notification settings to allow notifications. |
| `notifications.push_prompt.declined_body` | You turned off this reminder. You can still enable push any time. |
| `notifications.push_prompt.ask_title` | Turn on notifications |
| `notifications.push_prompt.ask_body` | Get notified the moment something needs your attention. |
| `notifications.push_prompt.open_settings` | Open settings |
| `notifications.push_prompt.enable` | Enable |
| `notifications.push_prompt.not_now` | Not now |
| `notifications.push_prompt.shell_notice` | Push is off |
| `notifications.push_prompt.shell_notice_a11y` | Push notifications are off |

### Colour roles

`PushPrompt`'s `blocked` and `on` presentations map to the `warning` and
`success` roles of the 17-key semantic alias contract (`design:sync`'s
`_aliasMappings`). Neither role ships a `-container` tint the way
`destructive` does, so the tile and its glyph go solid (`bg-warning` /
`bg-success` with a literal `text-white`) rather than inventing one, the same
pairing `toast.recipe.dart` already uses for these two roles. A host that
wants a softer treatment restyles by copying the recipe file; the component
exposes no per-instance className override today.

---

**Related**

- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
- [Notification Manager](https://magic.fluttersdk.com/packages/notifications/architecture/notification-manager)
