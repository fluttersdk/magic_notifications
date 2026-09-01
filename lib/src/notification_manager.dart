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

  /// Push notification driver set explicitly through [setPushDriver].
  PushDriver? _pushDriver;

  /// Registry of push driver factories, keyed by the name a consumer registered
  /// them under and the name `notifications.push.driver` selects between.
  final Map<String, PushDriver Function()> _pushFactories =
      <String, PushDriver Function()>{};

  /// The driver built from [_pushFactories], held so a second read does not
  /// wrap the platform SDK twice.
  PushDriver? _resolvedPushDriver;

  /// The external id this device SHOULD be subscribed as, and `null` when it
  /// should be subscribed as nobody.
  ///
  /// The INTENT, never a report of what the device carries: those two disagree
  /// for as long as the network is down, and every decision here turns on
  /// knowing which of the two it is holding.
  String? _pushIntent;

  /// Whether [_pushIntent] has been read back from the vault yet.
  bool _pushIntentLoaded = false;

  /// Whether the device is known to carry [_pushIntent].
  bool _pushIdentityConverged = false;

  /// The failure of the last identity operation, retained rather than only
  /// logged, because nothing retries and a caller has to be able to see it.
  Object? _pushIdentityError;

  /// The driver subscriptions the manager holds while a driver is attached.
  StreamSubscription<PushNotificationEvent>? _pushReceivedSubscription;
  StreamSubscription<PushNotificationEvent>? _pushClickedSubscription;
  StreamSubscription<PushIdentityChange>? _pushIdentitySubscription;

  /// Push events that passed the subject guard, republished for the app.
  final StreamController<PushNotificationEvent> _pushReceivedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _pushClickedController =
      StreamController<PushNotificationEvent>.broadcast();

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

  /// Drops every channel, every registered push factory, and every resolved
  /// push driver, so each of them answers from its factory again.
  ///
  /// The test-isolation seam, and it clears the push identity state with them:
  /// this manager is a `static final` that outlives a container reset, so an
  /// intent surviving into the next test would make the device claim a subject
  /// nothing ever gave it. Only the IN-MEMORY intent is dropped; the persisted
  /// one is left alone, because a test seam must not sign a real device out.
  void forgetDrivers() {
    _channels.clear();
    _pushFactories.clear();
    _pushDriver = null;
    _resolvedPushDriver = null;
    _detachPushDriver();
    _pushIntent = null;
    _pushIntentLoaded = false;
    _pushIdentityConverged = false;
    _pushIdentityError = null;
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

  /// The vault key the push identity intent is persisted under.
  ///
  /// Persisted rather than held in memory because an app kill between a sign-out
  /// and its retry would otherwise leave the device carrying the previous
  /// person's external id with nothing anywhere saying so.
  static const String pushIntentKey = 'magic_notifications.push_intent';

  /// Get the configured push driver.
  ///
  /// Resolution order: the instance [setPushDriver] was given, then the one
  /// already built from the registry, then the registry itself. Throws
  /// [NotificationException] when the build has no driver at all.
  PushDriver get pushDriver {
    final PushDriver? driver = pushDriverOrNull;

    if (driver == null) {
      throw NotificationException(
        'Push driver not configured. Register one with Notify.extend(name, '
        'factory), or set one explicitly with setPushDriver().',
        code: 'PUSH_DRIVER_NOT_CONFIGURED',
      );
    }

    return driver;
  }

  /// The push driver when this build has one, and `null` when it does not.
  ///
  /// The quiet read: an app with no push configured is a supported state, and
  /// the reconciler runs on every boot including that one.
  PushDriver? get pushDriverOrNull {
    if (_pushDriver != null) return _pushDriver;
    if (_resolvedPushDriver != null) return _resolvedPushDriver;

    final PushDriver Function()? factory = _pushFactory();
    if (factory == null) return null;

    final PushDriver created = factory();
    _resolvedPushDriver = created;
    _attachPushDriver(created);

    return created;
  }

  /// Registers [factory] as the driver named [name].
  ///
  /// Registering a factory does not call it; the driver is built when something
  /// first reads [pushDriver], and the resolved instance is evicted here so a
  /// registration made after a read still takes effect. That path is not an
  /// edge case: a test registers its double after whatever already resolved one.
  ///
  /// ```dart
  /// Notify.extend('fcm', () => FcmPushDriver());
  /// ```
  void extend(String name, PushDriver Function() factory) {
    _pushFactories[name] = factory;
    _resolvedPushDriver = null;

    // The evicted instance takes its subscriptions with it, but only when it is
    // the one in use: an explicit [setPushDriver] outranks the registry and is
    // still attached, so detaching here would leave the app deaf to a driver it
    // is still holding.
    if (_pushDriver == null) _detachPushDriver();
  }

  /// The factory `notifications.push.driver` names, or the only one there is.
  ///
  /// The fallback is what makes the registry reachable without a boot: a test
  /// registers one double and never runs the provider that would have
  /// registered the built-in the config names, so a strictly-by-name lookup
  /// would answer nothing at all. With two or more registered there is no
  /// unambiguous answer and the caller gets none.
  PushDriver Function()? _pushFactory() {
    if (_pushFactories.isEmpty) return null;

    final String? configured = Config.get<String>('notifications.push.driver');
    final PushDriver Function()? named =
        configured == null ? null : _pushFactories[configured];
    if (named != null) return named;

    if (_pushFactories.length == 1) return _pushFactories.values.first;

    return null;
  }

  /// Set the push notification driver explicitly.
  ///
  /// Outranks the registry, so it stays the escape hatch for a consumer holding
  /// an already-built driver. Prefer [extend], which lets the manager own the
  /// driver's lifetime.
  void setPushDriver(PushDriver driver) {
    _pushDriver = driver;
    _attachPushDriver(driver);
  }

  /// Listens to everything [driver] reports, replacing any earlier attachment.
  void _attachPushDriver(PushDriver driver) {
    _detachPushDriver();

    _pushReceivedSubscription =
        driver.onNotificationReceived.listen(_onPushReceived);
    _pushClickedSubscription =
        driver.onNotificationClicked.listen(_onPushClicked);
    _pushIdentitySubscription =
        driver.onIdentityChanged.listen(_onPushIdentityChanged);
  }

  /// Stops listening to the attached driver.
  void _detachPushDriver() {
    _pushReceivedSubscription?.cancel();
    _pushReceivedSubscription = null;
    _pushClickedSubscription?.cancel();
    _pushClickedSubscription = null;
    _pushIdentitySubscription?.cancel();
    _pushIdentitySubscription = null;
  }

  /// Push notifications that arrived in the foreground and are addressed to the
  /// person this device is currently subscribed as.
  Stream<PushNotificationEvent> get onPushReceived =>
      _pushReceivedController.stream;

  /// Push notifications the user tapped that are addressed to the person this
  /// device is currently subscribed as.
  Stream<PushNotificationEvent> get onPushClicked =>
      _pushClickedController.stream;

  /// The external id this device should be subscribed as, `null` for nobody.
  String? get pushIntent => _pushIntent;

  /// Whether the device is known to carry [pushIntent].
  ///
  /// False is the honest answer while a login or a sign-out has not landed, and
  /// it is a state the app is expected to spend real time in: the network is
  /// the thing that fails here. [onPushReceived] is what makes that state safe.
  bool get isPushIdentityConverged => _pushIdentityConverged;

  /// The failure of the last identity operation, or `null` when the last one
  /// succeeded.
  Object? get pushIdentityError => _pushIdentityError;

  /// Records who this device should be subscribed as, and persists it.
  ///
  /// Recording the intent is the whole point: the SDK call can fail, and when
  /// it does the difference between "this device wants nobody" and "this device
  /// carries user_A" is the only thing standing between the next person on it
  /// and somebody else's outage page.
  ///
  /// Nothing is sent to the SDK here; [reconcilePushIdentity] does that.
  Future<void> want(String? externalId) async {
    final String? wanted = _blankToNull(externalId);

    // A `want` before the first reconcile is fresher than whatever the vault
    // holds, so the load is marked done rather than allowed to overwrite it.
    _pushIntentLoaded = true;

    if (_pushIntent == wanted) return;

    _pushIntent = wanted;
    _pushIdentityConverged = false;
    _pushIdentityError = null;

    await _persistPushIntent(wanted);
  }

  /// Brings the device's subscribed identity in line with [pushIntent].
  ///
  /// Reads the device back first and returns without touching the SDK when the
  /// two already agree. That is what makes a team switch structurally free:
  /// `Auth.stateNotifier` bumps on login, on every cold-boot restore and on
  /// every team switch, and a notification belongs to the person, so the same
  /// user id produces zero SDK calls.
  ///
  /// Safe to call with no driver, and safe to call on every auth-state change.
  /// It does not retry: OneSignal retries the network call itself, and the job
  /// here is proving the call was issued against the right id.
  Future<void> reconcilePushIdentity() async {
    await _loadPushIntent();

    final PushDriver? driver = pushDriverOrNull;
    if (driver == null) return;

    final String? intent = _pushIntent;

    try {
      final String? actual = _blankToNull(await driver.currentExternalId());

      if (actual == intent) {
        _pushIdentityConverged = true;
        _pushIdentityError = null;

        return;
      }

      if (intent == null) {
        await driver.logout();
      } else {
        await driver.login(intent);
      }

      // The read-back. `login` and `logout` mutate the SDK's LOCAL user
      // immediately and queue the server half, so agreement here rules out a
      // call that never landed at all and nothing more; the SDK's own
      // observers, in [_onPushIdentityChanged], are the confirmation that it
      // reached the server.
      final String? readBack = _blankToNull(await driver.currentExternalId());
      _pushIdentityConverged = readBack == intent;
      _pushIdentityError = null;

      if (!_pushIdentityConverged) {
        _safeLogError(
          'Push identity did not take: wanted "${intent ?? 'nobody'}", '
          'the device reports "${readBack ?? 'nobody'}".',
        );
      }
    } catch (e) {
      // Recorded on the manager, not only logged: nothing retries, so a caller
      // and `notifications:doctor` both have to be able to see that this device
      // is not carrying the intent. A false [isPushIdentityConverged] with a
      // null [pushIdentityError] is the other case, where the call was issued
      // and simply did not take.
      _pushIdentityConverged = false;
      _pushIdentityError = e;
      _safeLogError(
        'Push identity operation failed for '
        '"${intent ?? 'sign-out'}": $e',
      );
    }
  }

  /// Applies what the SDK itself reports about the device's identity.
  ///
  /// A null [PushIdentityChange.externalId] means the event did not REPORT one
  /// (a subscription change carries only the subscription half), never that the
  /// device carries none, so it is not evidence in either direction.
  void _onPushIdentityChanged(PushIdentityChange change) {
    final String? reported = _blankToNull(change.externalId);
    if (reported == null) return;

    _pushIdentityConverged = reported == _pushIntent;
  }

  /// Republishes a foreground push and refreshes the list behind it.
  void _onPushReceived(PushNotificationEvent event) {
    if (!_addressedToIntent(event.data)) return;

    if (!_pushReceivedController.isClosed) {
      _pushReceivedController.add(event);
    }

    // The push says a row exists that the bell has not read yet, and the next
    // poll tick is up to 30 seconds away.
    unawaited(fetchNotifications());
  }

  /// Republishes a tapped push.
  void _onPushClicked(PushNotificationEvent event) {
    if (!_addressedToIntent(event.data)) return;

    if (!_pushClickedController.isClosed) {
      _pushClickedController.add(event);
    }
  }

  /// Whether a payload is addressed to the person this device is subscribed as.
  ///
  /// The receive-side half of the identity guard, and the half that actually
  /// prevents the leak: convergence is unachievable offline, so the
  /// un-converged window has to be SAFE rather than short.
  ///
  /// A payload carrying NO subject is un-checkable and is delivered, because a
  /// server older than that payload key must not silence the client.
  bool _addressedToIntent(Map<String, dynamic> data) {
    final Object? subject = data['subject'];
    if (subject == null) return true;
    if (subject is String && subject.isEmpty) return true;

    if (subject.toString() == _pushIntent) return true;

    _safeLogError(
      'Dropped a push addressed to "$subject" on a device subscribed as '
      '"${_pushIntent ?? 'nobody'}".',
    );

    return false;
  }

  /// Reads the persisted intent once per process.
  Future<void> _loadPushIntent() async {
    if (_pushIntentLoaded) return;
    _pushIntentLoaded = true;

    if (!Magic.bound('vault')) return;

    try {
      _pushIntent = _blankToNull(await Vault.get(pushIntentKey));
    } catch (e) {
      _safeLogError('Failed to read the persisted push intent: $e');
    }
  }

  /// Writes the intent to the vault, or removes it for a signed-out device.
  ///
  /// A build with no `VaultServiceProvider` registered has no vault to write
  /// to; that is an absent capability rather than a failure, and the in-memory
  /// intent still governs this process.
  Future<void> _persistPushIntent(String? externalId) async {
    if (!Magic.bound('vault')) return;

    try {
      if (externalId == null) {
        await Vault.delete(pushIntentKey);
      } else {
        await Vault.put(pushIntentKey, externalId);
      }
    } catch (e) {
      _safeLogError('Failed to persist the push intent: $e');
    }
  }

  /// [value] with an empty string read as absent.
  ///
  /// The SDK answers a device with no external id as `''` on one platform and
  /// `null` on the other, and an intent comparison that told those apart would
  /// issue a login the device does not need.
  String? _blankToNull(String? value) {
    if (value == null || value.isEmpty) return null;

    return value;
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

    if (externalId == null) return;

    // Through the intent, not straight to `login`: one path reaches the SDK's
    // identity, so an initialisation that fails to log in is recorded in the
    // same place a later reconcile reads.
    await want(externalId);
    await reconcilePushIdentity();
  }

  /// Request push notification permission from the user.
  ///
  /// Returns `true` if permission was granted, `false` otherwise.
  Future<bool> requestPushPermission() async {
    return await pushDriver.requestPermission();
  }

  // ========================================
  // Push Initialization Helper
  // ========================================

  /// Subscribes this device as [userId].
  ///
  /// [userId] is the external id the SERVER addresses, which for a Laravel
  /// backend is `user_<id>` including the prefix; it is forwarded unchanged.
  ///
  /// Recording the intent and reconciling it, rather than calling the SDK and
  /// hoping: a login that fails leaves the intent set and the manager reporting
  /// un-converged, so the next reconcile issues it again and, until then,
  /// [onPushReceived] drops anything addressed to anybody else.
  ///
  /// Does not throw when the build has no push driver. An app with push absent
  /// still has a person signed in, and their intent is worth recording for the
  /// boot that does have one.
  Future<void> initializePushWithUserId(String userId) async {
    await want(userId);
    await reconcilePushIdentity();
  }

  /// Detaches this device from whoever it is subscribed as.
  ///
  /// Call it on sign-out. The intent goes to `null` first and is persisted
  /// there, so a `logout()` that fails, or an app killed before it finished,
  /// still leaves a device that knows it should be subscribed as nobody.
  Future<void> logoutPush() async {
    await want(null);
    await reconcilePushIdentity();
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
