import '../push/onesignal_driver.dart';
import '../push/push_driver.dart';

/// Native-library arm of the platform factory: iOS and Android.
///
/// Selected on any build that has the native I/O library, which covers
/// mobile and desktop alike; [OneSignalDriver] itself narrows further to the
/// platforms it actually supports via [PushDriver.isSupported].
PushDriver createPlatformDriver() {
  return OneSignalDriver();
}
