/// Stub implementation for non-web platforms.
///
/// All methods are no-ops that return safe default values.
/// This allows the package to compile and run on all platforms
/// without conditional compilation in consuming code.
library;

/// Initialize OneSignal with configuration.
///
/// No-op on non-web platforms.
Future<void> init({
  required String appId,
  String? safariWebId,
  bool notifyButtonEnabled = false,
}) async {}

/// Whether the OneSignal SDK is available.
///
/// Always returns `false` on non-web platforms.
bool get isAvailable => false;

/// Sets the external user ID.
///
/// No-op on non-web platforms.
Future<void> login(String externalId) async {}

/// Removes the external user ID.
///
/// No-op on non-web platforms.
Future<void> logout() async {}

/// Requests push notification permission.
///
/// Always returns `false` on non-web platforms.
Future<bool> requestPermission() async => false;

/// Opts the user in to push notifications.
///
/// No-op on non-web platforms.
Future<void> optIn() async {}

/// Opts the user out of push notifications.
///
/// No-op on non-web platforms.
Future<void> optOut() async {}

/// Adds tags to the user.
///
/// No-op on non-web platforms.
Future<void> addTags(Map<String, String> tags) async {}

/// Removes a single tag from the user.
///
/// No-op on non-web platforms.
Future<void> removeTag(String key) async {}

/// Removes multiple tags from the user.
///
/// No-op on non-web platforms.
Future<void> removeTags(List<String> keys) async {}

/// Gets the current permission state.
///
/// Always returns `false` on non-web platforms.
bool getPermission() => false;

/// Gets the current opt-in state.
///
/// Always returns `false` on non-web platforms.
bool getOptedIn() => false;

/// Gets the current external user ID.
///
/// Always returns `null` on non-web platforms.
String? getExternalId() => null;

/// Gets the current subscription ID.
///
/// Always returns `null` on non-web platforms.
String? getSubscriptionId() => null;

/// Gets the OneSignal user ID.
///
/// Always returns `null` on non-web platforms.
String? getOneSignalId() => null;

/// Gets all tags for the current user.
///
/// Always returns `null` on non-web platforms.
Map<String, String>? getTags() => null;

/// Sets the language for the current user.
///
/// No-op on non-web platforms.
Future<void> setLanguage(String languageCode) async {}

/// Sets the log level for debugging.
///
/// No-op on non-web platforms.
void setLogLevel(String level) {}

/// Displays the push notification slidedown prompt.
///
/// No-op on non-web platforms.
Future<void> promptPush({bool force = false}) async {}

/// Displays the category slidedown prompt.
///
/// No-op on non-web platforms.
Future<void> promptPushCategories({bool force = false}) async {}

/// Adds a listener for permission state changes.
///
/// No-op on non-web platforms.
void addPermissionChangeListener(void Function(bool permission) callback) {}

/// Adds a listener for notification click events.
///
/// No-op on non-web platforms.
void addNotificationClickListener(
  void Function(Map<String, dynamic> event) callback,
) {}

/// Adds a listener for foreground notification display events.
///
/// No-op on non-web platforms.
void addNotificationForegroundListener(
  void Function(Map<String, dynamic> event) callback,
) {}

/// Adds a listener for user state changes.
///
/// No-op on non-web platforms.
void addUserStateChangeListener(
  void Function(Map<String, dynamic> event) callback,
) {}

/// Adds a listener for subscription state changes.
///
/// No-op on non-web platforms.
void addSubscriptionChangeListener(
  void Function(Map<String, dynamic> event) callback,
) {}
