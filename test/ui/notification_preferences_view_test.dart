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
        'notifications.bulk_title': 'Every notification type',
        'notifications.bulk_description': 'Turn a channel on or off at once',
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

  /// Fakes a matrix with two types, so a bulk write has more than one cell to
  /// reach, and one locked cell that has to survive it.
  void fakeTwoTypeMatrix() {
    Http.fake((request) {
      return MagicResponse(
        data: <String, dynamic>{
          'data': <String, dynamic>{
            'incident_opened': <String, dynamic>{
              'label': 'Incident opened',
              'channels': <String, dynamic>{
                // Locked and OFF, against a writable ON below. The two have to
                // disagree or the assertion cannot discriminate: with both ON,
                // `every` answers true whether or not the locked cell is
                // counted, and an implementation that counts it passes.
                'mail': <String, dynamic>{'enabled': false, 'locked': true},
                'push': <String, dynamic>{'enabled': false, 'locked': false},
              },
            },
            'incident_resolved': <String, dynamic>{
              'label': 'Incident resolved',
              'channels': <String, dynamic>{
                'mail': <String, dynamic>{'enabled': true, 'locked': false},
                'push': <String, dynamic>{'enabled': false, 'locked': false},
              },
            },
          },
          'meta': <String, dynamic>{'push_provisioned': true},
        },
        statusCode: 200,
      );
    });
  }

  testWidgets('the bulk row reaches every type that offers the channel', (
    tester,
  ) async {
    fakeTwoTypeMatrix();

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Every notification type'), findsOneWidget);

    final List<Map<String, dynamic>> sent = <Map<String, dynamic>>[];
    Http.fake((request) {
      sent.add(request.data as Map<String, dynamic>);

      return MagicResponse(data: <String, dynamic>{}, statusCode: 200);
    });

    await tester.tap(find.byKey(const ValueKey('notifications.bulk.push')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // ONE request carrying both cells, not one request per type: a loop has a
    // way to half-succeed, and a half-succeeded bulk renders exactly like a
    // complete one.
    expect(sent, hasLength(1));
    expect(sent.single['preferences'], <Map<String, dynamic>>[
      <String, dynamic>{
        'type': 'incident_opened',
        'channel': 'push',
        'is_enabled': true,
      },
      <String, dynamic>{
        'type': 'incident_resolved',
        'channel': 'push',
        'is_enabled': true,
      },
    ]);
  });

  /// A batch that fails puts every cell it touched back, so the switch cannot
  /// claim a channel is off while a type still delivers.
  testWidgets('a failed bulk write reverts every cell it touched', (
    tester,
  ) async {
    fakeTwoTypeMatrix();

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    Http.fake((request) {
      return MagicResponse(data: <String, dynamic>{}, statusCode: 500);
    });

    await tester.tap(find.byKey(const ValueKey('notifications.bulk.push')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final WSwitch push = tester.widget<WSwitch>(
      find.byKey(const ValueKey('notifications.bulk.push')),
    );

    expect(push.value, isFalse);
  });

  /// The bulk card does not look like the cards it summarises.
  ///
  /// Its rows are deliberately identical to a per-type row (same control, same
  /// touch target, same semantics), so the card shell is the only thing that can
  /// say "this one is a shortcut and the real settings are underneath". Rendered
  /// in the same tokens it read as the first per-type card, which is how it
  /// shipped and what this pins.
  testWidgets('the bulk card carries its own surface, not the matrix one', (
    tester,
  ) async {
    fakeTwoTypeMatrix();

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final WDiv bulk = tester.widget<WDiv>(
      find.byKey(const ValueKey('notifications.bulk')),
    );
    final WDiv type = tester.widget<WDiv>(
      find.byKey(const ValueKey('notifications.type.incident_opened')),
    );

    // Structural, over the className: the widget test runs in one brightness,
    // so a rendered colour cannot carry this and the token can.
    expect(bulk.className, contains('bg-surface-container-high'));
    expect(type.className, isNot(contains('bg-surface-container-high')));
    expect(bulk.className, isNot(equals(type.className)));

    // And a second signal that costs no vertical space, because the heading row
    // already reserves this height for its two lines of text.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('notifications.bulk')),
        matching: find.byIcon(Icons.tune_outlined),
      ),
      findsOneWidget,
    );
  });

  /// The bulk switch reads the cells it would write, not the cells that exist.
  ///
  /// `incident_opened.mail` is locked and on; `incident_resolved.mail` is
  /// unlocked and on. Counting the locked one would make the control claim mail
  /// is fully on, and the tap that follows would then try to turn it off and
  /// change exactly one type, leaving a switch that says off over a channel that
  /// is still delivering.
  testWidgets('the bulk switch ignores the cells it cannot write', (
    tester,
  ) async {
    fakeTwoTypeMatrix();

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final WSwitch mail = tester.widget<WSwitch>(
      find.byKey(const ValueKey('notifications.bulk.mail')),
    );
    final WSwitch push = tester.widget<WSwitch>(
      find.byKey(const ValueKey('notifications.bulk.push')),
    );

    expect(mail.value, isTrue);
    expect(push.value, isFalse);
  });

  testWidgets('renders the push row of the fetched preference matrix', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: true);

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Incident opened'), findsOneWidget);

    // Two of each channel now: the bulk card above the matrix carries a row per
    // channel too, and it labels them the same way on purpose. The switch count
    // is the same statement from the other side.
    expect(find.text('Push'), findsNWidgets(2));
    expect(find.text('Email'), findsNWidgets(2));
    expect(find.byType(WSwitch), findsNWidgets(4));
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

  testWidgets('the last channel row of a card carries no bottom border', (
    tester,
  ) async {
    fakeMatrix(pushProvisioned: true);

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Scoped to the per-type card: the bulk card above it renders the same row
    // shell, so an unscoped sweep counts four rows and the assertion below
    // stops describing one card.
    final List<WDiv> rows = tester
        .widgetList<WDiv>(
          find.descendant(
            of: find
                .byKey(const ValueKey('notifications.type.incident_opened')),
            matching: find.byType(WDiv),
          ),
        )
        .where((div) => div.className?.contains('px-6 py-4') ?? false)
        .toList();

    expect(rows, hasLength(2));

    // Wind implements no structural pseudo-variants, so `last:` is read as a
    // state name nothing activates: the class never fires, and because
    // `border-b-0` is itself a recognised token no debug hint appears either.
    // The card is `rounded-2xl overflow-hidden`, so the border the variant was
    // meant to remove runs into the clipped corner.
    for (final row in rows) {
      expect(row.className, isNot(contains('last:')));
    }

    expect(rows.first.className, contains('border-b'));
    expect(rows.last.className, isNot(contains('border-b')));
  });

  testWidgets('an enabled and a disabled channel chip resolve to one className',
      (tester) async {
    fakeMatrix(pushProvisioned: true);

    await tester
        .pumpWidget(wrap(Notify.view.make('notifications.preferences')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // The fixture ships mail enabled and push disabled, so the two chips
    // differ in exactly the state this assertion is about.
    final List<WDiv> chips = tester
        .widgetList<WDiv>(
          find.descendant(
            of: find
                .byKey(const ValueKey('notifications.type.incident_opened')),
            matching: find.byType(WDiv),
          ),
        )
        .where((div) => div.className?.contains('w-10 h-10') ?? false)
        .toList();

    expect(chips, hasLength(2));
    expect(chips.first.className, chips.last.className);
    expect(
      chips.where((chip) => chip.states?.contains('enabled') ?? false),
      hasLength(1),
    );

    // One className plus a state is only a fix if the state actually fires: a
    // mistyped state name would satisfy every assertion above and paint both
    // chips alike. Mail is enabled in the fixture and push is not, so their
    // glyphs must still differ exactly as they did when the tint was
    // interpolated into the string.
    final Icon enabledGlyph = tester.widget<Icon>(
      find
          .descendant(
            of: find
                .byKey(const ValueKey('notifications.type.incident_opened')),
            matching: find.byIcon(Icons.mail_outline),
          )
          .first,
    );
    final Icon disabledGlyph = tester.widget<Icon>(
      find
          .descendant(
            of: find
                .byKey(const ValueKey('notifications.type.incident_opened')),
            matching: find.byIcon(Icons.notifications_outlined),
          )
          .first,
    );

    expect(enabledGlyph.color, isNotNull);
    expect(enabledGlyph.color, isNot(disabledGlyph.color));
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
      // Two, because the bulk card carries a row for the same channel and the
      // exclusion applies to its label for the same reason.
      findsNWidgets(2),
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
