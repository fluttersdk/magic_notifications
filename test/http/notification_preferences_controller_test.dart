import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/http/notification_preferences_controller.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await initMagicForTests();
  });

  late NotificationPreferencesController controller;

  setUp(() {
    // The controller is a Magic singleton, so a stale matrix would otherwise
    // survive into the next case and certify a state nothing in this test set up.
    Magic.delete<NotificationPreferencesController>();
    controller = NotificationPreferencesController.instance;
  });

  tearDown(() {
    Http.unfake();
  });

  group('NotificationPreferencesController — failure paths', () {
    test('fetchPreferences() keeps the matrix empty on a 500 response',
        () async {
      // The error body still carries a `data` shape (a stale cache, a
      // degraded upstream) so this proves the early return on failure, not
      // just an empty body's absence of anything to parse.
      Http.fake((request) {
        return MagicResponse(
          data: <String, dynamic>{
            'data': <String, dynamic>{
              'monitor_down': <String, dynamic>{
                'label': 'Monitor Down',
                'channels': <String, dynamic>{},
              },
            },
          },
          statusCode: 500,
        );
      });

      await controller.fetchPreferences();

      expect(controller.matrixNotifier.value, isEmpty);
    });

    test(
      'updateTypePreference() reverts to the original matrix on a failed write',
      () async {
        final originalMatrix = <String, dynamic>{
          'monitor_down': <String, dynamic>{
            'label': 'Monitor Down',
            'channels': <String, dynamic>{
              'mail': <String, dynamic>{'enabled': true, 'locked': false},
            },
          },
        };
        controller.matrixNotifier.value = originalMatrix;

        Http.fake((request) {
          return MagicResponse(data: <String, dynamic>{}, statusCode: 422);
        });

        await controller.updateTypePreference('monitor_down', 'mail', false);

        expect(
          (((controller.matrixNotifier.value['monitor_down'] as Map)['channels']
              as Map)['mail'] as Map)['enabled'],
          isTrue,
        );
      },
    );

    test(
      'updateTypePreference() republishes the provisioning flag on a successful write',
      () async {
        controller.matrixNotifier.value = <String, dynamic>{
          'monitor_down': <String, dynamic>{
            'label': 'Monitor Down',
            'channels': <String, dynamic>{
              'mail': <String, dynamic>{'enabled': true, 'locked': false},
            },
          },
        };

        Http.fake((request) {
          return MagicResponse(
            data: <String, dynamic>{
              'data': <String, dynamic>{},
              'meta': <String, dynamic>{'push_provisioned': false},
            },
            statusCode: 200,
          );
        });

        await controller.updateTypePreference('monitor_down', 'mail', false);

        expect(controller.pushProvisionedNotifier.value, isFalse);
      },
    );
  });
}
