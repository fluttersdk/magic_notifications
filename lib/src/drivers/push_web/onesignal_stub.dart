import '../push/push_driver.dart';
import '../push/onesignal_driver.dart';

/// Creates a platform-specific push driver for non-web platforms.
///
/// This stub returns the mobile OneSignalDriver for iOS/Android.
PushDriver createPlatformDriver() {
  return OneSignalDriver();
}
