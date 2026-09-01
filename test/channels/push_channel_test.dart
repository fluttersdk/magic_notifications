import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import '../test_helper.dart';

/// The config key gating the client-triggered self-addressed push send.
const String _switchKey = 'notifications.push.self_test_enabled';

void main() {
  setUpAll(() async {
    await initMagicForTests();
  });

  group('PushChannel', () {
    // Every test below describes the channel of a deployment that has SWITCHED
    // THE SURFACE ON. The switch ships off, so without this line each of them
    // would assert against an inert channel and pass for the wrong reason: the
    // preference test would stop testing preferences, and the recipient test
    // would stop testing recipients. The off state has its own group.
    setUp(() {
      Config.set(_switchKey, true);
    });

    test('name is "push"', () {
      final channel = PushChannel(MockPushDriver());
      expect(channel.name, 'push');
    });

    test('isAvailable reflects driver.isSupported', () {
      final driver = MockPushDriver(supported: false);
      final channel = PushChannel(driver);
      expect(channel.isAvailable, isFalse);
    });

    test('isAvailable is true when driver is supported', () {
      final driver = MockPushDriver(supported: true);
      final channel = PushChannel(driver);
      expect(channel.isAvailable, isTrue);
    });

    test('send() skips if toPush() returns null', () async {
      final channel = PushChannel(MockPushDriver());

      final notification = TestNotification(pushMessage: null);
      // Should complete without errors
      await expectLater(
        channel.send(TestNotifiable('1'), notification),
        completes,
      );
    });

    test('send() carries a .url() destination into the payload', () async {
      final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
        'notifications/push-test': Http.response(
          <String, dynamic>{'delivered': true},
          202,
        ),
      });

      final channel = PushChannel(MockPushDriver());
      final message = PushMessage()
        ..heading('Monitor Down')
        ..content('api.example.com is not responding')
        ..url('https://uptizm.com/incidents/42')
        ..data(<String, dynamic>{'incident_id': '42'});

      await channel.send(
        TestNotifiable('1'),
        TestNotification(pushMessage: message),
      );

      final MagicRequest request = network.recorded.single.$1;
      final Map<String, dynamic> body = request.data as Map<String, dynamic>;
      final Map<String, dynamic> payload = body['data'] as Map<String, dynamic>;

      // The endpoint validates `title`, `body` and `data` and nothing else, so
      // a fourth top-level key never reaches the device. `url` is the first key
      // the deeplink handler reads out of a payload, so a test push whose whole
      // job is proving tap-through has to carry it there.
      expect(payload['url'], 'https://uptizm.com/incidents/42');
      expect(payload['incident_id'], '42');
      expect(body.keys, isNot(contains('url')));
    });

    test('send() POSTs to notifications/push-test with no recipient field',
        () async {
      final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
        'notifications/push-test': Http.response(
          <String, dynamic>{'delivered': true},
          202,
        ),
      });

      final channel = PushChannel(MockPushDriver());
      final message = PushMessage()
        ..heading('Monitor Down')
        ..content('api.example.com is not responding');
      final notification = TestNotification(pushMessage: message);

      await channel.send(TestNotifiable('1'), notification);

      network.assertSentCount(1);
      final MagicRequest request = network.recorded.single.$1;
      expect(request.method, 'POST');

      final Map<String, dynamic> body = request.data as Map<String, dynamic>;
      // The recipient is derived server-side from the session; the request
      // must not carry any recipient-shaped key, not even a null one.
      const recipientKeys = <String>[
        'user_id',
        'external_id',
        'to',
        'recipient'
      ];
      for (final key in recipientKeys) {
        expect(
          body.keys,
          isNot(contains(key)),
          reason: 'body must not carry recipient key "$key"',
        );
      }
      expect(body['title'], 'Monitor Down');
      expect(body['body'], 'api.example.com is not responding');
    });

    test('send() forwards data as the additionalData payload', () async {
      final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
        'notifications/push-test': Http.response(
          <String, dynamic>{'delivered': true},
          202,
        ),
      });

      final channel = PushChannel(MockPushDriver());
      final message = PushMessage()
        ..heading('Monitor Down')
        ..content('api.example.com is not responding')
        ..data({'monitor_id': '123'});
      final notification = TestNotification(pushMessage: message);

      await channel.send(TestNotifiable('1'), notification);

      final MagicRequest request = network.recorded.single.$1;
      final Map<String, dynamic> body = request.data as Map<String, dynamic>;
      expect(body['data'], <String, dynamic>{'monitor_id': '123'});
    });

    test('send() surfaces a non-2xx response rather than swallowing it',
        () async {
      Http.fake(<String, MagicResponse>{
        'notifications/push-test': Http.response(
          <String, dynamic>{
            'message':
                'Push notifications are not provisioned for this application.',
          },
          409,
        ),
      });

      final channel = PushChannel(MockPushDriver());
      final message = PushMessage()
        ..heading('Monitor Down')
        ..content('api.example.com is not responding');
      final notification = TestNotification(pushMessage: message);

      await expectLater(
        channel.send(TestNotifiable('1'), notification),
        throwsA(isA<NotificationException>()),
      );
    });

    // The endpoint derives the recipient from the authenticated session, so
    // this channel can only ever page the CALLER. A notifiable naming somebody
    // else used to page the caller instead, silently.
    group('the recipient is the authenticated user, or nobody', () {
      tearDown(Auth.unfake);

      test('send() refuses a notifiable that is not the authenticated user',
          () async {
        final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
          'notifications/push-test': Http.response(
            <String, dynamic>{'delivered': true},
            202,
          ),
        });
        Auth.fake(user: _makeUser(1));

        final channel = PushChannel(MockPushDriver());
        final message = PushMessage()
          ..heading('Monitor Down')
          ..content('api.example.com is not responding');
        final notification = TestNotification(pushMessage: message);

        await expectLater(
          channel.send(TestNotifiable('2'), notification),
          throwsA(isA<NotificationException>()),
        );
        network.assertNothingSent();
      });

      test('send() sends for the authenticated user', () async {
        final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
          'notifications/push-test': Http.response(
            <String, dynamic>{'delivered': true},
            202,
          ),
        });
        Auth.fake(user: _makeUser(1));

        final channel = PushChannel(MockPushDriver());
        final message = PushMessage()
          ..heading('Monitor Down')
          ..content('api.example.com is not responding');
        final notification = TestNotification(pushMessage: message);

        await channel.send(TestNotifiable('1'), notification);

        network.assertSentCount(1);
      });

      test('send() sends when nobody is authenticated', () async {
        // Nothing here can tell whose device this is, so the check has no
        // answer to give and the endpoint answers 401 instead.
        final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
          'notifications/push-test': Http.response(
            <String, dynamic>{'delivered': true},
            202,
          ),
        });
        Auth.fake();

        final channel = PushChannel(MockPushDriver());
        final message = PushMessage()
          ..heading('Monitor Down')
          ..content('api.example.com is not responding');
        final notification = TestNotification(pushMessage: message);

        await channel.send(TestNotifiable('7'), notification);

        network.assertSentCount(1);
      });
    });

    test('send() respects the preference matrix and makes no request',
        () async {
      final FakeNetworkDriver network = Http.fake();

      final channel = PushChannel(MockPushDriver());
      final message = PushMessage()
        ..heading('Monitor Down')
        ..content('api.example.com is not responding');
      final notification = TestNotification(pushMessage: message);
      final notifiable = TestNotifiable(
        '1',
        preference: const NotificationPreference(pushEnabled: false),
      );

      await channel.send(notifiable, notification);

      network.assertNothingSent();
    });

    // The endpoint behind this channel makes the platform emit a push on a
    // client's say-so, and nothing in this release asks it to. It therefore
    // ships switched off, on both halves: a client that refuses locally still
    // leaves the endpoint reachable by anything holding a token, and a server
    // that refuses leaves the client posting requests that always fail.
    //
    // Off is a SKIP rather than a throw. An operator who has not switched a
    // feature on has not made an error, which is the same shape as a disabled
    // preference; naming a foreign recipient is an error, which is why that one
    // throws. What must not happen is the third shape: reporting the channel
    // available and then doing nothing.
    group('the self-addressed send is switched off', () {
      test('isAvailable is false while the switch is absent', () {
        Config.forget(_switchKey);

        final channel = PushChannel(MockPushDriver(supported: true));

        expect(channel.isAvailable, isFalse);
      });

      test('isAvailable is false while the switch is explicitly false', () {
        Config.set(_switchKey, false);

        final channel = PushChannel(MockPushDriver(supported: true));

        expect(channel.isAvailable, isFalse);
      });

      test('send() issues no request while the switch is absent', () async {
        Config.forget(_switchKey);
        final FakeNetworkDriver network = Http.fake();

        final channel = PushChannel(MockPushDriver());

        await expectLater(
          channel.send(TestNotifiable('1'), _pushNotification()),
          completes,
        );
        network.assertNothingSent();
      });

      test('send() issues no request while the switch is explicitly false',
          () async {
        Config.set(_switchKey, false);
        final FakeNetworkDriver network = Http.fake();

        final channel = PushChannel(MockPushDriver());

        await channel.send(TestNotifiable('1'), _pushNotification());

        network.assertNothingSent();
      });

      // A value this channel cannot read as a boolean is a configuration
      // mistake, and the safe reading of a mistake on a switch that guards an
      // outbound send is OFF.
      test('a non-boolean switch value reads as off', () async {
        Config.set(_switchKey, 'true');
        final FakeNetworkDriver network = Http.fake();

        final channel = PushChannel(MockPushDriver(supported: true));

        expect(channel.isAvailable, isFalse);

        await channel.send(TestNotifiable('1'), _pushNotification());

        network.assertNothingSent();
      });

      // The switch is read FIRST, ahead of the recipient guard. A channel that
      // is switched off cannot page anybody, so there is no mis-page to refuse
      // and nothing to raise about.
      test('send() skips a foreign notifiable instead of refusing it',
          () async {
        Config.set(_switchKey, false);
        final FakeNetworkDriver network = Http.fake();
        Auth.fake(user: _makeUser(1));
        addTearDown(Auth.unfake);

        final channel = PushChannel(MockPushDriver());

        await expectLater(
          channel.send(TestNotifiable('2'), _pushNotification()),
          completes,
        );
        network.assertNothingSent();
      });
    });
  });
}

/// A notification carrying a push message, the shape every send test needs.
TestNotification _pushNotification() {
  return TestNotification(
    pushMessage: PushMessage()
      ..heading('Monitor Down')
      ..content('api.example.com is not responding'),
  );
}

/// A user model the fake auth guard can hold.
class _User extends Model with Authenticatable {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';

  @override
  List<String> get fillable => ['id'];
}

/// Builds a persisted [_User] carrying [id].
_User _makeUser(int id) {
  final user = _User();
  user.fill({'id': id});
  user.exists = true;

  return user;
}

class MockPushDriver extends PushDriver {
  final bool supported;
  MockPushDriver({this.supported = true});

  @override
  String get name => 'mock';
  @override
  bool get isSupported => supported;
  @override
  Future<PushPermissionState> permissionState() async =>
      PushPermissionState.notDetermined;
  @override
  bool get isOptedIn => false;
  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> login(String externalId) async {}
  @override
  Future<void> logout() async {}
  @override
  Future<String?> currentExternalId() async => null;
  @override
  Future<String?> currentSubscriptionId() async => null;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> optIn() async {}
  @override
  Future<void> optOut() async {}
  @override
  Future<void> setTags(Map<String, String> tags) async {}
  @override
  Future<void> removeTag(String key) async {}
  @override
  Stream<PushNotificationEvent> get onNotificationReceived => Stream.empty();
  @override
  Stream<PushNotificationEvent> get onNotificationClicked => Stream.empty();
  @override
  Stream<PushPermissionState> get onPermissionChanged => Stream.empty();
  @override
  Stream<PushIdentityChange> get onIdentityChanged => Stream.empty();
}

class TestNotifiable with Notifiable {
  final String _id;
  final NotificationPreference? _preference;
  TestNotifiable(this._id, {NotificationPreference? preference})
      : _preference = preference;

  @override
  String get notifiableId => _id;

  @override
  NotificationPreference? get notificationPreference => _preference;
}

class TestNotification extends Notification {
  final PushMessage? pushMessage;
  TestNotification({this.pushMessage});

  @override
  List<String> via(Notifiable notifiable) => ['push'];

  @override
  PushMessage? toPush(Notifiable notifiable) => pushMessage;
}
