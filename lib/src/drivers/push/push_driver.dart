import '../../models/push_subscription.dart';
import '../../support/notification_log.dart';

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
  ///
  /// **A `false` does not say whether the user was shown anything.** On a
  /// device that has already denied, every platform resolves this immediately
  /// with no dialog, so `false` covers "the user saw a prompt and declined",
  /// "nothing was shown at all", and, where [canOpenPlatformSettings] is true,
  /// "the settings page was opened and the user has not acted yet". Widening
  /// the return type would change this contract for every driver, so it stays
  /// a bool and the distinction is drawn by ASKING FIRST: a caller that needs
  /// it reads [canRaisePermissionRequest] before requesting. True there means
  /// a `false` afterwards was a real decline; false there means this call can
  /// only route the user somewhere, or do nothing at all.
  Future<bool> requestPermission();

  /// Whether raising the permission request would put a dialog in front of the
  /// user.
  ///
  /// The package's ONE answer to that question, so a policy never has to
  /// re-derive it from the permission enum. A device that has never been asked
  /// is the only one a prompt can appear for, and every driver already
  /// resolves its platform's version of that into
  /// [PushPermissionState.notDetermined]: the mobile driver asks the SDK's own
  /// `canRequest()` before it reports `denied`, and the web driver reads the
  /// browser's tri-state `Notification.permission` where `default` is exactly
  /// this state.
  ///
  /// A driver whose SDK answers this question directly overrides it; the
  /// derived answer stays correct for one that does not.
  Future<bool> canRaisePermissionRequest() async {
    return await permissionState() == PushPermissionState.notDetermined;
  }

  /// Whether a permission request on a DENIED device still routes the user to
  /// the platform setting.
  ///
  /// This is the one thing that keeps a reminder honest on a device the OS
  /// prompt is spent on. The mobile SDK can open the app's own settings page
  /// (`fallbackToSettings`), so a reminder there has somewhere to send the
  /// tap; the browser has no such API at all, and a control that opened
  /// nothing would be worse than a sentence saying where the switch lives.
  ///
  /// `false` by default, because a capability a driver has not declared cannot
  /// be assumed, and the cost of being wrong is a dead control.
  bool get canOpenPlatformSettings => false;

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

  /// Removes several tags at once.
  ///
  /// Derived rather than abstract, because a driver that can remove one tag can
  /// remove several and the loop is the same everywhere; a driver whose SDK
  /// offers a batch call overrides this and spends one platform round trip
  /// instead of one per key. Both OneSignal drivers do.
  ///
  /// The caller it exists for is the identity lifecycle: when the person on a
  /// device changes, everything this package wrote for the previous one comes
  /// off in a single step, and a per-key loop across a platform channel is a
  /// window in which half of somebody's tags are gone and half are not.
  Future<void> removeTags(List<String> keys) async {
    for (final String key in keys) {
      await removeTag(key);
    }
  }

  /// Attaches [email] to the identity this device carries.
  ///
  /// ADD rather than set, which is the verb both OneSignal SDKs use: a user
  /// owns zero or more email subscriptions and this attaches one more. What
  /// makes it read as "the address for this identity" is the manager, which
  /// detaches the address it previously attached whenever the described one
  /// changes and takes it back entirely when the identity does.
  ///
  /// **The default sends nothing and says so.** A driver whose platform has no
  /// email channel is a legitimate implementation, but a host that described
  /// somebody by their email address is entitled to know the address went
  /// nowhere; going quiet is how a deployment finds out months later that the
  /// campaigns it built never had an address to send to.
  Future<void> addEmail(String email) async {
    NotificationLog.error(
      'The "$name" push driver carries no email transport, so the address '
      'described for this identity was not sent.',
    );
  }

  /// Detaches [email] from the identity this device carries.
  ///
  /// The default is a no-op, deliberately without the report its [addEmail]
  /// twin makes: a driver that never attached an address has nothing to
  /// detach, and reporting a removal that was never needed would put an error
  /// in the log on every sign-out for the whole platform.
  Future<void> removeEmail(String email) async {}

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
