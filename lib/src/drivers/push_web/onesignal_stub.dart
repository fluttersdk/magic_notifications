import '../../exceptions/notification_exception.dart';
import '../push/push_driver.dart';

/// Default arm of the platform factory: no driver for this build.
///
/// Resolves when neither the `dart:io` guard (mobile and desktop) nor the
/// `dart:js_interop` guard (web) matches. There is no honourable push driver
/// to hand back for a platform this package does not implement, so this
/// throws instead of forwarding a driver that would silently do nothing.
PushDriver createPlatformDriver() {
  throw UnsupportedPlatformException(
    'Push notifications are not supported on this platform',
  );
}
