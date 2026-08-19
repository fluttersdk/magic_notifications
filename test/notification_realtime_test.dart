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

  setUpAll(() async {
    await initMagicForTests();
  });

  setUp(() {
    manager = NotificationManager();
    manager.forgetChannels();
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

      await manager.startRealtime(channel: 'App.Models.User.u1');

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
      await manager.startRealtime(channel: 'App.Models.User.u1');
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
      await manager.startRealtime(channel: 'App.Models.User.u1');
      final _RecordingChannel channel =
          echo.spy.channels['private-App.Models.User.u1']!;

      channel.emit('notification.created', row(id: 'n1', title: 'First'));
      channel.emit('notification.created', row(id: 'n1', title: 'Corrected'));

      final List<DatabaseNotification> current =
          await manager.notifications().first;
      expect(current, hasLength(1));
      expect(current.single.title, 'Corrected');
    });
  });

  group('NotificationManager polling under realtime', () {
    test('startPolling does not arm the timer while realtime is live',
        () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');

      manager.startPolling();

      // The whole point of the feature: an authenticated socket is already open,
      // so a 30-second HTTP timer on top of it is pure waste.
      expect(manager.isPolling, isFalse);
    });

    test('startRealtime stops a poller that was already running', () async {
      manager.startPolling();
      expect(manager.isPolling, isTrue);

      await manager.startRealtime(channel: 'App.Models.User.u1');

      expect(manager.isPolling, isFalse);
    });

    test('a lost connection falls back to polling', () async {
      await manager.startRealtime(channel: 'App.Models.User.u1');
      expect(manager.isPolling, isFalse);

      echo.spy.states.add(BroadcastConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);

      // Realtime is still the intent, so the subscription stays; polling is the
      // stand-in while the socket is away. Without this, a socket that never
      // comes back means a bell that never updates again.
      expect(manager.isPolling, isTrue);
      expect(manager.isRealtime, isTrue);
    });

    test('reconnecting stops the fallback and closes the replay gap', () async {
      final FakeNetworkDriver driver = Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{'data': <dynamic>[]}),
      });
      await manager.startRealtime(channel: 'App.Models.User.u1');
      echo.spy.states.add(BroadcastConnectionState.reconnecting);
      await Future<void>.delayed(Duration.zero);
      final int beforeReconnect = driver.recorded.length;

      echo.spy.states.add(BroadcastConnectionState.connected);
      await Future<void>.delayed(Duration.zero);

      // Reverb has no replay, so anything published while the socket was down is
      // gone from the stream and only a fetch can recover it.
      expect(manager.isPolling, isFalse);
      expect(driver.recorded.length, greaterThan(beforeReconnect));
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
