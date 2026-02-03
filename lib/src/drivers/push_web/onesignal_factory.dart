// Conditional imports to avoid dart:html on non-web platforms
import 'onesignal_stub.dart' if (dart.library.html) 'onesignal_web.dart';

import '../push/push_driver.dart';

/// Creates a platform-specific OneSignal driver.
///
/// Returns:
/// - [OneSignalDriver] on iOS/Android (via stub)
/// - [OneSignalWebDriver] on Web (via conditional import)
PushDriver createOneSignalDriver() {
  return createPlatformDriver();
}
