import 'package:flutter_test/flutter_test.dart';
import 'package:fluttersdk_magic_notifications/fluttersdk_magic_notifications.dart';

void main() {
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

    // Note: HTTP post testing would require mocking the HTTP facade
    // which is complex in this testing setup. Integration tests will
    // verify the full flow with real backend.
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
  PushPermissionState get permissionState => PushPermissionState.notDetermined;
  @override
  bool get isOptedIn => false;
  @override
  Future<void> initialize(Map<String, dynamic> config) async {}
  @override
  Future<void> login(String externalId) async {}
  @override
  Future<void> logout() async {}
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
}

class TestNotifiable with Notifiable {
  final String _id;
  TestNotifiable(this._id);
  @override
  String get notifiableId => _id;
}

class TestNotification extends Notification {
  final PushMessage? pushMessage;
  TestNotification({this.pushMessage});

  @override
  List<String> via(Notifiable notifiable) => ['push'];

  @override
  PushMessage? toPush(Notifiable notifiable) => pushMessage;
}
