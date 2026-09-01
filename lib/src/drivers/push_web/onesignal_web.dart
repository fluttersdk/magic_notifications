// Re-export the web driver from the main push directory
// This file exists for conditional imports in onesignal_factory.dart

export '../push/onesignal_web_driver.dart' show OneSignalWebDriver;

import '../push/onesignal_web_driver.dart';
import '../push/push_driver.dart';

/// `dart:js_interop` arm of the platform factory: the browser.
///
/// Returns [OneSignalWebDriver] which uses JS interop to communicate
/// with the OneSignal Web SDK v16.
PushDriver createPlatformDriver() {
  return OneSignalWebDriver();
}
