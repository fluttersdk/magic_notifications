import 'package:magic/magic.dart';

import '../channels/database_channel.dart';
import '../channels/push_channel.dart';
import '../drivers/push/push_driver.dart';
import '../drivers/push_web/onesignal_factory.dart';
import '../notification_manager.dart';

/// Binds notifications into magic's container and wires the push driver.
///
/// Register it in your app's kernel:
///
/// ```dart
/// (app) => NotificationServiceProvider(app),
/// ```
///
/// ## The register / boot split
///
/// [register] binds ONE string-keyed singleton and does nothing else. It runs
/// the moment the provider is registered, which is before every other provider
/// has bound anything, so a driver resolved there would be resolved against a
/// half-built container. [boot] runs after all of them and is where the driver,
/// the channels and the first identity reconcile are wired.
///
/// ## The configuration root, and the one key that selects a driver
///
/// This package reads `notifications.*` and nothing else. `notifications.push.driver`
/// names a driver by the name it was REGISTERED under, and `onesignal` is the
/// only one this package ships.
///
/// An ABSENT key is an answer: an app with no push configured is a supported
/// build, it stays quiet, and everything except push keeps working. A value this
/// package cannot serve is the opposite and is reported at error level before
/// [boot] degrades, because a silent acceptance leaves the operator believing
/// push was wired when nothing was.
///
/// A driver of your own is installed in code, with `Notify.extend(name, factory)`
/// before this provider boots; the container has no reflection to turn a string
/// into a constructor. The built-in goes through that same registry rather than
/// being constructed here, so the shipped driver and an override travel one path.
class NotificationServiceProvider extends ServiceProvider {
  /// Creates the provider against [app], magic's container.
  NotificationServiceProvider(super.app);

  /// The container key notifications are bound under.
  ///
  /// A string because magic's container has no reflection: `Magic.make` takes a
  /// name, so this is the word a consumer's own code resolves the manager with.
  static const String _containerKey = 'notifications';

  /// The name the built-in driver is registered under, and the value
  /// `notifications.push.driver` has to carry to select it.
  static const String _oneSignal = 'onesignal';

  static Object? _pushInitializationError;

  /// The failure of the last push initialisation, or `null` when the last boot
  /// initialised cleanly or had no push driver to initialise.
  ///
  /// Retained rather than only logged, so a broken push setup is
  /// distinguishable from an absent one after the fact: `Notify.requestPushPermission`
  /// failing on a device whose SDK never came up otherwise reads exactly like a
  /// build that ships no push at all. Cleared at the start of every [boot].
  static Object? get pushInitializationError => _pushInitializationError;

  @override
  void register() {
    app.singleton(_containerKey, () => NotificationManager());
  }

  @override
  Future<void> boot() async {
    // 1. Through the container, not straight to the singleton: this is also the
    //    proof that `register()` bound what a consumer will resolve, and a
    //    missing registration surfaces as magic's own diagnostic rather than as
    //    a provider that booted against a binding nobody can reach.
    final NotificationManager manager =
        app.make<NotificationManager>(_containerKey);

    _pushInitializationError = null;

    // 2. The database channel is available with or without push, and nothing
    //    else in production registers it, so `Notify.send` had no channel to
    //    dispatch to at all before this line.
    manager.registerChannel(DatabaseChannel());

    final PushDriver? driver = _resolvePushDriver(manager);

    if (driver != null) {
      manager.registerChannel(PushChannel(driver));
      await _initializePush(driver);
    }

    // 3. One unconditional reconcile, because the signed-out cold boot fires no
    //    auth event at all: magic's guards return from `restore()` before any
    //    `stateNotifier` bump when there is no cached token. Without this pass
    //    a device that was signed out while offline stays subscribed as the
    //    previous person until somebody signs in. Safe with no driver, and safe
    //    when the intent already matches the device.
    await manager.reconcilePushIdentity();

    Log.debug(
      '[notifications] push driver ${driver?.name ?? 'absent'}, '
      'channels database'
      '${manager.hasChannel('push') ? ' + push' : ''}',
    );
  }

  /// The driver this build should use, or `null` when push is not configured.
  ///
  /// Resolution runs THROUGH the manager rather than calling the OneSignal
  /// factory here, so a driver a consumer registered with `Notify.extend` is
  /// reached by exactly the path the built-in is.
  PushDriver? _resolvePushDriver(NotificationManager manager) {
    // 1. Anything already registered or set explicitly outranks the config.
    //    Asking first is also what keeps the error below honest: a consumer who
    //    registered their own driver has SERVED the configured value, and
    //    reporting it as unservable would be a false alarm.
    final PushDriver? supplied = manager.pushDriverOrNull;
    if (supplied != null) return supplied;

    final String? configured = Config.get<String>('notifications.push.driver');

    // 2. Absence is an answer, and a quiet one.
    if (configured == null || configured.isEmpty) return null;

    // 3. A value nothing can serve. Loud, then degrade: push is the only thing
    //    lost, and an app must not fail to boot over a typo in a config key.
    if (configured != _oneSignal) {
      Log.error(
        '[notifications] config notifications.push.driver is "$configured", '
        'and the only driver this package ships is "$_oneSignal". Push is '
        'left unconfigured. To supply a driver of your own, register it in '
        'code with Notify.extend("$configured", () => YourPushDriver()) '
        'before this provider boots.',
      );

      return null;
    }

    // 4. The built-in, registered as a factory rather than constructed, so the
    //    manager owns its lifetime and one resolution path serves both.
    manager.extend(_oneSignal, createOneSignalDriver);

    return manager.pushDriverOrNull;
  }

  /// Hands [driver] the app id and the web options from the package's config.
  ///
  /// A failure is recorded on [pushInitializationError] and reported, never
  /// swallowed: the SDK is then up on nobody's device, and the only difference
  /// between that and a build with no push at all is this record.
  Future<void> _initializePush(PushDriver driver) async {
    // An unsupported platform is an ABSENT capability rather than a broken
    // setup: the driver refuses there by contract, and recording that refusal
    // would put an error in every desktop and every test boot for a condition
    // nobody can fix.
    if (!driver.isSupported) return;

    final String? appId = Config.get<String>('notifications.push.app_id');
    if (appId == null || appId.isEmpty) return;

    try {
      await driver.initialize(<String, dynamic>{
        'app_id': appId,
        'safari_web_id': Config.get<String>(
          'notifications.push.safari_web_id',
        ),
        'notify_button_enabled':
            Config.get<bool>('notifications.push.notify_button_enabled') ??
                false,
      });
    } catch (e) {
      _pushInitializationError = e;
      Log.error(
        '[notifications] push driver "${driver.name}" failed to initialize: '
        '$e. Push is unavailable on this device for the rest of the session; '
        'read NotificationServiceProvider.pushInitializationError to see it.',
      );
    }
  }
}
