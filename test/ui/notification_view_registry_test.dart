import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/facades/notify.dart';
import 'package:magic_notifications/src/models/database_notification.dart';
import 'package:magic_notifications/src/ui/components/notification_dropdown/notification_dropdown.dart';
import 'package:magic_notifications/src/ui/notification_view_registry.dart';
import 'package:magic_notifications/src/ui/views/notification_preferences_view.dart';
import 'package:magic_notifications/src/ui/views/notifications_list_view.dart';

import '../test_helper.dart';

void main() {
  setUpAll(() async {
    await initMagicForTests();
  });

  Widget wrap(Widget child) {
    return MaterialApp(
      home: WindTheme(data: WindThemeData(), child: Scaffold(body: child)),
    );
  }

  DatabaseNotification makeNotification({required String type}) {
    final now = DateTime.now();

    return DatabaseNotification(
      id: 'n-${now.microsecondsSinceEpoch}',
      type: type,
      title: 'Test title',
      body: 'Test body',
      data: const <String, dynamic>{},
      createdAt: now,
    );
  }

  group('NotificationViewRegistry', () {
    late NotificationViewRegistry registry;

    setUp(() {
      registry = NotificationViewRegistry();
    });

    test('register() makes a builder resolvable by key', () {
      registry.register('notifications.list', () => const SizedBox.shrink());

      expect(registry.has('notifications.list'), isTrue);
      expect(registry.make('notifications.list'), isA<SizedBox>());
    });

    test('has() is false for an unregistered key', () {
      expect(registry.has('nope'), isFalse);
    });

    test('make() throws a StateError for an unregistered key', () {
      expect(() => registry.make('nope'), throwsA(isA<StateError>()));
    });

    test('registerLayout() makes a layout resolvable by key', () {
      registry.registerLayout(
        'layout.app',
        (child) => Padding(padding: const EdgeInsets.all(8), child: child),
      );

      expect(registry.hasLayout('layout.app'), isTrue);
      expect(
        registry.makeLayout('layout.app', child: const SizedBox.shrink()),
        isA<Padding>(),
      );
    });

    test('makeLayout() throws a StateError for an unregistered key', () {
      expect(
        () => registry.makeLayout('nope', child: const SizedBox.shrink()),
        throwsA(isA<StateError>()),
      );
    });

    test('registerModal() makes a modal resolvable by key', () {
      registry.registerModal('modal.confirm', () => const SizedBox.shrink());

      expect(registry.hasModal('modal.confirm'), isTrue);
      expect(registry.makeModal('modal.confirm'), isA<SizedBox>());
    });

    test('makeModal() throws a StateError for an unregistered key', () {
      expect(() => registry.makeModal('nope'), throwsA(isA<StateError>()));
    });

    testWidgets('slot() builds under the composed view.slot key', (
      tester,
    ) async {
      registry.slot(
        'notifications.list',
        'header',
        (context) => const Text('slot header'),
      );

      expect(registry.hasSlot('notifications.list', 'header'), isTrue);
      expect(registry.hasSlot('notifications.list', 'footer'), isFalse);

      late Widget? built;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              built = registry.buildSlot(
                'notifications.list',
                'header',
                context,
              );
              return built ?? const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(built, isNotNull);
      expect(find.text('slot header'), findsOneWidget);
    });

    testWidgets('buildSlot() answers null for an unregistered slot', (
      tester,
    ) async {
      late Widget? built;
      await tester.pumpWidget(
        wrap(
          Builder(
            builder: (context) {
              built = registry.buildSlot('notifications.list', 'nope', context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(built, isNull);
    });

    test('clear() drops builders, layouts, modals and slots', () {
      registry.register('notifications.list', () => const SizedBox.shrink());
      registry.registerLayout('layout.app', (child) => child);
      registry.registerModal('modal.confirm', () => const SizedBox.shrink());
      registry.slot('notifications.list', 'header', (_) => const SizedBox());

      registry.clear();

      expect(registry.has('notifications.list'), isFalse);
      expect(registry.hasLayout('layout.app'), isFalse);
      expect(registry.hasModal('modal.confirm'), isFalse);
      expect(registry.hasSlot('notifications.list', 'header'), isFalse);
    });
  });

  group('Notify.view', () {
    test('ships the package views under their documented keys', () {
      expect(Notify.view.has('notifications.list'), isTrue);
      expect(Notify.view.has('notifications.preferences'), isTrue);
    });

    test('resolves the package views by key', () {
      expect(
          Notify.view.make('notifications.list'), isA<NotificationsListView>());
      expect(
        Notify.view.make('notifications.preferences'),
        isA<NotificationPreferencesView>(),
      );
    });

    test('a host registration replaces the package default', () {
      addTearDown(() {
        Notify.view.register(
          'notifications.list',
          () => const NotificationsListView(),
        );
      });

      Notify.view.register('notifications.list', () => const SizedBox.shrink());

      expect(Notify.view.make('notifications.list'), isA<SizedBox>());
    });
  });

  group('notification type icon slot', () {
    late StreamController<List<DatabaseNotification>> stream;

    setUp(() {
      stream = StreamController<List<DatabaseNotification>>.broadcast();
    });

    tearDown(() async {
      await stream.close();
    });

    testWidgets('falls back to the package icon with no slot registered', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(NotificationDropdown(notificationStream: stream.stream)),
      );

      stream.add([makeNotification(type: 'order_shipped')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byIcon(Icons.notifications_none_outlined), findsOneWidget);
    });

    testWidgets('renders the adopter widget registered for the type', (
      tester,
    ) async {
      Notify.view.slot(
        NotificationViewRegistry.typeIconSlotView,
        'monitor_down',
        (context) => const Icon(Icons.bolt, key: ValueKey('adopter-icon')),
      );

      await tester.pumpWidget(
        wrap(NotificationDropdown(notificationStream: stream.stream)),
      );

      stream.add([makeNotification(type: 'monitor_down')]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.notifications_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('adopter-icon')), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none_outlined), findsNothing);
    });
  });
}
