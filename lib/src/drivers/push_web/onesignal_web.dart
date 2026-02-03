// Re-export the web driver from the main push directory
// This file exists for conditional imports in onesignal_factory.dart

export '../push/onesignal_web_driver.dart' show OneSignalWebDriver;

import '../push/onesignal_web_driver.dart';
import '../push/push_driver.dart';

/// Creates a platform-specific push driver for web platforms.
///
/// Returns [OneSignalWebDriver] which uses JS interop to communicate
/// with the OneSignal Web SDK v16.
PushDriver createPlatformDriver() {
  return OneSignalWebDriver();
}
