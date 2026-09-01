// Conditional imports to select the right platform arm.
//
// The stub is the default: it resolves only when neither guard below
// matches, which no real Flutter build target does. The web guard picks the
// `dart:js_interop` library rather than the legacy HTML one, because the
// legacy library is absent under a wasm web compile; guarding on it there
// would fall through to the second guard and hand a browser the native
// driver instead. The second guard picks the native (iOS/Android) arm.
import 'onesignal_stub.dart'
    if (dart.library.js_interop) 'onesignal_web.dart'
    if (dart.library.io) 'onesignal_io.dart';

import '../push/push_driver.dart';

/// Creates a platform-specific OneSignal driver.
///
/// Returns:
/// - [OneSignalDriver] on iOS/Android (via the native-library arm)
/// - [OneSignalWebDriver] on Web (via the js-interop-library arm)
PushDriver createOneSignalDriver() {
  return createPlatformDriver();
}
