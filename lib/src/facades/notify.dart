import '../contracts/notifiable.dart';
import '../contracts/notification.dart';
import '../models/database_notification.dart';
import '../models/paginated_notifications.dart';
import '../notification_manager.dart';

/// Notification facade.
///
/// Static API for sending and managing notifications.
///
/// Usage:
/// ```dart
/// // Send notification
/// await Notify.send(user, MonitorDownNotification(monitor));
///
/// // Listen to notifications
/// Notify.notifications().listen((notifications) {
///   print('Unread: ${notifications.where((n) => !n.isRead).length}');
/// });
///
/// // Mark as read
/// await Notify.markAsRead(notificationId);
/// ```
class Notify {
  Notify._(); // Prevent instantiation

  /// Get the notification manager instance.
  static NotificationManager get manager => NotificationManager();

  // ========================================
  // Sending
  // ========================================

  /// Send a notification to a notifiable entity.
  static Future<void> send(
    Notifiable notifiable,
    Notification notification,
  ) async {
    await manager.send(notifiable, notification);
  }

  // ========================================
  // Database (In-App) Notifications
  // ========================================

  /// Get stream of database notifications.
  ///
  /// Emits updated list whenever notifications are fetched, marked as read,
  /// or deleted. Immediately emits current cached list to new listeners.
  static Stream<List<DatabaseNotification>> notifications() {
    return manager.notifications();
  }

  /// Fetch notifications from backend.
  ///
  /// Updates the notification stream with fresh data from the API.
  static Future<void> fetchNotifications() async {
    await manager.fetchNotifications();
  }

  /// Fetch paginated notifications from backend.
  ///
  /// Returns [PaginatedNotifications] with data and pagination metadata.
  /// Useful for full-page notification lists with server-side pagination.
  ///
  /// Example:
  /// ```dart
  /// final result = await Notify.fetchPaginatedNotifications(page: 1, perPage: 15);
  /// print('Page ${result.currentPage} of ${result.lastPage}');
  /// ```
  static Future<PaginatedNotifications> fetchPaginatedNotifications({
    int page = 1,
    int perPage = 15,
  }) async {
    return await manager.fetchPaginatedNotifications(
      page: page,
      perPage: perPage,
    );
  }

  /// Alias for fetchNotifications() for convenience.
  static Future<void> refreshNotifications() async {
    await manager.refreshNotifications();
  }

  /// Get unread notification count.
  ///
  /// Returns count of unread notifications from backend.
  static Future<int> unreadCount() async {
    return await manager.unreadCount();
  }

  /// Mark notification as read.
  ///
  /// Optimistically updates local state, then syncs with backend.
  static Future<void> markAsRead(String id) async {
    await manager.markAsRead(id);
  }

  /// Mark all notifications as read.
  ///
  /// Optimistically updates local state, then syncs with backend.
  static Future<void> markAllAsRead() async {
    await manager.markAllAsRead();
  }

  /// Delete notification.
  ///
  /// Removes notification locally and from backend.
  static Future<void> deleteNotification(String id) async {
    await manager.deleteNotification(id);
  }

  // ========================================
  // Push Notifications
  // ========================================

  /// Initialize push notifications.
  ///
  /// Must be called after login with the user's ID.
  /// Automatically handles push driver configuration from app config.
  ///
  /// Example:
  /// ```dart
  /// await Notify.initializePush(user.id);
  /// ```
  static Future<void> initializePush(String userId) async {
    await manager.initializePushWithUserId(userId);
  }

  /// Request push notification permission.
  ///
  /// Shows the system permission dialog on mobile platforms.
  /// Returns `true` if permission was granted.
  static Future<bool> requestPushPermission() async {
    return await manager.requestPushPermission();
  }

  /// Logout from push notifications.
  ///
  /// Removes the external user ID from the push subscription.
  /// Call this when the user logs out to unlink the device from their account.
  ///
  /// Example:
  /// ```dart
  /// Future<void> doLogout() async {
  ///   await Notify.logoutPush();
  ///   Notify.stopPolling();
  ///   await Auth.logout();
  /// }
  /// ```
  static Future<void> logoutPush() async {
    await manager.logoutPush();
  }

  // ========================================
  // Polling
  // ========================================

  /// Start polling for new notifications.
  ///
  /// Begins fetching notifications from backend at regular intervals.
  /// Safe to call multiple times (idempotent).
  static void startPolling() {
    manager.startPolling();
  }

  /// Stop polling for notifications.
  ///
  /// Call when user logs out or app is closing.
  static void stopPolling() {
    manager.stopPolling();
  }

  /// Pause polling temporarily.
  ///
  /// Use when app goes to background. Resume with [resumePolling()].
  static void pausePolling() {
    manager.pausePolling();
  }

  /// Resume polling after pause.
  ///
  /// Use when app comes to foreground.
  static void resumePolling() {
    manager.resumePolling();
  }

  /// Whether the periodic poller is currently armed.
  static bool get isPolling => manager.isPolling;

  // ========================================
  // Realtime
  // ========================================

  /// Receive notification state over the app's broadcast socket instead of
  /// polling for it.
  ///
  /// [channel] is the private channel the backend publishes the user's rows on,
  /// `App.Models.User.{id}` by Laravel's default. Wire it to auth state next to
  /// [startPolling], which becomes a no-op while this is live:
  ///
  /// ```dart
  /// if (Auth.check()) {
  ///   await Notify.startRealtime(channel: 'App.Models.User.' + User.current.id);
  ///   Notify.startPolling(); // the fallback, if there is no socket
  /// } else {
  ///   Notify.stopRealtime();
  ///   Notify.stopPolling();
  /// }
  /// ```
  ///
  /// Returns false when the app has no broadcast driver configured, so the caller
  /// above keeps polling. See [NotificationManager.startRealtime].
  static Future<bool> startRealtime({
    String? channel,
    String event = NotificationManager.realtimeEvent,
  }) {
    return manager.startRealtime(channel: channel, event: event);
  }

  /// Stop receiving notification state over the socket.
  ///
  /// Call on logout, next to [stopPolling].
  static void stopRealtime() {
    manager.stopRealtime();
  }

  /// Whether notification state is currently arriving over a socket.
  static bool get isRealtime => manager.isRealtime;
}
