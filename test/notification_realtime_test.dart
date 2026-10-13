import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import 'test_helper.dart';

/// A channel that keeps its handlers so a test can deliver a frame.
///
/// The shipped [FakeBroadcastDriver]'s channel discards both the event name and
/// the callback, so a test against it can prove a channel was opened and nothing
/// about what the app does with a frame that arrives on it.
class _RecordingChannel implements BroadcastChannel {
  _RecordingChannel(this.name);

  @override
  final String name;

  final Map<String, void Function(BroadcastEvent)> handlers =
      <String, void Function(BroadcastEvent)>{};

  @override
  Stream<BroadcastEvent> get events => const Stream<BroadcastEvent>.empty();

  bool _subscribed = false;
  final StreamController<bool> _subscriptionChanges =
      StreamController<bool>.broadcast();

  @override
  bool get isSubscribed => _subscribed;

  @override
  Stream<bool> get onSubscriptionChanged => _subscriptionChanges.stream;

  /// Stands in for the server's `subscription_succeeded` (`true`) and for a
  /// dropped socket or a failed auth (`false`), emitting only on a change the
  /// way the driver does.
  void setSubscribed(bool value) {
    if (_subscribed == value) return;

    _subscribed = value;
    _subscriptionChanges.add(value);
  }

  @override
  BroadcastChannel listen(
    String event,
    void Function(BroadcastEvent) callback,
  ) {
    handlers[event] = callback;
    return this;
  }

  @override
  void stopListening(String event) => handlers.remove(event);

  /// Delivers [data] to the handler registered for [event], the way the driver
  /// delivers a real frame.
  void emit(String event, Map<String, dynamic> data) {
    handlers[event]?.call(
      BroadcastEvent(
        event: event,
        channel: name,
        data: data,
        receivedAt: DateTime(2026, 8, 19),
      ),
    );
  }
}

/// A driver whose private channels are inspectable and whose connection state is
/// drivable, so the fallback path can be tested at all.
class _RecordingDriver extends FakeBroadcastDriver {
  /// When set, [connect] fails with it, as a socket the server refused does.
  Object? connectError;

  @override
  Future<void> connect() async {
    final Object? error = connectError;
    if (error != null) throw error;
    await super.connect();
  }

  final Map<String, _RecordingChannel> channels = <String, _RecordingChannel>{};
  final List<String> left = <String>[];
  final StreamController<BroadcastConnectionState> states =
      StreamController<BroadcastConnectionState>.broadcast();

  @override
  Stream<BroadcastConnectionState> get connectionState => states.stream;

  @override
  BroadcastChannel private(String name) {
    super.private(name);
    return channels.putIfAbsent(
      'private-$name',
      () => _RecordingChannel('private-$name'),
    );
  }

  @override
  void leave(String name) {
    left.add(name);
    channels.remove(name);
    super.leave(name);
  }
}

/// Hands out the recording driver in place of the parent's private one.
class _RecordingManager extends FakeBroadcastManager {
  final _RecordingDriver spy = _RecordingDriver();

  @override
  BroadcastDriver connection([String? name]) => spy;
}

void main() {
  late NotificationManager manager;
  late _RecordingManager echo;

  /// One notification row as the API and the socket both shape it.
  Map<String, dynamic> row({
    String id = 'n1',
    String title = 'Incident opened',
    String createdAt = '2026-08-19T09:30:00.000Z',
  }) =>
      <String, dynamic>{
        'id': id,
        'type': 'App\\Notifications\\IncidentOpened',
        'data': <String, dynamic>{
          'title': title,
          'body': 'API Health is down',
          'action_url': '/incidents/$id',
        },
        'created_at': createdAt,
        'read_at': null,
      };

  /// Starts realtime on a channel the server has already confirmed, so the one
  /// read [NotificationManager.startRealtime] does is awaited rather than left to
  /// the fallback poller's first tick.
  Future<bool> startRealtimeSubscribed(String name) {
    echo.spy.channels['private-$name'] = _RecordingChannel('private-$name')
      ..setSubscribed(true);

    return manager.startRealtime(channel: name);
  }

  setUpAll(() async {
    await initMagicForTests();
  });

  setUp(() {
    manager = NotificationManager();
    manager.forgetDrivers();
    manager.stopRealtime();
    manager.stopPolling();
    echo = _RecordingManager();
    Magic.app.setInstance('broadcasting', echo);
    Config.set('broadcasting.default', 'reverb');
    Http.fake(<String, MagicResponse>{
      'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
    });
  });

  tearDown(() {
    manager.stopRealtime();
    manager.stopPolling();
    Config.forget('broadcasting.default');
    // The recording driver owns a broadcast StreamController per test; leaving it
    // open leaks a handle into every following test and hangs stricter runners.
    echo.spy.states.close();
  });

  group('NotificationManager realtime', () {
    test('subscribes to the private channel and reports realtime', () async {
      final bool started = await manager.startRealtime(
        channel: 'App.Models.User.u1',
      );

      expect(started, isTrue);
      expect(manager.isRealtime, isTrue);
      expect(
        echo.spy.channels['private-App.Models.User.u1']!.handlers.keys,
        contains('notification.created'),
      );
    });

    test('declines when no broadcast driver is configured', () async {
      // A deployment with `BROADCAST_CONNECTION=null` has no socket to receive
      // anything on. Reporting success here would silence the poller and leave
      // the bell permanently empty, which is worse than polling.
      Config.set('broadcasting.default', 'null');

      final bool started = await manager.startRealtime(
        channel: 'App.Models.User.u1',
      );

      expect(started, isFalse);
      expect(manager.isRealtime, isFalse);
    });

    test('fetches the existing list once when it starts', () async {
      final FakeNetworkDriver driver = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{
          'data': <dynamic>[row(id: 'old')],
        }),
      });

      await startRealtimeSubscribed('App.Models.User.u1');

      // The socket only ever carries what happens NEXT, so the list that already
      // exists has to be read once. This is the only HTTP the realtime path does
      // in its steady state.
      expect(
        driver.recorded
            .where((entry) => entry.$1.url.contains('notifications'))
            .length,
        1,
      );
      final List<DatabaseNotification> current =
          await manager.notifications().first;
      expect(current.map((DatabaseNotification n) => n.id), <String>['old']);
    });

    test('a frame prepends to the stream with no further HTTP', () async {
      final FakeNetworkDriver driver = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{
          'data': <dynamic>[row(id: 'old')],
        }),
      });
      await startRealtimeSubscribed('App.Models.User.u1');
      final int afterStart = driver.recorded.length;

      echo.spy.channels['private-App.Models.User.u1']!.emit(
        'notification.created',
        row(id: 'fresh', title: 'Checkout is down'),
      );

      final List<DatabaseNotification> current =
          await manager.notifications().first;
      // Newest first, and the frame IS the state: asking the API again for a row
      // that just arrived in full is the round trip this replaces.
      expect(
        current.map((DatabaseNotification n) => n.id),
        <String>['fresh', 'old'],
      );
      expect(current.first.title, 'Checkout is down');
      expect(driver.recorded.length, afterStart);
    });

    test('a frame the decoder cannot read is dropped, not thrown', () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');

      // A payload shaped by a newer or older backend must not take down the
      // listener that delivered it, and must not clear what is already held.
      echo.spy.channels['private-App.Models.User.u1']!.emit(
        'notification.created',
        <String, dynamic>{'id': 'broken'},
      );

      final List<DatabaseNotification> current =
          await manager.notifications().first;
      expect(current, isEmpty);
      expect(manager.isRealtime, isTrue);
    });

    test('a redelivered id replaces rather than duplicates', () async {
      await startRealtimeSubscribed('App.Models.User.u1');
      final _RecordingChannel channel =
          echo.spy.channels['private-App.Models.User.u1']!;

      channel.emit('notification.created', row(id: 'n1', title: 'First'));
      channel.emit('notification.created', row(id: 'n1', title: 'Corrected'));

      final List<DatabaseNotification> current =
          await manager.notifications().first;
      expect(current, hasLength(1));
      expect(current.single.title, 'Corrected');
    });

    test('a frame that lands mid-fetch survives the fetch', () async {
      Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{
          'data': <dynamic>[row(id: 'old')],
        }),
      });
      await manager.startRealtime(channel: 'App.Models.User.u1');
      final _RecordingChannel channel =
          echo.spy.channels['private-App.Models.User.u1']!;

      // `fetchNotifications()` sets its in-flight flag synchronously and then
      // suspends on the HTTP await, so emitting here lands the frame INSIDE the
      // window. Unhandled, the read then assigns the server's list over the top
      // and the notification is gone until something fetches again, which is
      // exactly the window `startRealtime` opens by subscribing before it fetches.
      final Future<void> reading = manager.fetchNotifications();
      channel.emit(
          'notification.created', row(id: 'fresh', title: 'Mid-flight'));
      await reading;

      final List<DatabaseNotification> current =
          await manager.notifications().first;
      expect(
        current.map((DatabaseNotification n) => n.id),
        <String>['fresh', 'old'],
      );
      expect(current.first.title, 'Mid-flight');
    });

    test('a second frame id from the same window is not duplicated', () async {
      Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{
          'data': <dynamic>[row(id: 'fresh', title: 'From the API')],
        }),
      });
      await manager.startRealtime(channel: 'App.Models.User.u1');
      final _RecordingChannel channel =
          echo.spy.channels['private-App.Models.User.u1']!;

      // The server's list already carries the row the frame announced, which is
      // the common case once a backlog drains. Merging must not leave two.
      final Future<void> reading = manager.fetchNotifications();
      channel.emit(
          'notification.created', row(id: 'fresh', title: 'From the socket'));
      await reading;

      final List<DatabaseNotification> current =
          await manager.notifications().first;
      expect(current, hasLength(1));
      expect(current.single.title, 'From the socket');
    });

    test('changing the event for the same channel re-subscribes', () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');

      await manager.startRealtime(
        channel: 'App.Models.User.u1',
        event: 'notification.pushed',
      );

      // The event is part of the idempotence key. Keyed on the channel alone, the
      // early return skipped the re-listen and the manager silently kept handling
      // the OLD event name, so a caller whose backend renamed it got nothing and
      // no error.
      expect(
        echo.spy.channels['private-App.Models.User.u1']!.handlers.keys,
        contains('notification.pushed'),
      );
    });
  });

  group('NotificationManager polling under realtime', () {
    const String channelName = 'private-App.Models.User.u1';

    /// Starts realtime and has the server confirm the subscription, the state
    /// every test below that wants "the socket is covering the bell" starts from.
    Future<_RecordingChannel> startSubscribed() async {
      await manager.startRealtime(channel: 'App.Models.User.u1');
      final _RecordingChannel channel = echo.spy.channels[channelName]!;
      channel.setSubscribed(true);
      await Future<void>.delayed(Duration.zero);

      return channel;
    }

    test('startPolling does not arm the timer while realtime is live',
        () async {
      await startSubscribed();

      manager.startPolling();

      // The whole point of the feature: an authenticated socket is already open,
      // so a 30-second HTTP timer on top of it is pure waste.
      expect(manager.isPolling, isFalse);
    });

    test('startRealtime keeps polling until the channel is subscribed',
        () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');

      // `connected` and a subscribed channel are not the same thing: a private
      // channel still waits on its auth call, so stopping the poller before the
      // server confirms leaves a bell that nothing feeds.
      expect(manager.isRealtime, isTrue);
      expect(manager.isPolling, isTrue);
    });

    test('a channel already subscribed at start needs no poller', () async {
      final FakeNetworkDriver driver = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
      });
      await startRealtimeSubscribed('App.Models.User.u1');

      expect(manager.isPolling, isFalse);
      expect(
        driver.recorded
            .where((entry) => entry.$1.url.contains('notifications'))
            .length,
        1,
      );
    });

    test('startRealtime hands a running poller over once subscribed', () async {
      manager.startPolling();
      expect(manager.isPolling, isTrue);

      await startSubscribed();

      expect(manager.isPolling, isFalse);
    });

    test('connected alone keeps the poller running', () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');

      // `connected` is emitted before the private channel is authorised, so a
      // connected but unsubscribed socket delivers nothing.
      echo.spy.states.add(BroadcastConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      expect(manager.isPolling, isTrue);
    });

    test('a subscription stops the poller and refetches once', () async {
      final FakeNetworkDriver driver = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
      });
      await manager.startRealtime(channel: 'App.Models.User.u1');
      await Future<void>.delayed(Duration.zero);
      final int beforeSubscribed = driver.recorded.length;

      echo.spy.channels[channelName]!.setSubscribed(true);
      await Future<void>.delayed(Duration.zero);

      // Reverb has no replay, so what was published before the channel came up
      // is only recoverable by a read, and one is enough.
      expect(manager.isPolling, isFalse);
      expect(driver.recorded.length, beforeSubscribed + 1);
    });

    test('losing the subscription restarts the poller', () async {
      final _RecordingChannel channel = await startSubscribed();
      expect(manager.isPolling, isFalse);

      channel.setSubscribed(false);
      await Future<void>.delayed(Duration.zero);

      expect(manager.isPolling, isTrue);
      expect(manager.isRealtime, isTrue);
    });

    test('stopRealtime stops listening for the subscription', () async {
      final _RecordingChannel channel = await startSubscribed();

      manager.stopRealtime();
      channel.setSubscribed(false);
      await Future<void>.delayed(Duration.zero);

      expect(manager.isPolling, isFalse);
    });

    test('a lost connection falls back to polling', () async {
      await startSubscribed();
      expect(manager.isPolling, isFalse);

      echo.spy.states.add(BroadcastConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      // Realtime is still the intent, so the subscription stays; polling is the
      // stand-in while the socket is away. Without this, a socket that never
      // comes back means a bell that never updates again.
      expect(manager.isPolling, isTrue);
      expect(manager.isRealtime, isTrue);
    });

    test(
        'a socket that is down at start subscribes anyway and polls until it '
        'connects', () async {
      // The realtime server was down when the app launched. Giving up here
      // left realtime off for the whole session: the driver connected later,
      // but nothing was subscribed, so every note waited for the poller.
      final FakeNetworkDriver driver = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
      });
      echo.spy.connectError = StateError('Connection refused');

      final bool armed =
          await manager.startRealtime(channel: 'App.Models.User.u1');

      expect(armed, isTrue);
      expect(manager.isRealtime, isTrue);
      expect(echo.spy.channels.keys, contains('private-App.Models.User.u1'));
      expect(manager.isPolling, isTrue);

      final int beforeConnect = driver.recorded.length;
      echo.spy.states.add(BroadcastConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      expect(manager.isPolling, isTrue);

      echo.spy.channels['private-App.Models.User.u1']!.setSubscribed(true);
      await Future<void>.delayed(Duration.zero);

      expect(manager.isPolling, isFalse);
      expect(driver.recorded.length, greaterThan(beforeConnect));
    });

    test('resubscribing stops the fallback and closes the replay gap',
        () async {
      final FakeNetworkDriver driver = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
      });
      final _RecordingChannel channel = await startSubscribed();
      echo.spy.states.add(BroadcastConnectionState.reconnecting);
      channel.setSubscribed(false);
      await Future<void>.delayed(Duration.zero);
      echo.spy.states.add(BroadcastConnectionState.connected);
      await Future<void>.delayed(Duration.zero);
      final int beforeResubscribed = driver.recorded.length;

      channel.setSubscribed(true);
      await Future<void>.delayed(Duration.zero);

      // Reverb has no replay, so anything published while the socket was down is
      // gone from the stream and only a fetch can recover it. The fetch waits for
      // the subscription, not for `connected`, which precedes the channel auth.
      expect(manager.isPolling, isFalse);
      expect(driver.recorded.length, greaterThan(beforeResubscribed));
    });

    test('stopRealtime leaves the channel and lets polling resume', () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');

      manager.stopRealtime();

      expect(manager.isRealtime, isFalse);
      expect(echo.spy.left, contains('private-App.Models.User.u1'));

      manager.startPolling();
      expect(manager.isPolling, isTrue);
    });

    test('starting realtime twice on the same channel is idempotent', () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');
      await manager.startRealtime(channel: 'App.Models.User.u1');

      // The app re-syncs on every auth-state bump, so this runs often. A second
      // subscribe on magic's Reverb channel REPLACES the first listener rather
      // than adding one, and a second `connect()` opens a second socket.
      expect(echo.spy.left, isEmpty);
      expect(
        echo.spy.subscribedChannels
            .where((String c) => c == 'private-App.Models.User.u1')
            .length,
        1,
      );
    });

    test('a different channel moves the subscription', () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');

      await manager.startRealtime(channel: 'App.Models.User.u2');

      expect(echo.spy.left, contains('private-App.Models.User.u1'));
      expect(
        echo.spy.channels.keys,
        contains('private-App.Models.User.u2'),
      );
    });
  });
}
