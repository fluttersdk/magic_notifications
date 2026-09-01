# Drivers

## Table of Contents

- <a name="toc-concept"></a>[Driver Concept](#concept)
- <a name="toc-abstract"></a>[PushDriver Abstract Class](#abstract)
- <a name="toc-onesignal-mobile"></a>[OneSignalDriver — Mobile (iOS/Android)](#onesignal-mobile)
- <a name="toc-onesignal-web"></a>[OneSignalWebDriver — Web](#onesignal-web)
- <a name="toc-conditional"></a>[Conditional Imports via onesignal_factory.dart](#conditional)
- <a name="toc-custom"></a>[Creating a Custom Driver](#custom)

---

## <a name="concept"></a>Driver Concept

A push driver wraps a platform-specific push SDK. The `PushChannel` delegates all SDK calls to whichever driver is registered with `NotificationManager.setPushDriver()`. Drivers expose a uniform API regardless of the underlying SDK (OneSignal, FCM, etc.), so channel logic never depends on SDK internals.

---

## <a name="abstract"></a>PushDriver Abstract Class

```dart
abstract class PushDriver {
  String get name;
  bool get isSupported;
  Future<PushPermissionState> permissionState();
  bool get isOptedIn;

  Future<void> initialize(Map<String, dynamic> config);
  Future<void> login(String externalId);
  Future<void> logout();
  Future<String?> currentExternalId();
  Future<String?> currentSubscriptionId();
  Future<bool> requestPermission();
  Future<void> optIn();
  Future<void> optOut();
  Future<void> setTags(Map<String, String> tags);
  Future<void> removeTag(String key);

  Stream<PushNotificationEvent> get onNotificationReceived;
  Stream<PushNotificationEvent> get onNotificationClicked;
  Stream<PushPermissionState> get onPermissionChanged;
  Stream<PushIdentityChange> get onIdentityChanged;

  Future<PushReachability> reachability(); // implemented in the base class
}
```

### Key Members

| Member | Description |
|--------|-------------|
| `name` | Driver identifier string (e.g., `'onesignal'`) |
| `isSupported` | Synchronous platform check; `PushChannel.isAvailable` delegates here |
| `permissionState()` | Reads the current `PushPermissionState`. Asynchronous on both platforms: mobile reads the native permission over a platform channel, web reads the browser's own `Notification.permission`. |
| `isOptedIn` | Whether the user is actively subscribed to push |
| `initialize(config)` | One-time SDK init; must be called before all other methods |
| `login(externalId)` | Associates a user account with the push subscription |
| `logout()` | Removes the external user ID from the subscription |
| `currentExternalId()` | Reads back the external id the device is currently subscribed as, or `null` when not initialized or unset. Closes the loop on `login`/`logout`: without it nothing can tell whether the SDK acted on the identity it was given. |
| `currentSubscriptionId()` | Reads back the platform subscription id, or `null` when not initialized or unsubscribed. A push cannot be addressed without one, which is why `reachability()` consults it. |
| `requestPermission()` | Triggers the OS permission dialog; returns `true` if granted |
| `optIn()` / `optOut()` | Re-subscribe / unsubscribe without clearing the external ID |
| `setTags(tags)` | Segmentation tags for OneSignal targeting |
| `onNotificationReceived` | Broadcast stream; fires when a notification arrives while the app is in foreground |
| `onNotificationClicked` | Broadcast stream; fires when the user taps a notification |
| `onPermissionChanged` | Broadcast stream; fires on OS permission state transitions |
| `onIdentityChanged` | Broadcast stream of `PushIdentityChange` events; fires whenever the SDK itself reports the user or subscription changed underneath the app. The only trustworthy confirmation that a `login`/`logout` actually landed. |
| `reachability()` | Whether push can actually reach this device right now (see below). Implemented once in the base class; drivers do not override it. |

### PushNotificationEvent

```dart
class PushNotificationEvent {
  final Map<String, dynamic> data;
  const PushNotificationEvent(this.data);
}
```

The `data` map contains the notification's `additionalData` payload (mobile) or the JS event data (web).

### PushIdentityChange

```dart
class PushIdentityChange {
  final String? externalId;
  final String? subscriptionId;
  final bool? optedIn;
  const PushIdentityChange({this.externalId, this.subscriptionId, this.optedIn});
}
```

Every field is nullable because a single SDK event reports only part of the state: a user change carries the external id, a subscription change carries the subscription id and the opt-in flag. A `null` field means "this event did not report it", never "it is empty".

### Reachability

`PushDriver.reachability()` derives a four-state answer instead of each driver
declaring one, so every driver answers the same way:

| State | Meaning |
|-------|---------|
| `PushReachability.unavailable` | No platform driver here at all (`isSupported == false`). |
| `PushReachability.blocked` | Permission was denied and the platform will not re-prompt. The app has to point the person at the OS/browser setting; calling `requestPermission()` again silently no-ops. |
| `PushReachability.off` | Never asked, or asked and not opted in. Safe to call `requestPermission()`. |
| `PushReachability.on` | Permitted, opted in, and holding a subscription id — the only state a push can actually reach. |

```dart
final reachability = await driver.reachability();
```

This is the read a soft-prompt UI should gate on before showing itself, and
the read that answers "can I send this device a push" without ever raising
the OS dialog.

---

## <a name="onesignal-mobile"></a>OneSignalDriver — Mobile (iOS/Android)

`OneSignalDriver` wraps the `onesignal_flutter` package.

```dart
class OneSignalDriver extends PushDriver {
  @override
  String get name => 'onesignal';

  @override
  bool get isSupported => Platform.isIOS || Platform.isAndroid;

  @override
  Future<PushPermissionState> permissionState() async {
    if (!_initialized) return PushPermissionState.notDetermined;

    final native = await OneSignal.Notifications.permissionNative();
    return switch (native) {
      OSNotificationPermission.authorized => PushPermissionState.authorized,
      OSNotificationPermission.provisional ||
      OSNotificationPermission.ephemeral =>
        PushPermissionState.provisional,
      OSNotificationPermission.notDetermined =>
        PushPermissionState.notDetermined,
      // Only iOS reports a real tri-state; elsewhere permissionNative
      // collapses onto denied, so ask the SDK whether a prompt would still
      // show. It does only when the device has never been asked.
      OSNotificationPermission.denied =>
        await OneSignal.Notifications.canRequest()
            ? PushPermissionState.notDetermined
            : PushPermissionState.denied,
    };
  }

  @override
  Future<String?> currentExternalId() async =>
      _initialized ? OneSignal.User.getExternalId() : null;

  @override
  Future<String?> currentSubscriptionId() async =>
      _initialized ? OneSignal.User.pushSubscription.id : null;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    final appId = config['app_id'] as String?;
    OneSignal.initialize(appId!);

    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      _receivedController.add(
        PushNotificationEvent(event.notification.additionalData ?? {}),
      );
    });

    OneSignal.Notifications.addClickListener((event) {
      _clickedController.add(
        PushNotificationEvent(event.notification.additionalData ?? {}),
      );
    });

    // The observer carries a bare bool; re-read permissionState() instead of
    // collapsing the tri-state onto denied.
    OneSignal.Notifications.addPermissionObserver((permission) {
      unawaited(permissionState().then(_permissionController.add));
    });

    OneSignal.User.addObserver((state) {
      _identityController.add(
        PushIdentityChange(externalId: state.current.externalId),
      );
    });

    OneSignal.User.pushSubscription.addObserver((state) {
      _identityController.add(
        PushIdentityChange(
          subscriptionId: state.current.id,
          optedIn: state.current.optedIn,
        ),
      );
    });

    _initialized = true;
  }

  @override
  Future<void> login(String externalId) => OneSignal.login(externalId);

  @override
  Future<void> logout() => OneSignal.logout();

  @override
  Future<bool> requestPermission() =>
      OneSignal.Notifications.requestPermission(true);

  @override
  Future<void> optIn() => OneSignal.User.pushSubscription.optIn();

  @override
  Future<void> optOut() => OneSignal.User.pushSubscription.optOut();

  @override
  Future<void> setTags(Map<String, String> tags) =>
      OneSignal.User.addTags(tags);

  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      _identityController.stream;
}
```

> [!NOTE]
> Throws `NotificationException` with code `PLATFORM_NOT_SUPPORTED` when `initialize` is called on an unsupported platform, and `NOT_INITIALIZED` when `login` or `requestPermission` is called before `initialize`. These are programmer errors — handle them at app startup.

### Listening to Events

```dart
final driver = NotificationManager().pushDriver as OneSignalDriver;

driver.onNotificationReceived.listen((event) {
  final title = event.data['title'];
  // show in-app snackbar
});

driver.onNotificationClicked.listen((event) {
  final url = event.data['action_url'];
  MagicRoute.to(url);
});
```

---

## <a name="onesignal-web"></a>OneSignalWebDriver — Web

`OneSignalWebDriver` communicates with the OneSignal Web SDK v16 via JavaScript interop through `OneSignalJsInterop`.

```dart
class OneSignalWebDriver extends PushDriver {
  @override
  String get name => 'onesignal';

  @override
  bool get isSupported => kIsWeb;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    await OneSignalJsInterop.init(
      appId: config['app_id'],
      safariWebId: config['safari_web_id'],
      notifyButtonEnabled: config['notify_button_enabled'] ?? false,
    );
  }

  @override
  Future<void> login(String externalId) => OneSignalJsInterop.login(externalId);

  @override
  Future<bool> requestPermission() => OneSignalJsInterop.requestPermission();
}
```

The web driver also exposes additional getters that surface JS interop values:

```dart
final webDriver = NotificationManager().pushDriver as OneSignalWebDriver;

print(webDriver.subscriptionId);  // OneSignal subscription UUID
print(webDriver.externalId);      // currently logged-in external user ID
print(webDriver.oneSignalId);     // OneSignal internal user ID
```

> [!TIP]
> Use `OneSignalWebDriver.getWebInitScript(appId: ..., safariWebId: ..., notifyButtonEnabled: ...)` to generate the `<script>` block for `web/index.html` programmatically.

---

## <a name="conditional"></a>Conditional Imports via onesignal_factory.dart

The service provider never imports `OneSignalDriver` or `OneSignalWebDriver` directly. It calls `createOneSignalDriver()` from `onesignal_factory.dart`, which uses Dart's conditional import system:

```dart
// onesignal_factory.dart
import 'onesignal_stub.dart' if (dart.library.html) 'onesignal_web.dart';

PushDriver createOneSignalDriver() => createPlatformDriver();
```

- On **web**: `dart.library.html` is available → `onesignal_web.dart` is imported → returns `OneSignalWebDriver()`
- On **mobile**: the stub is imported → returns `OneSignalDriver()`

This means the entire `onesignal_flutter` dependency (which uses `dart:io`) is tree-shaken out of the web build, and the JS interop code is tree-shaken out of the mobile build.

---

## <a name="custom"></a>Creating a Custom Driver

To add FCM or another push service, extend `PushDriver`:

```dart
import 'package:magic_notifications/magic_notifications.dart';

class FcmDriver extends PushDriver {
  final StreamController<PushNotificationEvent> _receivedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _clickedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushPermissionState> _permissionController =
      StreamController<PushPermissionState>.broadcast();
  final StreamController<PushIdentityChange> _identityController =
      StreamController<PushIdentityChange>.broadcast();

  @override
  String get name => 'fcm';

  @override
  bool get isSupported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.notDetermined;

  @override
  bool get isOptedIn => false;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    // FirebaseMessaging.instance.getToken(); etc.
  }

  @override
  Future<void> login(String externalId) async { /* store token */ }

  @override
  Future<void> logout() async { /* remove token */ }

  @override
  Future<String?> currentExternalId() async => null;

  @override
  Future<String?> currentSubscriptionId() async => null;

  @override
  Future<bool> requestPermission() async {
    // NotificationSettings settings = await FirebaseMessaging.instance.requestPermission();
    return false;
  }

  @override
  Future<void> optIn() async {}

  @override
  Future<void> optOut() async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> removeTag(String key) async {}

  @override
  Stream<PushNotificationEvent> get onNotificationReceived =>
      _receivedController.stream;

  @override
  Stream<PushNotificationEvent> get onNotificationClicked =>
      _clickedController.stream;

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      _permissionController.stream;

  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      _identityController.stream;

  // reachability() is inherited from the base class; no override needed.
}
```

Register it with the manager's driver registry in your service provider's
`boot()` (see [Notification Manager](../architecture/notification-manager.md#push-driver)
for the resolution order):

```dart
@override
Future<void> boot() async {
  final manager = NotificationManager();
  manager.extend('fcm', () => FcmDriver());
  await manager.pushDriver.initialize(
    {'project_id': Config.get('notifications.push.project_id')},
  );
}
```

---

**Related**

- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
- [Notification Manager](https://magic.fluttersdk.com/packages/notifications/architecture/notification-manager)
- [Service Provider](https://magic.fluttersdk.com/packages/notifications/architecture/service-provider)
