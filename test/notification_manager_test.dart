import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import 'test_helper.dart';

void main() {
  late NotificationManager manager;

  setUpAll(() async {
    await initMagicForTests();
  });

  setUp(() {
    manager = NotificationManager();
    manager.forgetDrivers(); // Reset for tests
  });

  group('NotificationManager', () {
    test('is singleton', () {
      final m1 = NotificationManager();
      final m2 = NotificationManager();
      expect(identical(m1, m2), isTrue);
    });

    test('registerChannel() adds channel', () {
      final channel = MockChannel('test');
      manager.registerChannel(channel);
      expect(manager.hasChannel('test'), isTrue);
    });

    test('send() dispatches to correct channels', () async {
      final channel = MockChannel('database');
      manager.registerChannel(channel);

      final notification = TestNotification(via: ['database']);
      final notifiable = TestNotifiable('1');

      await manager.send(notifiable, notification);

      expect(channel.sentCount, 1);
    });

    test('send() skips unavailable channels', () async {
      final channel = MockChannel('database', available: false);
      manager.registerChannel(channel);

      final notification = TestNotification(via: ['database']);
      await manager.send(TestNotifiable('1'), notification);

      expect(channel.sentCount, 0);
    });

    test(
        'send() still reaches the later channels when an earlier one throws, '
        'whatever order via() names them in', () async {
      final push = MockChannel(
        'push',
        throws: NotificationException('backend said no', code: 'HTTP_500'),
      );
      final database = MockChannel('database');

      manager.registerChannel(push);
      manager.registerChannel(database);

      // Push FIRST, which is the order that used to decide whether the in-app
      // row was written at all.
      await expectLater(
        manager.send(
            TestNotifiable('1'),
            TestNotification(
              via: ['push', 'database'],
            )),
        throwsA(isA<NotificationException>()),
      );

      expect(database.sentCount, 1);
    });

    test('send() rethrows the first failure with its own type and code',
        () async {
      manager.registerChannel(MockChannel(
        'push',
        throws: NotificationException('refused', code: 'PUSH_REFUSED'),
      ));
      manager.registerChannel(MockChannel(
        'database',
        throws: StateError('a second, different failure'),
      ));

      await expectLater(
        manager.send(
            TestNotifiable('1'),
            TestNotification(
              via: ['push', 'database'],
            )),
        throwsA(
          isA<NotificationException>()
              .having((e) => e.code, 'code', 'PUSH_REFUSED'),
        ),
      );
    });

    test('send() logs warning for unknown channels', () async {
      final notification = TestNotification(via: ['unknown']);
      // Should not throw, just log
      await expectLater(
        manager.send(TestNotifiable('1'), notification),
        completes,
      );
    });
  });

  group('NotificationManager reads that overlap', () {
    late _GatedNetworkDriver network;
    late _RecordingBroadcastManager echo;

    setUp(() {
      network = _GatedNetworkDriver();
      Magic.app.setInstance('network', network);
      echo = _RecordingBroadcastManager();
      Magic.app.setInstance('broadcasting', echo);
      Config.set('broadcasting.default', 'reverb');
    });

    tearDown(() {
      manager.stopRealtime();
      manager.stopPolling();
      Config.forget('broadcasting.default');
      echo.spy.states.close();
      Http.unfake();
    });

    /// Starts realtime against a gated read, answering the one fetch
    /// [NotificationManager.startRealtime] does on its way in.
    Future<_RecordingChannel> startRealtime() async {
      final Future<bool> starting = manager.startRealtime(
        channel: 'App.Models.User.u1',
      );
      await pumpEventQueue();
      network.answer(<Map<String, dynamic>>[]);
      expect(await starting, isTrue);

      return echo.spy.channels['private-App.Models.User.u1']!;
    }

    test('a frame between two overlapping reads survives the second', () async {
      final _RecordingChannel channel = await startRealtime();

      // Two reads in flight at once is the ordinary case, not a corner: a push
      // starts one without awaiting it and so does the reconnect watcher, and
      // two pushes in quick succession is what an incident looks like.
      final Future<void> first = manager.fetchNotifications();
      final Future<void> second = manager.fetchNotifications();
      await pumpEventQueue();

      network.answer(<Map<String, dynamic>>[_row(id: 'old')]);
      await first;

      // The window a boolean in-flight flag opens: the first read has already
      // lowered it and emptied the shared buffer, so this frame is held nowhere
      // but the cached list.
      channel.emit(
        'notification.created',
        _row(id: 'fresh', title: 'Checkout is down'),
      );

      // The second read's snapshot was taken by the server BEFORE that frame
      // existed, and assigning it over the top is what loses the row. In
      // realtime mode nothing fetches again until a reconnect, so the bell stays
      // missing an incident until then.
      network.answer(<Map<String, dynamic>>[_row(id: 'old')]);
      await second;

      final List<DatabaseNotification> current =
          await manager.notifications().first;
      expect(
        current.map((DatabaseNotification n) => n.id),
        <String>['fresh', 'old'],
      );
      expect(current.first.title, 'Checkout is down');
    });

    test('a read already in flight cannot put the signed-out rows back',
        () async {
      final Future<void> reading = manager.fetchNotifications();
      await pumpEventQueue();

      await manager.logoutPush();

      // The read was issued for the person who just signed out and answers with
      // their rows. Assigning them afterwards undoes the clear and puts their
      // incident titles back on the next person's bell.
      network.answer(<Map<String, dynamic>>[_row(id: 'theirs')]);
      await reading;

      expect(await manager.notifications().first, isEmpty);
    });

    test('a read in flight at forgetDrivers cannot land after it', () async {
      final Future<void> reading = manager.fetchNotifications();
      await pumpEventQueue();

      // The test-isolation seam runs between two tests with a read still in
      // the air, which is the one thing it exists to stop: the answer belongs
      // to whatever the previous test was doing, and it arrives inside the
      // next one.
      manager.forgetDrivers();

      network.answer(<Map<String, dynamic>>[_row(id: 'theirs')]);
      await reading;

      expect(await manager.notifications().first, isEmpty);

      // And the reset left the read path usable: a depth dropped under an
      // in-flight read must not go negative behind it.
      final Future<void> next = manager.fetchNotifications();
      await pumpEventQueue();
      network.answer(<Map<String, dynamic>>[_row(id: 'mine')]);
      await next;

      expect(
        (await manager.notifications().first)
            .map((DatabaseNotification n) => n.id),
        <String>['mine'],
      );
    });

    test('a frame for a session that ended cannot reach the bell', () async {
      final _RecordingChannel channel = await startRealtime();

      await manager.logoutPush();

      // Leaving a channel is not instantaneous, so a frame published just
      // before the sign-out still arrives on this socket. Applied, it prepends
      // the previous person's incident title back onto the next person's bell
      // and publishes it, which is the leak the fetch path already refuses.
      channel.emit(
        'notification.created',
        _row(id: 'theirs', title: 'Checkout is down'),
      );
      await pumpEventQueue();

      expect(await manager.notifications().first, isEmpty);
    });

    test('re-subscribing after a sign-out lets frames through again', () async {
      final _RecordingChannel channel = await startRealtime();
      await manager.logoutPush();

      // The companion guard for the test above: a repeat call for the same
      // channel is a no-op, so a session marker it does not adopt would leave
      // the bell permanently deaf on a channel it believes it is subscribed
      // to, which is a worse failure than the one being fixed.
      expect(
        await manager.startRealtime(channel: 'App.Models.User.u1'),
        isTrue,
      );

      channel.emit('notification.created', _row(id: 'mine'));
      await pumpEventQueue();

      expect(
        (await manager.notifications().first)
            .map((DatabaseNotification n) => n.id),
        <String>['mine'],
      );
    });
  });

  group('NotificationManager on sign-out', () {
    setUp(() {
      Http.fake(<String, MagicResponse>{
        'notifications': Http.response(<String, dynamic>{
          'data': <dynamic>[_row(id: 'theirs', title: 'API Health is down')],
        }),
      });
    });

    tearDown(Http.unfake);

    test('signing out drops the previous person rows from the bell', () async {
      await manager.fetchNotifications();
      expect(await manager.notifications().first, isNotEmpty);

      final List<List<DatabaseNotification>> seen =
          <List<DatabaseNotification>>[];
      final StreamSubscription<List<DatabaseNotification>> subscription =
          manager.notifications().listen(seen.add);
      addTearDown(subscription.cancel);

      await manager.logoutPush();
      await pumpEventQueue();

      // On a shared device the next person's bell shows the previous person's
      // incident titles and monitor names until the first fetch lands, and a
      // listener that subscribes in that window is handed the cached list
      // immediately.
      expect(await manager.notifications().first, isEmpty);
      expect(seen.last, isEmpty);
    });
  });

  group('NotificationManager paginated reads', () {
    tearDown(Http.unfake);

    test('answers the page the backend published', () async {
      Http.fake((MagicRequest request) {
        return MagicResponse(
          data: <String, dynamic>{
            'data': <dynamic>[_row(id: 'n1')],
            'meta': <String, dynamic>{
              'current_page': 2,
              'last_page': 4,
              'per_page': 15,
              'total': 50,
            },
          },
          statusCode: 200,
        );
      });

      final PaginatedNotifications page =
          await manager.fetchPaginatedNotifications(page: 2);

      expect(page.data, hasLength(1));
      expect(page.currentPage, 2);
      expect(page.lastPage, 4);
    });

    test('throws rather than answering an empty page on a failed response',
        () async {
      Http.fake((MagicRequest request) {
        return MagicResponse(data: <String, dynamic>{}, statusCode: 500);
      });

      // An empty page is indistinguishable from an empty inbox, and on this
      // product that difference is an on-call engineer reading "no alerts"
      // off a screen whose backend is down.
      await expectLater(
        manager.fetchPaginatedNotifications(),
        throwsA(isA<NotificationException>()),
      );
    });

    test('throws when the transport itself fails', () async {
      Http.fake((MagicRequest request) {
        throw StateError('connection closed');
      });

      await expectLater(
        manager.fetchPaginatedNotifications(),
        throwsA(isA<NotificationException>()),
      );
    });

    test('throws when the payload cannot be decoded', () async {
      Http.fake((MagicRequest request) {
        return MagicResponse(
          data: <String, dynamic>{
            'data': <dynamic>['not a notification row'],
          },
          statusCode: 200,
        );
      });

      // A 200 carrying a body this package cannot read is a failed read too:
      // answering it as an empty page would put the same false "nothing here"
      // on the screen the failed response would have.
      await expectLater(
        manager.fetchPaginatedNotifications(),
        throwsA(isA<NotificationException>()),
      );
    });
  });

  group('the polling interval', () {
    tearDown(() {
      manager.stopPolling();
      Config.forget('notifications.database.polling_interval');
      Http.unfake();
    });

    test('comes from config, not from the poller default', () async {
      // This key was validated by the CLI, reported by `notifications:doctor`
      // and shipped in every install stub, and the runtime never read it: the
      // poller was constructed with no argument so its own 30-second default
      // always won. A consumer who set 10 got 30, with nothing to say why.
      int reads = 0;

      Http.fake((request) {
        reads++;

        return MagicResponse(
          data: <String, dynamic>{'data': <Map<String, dynamic>>[]},
          statusCode: 200,
        );
      });

      Config.set('notifications.database.polling_interval', 1);

      manager.startPolling();

      // The immediate read on start, plus roughly two one-second ticks. On the
      // pre-fix code the timer is 30 seconds away, so only the immediate read
      // has happened by now.
      await Future<void>.delayed(const Duration(milliseconds: 2400));

      expect(reads, greaterThanOrEqualTo(3));
    });

    test('falls back to 30 seconds when the configured value cannot fire',
        () async {
      // Zero and negatives are refused rather than passed through, because
      // `Timer.periodic` accepts them and then fires on every event-loop turn:
      // a mistyped config value would take the app's network down instead of
      // polling a little too often.
      int reads = 0;

      Http.fake((request) {
        reads++;

        return MagicResponse(
          data: <String, dynamic>{'data': <Map<String, dynamic>>[]},
          statusCode: 200,
        );
      });

      Config.set('notifications.database.polling_interval', 0);

      manager.startPolling();
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(
        reads,
        1,
        reason: 'only the immediate read on start should have happened',
      );
    });
  });
}

/// One notification row as the API and the socket both shape it.
Map<String, dynamic> _row({
  String id = 'n1',
  String title = 'Incident opened',
}) =>
    <String, dynamic>{
      'id': id,
      'type': 'App\\Notifications\\IncidentOpened',
      'data': <String, dynamic>{
        'title': title,
        'body': 'API Health is down',
        'action_url': '/incidents/$id',
      },
      'created_at': '2026-08-19T09:30:00.000Z',
      'read_at': null,
    };

/// A network driver whose reads finish when the TEST says so.
///
/// The shipped [FakeNetworkDriver] answers within a microtask, which cannot
/// express two reads in flight at once with a frame arriving between the first
/// one completing and the second one assigning. That interleaving is the whole
/// defect, so the read has to be holdable.
class _GatedNetworkDriver extends FakeNetworkDriver {
  final List<Completer<MagicResponse>> _pending = <Completer<MagicResponse>>[];

  @override
  Future<MagicResponse> get(
    String url, {
    Map<String, dynamic>? query,
    Map<String, String>? headers,
  }) {
    final Completer<MagicResponse> completer = Completer<MagicResponse>();
    _pending.add(completer);

    return completer.future;
  }

  /// Answers the oldest read still waiting with [rows].
  void answer(List<Map<String, dynamic>> rows) {
    expect(_pending, isNotEmpty, reason: 'No read was waiting for an answer.');
    _pending.removeAt(0).complete(
          MagicResponse(
            data: <String, dynamic>{'data': rows},
            statusCode: 200,
          ),
        );
  }
}

/// A channel that keeps its handlers so a test can deliver a frame.
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

  /// Delivers [data] to the handler registered for [event].
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

/// A broadcast driver whose private channels are inspectable.
class _RecordingBroadcastDriver extends FakeBroadcastDriver {
  final Map<String, _RecordingChannel> channels = <String, _RecordingChannel>{};
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
    channels.remove(name);
    super.leave(name);
  }
}

/// Hands out the recording driver in place of the parent's private one.
class _RecordingBroadcastManager extends FakeBroadcastManager {
  final _RecordingBroadcastDriver spy = _RecordingBroadcastDriver();

  @override
  BroadcastDriver connection([String? name]) => spy;
}

// Mock channel for testing
class MockChannel extends NotificationChannel {
  final String _name;
  final bool _available;
  final Object? _throws;
  int sentCount = 0;

  MockChannel(this._name, {bool available = true, Object? throws})
      : _available = available,
        _throws = throws;

  @override
  String get name => _name;

  @override
  bool get isAvailable => _available;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    sentCount++;

    if (_throws != null) throw _throws;
  }
}

// Test notification
class TestNotification extends Notification {
  final List<String> channels;

  TestNotification({required List<String> via}) : channels = via;

  @override
  List<String> via(Notifiable notifiable) => channels;
}

// Test notifiable entity
class TestNotifiable with Notifiable {
  final String _id;

  TestNotifiable(this._id);

  @override
  String get notifiableId => _id;
}
