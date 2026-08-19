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

  /// The private channel notifications are being received on, or null when the
  /// realtime path is not active.
  BroadcastChannel? _realtimeChannel;

  /// The channel NAME realtime was started for, retained so a repeat call for the
  /// same channel is a no-op and a different one moves the subscription.
  String? _realtimeChannelName;

  /// The connection-state subscription that drives the polling fallback.
  StreamSubscription<BroadcastConnectionState>? _realtimeConnection;

  /// The event name realtime was started for, part of the idempotence key so a
  /// caller that changes the event for the same channel is not silently ignored.
  String? _realtimeEventName;

  /// Whether a [fetchNotifications] read is currently in flight.
  bool _fetching = false;

  /// Frames that arrived while a read was in flight, merged back on top of the
  /// fetched list so the read cannot clobber them.
  final List<DatabaseNotification> _framesDuringFetch =
      <DatabaseNotification>[];

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
    _fetching = true;

    try {
      final response = await Http.get('/notifications');

      if (response.successful) {
        final data = response.data;
        final List<dynamic> items = data['data'] ?? [];

        _notifications = _withFramesReceivedDuringFetch(
          items.map((item) {
            return DatabaseNotification.fromMap(item as Map<String, dynamic>);
          }).toList(),
        );

        _notificationController.add(_notifications);
      }
    } catch (e) {
      _safeLogError('Failed to fetch notifications: $e');
      // Don't throw - just keep current state
    } finally {
      // Always cleared, including on a failed read: a frame received during the
      // window was applied to `_notifications` as it arrived, so it is already
      // held and must not be re-merged into the NEXT fetch as well.
      _fetching = false;
      _framesDuringFetch.clear();
    }
  }

  /// The fetched list with every frame received DURING the read merged back on
  /// top, newest first and keyed by id.
  ///
  /// Without this the read clobbers a frame that landed mid-flight: the frame
  /// prepends to the cached list, then the server's list is assigned over the top
  /// and the notification is gone until something fetches again. The window is
  /// small and entirely real, because [startRealtime] subscribes and THEN fetches,
  /// which is the exact moment a backlog is most likely to be publishing.
  ///
  /// Merged in reverse arrival order, so successive prepends leave the newest
  /// frame at the head.
  List<DatabaseNotification> _withFramesReceivedDuringFetch(
    List<DatabaseNotification> fetched,
  ) {
    List<DatabaseNotification> merged = fetched;
    for (final DatabaseNotification frame in _framesDuringFetch.reversed) {
      merged = _prependKeyedById(frame, merged);
    }

    return merged;
  }

  /// [incoming] at the head of [into], with any earlier row carrying the same id
  /// removed, so a redelivery replaces rather than duplicates.
  List<DatabaseNotification> _prependKeyedById(
    DatabaseNotification incoming,
    List<DatabaseNotification> into,
  ) {
    return <DatabaseNotification>[
      incoming,
      ...into.where((DatabaseNotification n) => n.id != incoming.id),
    ];
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
    // A live socket already delivers every new notification, so a 30-second HTTP
    // timer on top of it asks the server for what it has just been told. The
    // realtime path does its own single initial fetch and its own refetch on
    // reconnect, so there is nothing left for the timer to cover.
    //
    // This is a NO-OP rather than an error: a consumer wires `startPolling()` to
    // its auth state and should not have to know whether a socket happens to be
    // up. `stopRealtime()` (or a dropped connection) restores the timer.
    if (isRealtime) return;

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

  /// Whether the periodic poller is currently armed and fetching.
  bool get isPolling => _poller?.isActive ?? false;

  // ========================================
  // Realtime Notification Methods
  // ========================================

  /// The wire event name a new notification arrives as.
  ///
  /// The server side is a notification declaring `broadcastAs()`. Laravel's own
  /// default is the fully-qualified `Illuminate\Notifications\Events\BroadcastNotificationCreated`,
  /// which works but reads badly in a Dart listener and ties the client to a
  /// framework internal, so the contract is this short name.
  static const String realtimeEvent = 'notification.created';

  /// Whether notification state is currently arriving over a socket.
  bool get isRealtime => _realtimeChannel != null;

  /// Receives notification state from a broadcast channel instead of polling for
  /// it.
  ///
  /// [channel] is the private channel the backend publishes the notifiable's rows
  /// on, `App.Models.User.{id}` for a Laravel `Notifiable` that has not overridden
  /// `receivesBroadcastNotificationsOn()`. The name has to come from the caller:
  /// this package has no user model and cannot know whose notifications these are.
  ///
  /// Returns false, changing nothing, when the app has no broadcast driver
  /// configured. That is the case a `null` `BROADCAST_CONNECTION` deployment is
  /// in, and reporting success there would stop the poller and leave the bell
  /// permanently empty, which is strictly worse than polling.
  ///
  /// On success it:
  ///
  ///  1. connects only if no connection exists. `connect()` is not idempotent in
  ///     magic's Reverb driver (it assigns a fresh channel without closing the
  ///     previous one), so a second call opens a second WebSocket and leaks the
  ///     first;
  ///  2. subscribes and listens for [realtimeEvent] exactly once. A second
  ///     `listen()` for one event REPLACES the earlier handler rather than adding
  ///     to it, so registering anywhere else would silently drop this one;
  ///  3. stops the poller, because the socket now covers it;
  ///  4. fetches the existing list ONCE. A socket carries only what happens next,
  ///     so the rows that already exist have to be read;
  ///  5. watches the connection so a drop falls back to polling and a reconnect
  ///     lifts the fallback and closes the replay gap.
  ///
  /// Idempotent per channel and safe to call on every auth-state change: the same
  /// channel is a no-op, a different one moves the subscription.
  Future<bool> startRealtime({
    String? channel,
    String event = realtimeEvent,
  }) async {
    if (channel == null || channel.isEmpty) return false;
    if (!_broadcastingEnabled()) return false;
    if (_realtimeChannelName == channel && _realtimeEventName == event) {
      return true;
    }

    // A move: drop the previous channel before the first await, so a failed
    // connect leaves a clean unsubscribed state the next call retries rather than
    // a marker pointing at a channel nothing is listening on.
    if (_realtimeChannel != null) stopRealtime();

    try {
      if (!Echo.connection.isConnected) {
        await Echo.connect();
      }
      final BroadcastChannel subscribed = Echo.private(channel);
      subscribed.listen(event, _applyRealtimeFrame);
      _realtimeChannel = subscribed;
      _realtimeChannelName = channel;
      _realtimeEventName = event;
      _watchRealtimeConnection();
    } catch (e) {
      _safeLogError('Failed to start realtime notifications: $e');
      stopRealtime();

      return false;
    }

    stopPolling();
    await fetchNotifications();

    return true;
  }

  /// Stops receiving notification state over a socket.
  ///
  /// Leaves the channel and drops the connection watcher, but does NOT touch the
  /// connection itself: it is shared with whatever else the app subscribes to.
  /// Polling is not restarted here either, because only the caller knows whether
  /// the user is still authenticated; a subsequent [startPolling] arms it.
  void stopRealtime() {
    final BroadcastChannel? channel = _realtimeChannel;
    if (channel != null) {
      Echo.leave(channel.name);
    }
    _realtimeChannel = null;
    _realtimeChannelName = null;
    _realtimeEventName = null;
    _realtimeConnection?.cancel();
    _realtimeConnection = null;
  }

  /// True when the app has a broadcast driver that can actually deliver a frame.
  ///
  /// Reads the configured driver rather than trying to subscribe and seeing what
  /// happens: the null driver accepts a subscription and silently delivers
  /// nothing, so an attempt-based probe would report success on the one
  /// configuration that cannot work.
  bool _broadcastingEnabled() {
    final String? driver = Config.get<String>('broadcasting.default');

    return driver != null && driver.isNotEmpty && driver != 'null';
  }

  /// Falls back to polling while the socket is away, and lifts the fallback with
  /// a refetch when it returns.
  ///
  /// Only `connectionState` is watched, not `onReconnect` as well: a reconnect
  /// necessarily transitions the state to `connected`, so listening to both would
  /// fetch the same list twice for one event.
  void _watchRealtimeConnection() {
    _realtimeConnection?.cancel();
    _realtimeConnection = Echo.connectionState.listen((
      BroadcastConnectionState state,
    ) {
      if (state == BroadcastConnectionState.connected) {
        // The socket is back. Reverb has no replay, so anything published while
        // it was down is gone from the stream and only a fetch recovers it.
        _poller?.stop();
        _poller = null;
        fetchNotifications();

        return;
      }

      // Anything else (reconnecting, disconnected) means frames are not arriving.
      // The subscription stays: realtime is still the intent, polling is the
      // stand-in. Without it a socket that never comes back is a bell that never
      // updates again.
      _poller ??= NotificationPoller(this);
      _poller!.start();
    });
  }

  /// Applies one `notification.created` frame to the cached list and the stream.
  ///
  /// The frame carries the whole row in the same shape `GET /notifications`
  /// returns, so it is decoded and applied rather than used as a signal to fetch:
  /// asking the API for a row that just arrived in full is the round trip this
  /// path exists to remove.
  ///
  /// Newest first, and keyed by id: a redelivery (a socket retry, or the same
  /// notification broadcast twice) replaces the held row instead of appending a
  /// duplicate the bell would count twice.
  ///
  /// A payload the decoder cannot read is logged and dropped. It must not throw
  /// into the driver's listener, and it must not clear what is already held: a
  /// backend one version ahead is a reason to miss one row, not to empty the
  /// list.
  void _applyRealtimeFrame(BroadcastEvent event) {
    try {
      final DatabaseNotification incoming = DatabaseNotification.fromMap(
        event.data,
      );
      // Applied immediately either way, so the bell shows it without waiting;
      // the buffer only exists so a read completing after this cannot drop it.
      if (_fetching) {
        _framesDuringFetch.add(incoming);
      }
      _notifications = _prependKeyedById(incoming, _notifications);
      _notificationController.add(_notifications);
    } catch (e) {
      _safeLogError('Failed to decode a realtime notification: $e');
    }
  }
}
