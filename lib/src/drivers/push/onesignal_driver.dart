import 'dart:async';
import 'dart:io' show Platform;

import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../exceptions/notification_exception.dart';
import '../../models/push_subscription.dart';
import 'push_driver.dart';

/// OneSignal push notification driver for mobile platforms (iOS/Android).
class OneSignalDriver extends PushDriver {
  final StreamController<PushNotificationEvent> _receivedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _clickedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushPermissionState> _permissionController =
      StreamController<PushPermissionState>.broadcast();

  bool _initialized = false;

  @override
  String get name => 'onesignal';

  @override
  bool get isSupported {
    // OneSignal SDK primarily supports iOS and Android
    try {
      return Platform.isIOS || Platform.isAndroid;
    } catch (e) {
      // Platform not available (e.g., in tests or web)
      return false;
    }
  }

  @override
  PushPermissionState get permissionState {
    if (!_initialized) return PushPermissionState.notDetermined;

    final permission = OneSignal.Notifications.permission;
    if (permission) {
      return PushPermissionState.authorized;
    }
    return PushPermissionState.denied;
  }

  @override
  bool get isOptedIn {
    if (!_initialized) return false;
    return OneSignal.User.pushSubscription.optedIn ?? false;
  }

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    if (!isSupported) {
      throw NotificationException(
        'OneSignal is not supported on this platform',
        code: 'PLATFORM_NOT_SUPPORTED',
      );
    }

    final appId = config['app_id'] as String?;
    if (appId == null || appId.isEmpty) {
      throw NotificationException(
        'OneSignal app_id is required in configuration',
        code: 'MISSING_APP_ID',
      );
    }

    // Initialize OneSignal
    OneSignal.initialize(appId);

    // Setup notification handlers
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      _receivedController.add(
        PushNotificationEvent(event.notification.additionalData ?? {}),
      );
    });

    OneSignal.Notifications.addClickListener((event) {
      _clickedController.add(
        PushNotificationEvent(event.notification.additionalData ?? {}),
      );
    });

    OneSignal.Notifications.addPermissionObserver((permission) {
      _permissionController.add(
        permission
            ? PushPermissionState.authorized
            : PushPermissionState.denied,
      );
    });

    _initialized = true;
  }

  @override
  Future<void> login(String externalId) async {
    if (!_initialized) {
      throw NotificationException(
        'OneSignal must be initialized before login',
        code: 'NOT_INITIALIZED',
      );
    }
    await OneSignal.login(externalId);
  }

  @override
  Future<void> logout() async {
    if (!_initialized) return;
    await OneSignal.logout();
  }

  @override
  Future<bool> requestPermission() async {
    if (!_initialized) {
      throw NotificationException(
        'OneSignal must be initialized before requesting permission',
        code: 'NOT_INITIALIZED',
      );
    }
    return await OneSignal.Notifications.requestPermission(true);
  }

  @override
  Future<void> optIn() async {
    if (!_initialized) return;
    await OneSignal.User.pushSubscription.optIn();
  }

  @override
  Future<void> optOut() async {
    if (!_initialized) return;
    await OneSignal.User.pushSubscription.optOut();
  }

  @override
  Future<void> setTags(Map<String, String> tags) async {
    if (!_initialized) return;
    await OneSignal.User.addTags(tags);
  }

  @override
  Future<void> removeTag(String key) async {
    if (!_initialized) return;
    await OneSignal.User.removeTag(key);
  }

  @override
  Stream<PushNotificationEvent> get onNotificationReceived =>
      _receivedController.stream;

  @override
  Stream<PushNotificationEvent> get onNotificationClicked =>
      _clickedController.stream;

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      _permissionController.stream;

  /// Disposes stream controllers.
  void dispose() {
    _receivedController.close();
    _clickedController.close();
    _permissionController.close();
  }
}
