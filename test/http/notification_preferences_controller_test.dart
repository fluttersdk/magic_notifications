import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/http/notification_preferences_controller.dart';

import '../test_helper.dart';

/// One type carrying two independent channels, both enabled.
Map<String, dynamic> _matrix() => <String, dynamic>{
      'monitor_down': <String, dynamic>{
        'label': 'Monitor Down',
        'channels': <String, dynamic>{
          'mail': <String, dynamic>{'enabled': true, 'locked': false},
          'push': <String, dynamic>{'enabled': true, 'locked': false},
        },
      },
    };

/// The `enabled` flag [channel] currently carries under `monitor_down`.
Object? _enabled(NotificationPreferencesController controller, String channel) {
  final Map<dynamic, dynamic> type =
      controller.matrixNotifier.value['monitor_down'] as Map<dynamic, dynamic>;
  final Map<dynamic, dynamic> channels =
      type['channels'] as Map<dynamic, dynamic>;

  return (channels[channel] as Map<dynamic, dynamic>)['enabled'];
}

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
      'updateTypePreference() does not swallow a second cell mid-write',
      () async {
        controller.matrixNotifier.value = _matrix();

        final List<String> written = <String>[];
        Http.fake((request) {
          final Map<String, dynamic> body =
              request.data as Map<String, dynamic>;
          written.add('${body['type']}.${body['channel']}');

          return MagicResponse(
            data: <String, dynamic>{'data': <String, dynamic>{}},
            statusCode: 200,
          );
        });

        // An operator silencing two noisy channels in a row. The first write is
        // still in flight when the second toggle lands, and a single flag across
        // the whole matrix turns that second tap into a tap that visibly does
        // nothing: no spinner, no snap-back, no message, and the channel keeps
        // paging them.
        final Future<void> mail = controller.updateTypePreference(
          'monitor_down',
          'mail',
          false,
        );
        final Future<void> push = controller.updateTypePreference(
          'monitor_down',
          'push',
          false,
        );
        await Future.wait(<Future<void>>[mail, push]);

        expect(written, <String>['monitor_down.mail', 'monitor_down.push']);
        expect(_enabled(controller, 'push'), isFalse);
      },
    );

    test(
      'updateTypePreference() still coalesces a repeat of the SAME cell',
      () async {
        controller.matrixNotifier.value = _matrix();

        int writes = 0;
        Http.fake((request) {
          writes++;

          return MagicResponse(
            data: <String, dynamic>{'data': <String, dynamic>{}},
            statusCode: 200,
          );
        });

        // The half the guard is actually for: one cell, two taps, one write.
        // Keyed per cell it still holds, and without this pair a fix could have
        // deleted the guard rather than narrowed it.
        final Future<void> first = controller.updateTypePreference(
          'monitor_down',
          'mail',
          false,
        );
        final Future<void> second = controller.updateTypePreference(
          'monitor_down',
          'mail',
          true,
        );
        await Future.wait(<Future<void>>[first, second]);

        expect(writes, 1);
      },
    );

    test(
      'updateTypePreference() reverts only the cell whose write failed',
      () async {
        controller.matrixNotifier.value = _matrix();

        Http.fake((request) {
          final Map<String, dynamic> body =
              request.data as Map<String, dynamic>;

          return body['channel'] == 'mail'
              ? MagicResponse(data: <String, dynamic>{}, statusCode: 422)
              : MagicResponse(
                  data: <String, dynamic>{'data': <String, dynamic>{}},
                  statusCode: 200,
                );
        });

        final Future<void> mail = controller.updateTypePreference(
          'monitor_down',
          'mail',
          false,
        );
        final Future<void> push = controller.updateTypePreference(
          'monitor_down',
          'push',
          false,
        );
        await Future.wait(<Future<void>>[mail, push]);

        // Rolling back to a whole-matrix snapshot taken before the neighbouring
        // edit would undo an edit the backend ACCEPTED, and nothing re-applies
        // it: the switch would read enabled while the channel is silenced.
        expect(_enabled(controller, 'mail'), isTrue);
        expect(_enabled(controller, 'push'), isFalse);
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
