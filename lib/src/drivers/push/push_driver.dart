import '../../models/push_subscription.dart';

/// Event fired when a push notification is received or clicked.
class PushNotificationEvent {
  /// The notification payload data.
  final Map<String, dynamic> data;

  /// Creates a new push notification event.
  const PushNotificationEvent(this.data);
}

/// Event fired when the push SDK reports an identity or subscription change.
///
/// Every field is nullable because a single SDK event reports only part of the
/// state: a user change carries the external id, a subscription change carries
/// the subscription id and the opt-in flag. A null field means "this event did
/// not report it", never "it is empty".
class PushIdentityChange {
  /// The external id the SDK now associates with this device, when reported.
  final String? externalId;

  /// The subscription id the SDK now holds for this device, when reported.
  final String? subscriptionId;

  /// Whether the device is opted in, when reported.
  final bool? optedIn;

  /// Creates a new identity change event.
  const PushIdentityChange({
    this.externalId,
    this.subscriptionId,
    this.optedIn,
  });
}

/// Abstract driver for push notification services.
///
/// Implementations should wrap platform-specific push SDKs (OneSignal, FCM, etc.).
abstract class PushDriver {
  /// The driver name (e.g., 'onesignal', 'fcm').
  String get name;

  /// Answers whether a push payload is addressed to the identity this device is
  /// currently subscribed as.
  ///
  /// Installed by the manager when it attaches a driver, so the subject
  /// comparison keeps exactly one implementation and stays where the push
  /// intent lives. A driver never matches subjects itself.
  ///
  /// `null` means nothing is judging, and [mayDisplay] then answers yes: a
  /// driver used without the manager must not go silent.
  bool Function(Map<String, dynamic> data)? subjectGuard;

  /// Whether the platform may DRAW [data] as a notification.
  ///
  /// The one place the "un-judged means display" default lives, so no driver
  /// can get it backwards. A driver that can suppress a notification before the
  /// OS draws it (a foreground-display hook) asks this first; one that cannot
  /// has nothing to ask.
  bool mayDisplay(Map<String, dynamic> data) =>
      subjectGuard?.call(data) ?? true;

  /// Whether push notifications are supported on this platform.
  bool get isSupported;

  /// Reads the current push permission from the platform.
  ///
  /// Asynchronous because both platforms answer asynchronously: mobile reads
  /// the native permission over a platform channel, web reads the browser's
  /// own `Notification.permission`.
  ///
  /// The four states are a PERMISSION, not a reachability answer; see
  /// [reachability] for the question a soft prompt should ask.
  Future<PushPermissionState> permissionState();

  /// Whether the user is opted in to push notifications.
  bool get isOptedIn;

  /// Initializes the push driver with configuration.
  ///
  /// Configuration typically includes:
  /// - `app_id`: The push service application ID
  /// - `sender_id`: The GCM/FCM sender ID (Android)
  /// - Additional platform-specific settings
  Future<void> initialize(Map<String, dynamic> config);

  /// Logs in a user by setting their external ID.
  ///
  /// This associates push notifications with a specific user account.
  Future<void> login(String externalId);

  /// Logs out the current user.
  ///
  /// This removes the external ID association.
  Future<void> logout();

  /// Reads back the external id the device is currently subscribed as.
  ///
  /// Returns `null` when the driver is not initialized or no external id is
  /// set. This is what closes the loop on [login] and [logout]: without it
  /// nothing can tell whether the SDK acted on the identity it was given.
  Future<String?> currentExternalId();

  /// Reads back the subscription id the platform holds for this device.
  ///
  /// Returns `null` when the driver is not initialized or the device has no
  /// subscription yet. A push cannot be addressed without one, which is why
  /// [reachability] consults it.
  Future<String?> currentSubscriptionId();

  /// Requests push notification permission from the user.
  ///
  /// Returns `true` if permission was granted, `false` otherwise.
  Future<bool> requestPermission();

  /// Opts the user in to push notifications.
  Future<void> optIn();

  /// Opts the user out of push notifications.
  Future<void> optOut();

  /// Sets custom tags for targeting.
  ///
  /// Tags can be used for segmenting users and targeting specific notifications.
  Future<void> setTags(Map<String, String> tags);

  /// Removes a specific tag.
  Future<void> removeTag(String key);

  /// Stream of notification received events (app in foreground).
  Stream<PushNotificationEvent> get onNotificationReceived;

  /// Stream of notification clicked events.
  Stream<PushNotificationEvent> get onNotificationClicked;

  /// Stream of permission state changes.
  Stream<PushPermissionState> get onPermissionChanged;

  /// Broadcast stream of identity and subscription changes the SDK reports.
  ///
  /// Fires whenever the SDK itself says the user or the push subscription
  /// changed underneath the app, which is the only trustworthy confirmation
  /// that a [login] or [logout] actually landed.
  Stream<PushIdentityChange> get onIdentityChanged;

  /// Whether push can actually reach this device right now.
  ///
  /// Derived rather than declared, so every driver answers it the same way:
  /// no platform driver is [PushReachability.unavailable]; a denied permission
  /// the platform will not re-prompt is [PushReachability.blocked]; permitted
  /// but not yet subscribed is [PushReachability.off]; and only a permitted,
  /// opted-in device holding a subscription id is [PushReachability.on].
  Future<PushReachability> reachability() async {
    if (!isSupported) return PushReachability.unavailable;

    // 1. A denied permission is the only unreachable-and-unpromptable state;
    //    each driver resolves "never asked" out of it before answering.
    final permission = await permissionState();
    if (permission == PushPermissionState.denied) {
      return PushReachability.blocked;
    }

    // 2. Never asked, or asked and not opted in, is off but promptable.
    if (permission == PushPermissionState.notDetermined) {
      return PushReachability.off;
    }
    if (!isOptedIn) return PushReachability.off;

    // 3. Permitted and opted in still cannot be addressed without an id.
    final subscriptionId = await currentSubscriptionId();
    if (subscriptionId == null || subscriptionId.isEmpty) {
      return PushReachability.off;
    }

    return PushReachability.on;
  }
}
