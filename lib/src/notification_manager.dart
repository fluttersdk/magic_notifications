import 'dart:async';

import 'package:magic/magic.dart';

import 'contracts/channel.dart';
import 'contracts/notifiable.dart';
import 'contracts/notification.dart';
import 'drivers/push/push_driver.dart';
import 'exceptions/notification_exception.dart';
import 'models/database_notification.dart';
import 'models/paginated_notifications.dart';
import 'notification_poller.dart';

/// Safe logging that doesn't throw when Log service isn't available.
///
/// Used for graceful degradation in test environments.
void _safeLogError(String message) {
  try {
    Log.error(message);
  } catch (_) {
    // Silently ignore when Log service isn't available (e.g., in tests)
  }
}

/// Core notification manager.
///
/// Singleton that manages notification channels and dispatches notifications
/// to multiple channels (database, push, mail).
///
/// Usage:
/// ```dart
/// // Register channels
/// NotificationManager().registerChannel(DatabaseChannel());
/// NotificationManager().registerChannel(PushChannel());
///
/// // Send notification
/// final notification = MonitorDownNotification(monitor);
/// await NotificationManager().send(user, notification);
/// ```
class NotificationManager {
  // Singleton instance
  static final NotificationManager _instance = NotificationManager._internal();

  /// Registry of notification channels
  final Map<String, NotificationChannel> _channels = {};

  /// Stream controller for database notifications
  final StreamController<List<DatabaseNotification>> _notificationController =
      StreamController<List<DatabaseNotification>>.broadcast();

  /// Current list of notifications (cached)
  // ignore: prefer_final_fields
  List<DatabaseNotification> _notifications = [];

  /// Push notification driver (OneSignal, FCM, etc.)
  PushDriver? _pushDriver;

  /// Notification poller for periodic fetching
  NotificationPoller? _poller;

  factory NotificationManager() {
    return _instance;
  }

  NotificationManager._internal();

  /// Register a notification channel.
  ///
  /// Channels are identified by their [name]. If a channel with the same
  /// name already exists, it will be replaced.
  void registerChannel(NotificationChannel channel) {
    _channels[channel.name] = channel;
  }

  /// Check if a channel is registered.
  bool hasChannel(String name) {
    return _channels.containsKey(name);
  }

  /// Send a notification to a notifiable entity.
  ///
  /// Dispatches the notification to all channels returned by
  /// [Notification.via]. Skips unavailable channels and logs warnings
  /// for unknown channels without throwing.
  Future<void> send(Notifiable notifiable, Notification notification) async {
    final channels = notification.via(notifiable);

    for (final channelName in channels) {
      final channel = _channels[channelName];

      if (channel == null) {
        // Log warning for unknown channel (but don't throw)
        // ignore: avoid_print
        print('Warning: Unknown notification channel: $channelName');
        continue;
      }

      if (!channel.isAvailable) {
        // Skip unavailable channels
        continue;
      }

      await channel.send(notifiable, notification);
    }
  }

  /// Clear all registered channels (for testing).
  void forgetChannels() {
    _channels.clear();
  }

  // ========================================
  // Database Notification Methods
  // ========================================

  /// Get stream of database notifications.
  ///
  /// Emits updated list whenever notifications are fetched, marked as read,
  /// or deleted. Immediately emits current cached list to new listeners.
  Stream<List<DatabaseNotification>> notifications() async* {
    // Immediately emit current state to new listener
    yield _notifications;

    // Then yield all future updates
    yield* _notificationController.stream;
  }

  /// Fetch notifications from backend.
  ///
  /// Updates the notification stream with fresh data from the API.
  Future<void> fetchNotifications() async {
    try {
      final response = await Http.get('/notifications');

      if (response.successful) {
        final data = response.data;
        final List<dynamic> items = data['data'] ?? [];

        _notifications = items.map((item) {
          return DatabaseNotification.fromMap(item as Map<String, dynamic>);
        }).toList();

        _notificationController.add(_notifications);
      }
    } catch (e) {
      _safeLogError('Failed to fetch notifications: $e');
      // Don't throw - just keep current state
    }
  }

  /// Fetch paginated notifications from backend.
  ///
  /// Returns a [PaginatedNotifications] wrapper with meta info
  /// (current_page, last_page, per_page, total) for server-side pagination.
  Future<PaginatedNotifications> fetchPaginatedNotifications({
    int page = 1,
    int perPage = 15,
  }) async {
    try {
      final response = await Http.get('/notifications', query: {
        'page': page.toString(),
        'perPage': perPage.toString(),
      });
      if (response.successful) {
        return PaginatedNotifications.fromMap(response.data);
      }
    } catch (e) {
      _safeLogError('Failed to fetch paginated notifications: $e');
    }
    return PaginatedNotifications.empty();
  }

  /// Alias for fetchNotifications() for convenience.
  Future<void> refreshNotifications() async {
    await fetchNotifications();
  }

  /// Get unread notification count.
  ///
  /// Returns count of unread notifications from backend.
  Future<int> unreadCount() async {
    try {
      final response = await Http.get('/notifications/unread-count');

      if (response.successful) {
        return (response.data['count'] as num?)?.toInt() ?? 0;
      }
    } catch (e) {
      _safeLogError('Failed to get unread count: $e');
    }
    return 0;
  }

  /// Mark notification as read.
  ///
  /// Optimistically updates local state, then syncs with backend.
  Future<void> markAsRead(String id) async {
    // Optimistically update local state
    final index = _notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      _notifications[index] = _notifications[index].copyWith(
        readAt: DateTime.now(),
      );
      _notificationController.add(_notifications);
    }

    // Sync with backend
    try {
      await Http.post('/notifications/$id/read');
    } catch (e) {
      _safeLogError('Failed to mark notification as read: $e');
      // Revert optimistic update on failure
      await fetchNotifications();
    }
  }

  /// Mark all notifications as read.
  ///
  /// Optimistically updates local state, then syncs with backend.
  Future<void> markAllAsRead() async {
    // Optimistically update local state
    _notifications = _notifications.map((n) {
      return n.copyWith(readAt: DateTime.now());
    }).toList();
    _notificationController.add(_notifications);

    // Sync with backend
    try {
      await Http.post('/notifications/read-all');
    } catch (e) {
      _safeLogError('Failed to mark all notifications as read: $e');
      // Revert optimistic update on failure
      await fetchNotifications();
    }
  }

  /// Delete notification.
  ///
  /// Removes notification locally and from backend.
  Future<void> deleteNotification(String id) async {
    // Optimistically remove from local state
    final removed = _notifications.where((n) => n.id == id).toList();
    _notifications.removeWhere((n) => n.id == id);
    _notificationController.add(_notifications);

    // Sync with backend
    try {
      await Http.delete('/notifications/$id');
    } catch (e) {
      _safeLogError('Failed to delete notification: $e');
      // Revert optimistic update on failure
      _notifications.addAll(removed);
      _notificationController.add(_notifications);
    }
  }

  // ========================================
  // Push Notification Methods
  // ========================================

  /// Get the configured push driver.
  ///
  /// Throws [NotificationException] if no driver is configured.
  PushDriver get pushDriver {
    if (_pushDriver == null) {
      throw NotificationException(
        'Push driver not configured. Call setPushDriver() first.',
        code: 'PUSH_DRIVER_NOT_CONFIGURED',
      );
    }
    return _pushDriver!;
  }

  /// Set the push notification driver.
  ///
  /// This should be called during app initialization, typically in a
  /// service provider's boot() method.
  void setPushDriver(PushDriver driver) {
    _pushDriver = driver;
  }

  /// Initialize push notifications.
  ///
  /// Must be called before any other push operations. Optionally logs in
  /// the user by setting their external ID.
  ///
  /// Example:
  /// ```dart
  /// await NotificationManager().initializePush(
  ///   {'app_id': 'onesignal-app-id'},
  ///   externalId: user.id,
  /// );
  /// ```
  Future<void> initializePush(
    Map<String, dynamic> config, {
    String? externalId,
  }) async {
    await pushDriver.initialize(config);

    if (externalId != null) {
      await pushDriver.login(externalId);
    }
  }

  /// Request push notification permission from the user.
  ///
  /// Returns `true` if permission was granted, `false` otherwise.
  Future<bool> requestPushPermission() async {
    return await pushDriver.requestPermission();
  }

  /// Clear push driver (for testing).
  void forgetPushDriver() {
    _pushDriver = null;
  }

  // ========================================
  // Push Initialization Helper
  // ========================================

  /// Initialize push notifications with user ID.
  ///
  /// Logs in the user with the push driver. The driver should already be
  /// initialized by the NotificationServiceProvider during boot.
  ///
  /// Call this after user login to associate their device with their account.
  ///
  /// Note: This may fail silently if:
  /// - User hasn't granted push notification permission yet
  /// - There's no active push subscription
  /// - Network/API issues
  ///
  /// The external ID will be set once the user grants permission and a
  /// subscription is created.
  Future<void> initializePushWithUserId(String userId) async {
    if (_pushDriver == null) {
      throw NotificationException(
        'Push driver not configured. Ensure NotificationServiceProvider is registered.',
        code: 'PUSH_DRIVER_NOT_CONFIGURED',
      );
    }

    // Try to login the user with the push provider
    // This may fail if there's no subscription yet - that's OK
    try {
      await _pushDriver!.login(userId);
    } catch (e) {
      _safeLogError(
        'Push login deferred - will retry when subscription is active: $e',
      );
      // Don't rethrow - the external ID will be set when user grants permission
    }
  }

  /// Logout from push notifications.
  ///
  /// Removes the external user ID from the push subscription.
  /// Call this when the user logs out to unlink the device from their account.
  ///
  /// This is important for:
  /// - Preventing targeted transactional messages to this device after logout
  /// - Security: ensuring the next user on this device doesn't receive
  ///   the previous user's notifications
  Future<void> logoutPush() async {
    if (_pushDriver == null) {
      // No driver configured, nothing to logout from
      return;
    }

    try {
      await _pushDriver!.logout();
    } catch (e) {
      _safeLogError('Failed to logout from push: $e');
      // Don't throw - logout should be graceful
    }
  }

  // ========================================
  // Polling Management
  // ========================================

  /// Start polling for new notifications.
  ///
  /// Creates and starts a poller if one doesn't exist.
  /// Safe to call multiple times (idempotent).
  void startPolling() {
    _poller ??= NotificationPoller(this);
    _poller!.start();
  }

  /// Stop polling completely.
  ///
  /// Call when user logs out.
  void stopPolling() {
    _poller?.stop();
    _poller = null;
  }

  /// Pause polling temporarily.
  ///
  /// Call when app goes to background.
  void pausePolling() {
    _poller?.pause();
  }

  /// Resume polling after pause.
  ///
  /// Call when app comes to foreground.
  void resumePolling() {
    _poller?.resume();
  }
}
