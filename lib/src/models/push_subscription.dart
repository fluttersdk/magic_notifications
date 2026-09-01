/// Push notification permission states.
enum PushPermissionState {
  /// Permission has not been requested yet.
  notDetermined,

  /// User has denied push notification permission.
  denied,

  /// User has authorized push notifications.
  authorized,

  /// User has granted provisional authorization (iOS quiet notifications).
  provisional,
}

/// Whether push can actually reach a device right now.
///
/// This answers a different question from [PushPermissionState]: a device can
/// be permitted and still unreachable, so a soft-prompt policy reads this
/// rather than the permission enum. It is derived from the permission, the
/// opt-in flag and the presence of a subscription id.
enum PushReachability {
  /// No push driver exists on this build, so nothing can be reached.
  unavailable,

  /// Permission was denied and the platform will not prompt again.
  blocked,

  /// Reachable in principle but off today: never asked, not opted in, or with
  /// no subscription yet.
  off,

  /// Permitted, opted in, and holding a subscription the server can address.
  on,
}

/// Represents a push notification subscription.
class PushSubscription {
  /// The OneSignal subscription ID.
  final String? subscriptionId;

  /// The push token.
  final String? token;

  /// Whether the user has opted in to push notifications.
  final bool optedIn;

  /// The current permission state.
  final PushPermissionState? permissionState;

  /// Creates a new push subscription.
  const PushSubscription({
    this.subscriptionId,
    this.token,
    this.optedIn = false,
    this.permissionState,
  });
}
