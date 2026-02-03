// Conditional imports to provide platform-specific implementations
// ignore: unused_import
import 'onesignal_js_interop_stub.dart'
    if (dart.library.html) 'onesignal_js_interop_web.dart' as impl;

/// OneSignal JavaScript SDK interop layer.
///
/// Provides static methods to interact with OneSignal Web SDK v16.
/// Uses conditional imports to provide no-op implementations on non-web platforms.
///
/// ## Usage
///
/// ```dart
/// // Login user
/// await OneSignalJsInterop.login('user-123');
///
/// // Logout user
/// await OneSignalJsInterop.logout();
///
/// // Request permission
/// final granted = await OneSignalJsInterop.requestPermission();
///
/// // Manage tags
/// await OneSignalJsInterop.addTags({'tier': 'premium'});
/// await OneSignalJsInterop.removeTag('tier');
/// ```
class OneSignalJsInterop {
  OneSignalJsInterop._();

  /// Initialize OneSignal with configuration.
  ///
  /// This should be called once during app startup. Config options:
  /// - `appId` (required): Your OneSignal App ID
  /// - `safariWebId` (optional): Safari Web ID for Safari browser support
  /// - `notifyButtonEnabled` (optional): Show floating bell widget (default: false)
  static Future<void> init({
    required String appId,
    String? safariWebId,
    bool notifyButtonEnabled = false,
  }) =>
      impl.init(
        appId: appId,
        safariWebId: safariWebId,
        notifyButtonEnabled: notifyButtonEnabled,
      );

  /// Whether the OneSignal SDK is available in the current environment.
  ///
  /// Returns `true` on web when the SDK script is loaded, `false` otherwise.
  static bool get isAvailable => impl.isAvailable;

  /// Sets the external user ID to identify the user.
  ///
  /// Call this after the user logs in to link the browser subscription
  /// to a known user account.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#loginexternal_id
  static Future<void> login(String externalId) => impl.login(externalId);

  /// Removes the external user ID from the current subscription.
  ///
  /// Call this when the user logs out to unlink the browser subscription
  /// from the user account.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#logout
  static Future<void> logout() => impl.logout();

  /// Requests push notification permission from the browser.
  ///
  /// Returns `true` if permission was granted, `false` otherwise.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#requestpermission
  static Future<bool> requestPermission() => impl.requestPermission();

  /// Opts the user in to push notifications.
  ///
  /// If the user has a valid push token, sets subscription status to subscribed.
  /// Otherwise, displays the permission prompt.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#optout-optin-optedin
  static Future<void> optIn() => impl.optIn();

  /// Opts the user out of push notifications.
  ///
  /// Sets subscription status to unsubscribed even if user has a valid token.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#optout-optin-optedin
  static Future<void> optOut() => impl.optOut();

  /// Adds tags to the user for segmentation.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#addtag-addtags
  static Future<void> addTags(Map<String, String> tags) => impl.addTags(tags);

  /// Removes a single tag from the user.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#removetag-removetags
  static Future<void> removeTag(String key) => impl.removeTag(key);

  /// Removes multiple tags from the user.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#removetag-removetags
  static Future<void> removeTags(List<String> keys) => impl.removeTags(keys);

  /// Gets the current push permission state.
  ///
  /// Returns `true` if permission is granted, `false` otherwise.
  static bool getPermission() => impl.getPermission();

  /// Gets the current opt-in state.
  ///
  /// Returns `true` if the user is opted in, `false` otherwise.
  static bool getOptedIn() => impl.getOptedIn();

  /// Gets the current external user ID.
  ///
  /// Returns `null` if no external ID is set.
  static String? getExternalId() => impl.getExternalId();

  /// Gets the current subscription ID (browser/device ID).
  ///
  /// Returns `null` if no subscription exists.
  static String? getSubscriptionId() => impl.getSubscriptionId();

  /// Gets the OneSignal user ID.
  ///
  /// Returns `null` if not initialized.
  static String? getOneSignalId() => impl.getOneSignalId();

  /// Gets all tags for the current user.
  ///
  /// Returns `null` if tags are not available.
  static Map<String, String>? getTags() => impl.getTags();

  /// Sets the language for the current user.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#getlanguage-setlanguage
  static Future<void> setLanguage(String languageCode) =>
      impl.setLanguage(languageCode);

  /// Sets the log level for debugging.
  ///
  /// Valid values: 'trace', 'debug', 'info', 'warn', 'error'
  static void setLogLevel(String level) => impl.setLogLevel(level);

  /// Displays the push notification slidedown prompt.
  ///
  /// Use `force: true` to bypass backoff logic (for testing).
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#promptpush
  static Future<void> promptPush({bool force = false}) =>
      impl.promptPush(force: force);

  /// Displays the category slidedown prompt.
  ///
  /// See: https://documentation.onesignal.com/docs/web-sdk-reference#promptpushcategories
  static Future<void> promptPushCategories({bool force = false}) =>
      impl.promptPushCategories(force: force);

  /// Adds a listener for permission state changes.
  ///
  /// The callback receives `true` when permission is granted, `false` otherwise.
  static void addPermissionChangeListener(
          void Function(bool permission) callback) =>
      impl.addPermissionChangeListener(callback);

  /// Adds a listener for notification click events.
  ///
  /// The callback receives the notification data as a map.
  static void addNotificationClickListener(
    void Function(Map<String, dynamic> event) callback,
  ) =>
      impl.addNotificationClickListener(callback);

  /// Adds a listener for foreground notification display events.
  ///
  /// The callback receives the notification data as a map.
  static void addNotificationForegroundListener(
    void Function(Map<String, dynamic> event) callback,
  ) =>
      impl.addNotificationForegroundListener(callback);

  /// Adds a listener for user state changes.
  ///
  /// The callback receives the user change event data.
  static void addUserStateChangeListener(
    void Function(Map<String, dynamic> event) callback,
  ) =>
      impl.addUserStateChangeListener(callback);

  /// Adds a listener for subscription state changes.
  ///
  /// The callback receives the subscription change event data.
  static void addSubscriptionChangeListener(
    void Function(Map<String, dynamic> event) callback,
  ) =>
      impl.addSubscriptionChangeListener(callback);
}
