@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';

import 'package:magic_notifications/src/drivers/push/onesignal_js_interop_web.dart'
    as web;

/// Runs the real web interop against a stand-in SDK, so the options handed to
/// `OneSignal.init` are read back exactly as the SDK would receive them.
///
/// Browser only: `flutter test --platform chrome test/drivers/push/onesignal_js_interop_web_test.dart`.
void main() {
  late JSObject? captured;

  setUp(() {
    captured = null;

    final sdk = JSObject();
    sdk['init'] = ((JSObject options) {
      captured = options;
    }).toJS;

    // A queue whose `push` runs the callback at once, as the loaded SDK does.
    final JSObject deferred = JSArray();
    deferred['push'] = ((JSFunction callback) {
      callback.callAsFunction(null, sdk);
    }).toJS;
    globalContext['OneSignalDeferred'] = deferred;
  });

  tearDown(() {
    globalContext.delete('OneSignalDeferred'.toJS);
  });

  test('init asks the worker to focus an open tab of the app', () async {
    final initialized = await web.init(appId: 'test-app-id');

    expect(initialized, isTrue);
    expect(
      (captured!['notificationClickHandlerMatch'] as JSString).toDart,
      'origin',
    );
    expect(
      (captured!['notificationClickHandlerAction'] as JSString).toDart,
      'focus',
    );
  });
}
