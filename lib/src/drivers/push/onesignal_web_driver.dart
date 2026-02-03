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

  bool _initialized = false;

  @override
  String get name => 'onesignal';

  @override
  bool get isSupported => kIsWeb;

  @override
  PushPermissionState get permissionState {
    if (!_initialized) return PushPermissionState.notDetermined;

    // Query actual permission state from JS SDK
    final hasPermission = OneSignalJsInterop.getPermission();
    if (hasPermission) {
      return PushPermissionState.authorized;
    }
    return PushPermissionState.notDetermined;
  }

  @override
  bool get isOptedIn {
    if (!_initialized) return false;
    return OneSignalJsInterop.getOptedIn();
  }

  /// Gets the current subscription ID from the OneSignal SDK.
  ///
  /// Returns `null` if not initialized or no subscription exists.
  String? get subscriptionId {
    if (!_initialized) return null;
    return OneSignalJsInterop.getSubscriptionId();
  }

  /// Gets the current external user ID from the OneSignal SDK.
  ///
  /// Returns `null` if not initialized or no external ID is set.
  String? get externalId {
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

    // Initialize OneSignal via JS interop with all config values
    await OneSignalJsInterop.init(
      appId: appId,
      safariWebId: safariWebId,
      notifyButtonEnabled: notifyButtonEnabled,
    );

    _initialized = true;

    // Setup event listeners via JS interop
    _setupEventListeners();
  }

  /// Sets up event listeners for OneSignal SDK events.
  void _setupEventListeners() {
    // Permission change listener
    OneSignalJsInterop.addPermissionChangeListener((permission) {
      _permissionController.add(
        permission
            ? PushPermissionState.authorized
            : PushPermissionState.denied,
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
  /// );
  /// ```
  static String getWebInitScript({
    required String appId,
    String? safariWebId,
    bool notifyButtonEnabled = false,
  }) {
    final safariLine =
        safariWebId != null ? '\n      safari_web_id: "$safariWebId",' : '';

    return '''
<script src="$_sdkUrl" defer></script>
<script>
  window.OneSignalDeferred = window.OneSignalDeferred || [];
  OneSignalDeferred.push(async function(OneSignal) {
    await OneSignal.init({
      appId: "$appId",$safariLine
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
  }) {
    return {
      'app_id': appId,
      if (safariWebId != null) 'safari_web_id': safariWebId,
      'notify_button_enabled': notifyButtonEnabled,
    };
  }

  /// Disposes stream controllers.
  void dispose() {
    _receivedController.close();
    _clickedController.close();
    _permissionController.close();
  }
}
