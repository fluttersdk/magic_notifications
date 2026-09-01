import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/models/database_notification.dart';
import 'package:magic_notifications/src/ui/components/notification_dropdown/notification_dropdown.dart';
import 'package:magic_notifications/src/ui/components/notification_dropdown/notification_dropdown.preview.dart';
import 'package:magic_notifications/src/ui/components/notification_dropdown/notification_dropdown.recipe.dart';

import '../../test_helper.dart';

/// Feeds the translator a literal map so the popover lays out real labels.
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
        'notifications.title': 'Notifications',
        'notifications.mark_all_read': 'Mark all as read',
        'notifications.empty': 'Nothing here yet',
        'notifications.load_failed': 'Could not load notifications',
        'notifications.badge_overflow': '9+',
        'notifications.view_all': 'View all',
      }),
    );

    await Translator.instance.load(const Locale('en'));
  });

  late StreamController<List<DatabaseNotification>> streamController;

  setUp(() {
    streamController = StreamController<List<DatabaseNotification>>.broadcast();
  });

  tearDown(() async {
    await streamController.close();
  });

  DatabaseNotification makeNotification({bool isRead = false}) {
    final now = DateTime.now();
    return DatabaseNotification.fromMap({
      'id': 'test-id-${now.microsecondsSinceEpoch}',
      'type': 'monitor_down',
      'data': {'title': 'Test Notification', 'body': 'Test body'},
      'read_at': isRead ? now.toIso8601String() : null,
      'created_at': now.toIso8601String(),
    });
  }

  Widget wrap(Widget child, {TextScaler textScaler = TextScaler.noScaling}) {
    return MaterialApp(
      home: WindTheme(
        data: WindThemeData(),
        child: Scaffold(
          body: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders the bell icon', (tester) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);

    streamController.add([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('shows the unread badge when unread count is greater than zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([
      makeNotification(),
      makeNotification(),
      makeNotification(isRead: true),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('hides the badge when every notification is read', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([
      makeNotification(isRead: true),
      makeNotification(isRead: true),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('0'), findsNothing);
    expect(find.text('1'), findsNothing);
    expect(find.text('2'), findsNothing);
  });

  testWidgets('renders the empty state in the popover content', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Nothing here yet'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
  });

  testWidgets(
    'the unread badge stays inside its pill at an accessibility text scale',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          NotificationDropdown(notificationStream: streamController.stream),
          textScaler: const TextScaler.linear(3.0),
        ),
      );

      streamController.add([makeNotification(), makeNotification()]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final Finder count = find.text('2');

      // The pill is a fixed-height box, so the digit's own render box is
      // CONSTRAINT-clamped to that height whether or not the glyph fits: at a
      // 3.0 scale the box still measures 14.0 while the line paints at 39.0.
      // The intrinsic height is the only honest reading of what the text
      // actually needs, so the assertion goes against that, not against
      // `digit.size.height`, which would pass vacuously.
      final Size pill = tester.getSize(
        find.ancestor(of: count, matching: find.byType(WDiv)).first,
      );
      final RenderBox digit = tester.renderObject<RenderBox>(count);
      final double needed = digit.getMaxIntrinsicHeight(digit.size.width);

      expect(needed, lessThanOrEqualTo(pill.height));
    },
  );

  testWidgets('the styling seam reaches the trigger, badge and panel', (
    tester,
  ) async {
    const String triggerClassName = 'p-2 rounded-lg bg-transparent';
    const String triggerIconClassName = 'text-[18px] text-primary';
    const String badgeClassName = '''
      min-w-[14px] h-[14px] px-1 rounded-full
      bg-primary
      flex items-center justify-center
    ''';
    const String badgeTextClassName = 'text-[9px] font-bold text-black';
    const String panelClassName = 'w-96 bg-primary rounded-md';

    await tester.pumpWidget(
      wrap(
        NotificationDropdown(
          notificationStream: streamController.stream,
          triggerClassName: triggerClassName,
          triggerIconClassName: triggerIconClassName,
          badgeClassName: badgeClassName,
          badgeTextClassName: badgeTextClassName,
          panelClassName: panelClassName,
        ),
      ),
    );

    streamController.add([makeNotification()]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byWidgetPredicate(
        (w) => w is WPopover && w.className == panelClassName,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is WDiv && w.className == triggerClassName,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is WIcon && w.className == triggerIconClassName,
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate((w) => w is WDiv && w.className == badgeClassName),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is WText && w.className == badgeTextClassName,
      ),
      findsOneWidget,
    );
  });

  testWidgets('a read and an unread row resolve to one className', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([
      makeNotification(),
      makeNotification(isRead: true),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final List<WDiv> rows = tester
        .widgetList<WDiv>(find.byType(WDiv))
        .where((div) => div.className?.contains('items-start') ?? false)
        .toList();

    expect(rows, hasLength(2));

    // Two classNames for one row shape is two parser cache keys per row, so a
    // list of twenty notifications parses twice as many variants as it has
    // shapes. The unread difference belongs in `states:`, which the parser
    // resolves against ONE cached string.
    expect(rows.first.className, rows.last.className);
    expect(
      rows.where((row) => row.states?.contains('unread') ?? false),
      hasLength(1),
    );

    // One className plus a state is only a fix if the state actually fires; a
    // mistyped state name would satisfy every assertion above and render both
    // rows identically. The unread title is the one that paints heavier, as it
    // did when the weight was interpolated into the string.
    final List<FontWeight?> weights = tester
        .widgetList<Text>(find.text('Test Notification'))
        .map((text) => text.style?.fontWeight)
        .toList();

    expect(weights, hasLength(2));
    expect(weights.toSet(), hasLength(2));
    expect(weights, contains(FontWeight.w600));
  });

  testWidgets('the unread row tint carries its dark peer', (tester) async {
    await tester.pumpWidget(
      wrap(NotificationDropdown(notificationStream: streamController.stream)),
    );

    streamController.add([makeNotification()]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final WDiv row = tester
        .widgetList<WDiv>(find.byType(WDiv))
        .firstWhere((div) => div.className?.contains('items-start') ?? false);

    // A structural check over the className string, not a rendered colour: the
    // widget test runs in one brightness, so the dark half of every pair is
    // unreachable by rendering and only the string can carry the assertion.
    expect(row.className, contains('unread:bg-primary/5'));
    expect(row.className, contains('dark:unread:bg-primary/10'));
  });

  testWidgets('the mark-all-as-read hover stays on the adopter brand', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        NotificationDropdown(
          notificationStream: streamController.stream,
          onMarkAllAsRead: () async {},
        ),
      ),
    );

    streamController.add([makeNotification()]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final WText action = tester.widget<WText>(
      find.byWidgetPredicate(
        (widget) => widget is WText && widget.data == 'Mark all as read',
      ),
    );

    // `text-primary` resolves to the ADOPTER's brand, so a hover jumping to a
    // fixed palette green reads as deliberate only while the adopter happens to
    // be green. Structural again: hover is a rendered state this test does not
    // enter, so the assertion is over the token, not over a painted colour.
    expect(action.className, contains('hover:text-primary'));
    expect(action.className, isNot(contains('green')));
  });

  group('NotificationDropdown defaults — dark-mode pairing', () {
    /// Asserts every colour [families] in [className] declares both a light
    /// token and a `dark:` peer of the same family.
    ///
    /// This is a structural check over the default string rather than a
    /// rendered one: a widget test paints in a single brightness, so the dark
    /// half of a pair can only be asserted as a token.
    void expectDarkPeers(String className, {required Set<String> families}) {
      final List<String> tokens = className
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .toList();

      for (final family in families) {
        expect(
          tokens.where(
            (token) => token.startsWith('$family-'),
          ),
          isNotEmpty,
          reason: 'expected a light-mode $family- token',
        );
        expect(
          tokens.where((token) => token.startsWith('dark:$family-')),
          isNotEmpty,
          reason: 'expected a dark: peer for the $family- token',
        );
      }
    }

    test('the badge pill pairs its background', () {
      expectDarkPeers(
        kNotificationDropdownBadgeClassName,
        families: <String>{'bg'},
      );
    });

    test('the badge count pairs its text colour', () {
      expectDarkPeers(
        kNotificationDropdownBadgeTextClassName,
        families: <String>{'text'},
      );
    });

    test('the panel, trigger and glyph keep the pairing they already had', () {
      expectDarkPeers(
        kNotificationDropdownPanelClassName,
        families: <String>{'bg', 'border'},
      );
      expectDarkPeers(
        kNotificationDropdownTriggerClassName,
        families: <String>{'hover:bg'},
      );
      expectDarkPeers(
        kNotificationDropdownTriggerIconClassName,
        families: <String>{'text'},
      );
    });
  });

  testWidgets('the dropdown preview renders without error', (tester) async {
    await tester.pumpWidget(wrap(const NotificationDropdownPreview()));
    await tester.pump();

    expect(find.byType(NotificationDropdownPreview), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
