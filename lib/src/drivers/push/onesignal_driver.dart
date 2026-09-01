import 'dart:async';
import 'dart:io' show Platform;

import 'package:onesignal_flutter/onesignal_flutter.dart';

import '../../exceptions/notification_exception.dart';
import '../../models/push_subscription.dart';
import 'push_driver.dart';

/// OneSignal push notification driver for mobile platforms (iOS/Android).
///
/// ## What the subject guard here can and cannot close
///
/// A push addressed to an identity this device is no longer reaches the SDK
/// anyway, because a subscription the server believes is current takes minutes
/// to stop being addressed. While the app is in the FOREGROUND the SDK asks
/// before it draws, so [handleForegroundWillDisplay] can answer "do not draw"
/// and keep somebody else's incident title off this lock screen.
///
/// Backgrounded or killed, that listener does not run at all: the OS draws the
/// notification with no client code involved. That half cannot be closed from
/// here. It needs the server to stop addressing a subscription it believes is
/// stale.
class OneSignalDriver extends PushDriver {
  final StreamController<PushNotificationEvent> _receivedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _clickedController =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushPermissionState> _permissionController =
      StreamController<PushPermissionState>.broadcast();
  final StreamController<PushIdentityChange> _identityController =
      StreamController<PushIdentityChange>.broadcast();

  bool _initialized = false;

  @override
  String get name => 'onesignal';

  /// Whether [initialize] completed against the OneSignal SDK.
  bool get isInitialized => _initialized;

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
  Future<PushPermissionState> permissionState() async {
    if (!_initialized) return PushPermissionState.notDetermined;

    final native = await OneSignal.Notifications.permissionNative();

    return switch (native) {
      OSNotificationPermission.authorized => PushPermissionState.authorized,
      // Provisional and ephemeral both deliver without a prompt, so they are
      // the same answer to "may this app notify", which is what callers ask.
      OSNotificationPermission.provisional ||
      OSNotificationPermission.ephemeral =>
        PushPermissionState.provisional,
      OSNotificationPermission.notDetermined =>
        PushPermissionState.notDetermined,
      // Only iOS reports a real tri-state; everywhere else permissionNative
      // collapses onto denied, so ask the SDK whether a prompt would still
      // show. It does only when the device has never been asked.
      OSNotificationPermission.denied =>
        await OneSignal.Notifications.canRequest()
            ? PushPermissionState.notDetermined
            : PushPermissionState.denied,
    };
  }

  @override
  bool get isOptedIn {
    if (!_initialized) return false;
    return OneSignal.User.pushSubscription.optedIn ?? false;
  }

  @override
  Future<String?> currentExternalId() async {
    if (!_initialized) return null;
    return OneSignal.User.getExternalId();
  }

  @override
  Future<String?> currentSubscriptionId() async {
    if (!_initialized) return null;
    return OneSignal.User.pushSubscription.id;
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
      handleForegroundWillDisplay(
        event.notification.additionalData ?? {},
        event.preventDefault,
      );
    });

    OneSignal.Notifications.addClickListener((event) {
      _clickedController.add(
        PushNotificationEvent(event.notification.additionalData ?? {}),
      );
    });

    // The observer carries a bare bool, and the tri-state needs the native
    // read, so re-read instead of collapsing the bool onto denied.
    OneSignal.Notifications.addPermissionObserver((permission) {
      if (_permissionController.isClosed) return;
      unawaited(
        permissionState()
            .then(_permissionController.add)
            .catchError(_permissionController.addError),
      );
    });

    OneSignal.User.addObserver((state) {
      if (_identityController.isClosed) return;
      _identityController.add(
        PushIdentityChange(externalId: state.current.externalId),
      );
    });

    OneSignal.User.pushSubscription.addObserver((state) {
      if (_identityController.isClosed) return;
      _identityController.add(
        PushIdentityChange(
          subscriptionId: state.current.id,
          optedIn: state.current.optedIn,
        ),
      );
    });

    _initialized = true;
  }

  /// Decides what happens to a push that arrived while the app is foregrounded.
  ///
  /// [preventDisplay] is the SDK's own `preventDefault`, taken as a parameter
  /// rather than reached for through the event, because it is a
  /// platform-channel call: passing it in is what lets the decision be
  /// exercised without a device.
  ///
  /// A payload the subject guard rejects is suppressed on BOTH halves, the OS
  /// draw and the in-app republish, because a notification drawn for somebody
  /// who signed out is the leak, not the republish. See the class docblock for
  /// the half this cannot close.
  void handleForegroundWillDisplay(
    Map<String, dynamic> data,
    void Function() preventDisplay,
  ) {
    if (!mayDisplay(data)) {
      preventDisplay();

      return;
    }

    if (_receivedController.isClosed) return;

    _receivedController.add(PushNotificationEvent(data));
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

  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      _identityController.stream;

  /// Disposes stream controllers.
  void dispose() {
    _receivedController.close();
    _clickedController.close();
    _permissionController.close();
    _identityController.close();
  }
}
