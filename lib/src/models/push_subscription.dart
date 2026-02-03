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
