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
///
/// ## What the subject guard here can and cannot close
///
/// A push addressed to an identity this browser no longer carries still
/// arrives, because a subscription the server believes is current takes minutes
/// to stop being addressed. The service worker asks a VISIBLE page before it
/// draws, so [handleForegroundWillDisplay] can answer "do not draw" and keep
/// somebody else's incident title off this screen.
///
/// With no visible page, the worker draws the notification with no client code
/// involved. That half cannot be closed from here. It needs the server to stop
/// addressing a subscription it believes is stale.
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
    OneSignalJsInterop.addNotificationClickListener(handleNotificationClicked);

    // Notification foreground display listener. The interop hands over the
    // event's own suppression, so the decision can be made here.
    OneSignalJsInterop.addNotificationForegroundListener(
      handleForegroundWillDisplay,
    );

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

  /// Decides what happens to a push that arrived while the page is foregrounded.
  ///
  /// [preventDisplay] is the SDK's own `preventDefault`, taken as a parameter
  /// rather than reached for through the event, because it lives on the JS
  /// event the interop already converted away: passing it in is what lets the
  /// decision be exercised without a browser. It must be called synchronously,
  /// which is why nothing here awaits.
  ///
  /// A payload the subject guard rejects is suppressed on BOTH halves, the
  /// browser draw and the in-app republish, because a notification drawn for
  /// somebody who signed out is the leak, not the republish. See the class
  /// docblock for the half this cannot close.
  ///
  /// An accepted push republishes the server's own payload, the map [_payloadOf]
  /// reads out of the event, which is the map the mobile driver publishes:
  /// `PushNotificationEvent.data` carries the same shape on both platforms, on
  /// this stream and on the click one.
  void handleForegroundWillDisplay(
    Map<String, dynamic> event,
    void Function() preventDisplay,
  ) {
    final Map<String, dynamic> payload = _payloadOf(event);

    if (!mayDisplay(payload)) {
      preventDisplay();

      return;
    }

    if (_receivedController.isClosed) return;

    _receivedController.add(PushNotificationEvent(payload));
  }

  /// Decides whether a tapped push notification is republished to the app.
  ///
  /// The tap already happened, foregrounded or not: nothing here can undraw a
  /// notification the OS already showed. What is still at stake is the
  /// navigation `Notify.onPushClicked` drives from the payload, which is why
  /// a payload the subject guard rejects is dropped here rather than
  /// republished. See [_payloadOf] for why the guard reads the nested
  /// payload; [handleForegroundWillDisplay] applies the identical shape to
  /// the display path.
  ///
  /// An accepted [event] republishes the server's payload, not the SDK wrapper
  /// around it, so `PushNotificationEvent.data` is the same shape here as on
  /// mobile: the keys the server sent, flat. A consumer navigates off exactly
  /// those keys (`data['deep_link']`), and handing it the wrapper answers null
  /// for every one of them, which is a tap that silently goes nowhere.
  void handleNotificationClicked(Map<String, dynamic> event) {
    final Map<String, dynamic> payload = _payloadOf(event);

    if (!mayDisplay(payload)) return;

    if (_clickedController.isClosed) return;

    _clickedController.add(PushNotificationEvent(payload));
  }

  /// Reads the custom payload the SDK nests inside a web event.
  ///
  /// The web event wraps the notification, and the object the server sent
  /// arrives as its `additionalData`, which is exactly the map the mobile
  /// driver is handed. It is what the manager's one guard judges AND what both
  /// streams republish, because those two have to be the same map: a guard
  /// reading the payload while the stream carried the wrapper made the
  /// manager's own subject re-check on the click stream vacuous on web, and
  /// left every consumer reading the server's keys off an object that does not
  /// have them.
  ///
  /// An event nesting nothing answers empty, which is un-judgeable rather than
  /// addressed to nobody, and the guard passes it.
  Map<String, dynamic> _payloadOf(Map<String, dynamic> event) {
    final notification = event['notification'];
    if (notification is! Map<String, dynamic>) return const {};

    final additionalData = notification['additionalData'];

    return additionalData is Map<String, dynamic> ? additionalData : const {};
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
