import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../exceptions/notification_exception.dart';
import '../../models/push_subscription.dart';
import 'onesignal_js_interop.dart';
import 'push_driver.dart';

/// OneSignal push notification driver for Web platform.
///
/// Uses OneSignal Web SDK (v16) via JavaScript interop.
/// For mobile platforms, use [OneSignalDriver] instead.
///
/// ## Setup
///
/// Add the OneSignal SDK script to your `web/index.html`:
///
/// ```html
/// <script src="https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js" defer></script>
/// <script>
///   window.OneSignalDeferred = window.OneSignalDeferred || [];
///   OneSignalDeferred.push(async function(OneSignal) {
///     await OneSignal.init({
///       appId: "YOUR_APP_ID",
///       safari_web_id: "YOUR_SAFARI_WEB_ID", // Optional
///       notifyButton: { enable: true },      // Optional
///     });
///   });
/// </script>
/// ```
///
/// Or use [getWebInitScript] to generate this code programmatically.
class OneSignalWebDriver extends PushDriver {
  static const String _sdkUrl =
      'https://cdn.onesignal.com/sdks/web/v16/OneSignalSDK.page.js';

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

  @override
  bool get isSupported => kIsWeb;

  /// Whether [initialize] saw the SDK's own init callback run.
  bool get isInitialized => _initialized;

  @override
  Future<PushPermissionState> permissionState() async {
    if (!_initialized) return PushPermissionState.notDetermined;

    // The SDK's own `Notifications.permission` is a bare boolean, so a blocked
    // browser and one that was never asked look identical through it. The
    // browser's own tri-state is the only source that separates them.
    return permissionStateFor(OneSignalJsInterop.getBrowserPermission());
  }

  /// Maps a browser `Notification.permission` value onto the permission enum.
  ///
  /// `null` means the browser has no Notification API, so nothing has been
  /// asked and nothing can be.
  static PushPermissionState permissionStateFor(String? browserPermission) {
    return switch (browserPermission) {
      'granted' => PushPermissionState.authorized,
      'denied' => PushPermissionState.denied,
      _ => PushPermissionState.notDetermined,
    };
  }

  @override
  bool get isOptedIn {
    if (!_initialized) return false;
    return OneSignalJsInterop.getOptedIn();
  }

  @override
  Future<String?> currentSubscriptionId() async {
    if (!_initialized) return null;
    return OneSignalJsInterop.getSubscriptionId();
  }

  @override
  Future<String?> currentExternalId() async {
    if (!_initialized) return null;
    return OneSignalJsInterop.getExternalId();
  }

  /// Gets the OneSignal user ID.
  ///
  /// Returns `null` if not initialized.
  String? get oneSignalId {
    if (!_initialized) return null;
    return OneSignalJsInterop.getOneSignalId();
  }

  @override
  Future<void> initialize(Map<String, dynamic> config) async {
    if (!isSupported) {
      throw NotificationException(
        'OneSignal Web driver is only supported on web platform',
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

    // Get optional config values
    final safariWebId = config['safari_web_id'] as String?;
    final notifyButtonEnabled =
        config['notify_button_enabled'] as bool? ?? false;
    final serviceWorkerPath = config['service_worker_path'] as String?;
    final serviceWorkerScope = config['service_worker_scope'] as String?;

    // Initialize OneSignal via JS interop with all config values
    final initialized = await OneSignalJsInterop.init(
      appId: appId,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
      serviceWorkerPath: serviceWorkerPath,
      serviceWorkerScope: serviceWorkerScope,
    );

    // A page without the OneSignal script queues our callback and nothing ever
    // runs it. Refuse rather than report a readiness this driver never reached.
    if (!initialized) {
      throw NotificationException(
        'OneSignal Web SDK did not initialize. Check that the SDK script is '
        'loaded in web/index.html.',
        code: 'SDK_NOT_AVAILABLE',
      );
    }

    _initialized = true;

    // Setup event listeners via JS interop
    _setupEventListeners();
  }

  /// Sets up event listeners for OneSignal SDK events.
  void _setupEventListeners() {
    // Permission change listener. The event carries a bare bool, so re-read the
    // browser's tri-state rather than collapsing it onto denied.
    OneSignalJsInterop.addPermissionChangeListener((permission) {
      if (_permissionController.isClosed) return;
      _permissionController.add(
        permissionStateFor(OneSignalJsInterop.getBrowserPermission()),
      );
    });

    // Notification click listener
    OneSignalJsInterop.addNotificationClickListener((event) {
      _clickedController.add(PushNotificationEvent(event));
    });

    // Notification foreground display listener
    OneSignalJsInterop.addNotificationForegroundListener((event) {
      _receivedController.add(PushNotificationEvent(event));
    });

    // Identity listeners. The SDK reports the user and the subscription
    // separately, so each event carries only the half it knows.
    OneSignalJsInterop.addUserStateChangeListener((event) {
      if (_identityController.isClosed) return;
      final current = _currentOf(event);
      _identityController.add(
        PushIdentityChange(externalId: current['externalId'] as String?),
      );
    });

    OneSignalJsInterop.addSubscriptionChangeListener((event) {
      if (_identityController.isClosed) return;
      final current = _currentOf(event);
      _identityController.add(
        PushIdentityChange(
          subscriptionId: current['id'] as String?,
          optedIn: current['optedIn'] as bool?,
        ),
      );
    });
  }

  /// Reads the `current` state out of an SDK change event.
  ///
  /// Both web change events wrap their state in a `current` object; an event
  /// without one carries nothing this driver can report.
  Map<String, dynamic> _currentOf(Map<String, dynamic> event) {
    final current = event['current'];
    return current is Map<String, dynamic> ? current : const {};
  }

  @override
  Future<void> login(String externalId) async {
    if (!_initialized) {
      throw NotificationException(
        'OneSignal must be initialized before login',
        code: 'NOT_INITIALIZED',
      );
    }
    await OneSignalJsInterop.login(externalId);
  }

  @override
  Future<void> logout() async {
    if (!_initialized) return;
    await OneSignalJsInterop.logout();
  }

  @override
  Future<bool> requestPermission() async {
    if (!_initialized) {
      throw NotificationException(
        'OneSignal must be initialized before requesting permission',
        code: 'NOT_INITIALIZED',
      );
    }
    return await OneSignalJsInterop.requestPermission();
  }

  @override
  Future<void> optIn() async {
    if (!_initialized) return;
    await OneSignalJsInterop.optIn();
  }

  @override
  Future<void> optOut() async {
    if (!_initialized) return;
    await OneSignalJsInterop.optOut();
  }

  @override
  Future<void> setTags(Map<String, String> tags) async {
    if (!_initialized) return;
    await OneSignalJsInterop.addTags(tags);
  }

  @override
  Future<void> removeTag(String key) async {
    if (!_initialized) return;
    await OneSignalJsInterop.removeTag(key);
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

  /// Generates the HTML/JavaScript code needed to initialize OneSignal on web.
  ///
  /// Add this to your `web/index.html` `<head>` section.
  ///
  /// Example:
  /// ```dart
  /// final script = OneSignalWebDriver.getWebInitScript(
  ///   appId: '4573490d-2dfa-44c3-b211-8e04e2e96bdd',
  ///   safariWebId: 'web.onesignal.auto.abc123',
  ///   notifyButtonEnabled: true,
  ///   serviceWorkerPath: 'push/OneSignalSDKWorker.js',
  ///   serviceWorkerScope: '/push/',
  /// );
  /// ```
  static String getWebInitScript({
    required String appId,
    String? safariWebId,
    bool notifyButtonEnabled = false,
    String? serviceWorkerPath,
    String? serviceWorkerScope,
  }) {
    final safariLine =
        safariWebId != null ? '\n      safari_web_id: "$safariWebId",' : '';
    // A Flutter build owns the root scope with its own service worker, so the
    // OneSignal worker needs its own path and scope to avoid the collision.
    final workerPathLine = serviceWorkerPath != null
        ? '\n      serviceWorkerPath: "$serviceWorkerPath",'
        : '';
    final workerScopeLine = serviceWorkerScope != null
        ? '\n      serviceWorkerParam: { scope: "$serviceWorkerScope" },'
        : '';

    return '''
<script src="$_sdkUrl" defer></script>
<script>
  window.OneSignalDeferred = window.OneSignalDeferred || [];
  OneSignalDeferred.push(async function(OneSignal) {
    await OneSignal.init({
      appId: "$appId",$safariLine$workerPathLine$workerScopeLine
      notifyButton: {
        enable: $notifyButtonEnabled,
      },
    });
  });
</script>''';
  }

  /// Builds a configuration map for the web driver from environment/config values.
  ///
  /// Use this to construct the config passed to [initialize].
  static Map<String, dynamic> buildConfigFromEnv({
    required String appId,
    String? safariWebId,
    bool notifyButtonEnabled = false,
    String? serviceWorkerPath,
    String? serviceWorkerScope,
  }) {
    return {
      'app_id': appId,
      if (safariWebId != null) 'safari_web_id': safariWebId,
      if (serviceWorkerPath != null) 'service_worker_path': serviceWorkerPath,
      if (serviceWorkerScope != null)
        'service_worker_scope': serviceWorkerScope,
      'notify_button_enabled': notifyButtonEnabled,
    };
  }

  /// Disposes stream controllers.
  void dispose() {
    _receivedController.close();
    _clickedController.close();
    _permissionController.close();
    _identityController.close();
  }
}
