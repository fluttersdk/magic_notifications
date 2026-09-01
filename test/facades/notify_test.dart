import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('Notify', () {
    test('manager returns NotificationManager singleton', () {
      final manager = Notify.manager;
      expect(manager, isA<NotificationManager>());
      // Verify it's the same singleton
      expect(identical(manager, NotificationManager()), isTrue);
    });

    test('send() delegates to manager', () async {
      final notification = TestNotification();
      final notifiable = TestNotifiable('1');

      // Reset and register mock channel
      Notify.forgetDrivers();
      final mockChannel = MockChannel('test');
      Notify.manager.registerChannel(mockChannel);

      await Notify.send(notifiable, notification);

      expect(mockChannel.sentCount, 1);
    });

    test('extend() registers a driver the manager then resolves', () {
      final driver = MockFacadePushDriver();
      Notify.extend('mock', () => driver);
      addTearDown(Notify.forgetDrivers);

      expect(identical(Notify.manager.pushDriver, driver), isTrue);
    });

    test('forgetDrivers() clears the registry through the facade', () {
      Notify.extend('mock', MockFacadePushDriver.new);

      Notify.forgetDrivers();

      expect(
        () => Notify.manager.pushDriver,
        throwsA(isA<NotificationException>()),
      );
    });
  });
}

// Minimal push driver, present only so the facade has something to register.
class MockFacadePushDriver extends PushDriver {
  @override
  String get name => 'mock';

  @override
  bool get isSupported => true;

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
  Future<bool> requestPermission() async => false;

  @override
  Future<void> optIn() async {}

  @override
  Future<void> optOut() async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> removeTag(String key) async {}

  @override
  Stream<PushNotificationEvent> get onNotificationReceived =>
      const Stream<PushNotificationEvent>.empty();

  @override
  Stream<PushNotificationEvent> get onNotificationClicked =>
      const Stream<PushNotificationEvent>.empty();

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      const Stream<PushPermissionState>.empty();

  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      const Stream<PushIdentityChange>.empty();
}

// Test notification
class TestNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['test'];
}

// Test notifiable entity
class TestNotifiable with Notifiable {
  final String _id;

  TestNotifiable(this._id);

  @override
  String get notifiableId => _id;
}

// Mock channel for testing
class MockChannel extends NotificationChannel {
  final String _name;
  int sentCount = 0;

  MockChannel(this._name);

  @override
  String get name => _name;

  @override
  bool get isAvailable => true;

  @override
  Future<void> send(Notifiable notifiable, Notification notification) async {
    sentCount++;
  }
}
