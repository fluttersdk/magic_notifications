import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/support/notification_log.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await initMagicForTests();
  });

  late FakeLogManager log;

  setUp(() {
    // Bound as a container INSTANCE, which is what `Magic.bound('log')` reads,
    // so this also restores the binding a case below flushed away.
    log = Log.fake();
  });

  group('NotificationLog on a host that bound log', () {
    test('error() reports at error level, unchanged', () {
      NotificationLog.error('[notifications] the read did not land');

      log.assertLoggedError('[notifications] the read did not land');
      log.assertLoggedCount(1);
    });

    test('debug() reports at debug level, unchanged', () {
      NotificationLog.debug('[notifications] push driver absent');

      log.assertLogged('debug', '[notifications] push driver absent');
      log.assertLoggedCount(1);
    });
  });

  group('NotificationLog on a host that has not bound log', () {
    test('error() writes nowhere instead of throwing', () {
      Magic.flush();

      // `Log.error` resolves `log` out of the container and THROWS when nothing
      // bound it. A package must not require its consumer to have registered a
      // logging provider, and the calls this seam replaces all sit inside a
      // `catch`, where a throw turns a handled failure into an unhandled one.
      expect(
          () => NotificationLog.error('nobody is listening'), returnsNormally);
    });

    test('debug() writes nowhere instead of throwing', () {
      Magic.flush();

      expect(
          () => NotificationLog.debug('nobody is listening'), returnsNormally);
    });
  });
}
