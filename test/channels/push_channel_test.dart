import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await initMagicForTests();
  });

  group('PushChannel', () {
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
  });
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
