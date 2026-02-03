import '../../models/push_subscription.dart';

/// Event fired when a push notification is received or clicked.
class PushNotificationEvent {
  /// The notification payload data.
  final Map<String, dynamic> data;

  /// Creates a new push notification event.
  const PushNotificationEvent(this.data);
}

/// Abstract driver for push notification services.
///
/// Implementations should wrap platform-specific push SDKs (OneSignal, FCM, etc.).
abstract class PushDriver {
  /// The driver name (e.g., 'onesignal', 'fcm').
  String get name;

  /// Whether push notifications are supported on this platform.
  bool get isSupported;

  /// Current push permission state.
  PushPermissionState get permissionState;

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
}
