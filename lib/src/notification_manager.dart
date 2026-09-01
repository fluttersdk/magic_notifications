import 'dart:async';

import 'package:magic/magic.dart';

import 'contracts/channel.dart';
import 'contracts/notifiable.dart';
import 'contracts/notification.dart';
import 'drivers/push/push_driver.dart';
import 'exceptions/notification_exception.dart';
import 'models/database_notification.dart';
import 'models/paginated_notifications.dart';
import 'models/push_delivery_snapshot.dart';
import 'models/push_prompt_advice.dart';
import 'models/push_subscription.dart';
import 'models/push_user_attributes.dart';
import 'notification_poller.dart';
import 'support/notification_log.dart';

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
  ///
  /// Answers "the read FINISHED", which is the only reading its two consumers
  /// can use: [want] compares against the intent behind it, and
  /// [_addressedToIntent] opens its escape hatch on it.
  bool _pushIntentLoaded = false;

  /// The vault read currently in flight, or `null` when none is.
  ///
  /// The read has to be JOINABLE rather than skippable. A second caller that
  /// walked past a read which had only STARTED would compare against an intent
  /// the vault has not answered for yet: a sign-out arriving mid-read reads the
  /// device as already subscribed to nobody, returns early, and is then
  /// overtaken by the login the first caller resumes into, which leaves the
  /// device subscribed as the person who just signed out.
  Future<void>? _pushIntentLoad;

  /// Whether the device is known to carry [_pushIntent].
  bool _pushIdentityConverged = false;

  /// Whether the automatic permission request has already had its one turn in
  /// this process.
  ///
  /// Set when the pass STARTS rather than when it raises a dialog, so an
  /// overlapping second login cannot slip past it while the first is reading
  /// the platform, and so a pass that decided not to ask does not decide again
  /// on the next auth bump. A consumer wires the login path to auth state, and
  /// that bumps on every cold-boot restore and every team switch; asking on
  /// each of those is a dialog the operator has already answered.
  ///
  /// A pass with NO DRIVER to ask through is not a pass and does not take the
  /// turn. It is claimed after that one synchronous read and before every
  /// await, which keeps the property above exactly as it was: the ordering
  /// exists to beat a second login in the same breath, and a driver read that
  /// cannot suspend gives one nowhere to arrive.
  ///
  /// A pass that THREW gives the turn back for the same reason: a throw is
  /// evidence that no dialog reached anybody, so the ask has not been spent.
  /// A pass that decided not to ask keeps it, because that decision was made on
  /// a platform answer and will be the same one on the next bump.
  bool _autoRequestRaised = false;

  /// The failure of the last identity operation, retained rather than only
  /// logged, because nothing retries and a caller has to be able to see it.
  Object? _pushIdentityError;

  /// The reconcile pass currently in flight, or `null` when none is.
  Future<void>? _reconcileInFlight;

  /// The intent the most recent pass targeted.
  ///
  /// How a caller that joined a pass tells "it covered me" from "the intent
  /// moved while it was running", which is the difference between a duplicate
  /// login and a device left subscribed as somebody who signed out.
  String? _reconciledIntent;

  /// How the host describes whoever this device is subscribed as, or `null`
  /// when it describes nobody.
  PushUserAttributesResolver? _describePushUser;

  /// What this process last wrote to the push platform, and `null` when it has
  /// written nothing since the last identity change.
  ///
  /// Held so the write can be TAKEN BACK. Only what this package wrote is ever
  /// removed: a tag somebody set from the dashboard, from a backend, or from
  /// another client is not this device's to delete.
  PushUserAttributes? _writtenAttributes;

  /// The external id [_writtenAttributes] was written for.
  ///
  /// Separate from the intent because they answer different questions: the
  /// intent is who this device SHOULD be subscribed as, this is who it last
  /// described. A pass compares them to decide whether there is anything to
  /// write at all.
  String? _writtenAttributesFor;

  /// The driver the manager is currently listening to, held so its subject
  /// guard can be taken back when it is detached.
  PushDriver? _attachedPushDriver;

  /// The driver subscriptions the manager holds while a driver is attached.
  StreamSubscription<PushNotificationEvent>? _pushReceivedSubscription;
  StreamSubscription<PushNotificationEvent>? _pushClickedSubscription;
  StreamSubscription<PushIdentityChange>? _pushIdentitySubscription;

  /// Push events that passed the subject guard, republished for the app.
  final StreamController<PushNotificationEvent> _pushReceivedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _pushClickedController =
      StreamController<PushNotificationEvent>.broadcast();

  /// Drivers as they are attached, for a host that has to act on one it did not
  /// have at the moment it needed it. See [onPushDriverAttached].
  final StreamController<PushDriver> _pushDriverAttachedController =
      StreamController<PushDriver>.broadcast();

  /// The end of a session, for anything holding notification state of its own.
  /// See [onSessionCleared].
  final StreamController<void> _sessionClearedController =
      StreamController<void>.broadcast();

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

  /// How many [fetchNotifications] reads are in flight right now.
  ///
  /// A DEPTH rather than a flag: two reads overlapping is the ordinary case,
  /// because a push and the reconnect watcher each start one without awaiting
  /// it, and two pushes in quick succession is what an incident looks like.
  int _fetchesInFlight = 0;

  /// Frames that arrived while a read was in flight, merged back on top of the
  /// fetched list so the read cannot clobber them.
  final List<DatabaseNotification> _framesDuringFetch =
      <DatabaseNotification>[];

  /// Bumped every time the rows held for a session that ended stop being this
  /// device's rows: a sign-out, and the test-isolation reset.
  ///
  /// A read issued for the previous session answers with the previous person's
  /// rows, and it answers AFTER the clear; without a marker to compare against,
  /// assigning that answer puts their incident titles back on the bell.
  int _session = 0;

  /// The session the realtime subscription was made for, or `null` when there
  /// is no subscription.
  ///
  /// The socket needs its own copy because a frame is applied SYNCHRONOUSLY as
  /// it arrives, so by then [_session] has already moved and there is nothing
  /// left to compare it against. Leaving a channel is not instantaneous, and
  /// the realtime path fires far more often than the fetch path, so a frame
  /// published just before a sign-out is the likelier of the two to prepend the
  /// previous person's incident title back onto the bell.
  int? _realtimeSession;

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
  /// Dispatches the notification to every channel [Notification.via] returns.
  /// An unknown channel and an unavailable one are both skipped with a warning.
  ///
  /// Every channel gets its attempt even when an earlier one fails, and the
  /// first failure is rethrown once they all have. Channels are independent
  /// delivery attempts, so the loop must not let one decide whether the others
  /// happen: with `via()` answering `['push', 'database']` and a push send
  /// throwing, an abort here means the in-app row is written or not depending
  /// on the ORDER of that list, which is not something a caller writing
  /// `via()` is choosing. Push became able to throw at all in the release that
  /// added the self-test endpoint; before it, this path could not fail.
  ///
  /// The failure still reaches the caller rather than being swallowed. The
  /// first one is rethrown with its type and stack intact, so a caller catching
  /// [NotificationException] for a specific `code` still sees it; any further
  /// ones are reported at error level, because an exception can only carry one.
  Future<void> send(Notifiable notifiable, Notification notification) async {
    final channels = notification.via(notifiable);

    Object? firstError;
    StackTrace? firstStack;

    for (final channelName in channels) {
      final channel = _channels[channelName];

      if (channel == null) {
        NotificationLog.warning(
          'Unknown notification channel: $channelName',
        );

        continue;
      }

      if (!channel.isAvailable) {
        // Skip unavailable channels
        continue;
      }

      try {
        await channel.send(notifiable, notification);
      } catch (error, stack) {
        if (firstError == null) {
          firstError = error;
          firstStack = stack;
        } else {
          NotificationLog.error(
            'The $channelName channel also failed to send '
            '${notification.type}: $error',
          );
        }
      }
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStack!);
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
  ///
  /// Everything still IN FLIGHT is dropped with it. A reconcile pass or a vault
  /// read left in a field is a future minted by the previous test that the next
  /// test's caller joins and waits on, and a read left in the air lands on
  /// whoever comes after it; leaking those through the one seam that exists to
  /// stop exactly that is the worst place for them to hide.
  ///
  /// The host's user description goes with them, for the same reason the
  /// driver registry does: it is a registration, and one made in a previous
  /// test would otherwise describe the person in the next. What it wrote is
  /// forgotten rather than taken back, because this seam does not touch a
  /// device; a driver it just dropped is not one to issue removals through.
  void forgetDrivers() {
    _channels.clear();
    _pushFactories.clear();
    _pushDriver = null;
    _resolvedPushDriver = null;
    _describePushUser = null;
    _writtenAttributes = null;
    _writtenAttributesFor = null;
    _detachPushDriver();
    _pushIntent = null;
    _pushIntentLoaded = false;
    _pushIntentLoad = null;
    _pushIdentityConverged = false;
    _pushIdentityError = null;
    _reconciledIntent = null;
    _reconcileInFlight = null;
    _autoRequestRaised = false;
    _dropInFlightReads();
  }

  /// Drops the state a notification read still in the air owns.
  ///
  /// The session bump is what actually stops that read from landing: zeroing
  /// the depth only stops the NEXT read from inheriting it, while the answer
  /// itself is still on its way back and would otherwise be assigned to
  /// whatever is holding the manager by then. The cached list is deliberately
  /// left alone; this is a reset of the reading machinery, not a sign-out.
  void _dropInFlightReads() {
    _session++;
    _fetchesInFlight = 0;
    _framesDuringFetch.clear();
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
    _fetchesInFlight++;
    final int session = _session;

    try {
      final response = await Http.get('/notifications');

      if (response.successful) {
        final data = response.data;
        final List<dynamic> items = data['data'] ?? [];

        // Rows read for a session that has since ended belong to the person who
        // signed out, and assigning them would undo the clear that dropped them.
        if (session != _session) return;

        _notifications = _withFramesReceivedDuringFetch(
          items.map((item) {
            return DatabaseNotification.fromMap(item as Map<String, dynamic>);
          }).toList(),
        );

        _notificationController.add(_notifications);
      }
    } catch (e) {
      NotificationLog.error('Failed to fetch notifications: $e');
      // Don't throw - just keep current state
    } finally {
      // Cleared when the LAST read finishes, including a failed one: a frame
      // received during the window was applied to `_notifications` as it
      // arrived, so it is already held and must not be re-merged into the NEXT
      // fetch as well. Clearing it when the FIRST of two overlapping reads
      // finishes is what loses a frame: the buffer is shared, so the second
      // read then merges nothing and assigns its older snapshot over the top.
      //
      // Clamped rather than compared against zero exactly: [forgetDrivers]
      // drops the depth while a read is still in the air, so that read comes
      // back and decrements past zero, and a depth left negative would keep
      // the NEXT read's buffer from ever being cleared.
      _fetchesInFlight--;
      if (_fetchesInFlight <= 0) {
        _fetchesInFlight = 0;
        _framesDuringFetch.clear();
      }
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
  ///
  /// Throws [NotificationException] when the read did not land: a dropped
  /// connection, an expired token, a 500, or a body this package cannot
  /// decode. It deliberately does NOT answer an empty page there. An empty
  /// page is exactly what an empty inbox looks like, so a caller handed one
  /// cannot tell "you have no alerts" from "we could not ask", and on an
  /// on-call product those two answers send a person to sleep or to the phone.
  ///
  /// A caller that genuinely wants an empty page on failure catches this and
  /// says so at its own call site, where the choice is visible.
  Future<PaginatedNotifications> fetchPaginatedNotifications({
    int page = 1,
    int perPage = 15,
  }) async {
    // 1. Read the page. A throw from the transport is handled, not swallowed:
    //    logged here where the driver detail still exists, then raised as this
    //    package's own failure.
    final MagicResponse response;
    try {
      response = await Http.get('/notifications', query: {
        'page': page.toString(),
        'perPage': perPage.toString(),
      });
    } catch (e) {
      _failedPageRead(page, '$e', code: 'NOTIFICATIONS_FETCH_FAILED');
    }

    // 2. A non-2xx answer is a failed read too, and the one the old empty page
    //    hid best: nothing throws on a 500, so the screen rendered it as calm.
    if (!response.successful) {
      _failedPageRead(
        page,
        'the backend answered ${response.statusCode}',
        code: 'NOTIFICATIONS_FETCH_FAILED',
      );
    }

    // 3. A 200 carrying a body this package cannot read is a failed read as
    //    well; answering it as an empty page tells the same lie.
    try {
      return PaginatedNotifications.fromMap(response.data);
    } catch (e) {
      _failedPageRead(page, '$e', code: 'NOTIFICATIONS_DECODE_FAILED');
    }
  }

  /// Logs a failed page read and raises it as a [NotificationException].
  ///
  /// Returns [Never], so each call site reads as the end of that path and the
  /// success path stays the only one that produces a page.
  Never _failedPageRead(int page, String reason, {required String code}) {
    final String message = 'Failed to read notifications page $page: $reason.';
    NotificationLog.error(message);

    throw NotificationException(message, code: code);
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
      NotificationLog.error('Failed to get unread count: $e');
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
      NotificationLog.error('Failed to mark notification as read: $e');
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
      NotificationLog.error('Failed to mark all notifications as read: $e');
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
      NotificationLog.error('Failed to delete notification: $e');
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

  /// The factory `notifications.push.driver` names, or, when it names none, the
  /// only one there is.
  ///
  /// A PRESENT config value is an instruction, and the only thing that can
  /// serve it is a factory registered under that name. Falling back to "the
  /// only one there is" would hand the app a driver nobody selected, and it
  /// would silence the provider's unservable-value error too: that check reads
  /// a served driver as a consumer having supplied their own.
  ///
  /// With no value configured there is no instruction to contradict, and one
  /// registered factory is an unambiguous answer. That fallback is what makes
  /// the registry reachable without a boot: a test registers one double and
  /// never runs the provider that would have registered the built-in. With two
  /// or more registered there is no unambiguous answer and the caller gets none.
  PushDriver Function()? _pushFactory() {
    if (_pushFactories.isEmpty) return null;

    final String? configured = Config.get<String>('notifications.push.driver');
    if (configured != null && configured.isNotEmpty) {
      return _pushFactories[configured];
    }

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
  ///
  /// The subject guard is handed to the driver here, rather than reimplemented
  /// there: [_addressedToIntent] is the only comparison in this package, and a
  /// driver that can refuse to DRAW a notification needs the same answer the
  /// republish path uses.
  void _attachPushDriver(PushDriver driver) {
    _detachPushDriver();

    _attachedPushDriver = driver;
    driver.subjectGuard = _addressedToIntent;

    _pushReceivedSubscription =
        driver.onNotificationReceived.listen(_onPushReceived);
    _pushClickedSubscription =
        driver.onNotificationClicked.listen(_onPushClicked);
    _pushIdentitySubscription =
        driver.onIdentityChanged.listen(_onPushIdentityChanged);

    // Announced LAST, so a listener that reads the manager back sees a fully
    // attached driver rather than one halfway through being wired.
    if (!_pushDriverAttachedController.isClosed) {
      _pushDriverAttachedController.add(driver);
    }
  }

  /// Stops listening to the attached driver.
  void _detachPushDriver() {
    _attachedPushDriver?.subjectGuard = null;
    _attachedPushDriver = null;

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

  /// Announces every push driver this manager attaches, as it attaches it.
  ///
  /// It exists for one ordering, and that ordering is the ORDINARY launch
  /// rather than an edge case. A driver is resolved inside
  /// `NotificationServiceProvider.boot()`, while a host's auth provider is
  /// normally registered ahead of it (it has to be: notifications follow a
  /// session). So a cold boot that restores a stored session bumps the auth
  /// state from the earlier provider, and whatever the host wired to that bump
  /// runs while [pushDriverOrNull] is still null. Nothing about that is a race;
  /// the provider order decides it.
  ///
  /// Anything a host does WITH a driver on that path (posting the device's
  /// delivery state to its own backend is the case that asked for this) would
  /// otherwise run once, against nothing, with no way to run again: the
  /// driver's own streams cannot cover it, because subscribing to them is the
  /// very thing that needs a driver.
  ///
  /// Broadcast, and it deliberately does NOT replay: a subscriber arriving
  /// after an attachment reads [pushDriverOrNull] for the current answer and
  /// listens here for the next one. Delivery is asynchronous, so a listener
  /// cannot re-enter the attachment that announced it.
  Stream<PushDriver> get onPushDriverAttached =>
      _pushDriverAttachedController.stream;

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
  ///
  /// This is also the one path that can raise a permission prompt, and only
  /// when [autoRequestOnLoginKey] is switched on. Declaring SOMEBODY is the
  /// trigger, because that is the moment the app has just earned the right to
  /// ask: a person signed in, and the notifications this permission is for are
  /// now addressed to them. Nothing is raised for a sign-out, and nothing is
  /// raised anywhere else in this class.
  Future<void> want(String? externalId) async {
    final String? wanted = _blankToNull(externalId);

    // The vault is read BEFORE the equality check, and the check is what makes
    // that load load-bearing: on a signed-out cold boot `logoutPush()` calls
    // this with null while the in-memory intent is still null and the vault
    // still holds the previous person, so an early return here would skip the
    // delete and leave that id to be read back, and logged in, on the next
    // boot. The load is a no-op once it has run, so a `want` that follows one
    // still overwrites what the vault held.
    await _loadPushIntent();

    // Fired for a DECLARATION, not for a change, so it sits in front of the
    // equality check below: an app that switches the key on ships an update to
    // people who are already signed in, and for every one of them the next
    // declaration is the same id the vault already holds. Gating it on a
    // changed intent would mean nobody was ever asked.
    //
    // Not awaited, and that is the point: the platform dialog resolves when
    // the user taps it, and this call sits on the login path in front of
    // [reconcilePushIdentity]. Awaiting it would hold the identity reconcile,
    // and with it every guarantee that depends on the device carrying the
    // right subject, behind a dialog somebody may never look at.
    if (wanted != null) unawaited(_autoRequestPermissionOnLogin());

    if (_pushIntent == wanted) return;

    final String? previous = _pushIntent;

    _pushIntent = wanted;
    _pushIdentityConverged = false;
    _pushIdentityError = null;

    // A different person now holds this device, so everything held for the last
    // one goes, exactly as it does on sign-out. [logoutPush] cannot cover this:
    // an account switcher, or a token refresh that resolves to a different
    // subject, moves from `user_A` straight to `user_B` with no sign-out
    // between them, and this is the only line that sees it happen.
    //
    // Gated on the PREVIOUS intent being non-null, so a first sign-in and a
    // cold-boot restore do not fire it: there is nobody before them to clear
    // after. A sign-out reaches this too and clears a second time, which is
    // harmless, because [logoutPush] clears unconditionally in front of a
    // `want(null)` that returns early on a device whose intent is already null.
    if (previous != null) _clearCachedNotifications();

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
  ///
  /// Single-flight. A caller arriving while a pass is running JOINS it instead
  /// of starting a second one: the consumer fires this unawaited from more than
  /// one lifecycle path, those paths overlap on a restore-then-bump, and two
  /// passes both reading `actual != intent` both call `login()`. That is the
  /// double call the SDK's own single-flight patch exists to survive, and
  /// re-creating it one layer above the SDK is not a thing to leave in place.
  /// Joining is not dropping, either: the intent can move while a pass runs, so
  /// a joiner whose intent the pass did not cover runs its own afterwards.
  Future<void> reconcilePushIdentity() async {
    // 1. Join whatever is already running, and keep joining: a caller that woke
    //    up behind another joiner's fresh pass has to join THAT one too, or the
    //    two run side by side and the duplicate login is back.
    while (true) {
      final Future<void>? inFlight = _reconcileInFlight;
      if (inFlight == null) break;

      await inFlight;

      // Not a retry, which was deliberately refused: only an intent that MOVED
      // under the pass earns another one. A pass that failed on the intent this
      // caller wants stays failed, and [pushIdentityError] carries the reason.
      if (_pushIntent == _reconciledIntent) return;
    }

    // 2. Publish the pass before the first await, so a caller arriving in the
    //    same turn of the loop sees it and joins.
    final Completer<void> pass = Completer<void>();
    _reconcileInFlight = pass.future;

    try {
      await _runPushIdentityPass();
    } finally {
      // Cleared BEFORE the joiners are woken, so one of them can start the next
      // pass rather than joining a future that has already completed.
      //
      // Guarded on identity for the same reason [_loadPushIntent] guards its
      // own write: [forgetDrivers] nulls this marker, so a pass that started
      // before it and finishes after it would otherwise clear the marker a
      // NEWER pass had already published, and the next caller would start a
      // second concurrent pass and issue the duplicate `login()` the
      // single-flight exists to prevent.
      if (identical(_reconcileInFlight, pass.future)) {
        _reconcileInFlight = null;
      }

      pass.complete();
    }
  }

  /// One reconcile pass, with no single-flight of its own.
  Future<void> _runPushIdentityPass() async {
    await _loadPushIntent();

    final PushDriver? driver = pushDriverOrNull;
    final String? intent = _pushIntent;
    _reconciledIntent = intent;

    if (driver == null) return;

    try {
      final String? actual = _blankToNull(await driver.currentExternalId());

      if (actual == intent) {
        _pushIdentityConverged = true;
        _pushIdentityError = null;
      } else {
        // Before the identity moves, never after. Everything this process
        // wrote belongs to the person the device is about to stop being, and
        // the same call issued afterwards deletes tags off the record of
        // whoever has just arrived. See [describePushUserUsing] for what the
        // SDK does and does not promise here.
        await _retirePushAttributes(driver);

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
          NotificationLog.error(
            'Push identity did not take: wanted "${intent ?? 'nobody'}", '
            'the device reports "${readBack ?? 'nobody'}".',
          );
        }
      }

      // Only onto an identity that actually landed. Writing an email address
      // and a name onto a device still carrying the previous person is the
      // leak this whole pass exists to prevent, wearing a different hat.
      if (_pushIdentityConverged) {
        await _applyPushAttributes(driver, intent);
      }
    } catch (e) {
      // Recorded on the manager, not only logged: nothing retries, so a caller
      // and `notifications:doctor` both have to be able to see that this device
      // is not carrying the intent. A false [isPushIdentityConverged] with a
      // null [pushIdentityError] is the other case, where the call was issued
      // and simply did not take.
      _pushIdentityConverged = false;
      _pushIdentityError = e;
      NotificationLog.error(
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
  /// The receive-side half of the identity guard: convergence is unachievable
  /// offline, so the un-converged window has to be SAFE rather than short.
  ///
  /// What it makes safe is bounded, and the bound is worth stating plainly. It
  /// covers the in-app republish, and, through [PushDriver.subjectGuard], the
  /// OS notification a FOREGROUNDED app is asked about before it is drawn.
  /// Backgrounded or killed, no client code runs at all and the OS draws
  /// whatever arrives; only the server can close that half, by not addressing
  /// a subscription it believes is stale.
  ///
  /// A payload carrying NO subject is un-checkable and is delivered, because a
  /// server older than that payload key must not silence the client.
  ///
  /// An intent nothing has READ yet is un-checkable for the same reason: it is
  /// not a report that this device carries nobody, and comparing against it
  /// drops a real page. Resolving a driver attaches this listener, and the SDK
  /// replays a cold start from a notification TAP while it initialises, which
  /// is before anything has been near the vault.
  bool _addressedToIntent(Map<String, dynamic> data) {
    final Object? subject = data['subject'];
    if (subject == null) return true;
    if (subject is String && subject.isEmpty) return true;
    if (!_pushIntentLoaded) return true;

    if (subject.toString() == _pushIntent) return true;

    NotificationLog.error(
      'Dropped a push addressed to "$subject" on a device subscribed as '
      '"${_pushIntent ?? 'nobody'}".',
    );

    return false;
  }

  /// Reads the persisted intent into memory, once per process.
  ///
  /// Public because the ORDER matters and only the caller controls it: the
  /// service provider runs this before it resolves a driver, because resolving
  /// one attaches the push listeners and the SDK replays a cold-start tap while
  /// it initialises. Called again later it is free, so wiring it early costs
  /// nothing anywhere else.
  Future<void> loadPushIntent() => _loadPushIntent();

  /// Reads the persisted intent once per process.
  ///
  /// Single-flight, and a caller arriving while the read is in the air JOINS it
  /// rather than passing it. Marking the intent loaded on the way IN was the
  /// same bug in two places: it defeated the load-before-compare in [want], and
  /// it closed [_addressedToIntent]'s escape hatch for the whole read window,
  /// which is exactly the window the SDK replays a cold-start tap into.
  ///
  /// A read that throws still counts as read and still completes. Leaving the
  /// flag down there would re-read a vault that is failing on every later call,
  /// and leave the subject guard un-judging for the rest of the process;
  /// leaving the future in place would wedge every later caller on something
  /// nothing completes.
  Future<void> _loadPushIntent() async {
    if (_pushIntentLoaded) return;

    final Future<void>? inFlight = _pushIntentLoad;
    if (inFlight != null) return inFlight;

    // Published before the first await, so a caller arriving in the same turn
    // of the loop sees it and joins.
    final Completer<void> read = Completer<void>();
    _pushIntentLoad = read.future;

    String? persisted;
    bool answered = false;

    try {
      // A build with no `VaultServiceProvider` has nothing to read, which is a
      // finished read rather than an absent one: the in-memory intent is the
      // whole truth there, and the guard has to be allowed to compare with it.
      if (Magic.bound('vault')) {
        persisted = _blankToNull(await Vault.get(pushIntentKey));
      }
      answered = true;
    } catch (e) {
      NotificationLog.error('Failed to read the persisted push intent: $e');
    } finally {
      // Written only while this is still the read the manager is waiting on: a
      // [forgetDrivers] in the window took the handle to it, and an answer for
      // a state that no longer exists must not land in the one that replaced
      // it. Both flags are set before the joiners are woken, so none of them
      // can see a half-finished read and start a second one, and the joiners
      // are woken either way rather than left on a future nothing completes.
      if (identical(_pushIntentLoad, read.future)) {
        if (answered) _pushIntent = persisted;
        _pushIntentLoaded = true;
        _pushIntentLoad = null;
      }
      read.complete();
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
      NotificationLog.error('Failed to persist the push intent: $e');
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

  // ========================================
  // Push User Attributes
  // ========================================

  /// The config key deciding whether anything a host describes is sent to the
  /// push platform at all.
  ///
  /// Absent means off, and off is the shipped state. What travels this path is
  /// an email address and whatever a host puts in a tag, which on the product
  /// that asked for it is a person's first and last name: personal data
  /// leaving the app for a third party under that vendor's own retention and
  /// export rules. An adopter opts IN to that, deliberately, per deployment;
  /// discovering afterwards that a package they installed has been sending it
  /// is the outcome this default exists to make impossible.
  ///
  /// It gates the WHOLE seam rather than the email alone, because this package
  /// cannot tell one tag from another: `{'first_name': 'Ada'}` is as personal
  /// as an address and `{'plan': 'pro'}` is not, and both arrive here as two
  /// strings. Sorting them would be this package guessing at a classification
  /// only the host can make.
  static const String shareUserAttributesKey =
      'notifications.push.share_user_attributes';

  /// Registers how this app describes whoever signs in, once.
  ///
  /// The package owns the transport and the identity lifecycle; the host owns
  /// the values. [describe] is called with the external id the device is being
  /// subscribed as, on every login and on every account switch, so nothing has
  /// to re-register per login and no login path has to remember to push a
  /// profile after it.
  ///
  /// ```dart
  /// Notify.describePushUserUsing((String externalId) => PushUserAttributes(
  ///       email: Auth.user()?.email,
  ///       tags: <String, String>{'first_name': ..., 'last_name': ...},
  ///     ));
  /// ```
  ///
  /// Nothing is sent until [shareUserAttributesKey] is switched on, and a host
  /// that never calls this behaves exactly as it did before it existed.
  /// Passing `null` unregisters.
  ///
  /// ### What OneSignal does on a login to a different external id
  ///
  /// From the SDK's own migration guide (`onesignal_flutter-5.6.0`,
  /// `MIGRATION_GUIDE.md:195-196`), which is the reason this package takes its
  /// writes back itself rather than trusting the switch:
  ///
  ///  - `login` to an id that EXISTS retrieves that user and sets the context
  ///    from the server's copy, and operations performed under a device-scoped
  ///    user "will not be applied to the now logged in user (they will be
  ///    lost)";
  ///  - `login` to an id that does NOT exist creates the user "and the context
  ///    set from the current local state", and operations performed under a
  ///    device-scoped user "***will*** be applied to the newly created user";
  ///  - `logout` reverts to a fresh device-scoped user, and the push
  ///    subscription (which is owned by the DEVICE, unlike tags and email
  ///    subscriptions) transfers to whoever logs in next.
  ///
  /// So the documented promise covers a device-scoped user's operations, and
  /// the one branch it promises anything about at all is the branch that
  /// CARRIES them onto the next person. A sign-out followed by a first login
  /// for somebody new is the ordinary shape of a shared device, and it is
  /// precisely the branch where a write left behind lands on the wrong record.
  /// The guide says nothing either way about a straight switch from one
  /// identified user to another.
  ///
  /// That is not a guarantee to build a privacy boundary on, so this package
  /// does not: everything it wrote is removed WHILE the SDK still points at
  /// the person it was written for, before the `login` or `logout` that moves
  /// the device on. The cost is that the previous person's tags come off their
  /// OneSignal record when they leave this device, and the resolver puts them
  /// straight back on their next login anywhere; the alternative is leaving a
  /// name and an email address attached to a subscription that has moved to
  /// somebody else.
  void describePushUserUsing(PushUserAttributesResolver? describe) {
    _describePushUser = describe;
  }

  /// Writes what the host describes [intent] with, unless this process has
  /// already written exactly that for exactly that identity.
  ///
  /// Runs on every reconcile, which is what makes "register once" true: a cold
  /// boot has written nothing yet and writes, a team switch has already
  /// written for the same person and writes nothing, and a described value
  /// that changed reaches the platform at the next pass.
  ///
  /// Failure is logged and dropped rather than raised, and that asymmetry is
  /// the point: a tag is segmentation, the identity is what keeps somebody
  /// else's outage off this screen, and a refused attribute write must not be
  /// reported as an identity that did not land.
  Future<void> _applyPushAttributes(PushDriver driver, String? intent) async {
    if (intent == null) return;

    final PushUserAttributes previous =
        _writtenAttributes ?? PushUserAttributes.none;

    try {
      final PushUserAttributes wanted = _describedAttributes(intent);
      if (_writtenAttributesFor == intent && previous == wanted) return;

      // Ownership is claimed BEFORE the writes. A pass that fails halfway has
      // put something on the device, and a record saying it wrote nothing is
      // how that half survives the next account switch; removing a tag that
      // never landed costs nothing, since both SDKs treat it as absent.
      _writtenAttributes = wanted;
      _writtenAttributesFor = intent;

      // 1. The described state first. A key present in both is OVERWRITTEN by
      //    this write, so retiring the leftovers afterwards never leaves a tag
      //    missing for a moment the way a clear-then-write would.
      if (wanted.tags.isNotEmpty) await driver.setTags(wanted.tags);

      final String? email = wanted.email;
      if (email != null && email != previous.email) {
        await driver.addEmail(email);
      }

      // 2. Then whatever THIS PACKAGE wrote that is no longer described. A tag
      //    set from the dashboard, a backend or another client is not this
      //    device's to delete, so only the keys it put there are taken back.
      final List<String> retired = previous.tags.keys
          .where((String key) => !wanted.tags.containsKey(key))
          .toList();
      if (retired.isNotEmpty) await driver.removeTags(retired);

      final String? retiredEmail = previous.email;
      if (retiredEmail != null && retiredEmail != wanted.email) {
        await driver.removeEmail(retiredEmail);
      }
    } catch (e) {
      NotificationLog.error(
        'Failed to describe "$intent" to the push platform: $e',
      );
    }
  }

  /// Takes back everything this process wrote for the identity the device
  /// currently carries.
  ///
  /// Called with the SDK still pointing at that person, which is the only
  /// moment a removal reaches the right record: a device-scoped user's
  /// operations are applied to the next user a `login` CREATES, so a removal
  /// issued after a sign-out follows the next person onto their brand-new
  /// record, and one issued after a switch runs against the person who has
  /// just arrived.
  ///
  /// Failure is logged and the pass continues to its identity call. Of the two
  /// available failures, a tag that could not be removed is a leak of
  /// segmentation data on one vendor's record; a device left subscribed as
  /// somebody who signed out pages the wrong person about somebody else's
  /// outage. The identity call is not held behind the softer one.
  ///
  /// ## What this does NOT cover, stated because the rest reads like it does
  ///
  /// The record of what to take back, [_writtenAttributes], is process-local by
  /// construction: it is what THIS launch wrote. So the guarantee holds across a
  /// switch and a sign-out within one process, and not across a restart between
  /// them. An app that describes a user, is killed, and comes back to a
  /// different account leaves the first person's email and tags on the vendor's
  /// record, because nothing in this process knows they were ever written.
  ///
  /// Persisting the record would close that, and it is deliberately not done
  /// here: it would put a person's email address into device storage in order to
  /// be able to delete it later, which is a worse trade for the same feature.
  /// The honest mitigation is on the other side, a server-side write through the
  /// vendor's own API keyed on the external id, which needs no local copy of
  /// anything. Until that exists, an adopter turning
  /// [shareUserAttributesKey] on should know the boundary is one process wide.
  Future<void> _retirePushAttributes(PushDriver driver) async {
    final PushUserAttributes written =
        _writtenAttributes ?? PushUserAttributes.none;

    // Dropped before the calls rather than after them: whatever becomes of
    // them, they are no longer this process's to re-apply or to remove a
    // second time against whoever arrives next.
    _writtenAttributes = null;
    _writtenAttributesFor = null;

    if (written.isEmpty) return;

    try {
      if (written.tags.isNotEmpty) {
        await driver.removeTags(written.tags.keys.toList());
      }

      final String? email = written.email;
      if (email != null) await driver.removeEmail(email);
    } catch (e) {
      NotificationLog.error(
        'Failed to take back the push attributes of the previous identity: $e',
      );
    }
  }

  /// What the host describes [externalId] with, or nothing at all.
  ///
  /// The three ways of saying nothing (a deployment that has not opted in, a
  /// host that registered no resolver, and a resolver answering `null` for a
  /// guest) collapse onto one value here, so the write path has one shape
  /// rather than three null checks.
  PushUserAttributes _describedAttributes(String externalId) {
    if (Config.get<bool>(shareUserAttributesKey) != true) {
      return PushUserAttributes.none;
    }

    final PushUserAttributesResolver? describe = _describePushUser;
    if (describe == null) return PushUserAttributes.none;

    return describe(externalId) ?? PushUserAttributes.none;
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
  /// Returns `true` if permission was granted, `false` otherwise. See
  /// [PushDriver.requestPermission] for what a `false` does and does not say.
  Future<bool> requestPushPermission() async {
    return await pushDriver.requestPermission();
  }

  // ========================================
  // Permission Policy
  // ========================================

  /// The config key that lets this package raise the permission request by
  /// itself, once, after somebody signs in.
  ///
  /// Absent means off. Raising a system dialog is the most interruptive thing
  /// a notification package can do, and an app that upgrades without touching
  /// its config must not start doing it.
  static const String autoRequestOnLoginKey =
      'notifications.push.auto_request_on_login';

  /// The config key carrying how long the app waits before reminding somebody
  /// again, in HOURS.
  ///
  /// Hours rather than days because the useful cadence on an on-call product
  /// is a day or less, and a day-based key cannot express anything under one
  /// without a fraction. `0`, absent, or a negative value all mean never, so
  /// the reminder stays a one-shot until an app asks for otherwise.
  static const String repromptAfterHoursKey =
      'notifications.push.reprompt_after_hours';

  /// The config key an app uses to switch its own reminder off wholesale.
  ///
  /// Older than both keys above and previously read only by the host's own
  /// prompt; [pushPromptAdvice] now honours it, so an app that turned the
  /// prompt off does not have to remember to check it twice. Absent means on,
  /// which is what it has always meant.
  static const String softPromptEnabledKey =
      'notifications.soft_prompt.enabled';

  /// Whether the app may put its own push reminder in front of the user right
  /// now, and what that reminder's control can accomplish.
  ///
  /// [declinedAt] is the last time the operator turned the reminder down on
  /// THIS device, or `null` when they never have. The package does not store
  /// it and will not: a decline is the consumer's own UI event, recorded
  /// wherever that consumer already keeps device state, and a second copy in
  /// here would be a second answer to drift out of sync. What the package owns
  /// is the POLICY, because that is the part two consumers would each get
  /// wrong in their own way.
  ///
  /// The policy, in order:
  ///
  ///  1. a device that is already subscribed, or a build with no push at all,
  ///     is never reminded, and there is nothing for a control to do;
  ///  2. an app that switched [softPromptEnabledKey] off is never reminded;
  ///  3. a device that has never turned the reminder down may be reminded now;
  ///  4. otherwise the reminder is due only once [repromptAfterHoursKey] has
  ///     elapsed since [declinedAt], and never at all when that key is unset.
  ///
  /// A DENIED device is included on purpose. The OS prompt cannot recur there,
  /// but the app's own reminder is not the OS prompt: on mobile its action
  /// opens the app's settings page, which is a real route back, so silencing
  /// it would strand exactly the people whose pages are going nowhere. What
  /// the action can do is carried in [PushPromptAdvice.action] rather than
  /// left to the caller to infer from the platform.
  Future<PushPromptAdvice> pushPromptAdvice({DateTime? declinedAt}) async {
    // 1. Read the device once. Everything below is derived from this reading,
    //    so a caller never has to reconcile two reads taken a moment apart.
    //
    //    The read is guarded the same way `pushDeliverySnapshot()` guards its
    //    own, and for the same reason: `reachability()` reaches a platform
    //    channel, a throw there is a failure to ASK rather than an answer, and
    //    letting it escape would take down the widget that called this to
    //    decide whether to render a reminder. `unavailable` is the honest
    //    reading of a device that cannot say, and it resolves to
    //    `PushPromptAction.none`, so a host shows nothing rather than a control
    //    that cannot work.
    final PushDriver? driver = pushDriverOrNull;
    PushReachability reachability = PushReachability.unavailable;

    if (driver != null) {
      try {
        reachability = await driver.reachability();
      } catch (e) {
        NotificationLog.error('Failed to read push reachability: $e');
      }
    }
    final PushPromptAction action = _promptAction(driver, reachability);

    // 2. Nothing to offer is the end of it, whatever the timestamps say.
    if (action == PushPromptAction.none) {
      return PushPromptAdvice(
        show: false,
        reachability: reachability,
        action: action,
      );
    }

    return PushPromptAdvice(
      show: _softPromptEnabled && _remindersDue(declinedAt),
      reachability: reachability,
      action: action,
    );
  }

  /// What a reminder's control could accomplish for [reachability].
  ///
  /// The `blocked` branch is the one that cannot be answered from the state
  /// alone: whether there is anywhere to send the tap is a property of the
  /// PLATFORM, and only the driver knows it.
  PushPromptAction _promptAction(
    PushDriver? driver,
    PushReachability reachability,
  ) {
    return switch (reachability) {
      PushReachability.unavailable ||
      PushReachability.on =>
        PushPromptAction.none,
      PushReachability.off => PushPromptAction.request,
      PushReachability.blocked => driver?.canOpenPlatformSettings ?? false
          ? PushPromptAction.openSettings
          : PushPromptAction.instructions,
    };
  }

  /// Whether enough time has passed since [declinedAt] to ask again.
  ///
  /// A never-declined device is always due. A declined one is due only when an
  /// interval is configured AND it has fully elapsed; a timestamp in the
  /// future (a device whose clock is ahead) elapses nothing, so it answers no
  /// rather than reading a negative difference as time served.
  bool _remindersDue(DateTime? declinedAt) {
    if (declinedAt == null) return true;

    final int hours = Config.get<int>(repromptAfterHoursKey) ?? 0;
    if (hours <= 0) return false;

    return DateTime.now().difference(declinedAt) >= Duration(hours: hours);
  }

  /// Whether the host app has left its own reminder switched on.
  bool get _softPromptEnabled => Config.get<bool>(softPromptEnabledKey) ?? true;

  /// Raises the platform permission request once per process, when the app
  /// asked for that and the OS has never been asked.
  ///
  /// Called from [want] and nowhere else, so there is exactly one path in this
  /// package that can put a system dialog on screen. It deliberately does NOT
  /// run from [reconcilePushIdentity], which fires on every auth-state change
  /// and on a signed-out boot: a dialog raised from there arrives with nothing
  /// in front of it explaining what it is for.
  ///
  /// Failure releases the turn and is then logged and dropped rather than
  /// raised. It runs unawaited off the login path, so a throw would surface as
  /// an unhandled async error, and a permission this app could not ask for is
  /// not a reason to fail a login.
  Future<void> _autoRequestPermissionOnLogin() async {
    // 1. Absent means off, and so does a value that is not a boolean.
    if (Config.get<bool>(autoRequestOnLoginKey) != true) return;

    // 2. Nothing to ask through, and this is read BEFORE the turn is claimed.
    //    A host's auth provider is normally registered ahead of the
    //    notifications one, so a cold boot that restores a stored session
    //    declares an identity while `NotificationServiceProvider` (the only
    //    thing that resolves a driver) has not booted: claiming the turn there
    //    spends the single ask having asked nobody, and no OS prompt can be
    //    raised for the rest of the launch. See [onPushDriverAttached] for the
    //    signal a host uses to come back once a driver exists.
    final PushDriver? driver = pushDriverOrNull;
    if (driver == null) return;

    // 3. One turn per process, claimed before the first await so two logins in
    //    the same breath cannot both take it. The read above is synchronous, so
    //    reading it first costs that property nothing.
    if (_autoRequestRaised) return;
    _autoRequestRaised = true;

    try {
      // 4. `off` is the only state worth asking in: `on` is already
      //    subscribed, `blocked` has spent the prompt, `unavailable` has no
      //    platform to ask.
      if (await driver.reachability() != PushReachability.off) return;

      // 5. Reachable is not the same as promptable. A device that was asked
      //    once, granted, and then opted out reads `off` too, and a request
      //    there resolves without showing anybody anything.
      if (!await driver.canRaisePermissionRequest()) return;

      await driver.requestPermission();
    } catch (e) {
      // 6. The turn goes back BEFORE the failure is logged, because a throw out
      //    of any of the three calls above is positive evidence that no dialog
      //    was ever put in front of anybody: nothing here draws a prompt except
      //    `requestPermission()`, and it threw instead of resolving. Keeping the
      //    claim would spend the single ask per launch on a pass that showed
      //    nobody anything, which is the same defect the driver-less ordering
      //    above carries, burnt by a driver that threw rather than by one that
      //    was absent. The realistic route in is a web driver whose
      //    `initialize` has not finished: `permissionState()` answers
      //    `notDetermined`, so [PushDriver.reachability] reads `off` and
      //    [PushDriver.canRaisePermissionRequest] passes, and the SDK then
      //    raises NOT_INITIALIZED.
      //
      //    Releasing is the whole of it. Nothing is retried from here: the next
      //    DECLARATION asks again (which for the ordering above is the next
      //    auth-state bump, and for a host reading `onPushDriverAttached` is the
      //    moment a driver exists), and a retry loop on a platform that is
      //    failing would be a dialog attempt nobody asked for.
      _autoRequestRaised = false;

      NotificationLog.error(
        'The automatic push permission request failed: $e',
      );
    }
  }

  /// Reads whether a push can reach this device right now, in a shape a
  /// consumer can POST to its own backend.
  ///
  /// The server half of an escalation policy cannot see any of this: the
  /// permission, the opt-in flag and the subscription id all live on the
  /// device. Handed the snapshot, it can move on to the next responder
  /// immediately instead of waiting out an acknowledgement from a phone that
  /// was never going to ring.
  ///
  /// No transport is shipped with it, on purpose. This package does not know
  /// the consumer's API, and an endpoint invented here would be one more
  /// contract to keep in sync with a backend it cannot see. See
  /// [PushDeliverySnapshot] for the shape and what it deliberately omits.
  ///
  /// A platform read that throws answers `unavailable` rather than raising.
  /// The caller is on a lifecycle path, and of the two wrong answers available
  /// on a failed read, "this device may not be reachable" escalates to a human
  /// who is, while "reachable" strands the page on a device nobody can prove
  /// is there.
  Future<PushDeliverySnapshot> pushDeliverySnapshot() async {
    final DateTime capturedAt = DateTime.now().toUtc();
    final PushDriver? driver = pushDriverOrNull;

    if (driver == null) {
      return PushDeliverySnapshot(
        reachability: PushReachability.unavailable,
        capturedAt: capturedAt,
      );
    }

    try {
      return PushDeliverySnapshot(
        reachability: await driver.reachability(),
        externalId: _blankToNull(await driver.currentExternalId()),
        subscriptionId: _blankToNull(await driver.currentSubscriptionId()),
        capturedAt: capturedAt,
      );
    } catch (e) {
      NotificationLog.error('Failed to read the push delivery state: $e');

      return PushDeliverySnapshot(
        reachability: PushReachability.unavailable,
        capturedAt: capturedAt,
      );
    }
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
  ///
  /// It also drops the rows held for the session that just ended, because this
  /// is the sign-out call: it runs on a build with no push driver at all, and
  /// it is unconditional, where `want(null)` returns early on a device whose
  /// intent is already null.
  Future<void> logoutPush() async {
    // Here rather than in [stopPolling], which is NOT a sign-out: [startRealtime]
    // calls it on its way in, so clearing there would empty the bell every time
    // a socket comes up.
    _clearCachedNotifications();

    await want(null);
    await reconcilePushIdentity();
  }

  /// Drops the notifications held for the session that just ended and publishes
  /// the empty state.
  ///
  /// [notifications] hands its cached list to every new listener immediately,
  /// so without this the next person on a shared device reads the previous
  /// person's incident titles and monitor names off the bell until the first
  /// fetch lands. Bumping [_session] is the other half: a read issued for the
  /// previous session is still in flight and answers with their rows.
  void _clearCachedNotifications() {
    _session++;
    _notifications = <DatabaseNotification>[];
    _framesDuringFetch.clear();
    _notificationController.add(_notifications);

    if (!_sessionClearedController.isClosed) {
      _sessionClearedController.add(null);
    }
  }

  /// Fires when the session ends and this manager drops what it held for it.
  ///
  /// The bell's own cache is cleared by [logoutPush] directly, but it is not
  /// the only place a person's notifications live: the list and preferences
  /// controllers are `Magic.findOrPut` singletons and magic's controller
  /// registry is process-lifetime, so nothing disposes them between two people
  /// using the same device. Without this signal, B signs in and the list paints
  /// A's incident titles from `pageNotifier` before the first refresh lands,
  /// and a refresh that FAILS deliberately leaves those rows up, so they stay.
  ///
  /// Anything caching per-person notification state subscribes here and drops
  /// it. Published rather than pushed: the manager is the core and must not
  /// reach up into the UI layer to reset it.
  Stream<void> get onSessionCleared => _sessionClearedController.stream;

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
      // The no-op branch still adopts the session now in effect. A caller
      // re-arming realtime after a sign-out is declaring this channel current
      // for whoever is signed in now, and a marker left pointing at the ended
      // session would leave the bell permanently deaf on a channel the manager
      // believes it is subscribed to.
      _realtimeSession = _session;

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
      _realtimeSession = _session;
      _watchRealtimeConnection();
    } catch (e) {
      NotificationLog.error('Failed to start realtime notifications: $e');
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
    _realtimeSession = null;
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
  ///
  /// A frame for a session that has ended is dropped too, on the same reasoning
  /// the fetch path already drops a read issued before a sign-out: it is the
  /// previous person's row, and prepending it publishes their incident title to
  /// whoever is holding the device now.
  void _applyRealtimeFrame(BroadcastEvent event) {
    if (_realtimeSession != _session) return;

    try {
      final DatabaseNotification incoming = DatabaseNotification.fromMap(
        event.data,
      );
      // Applied immediately either way, so the bell shows it without waiting;
      // the buffer only exists so a read completing after this cannot drop it.
      if (_fetchesInFlight > 0) {
        _framesDuringFetch.add(incoming);
      }
      _notifications = _prependKeyedById(incoming, _notifications);
      _notificationController.add(_notifications);
    } catch (e) {
      NotificationLog.error('Failed to decode a realtime notification: $e');
    }
  }
}
