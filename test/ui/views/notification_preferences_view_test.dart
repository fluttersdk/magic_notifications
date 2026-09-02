import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/http/notification_preferences_controller.dart';
import 'package:magic_notifications/src/ui/views/notification_preferences_view.dart';

import '../../test_helper.dart';

/// Feeds the translator a literal map so the view lays out real labels.
///
/// A widget test that asserts on a label needs its language keys loaded, or the
/// raw key is what gets measured and a green result says nothing.
class _MapTranslationLoader implements TranslationLoader {
  const _MapTranslationLoader(this.sentences);

  final Map<String, dynamic> sentences;

  @override
  Future<Map<String, dynamic>> load(Locale locale) async => sentences;
}

void main() {
  setUpAll(() async {
    await initMagicForTests();

    Translator.instance.setLoader(
      const _MapTranslationLoader(<String, dynamic>{
        'notifications.preferences_title': 'Notification Preferences',
        'notifications.preferences_description': 'Manage your notifications',
        'notifications.no_preferences': 'Nothing to configure',
        'notifications.fetch_error': 'Could not load your preferences',
        'notifications.channel_email': 'Email',
        'notifications.channel_in_app': 'In-App',
        'notifications.channel_push': 'Push',
        'notifications.channel_sms': 'SMS',
        'notifications.channel_push_unconfigured': 'Push not yet configured',
        'common.back': 'Back',
      }),
    );

    await Translator.instance.load(const Locale('en'));
  });

  setUp(() {
    // The controller behind this screen is a Magic singleton, so a matrix a
    // previous case loaded would otherwise survive into the next one.
    Magic.delete<NotificationPreferencesController>();
  });

  tearDown(() {
    Http.unfake();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      home: WindTheme(
        data: WindThemeData(),
        child: Scaffold(
          body: SizedBox(width: 1024, height: 2000, child: child),
        ),
      ),
    );
  }

  /// Answers `GET /notification-preferences` with one type offering every
  /// channel the backend actually ships, which is the shape a default
  /// `magic-starter-laravel` install produces.
  void fakeMatrix() {
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'incident_opened': <String, dynamic>{
              'label': 'Incident opened',
              'channels': <String, dynamic>{
                'mail': <String, dynamic>{'enabled': true, 'locked': false},
                'database': <String, dynamic>{'enabled': true, 'locked': false},
                'push': <String, dynamic>{'enabled': true, 'locked': false},
                'sms': <String, dynamic>{'enabled': false, 'locked': false},
              },
            },
          },
          'meta': <String, dynamic>{'push_provisioned': true},
        },
        statusCode: 200,
      );
    });
  }

  testWidgets('every offered channel renders a translated label', (
    tester,
  ) async {
    // `sms` used to fall through to the machine-name fallback, so a screen
    // whose other three rows were properly localised carried a bare "Sms"
    // beside them, untranslated in every locale. The backend offers sms out of
    // the box, so that fallback was reachable on a default install rather than
    // only on an exotic one.
    fakeMatrix();

    await tester.pumpWidget(wrap(const NotificationPreferencesView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Email'), findsOneWidget);
    expect(find.text('In-App'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('SMS'), findsOneWidget);

    // The fallback's own output, which is what the defect looked like.
    expect(
      find.text('Sms'),
      findsNothing,
      reason: 'the machine name reached the screen instead of a translation',
    );
  });

  testWidgets('a channel this package has no name for still renders', (
    tester,
  ) async {
    // The fallback is not dead: a host can register a channel of its own, and
    // the machine name is the only thing available to show for it.
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'incident_opened': <String, dynamic>{
              'label': 'Incident opened',
              'channels': <String, dynamic>{
                'carrier_pigeon': <String, dynamic>{
                  'enabled': false,
                  'locked': false,
                },
              },
            },
          },
          'meta': <String, dynamic>{'push_provisioned': true},
        },
        statusCode: 200,
      );
    });

    await tester.pumpWidget(wrap(const NotificationPreferencesView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Carrier pigeon'), findsOneWidget);
  });
}
