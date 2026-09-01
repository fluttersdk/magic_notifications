import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/facades/notify.dart';
import 'package:magic_notifications/src/http/notification_preferences_controller.dart';
import 'package:magic_notifications/src/ui/views/notification_preferences_view.dart';

import '../test_helper.dart';

/// Feeds the translator a literal map so the view lays out real labels.
///
/// A widget test that renders a label needs its language keys loaded, or the
/// raw key is what gets measured and a failure says nothing about the widget.
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
        'notifications.preferences_title': 'Notification preferences',
        'notifications.preferences_description': 'Choose how we reach you',
        'notifications.no_preferences': 'Nothing to configure',
        'notifications.channel_email': 'Email',
        'notifications.channel_in_app': 'In app',
        'notifications.channel_push': 'Push',
        'notifications.channel_push_unconfigured': 'Push is not set up yet',
        'notifications.fetch_error': 'Could not load preferences',
        'common.back': 'Back',
        'errors.unexpected': 'Something went wrong',
      }),
    );

    await Translator.instance.load(const Locale('en'));
  });

  setUp(() {
    // The controller is a Magic singleton, so a stale matrix would otherwise
    // survive into the next case and certify a render nothing fetched.
    Magic.delete<NotificationPreferencesController>();
  });

  tearDown(() {
    Http.unfake();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      home: WindTheme(data: WindThemeData(), child: Scaffold(body: child)),
    );
  }

  /// Fakes the preference matrix endpoint with one type and two channels.
  void fakeMatrix({required bool pushProvisioned}) {
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'incident_opened': <String, dynamic>{
              'label': 'Incident opened',
              'channels': <String, dynamic>{
                'mail': <String, dynamic>{'enabled': true, 'locked': false},
                'push': <String, dynamic>{'enabled': false, 'locked': false},
              },
            },
          },
          'meta': <String, dynamic>{'push_provisioned': pushProvisioned},
        },
        statusCode: 200,
      );
    });
  }

  testWidgets('renders the push row of the fetched preference matrix', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: true);

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Incident opened'), findsOneWidget);
    expect(find.text('Push'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.byType(WSwitch), findsNWidgets(2));
    expect(find.text('Push is not set up yet'), findsNothing);
  });

  testWidgets('warns under the push row when push is unprovisioned', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: false);

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Push is not set up yet'), findsOneWidget);
  });

  testWidgets('toggling a channel writes the preference back', (tester) async {
    fakeMatrix(pushProvisioned: true);

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final fake = Http.fake((request) {
      return MagicResponse(data: <String, dynamic>{}, statusCode: 200);
    });

    await tester.tap(find.byType(WSwitch).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    fake.assertSent(
      (request) =>
          request.method == 'PUT' &&
          request.url == '/notification-preferences' &&
          (request.data as Map)['channel'] == 'push' &&
          (request.data as Map)['is_enabled'] == true,
    );
  });

  testWidgets('renders no back affordance without a back route', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: true);

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.chevron_left), findsNothing);
  });

  testWidgets('renders a back affordance when the host supplies a route', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: true);

    await tester.pumpWidget(
      wrap(const NotificationPreferencesView(backRoute: '/settings')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
  });

  testWidgets('renders the loading state before the fetch resolves', (
    tester,
  ) async {
    // Faked so onInit()'s fetch has somewhere real to land instead of hitting
    // the network; set loading explicitly first so the assertion reads the
    // state the spinner actually gates on, not a race against that fetch.
    fakeMatrix(pushProvisioned: true);
    NotificationPreferencesController.instance.setLoading();

    await tester.pumpWidget(wrap(const NotificationPreferencesView()));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('renders the empty-matrix state when the backend has nothing', (
    tester,
  ) async {
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{'data': <String, dynamic>{}},
        statusCode: 200,
      );
    });

    await tester.pumpWidget(wrap(const NotificationPreferencesView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Nothing to configure'), findsOneWidget);
  });

  testWidgets('disables the switch for a locked channel', (tester) async {
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'incident_opened': <String, dynamic>{
              'label': 'Incident opened',
              'channels': <String, dynamic>{
                'mail': <String, dynamic>{'enabled': true, 'locked': true},
              },
            },
          },
        },
        statusCode: 200,
      );
    });

    await tester.pumpWidget(wrap(const NotificationPreferencesView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final switchWidget = tester.widget<WSwitch>(find.byType(WSwitch));
    expect(switchWidget.disabled, isTrue);
  });

  testWidgets('a push row with its hint fits a phone width', (tester) async {
    // Every other case in this file runs at the wrap() helper's fixed size,
    // which is why an overflow here never showed at that width: the row only
    // broke at a phone width on a channel carrying the two-line push hint.
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'incident_opened': <String, dynamic>{
              'label': 'Incident opened',
              'channels': <String, dynamic>{
                'mail': <String, dynamic>{'enabled': true, 'locked': false},
                'push': <String, dynamic>{'enabled': true, 'locked': false},
              },
            },
          },
        },
        statusCode: 200,
      );
    });

    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: WindTheme(
          data: WindThemeData(),
          child: MediaQuery(
            data: const MediaQueryData(size: Size(430, 900)),
            child: const Scaffold(
              body: SizedBox(
                width: 430,
                height: 900,
                child: NotificationPreferencesView(pushProvisioned: false),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Push is not set up yet'), findsOneWidget);
    expect(
      tester.takeException(),
      isNull,
      reason: 'the preference row must not overflow at a phone width',
    );
  });

  testWidgets('a host override wins over the backend-reported flag', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: false);

    await tester.pumpWidget(
      wrap(const NotificationPreferencesView(pushProvisioned: true)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Push is not set up yet'), findsNothing);
  });

  testWidgets('renders no hint when the payload carries no provisioning flag', (
    tester,
  ) async {
    // No 'meta' key at all: a backend that predates the flag, not a claim
    // that push became unconfigured, so the optimistic default must stand.
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'incident_opened': <String, dynamic>{
              'label': 'Incident opened',
              'channels': <String, dynamic>{
                'push': <String, dynamic>{'enabled': false, 'locked': false},
              },
            },
          },
        },
        statusCode: 200,
      );
    });

    await tester.pumpWidget(wrap(const NotificationPreferencesView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Push is not set up yet'), findsNothing);
  });

  testWidgets('keeps the push hint out of the label semantics exclusion', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: false);

    await tester.pumpWidget(wrap(const NotificationPreferencesView()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The channel label is excluded from semantics (the switch carries it as
    // its own semanticLabel), but the hint says something the switch label
    // does not, so it must stay announceable.
    expect(
      find.descendant(
        of: find.byType(ExcludeSemantics),
        matching: find.text('Push'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ExcludeSemantics),
        matching: find.text('Push is not set up yet'),
      ),
      findsNothing,
    );
  });
}
