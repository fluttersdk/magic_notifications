import 'package:magic/magic.dart';

import '../drivers/push_web/onesignal_factory.dart';
import '../facades/notify.dart';
import '../notification_manager.dart';

/// Service provider for notifications.
///
/// Register in your app's kernel:
///
/// ```dart
/// (app) => NotificationServiceProvider(app),
/// ```
class NotificationServiceProvider extends ServiceProvider {
  NotificationServiceProvider(super.app);

  /// Whether the auth state listener has been attached.
  ///
  /// Prevents duplicate listeners when `boot()` runs more than once
  /// (tests, hot restart, multiple `MagicApp` initializations).
  static bool _authListenerAttached = false;

  /// Reset static state for testing.
  static void resetForTesting() {
    _authListenerAttached = false;
  }

  @override
  void register() {
    // Register manager singleton
    app.singleton('notifications', () => NotificationManager());
  }

  @override
  Future<void> boot() async {
    final manager = NotificationManager();

    // Configure push driver if push notifications are enabled
    final pushDriver = Config.get<String>('notifications.push.driver');
    if (pushDriver == 'onesignal') {
      final driver = createOneSignalDriver();
      manager.setPushDriver(driver);

      // Get config values
      final appId = Config.get<String>('notifications.push.app_id');
      final safariWebId = Config.get<String>(
        'notifications.push.safari_web_id',
      );
      final notifyButtonEnabled =
          Config.get<bool>('notifications.push.notify_button_enabled') ?? false;

      if (appId != null && appId.isNotEmpty) {
        try {
          // Initialize OneSignal with config values from Dart
          await driver.initialize({
            'app_id': appId,
            'safari_web_id': safariWebId,
            'notify_button_enabled': notifyButtonEnabled,
          });
          _log('OneSignal initialized with config');
        } catch (e) {
          _log('Failed to initialize OneSignal: $e', isError: true);
        }
      }
    }

    // Auto-attach push on Auth state change
    final autoAttach =
        Config.get<bool>('notifications.push.auto_attach_on_auth') ?? true;

    if (autoAttach && !_authListenerAttached) {
      _authListenerAttached = true;

      final externalIdPrefix =
          Config.get<String>('notifications.push.external_id_prefix') ??
              'user_';
      final autoRequestPermission =
          Config.get<bool>('notifications.push.auto_request_permission') ??
              true;

      var lastUserId = '';
      Future<void> authListenerQueue = Future.value();

      Auth.stateNotifier.addListener(() {
        final isAuthenticated = Auth.check();
        final id = isAuthenticated ? '${Auth.id() ?? ''}' : '';

        authListenerQueue = authListenerQueue.then((_) async {
          try {
            if (!isAuthenticated) {
              lastUserId = '';
              Notify.stopPolling();
              await Notify.logoutPush();
              return;
            }
            if (id.isEmpty || id == lastUserId) return;
            lastUserId = id;
            await Notify.initializePush('$externalIdPrefix$id');
            if (autoRequestPermission) {
              await Notify.requestPushPermission();
            }
          } catch (e) {
            _log(
              '[NotificationServiceProvider] auth state change failed: $e',
              isError: true,
            );
          }
        });
      });
    }
  }

  /// Safe logging that doesn't throw if Log service isn't registered.
  void _log(String message, {bool isError = false}) {
    try {
      if (isError) {
        Log.error(message);
      } else {
        Log.info(message);
      }
    } catch (_) {
      // Log service not available, ignore
    }
  }
}
