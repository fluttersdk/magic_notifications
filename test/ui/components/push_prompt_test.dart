import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/src/drivers/push/push_driver.dart';
import 'package:magic_notifications/src/facades/notify.dart';
import 'package:magic_notifications/src/models/push_prompt_advice.dart';
import 'package:magic_notifications/src/models/push_subscription.dart';
import 'package:magic_notifications/src/notification_manager.dart';
import 'package:magic_notifications/src/ui/components/push_prompt/push_prompt.dart';

import '../../test_helper.dart';

/// The vault key every test in this file gives [PushPromptHost].
///
/// A host supplies its own key; this is a test's stand-in for one.
const String _declinedVaultKey = 'test.push_prompt_declined';

/// Feeds the translator a literal map so the prompt lays out real labels.
class _MapTranslationLoader implements TranslationLoader {
  const _MapTranslationLoader(this.sentences);

  final Map<String, dynamic> sentences;

  @override
  Future<Map<String, dynamic>> load(Locale locale) async => sentences;
}

/// The sentences every test in this file lays out with.
const Map<String, dynamic> _sentences = <String, dynamic>{
  'notifications.push_prompt.unavailable_body':
      'Push is not available on this build.',
  'notifications.push_prompt.on_body':
      'This device can receive push notifications.',
  'notifications.push_prompt.blocked_title': 'Notifications are blocked',
  'notifications.push_prompt.blocked_body_settings':
      'Turn notifications back on in Settings.',
  'notifications.push_prompt.blocked_body_web':
      'Open the padlock icon in your browser bar to allow notifications.',
  'notifications.push_prompt.blocked_body_ios':
      'Open Settings > Notifications to allow notifications.',
  'notifications.push_prompt.blocked_body_android':
      'Open the app info screen to allow notifications.',
  'notifications.push_prompt.declined_body': 'You turned off this reminder.',
  'notifications.push_prompt.ask_title': 'Turn on notifications',
  'notifications.push_prompt.ask_body':
      'Get notified the moment something needs your attention.',
  'notifications.push_prompt.open_settings': 'Open settings',
  'notifications.push_prompt.enable': 'Enable',
  'notifications.push_prompt.not_now': 'Not now',
  'notifications.push_prompt.shell_notice': 'Push is off',
  'notifications.push_prompt.shell_notice_a11y': 'Push notifications are off',
};

/// A push driver double that records every permission request it is asked
/// for.
///
/// Contract inheritance rather than a mock package, matching
/// `notification_manager_reconcile_test.dart`'s `_RecordingPushDriver`. The
/// COUNT is the subject: the whole point of a soft prompt is that a decline
/// never reaches the platform, because the OS prompt fires once per install
/// and a declined one cannot be re-asked.
class _RecordingPushDriver extends PushDriver {
  _RecordingPushDriver({
    this.permission = PushPermissionState.notDetermined,
    this.optedIn = false,
    this.subscriptionId,
    this.opensPlatformSettings = false,
  });

  /// The permission the platform reports.
  final PushPermissionState permission;

  /// Whether this fake device is opted in.
  final bool optedIn;

  /// The subscription id the platform holds, or null for none.
  final String? subscriptionId;

  /// Whether a request on a DENIED device routes the user to the platform
  /// setting, which is the mobile `fallback_to_settings` capability. False is
  /// the browser, where no API opens the site settings panel from a page.
  final bool opensPlatformSettings;

  /// How many times [requestPermission] was called.
  int permissionRequests = 0;

  final StreamController<PushNotificationEvent> _received =
      StreamController<PushNotificationEvent>.broadcast();
  final StreamController<PushNotificationEvent> _clicked =
      StreamController<PushNotificationEvent>.broadcast();

  @override
  bool get canOpenPlatformSettings => opensPlatformSettings;

  @override
  String get name => 'test';

  @override
  bool get isSupported => true;

  @override
  bool get isOptedIn => optedIn;

  @override
  Future<PushPermissionState> permissionState() async => permission;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> login(String externalId) async {}

  @override
  Future<void> logout() async {}

  @override
  Future<String?> currentExternalId() async => 'user_u1';

  @override
  Future<String?> currentSubscriptionId() async => subscriptionId;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;

    return true;
  }

  @override
  Future<void> optIn() async {}

  @override
  Future<void> optOut() async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> removeTag(String key) async {}

  @override
  Stream<PushNotificationEvent> get onNotificationReceived => _received.stream;

  @override
  Stream<PushNotificationEvent> get onNotificationClicked => _clicked.stream;

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      const Stream<PushPermissionState>.empty();

  @override
  Stream<PushIdentityChange> get onIdentityChanged =>
      const Stream<PushIdentityChange>.empty();

  /// Closes the internal controllers. Registered through `addTearDown`.
  Future<void> dispose() async {
    await _received.close();
    await _clicked.close();
  }
}

/// A [_RecordingPushDriver] whose [requestPermission] throws.
///
/// Reproduces a platform SDK failure (a denied browser permission API, a
/// missing native module) so the row's boundary handling can be exercised
/// without a real device.
class _ThrowingRequestPushDriver extends _RecordingPushDriver {
  /// How many times [permissionState] was read; used to prove the row
  /// re-read the platform after the throw instead of getting stuck.
  int permissionStateReads = 0;

  @override
  Future<PushPermissionState> permissionState() async {
    permissionStateReads++;

    return super.permissionState();
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;

    throw StateError('push permission request failed');
  }
}

/// A [_RecordingPushDriver] whose [permissionState] always throws.
///
/// Reproduces a platform-channel failure on the very FIRST read, before any
/// tap: `reachability()` (the base class method the host's advice read
/// reaches) calls [permissionState] unconditionally, so a throw here
/// reproduces the boot-time defect rather than the enable-button one
/// [_ThrowingRequestPushDriver] covers.
class _ThrowingReachabilityPushDriver extends _RecordingPushDriver {
  @override
  Future<PushPermissionState> permissionState() async {
    throw StateError('permission state read failed');
  }
}

/// A driver whose reported state can change and whose change streams a test
/// can drive.
///
/// [_RecordingPushDriver] answers `const Stream.empty()` for both change
/// streams, which is exactly the condition a widget that never subscribes
/// cannot be told apart from. This double carries real broadcast controllers
/// so a grant that arrives OUT OF BAND can be delivered, which is how a grant
/// normally arrives: `requestPermission` on an already-denied device opens
/// the platform settings page rather than a dialog, so the permission
/// changes while the app is backgrounded.
class _LivePushDriver extends _RecordingPushDriver {
  _LivePushDriver({
    this.permissionNow = PushPermissionState.notDetermined,
    this.optedInNow = false,
    this.subscriptionIdNow,
  });

  /// The permission the platform reports right now.
  PushPermissionState permissionNow;

  /// Whether this fake device is opted in right now.
  bool optedInNow;

  /// The subscription id the platform holds right now, or null for none.
  String? subscriptionIdNow;

  final StreamController<PushPermissionState> _permissions =
      StreamController<PushPermissionState>.broadcast();

  final StreamController<PushIdentityChange> _identities =
      StreamController<PushIdentityChange>.broadcast();

  @override
  Future<PushPermissionState> permissionState() async => permissionNow;

  @override
  bool get isOptedIn => optedInNow;

  @override
  Future<String?> currentSubscriptionId() async => subscriptionIdNow;

  @override
  Stream<PushPermissionState> get onPermissionChanged => _permissions.stream;

  @override
  Stream<PushIdentityChange> get onIdentityChanged => _identities.stream;

  /// Turns this device into a subscribed one and announces it the way the SDK
  /// does: the permission first, then the subscription landing behind it.
  void grantAndSubscribe(String subscriptionId) {
    permissionNow = PushPermissionState.authorized;
    optedInNow = true;
    subscriptionIdNow = subscriptionId;
    _permissions.add(PushPermissionState.authorized);
    _identities.add(const PushIdentityChange(externalId: 'user_u1'));
  }

  /// Pushes an error onto the permission stream, the way the real driver does.
  void failPermissionRead() =>
      _permissions.addError(StateError('permission channel unavailable'));

  @override
  Future<void> dispose() async {
    await _permissions.close();
    await _identities.close();
    await super.dispose();
  }
}

/// A [_LivePushDriver] whose [permissionState] can be held open, so a test can
/// control exactly when a read that started earlier answers.
///
/// The generation-counter fix this double exercises is about ORDER, not
/// content: [holdNextPermissionRead] does not change what the platform would
/// have answered, only when the caller finds out.
class _RacePushDriver extends _LivePushDriver {
  Completer<PushPermissionState>? _held;

  /// Makes the NEXT call to [permissionState] wait on [completer] instead of
  /// resolving immediately.
  void holdNextPermissionRead(Completer<PushPermissionState> completer) {
    _held = completer;
  }

  /// Fires the permission-changed stream without moving [permissionNow], the
  /// way the widget's own listener has to re-read to find out what changed:
  /// the announcement carries no payload the widget trusts on its own.
  void announcePermissionChanged() => _permissions.add(permissionNow);

  @override
  Future<PushPermissionState> permissionState() async {
    final Completer<PushPermissionState>? held = _held;
    if (held != null) {
      _held = null;

      return held.future;
    }

    return super.permissionState();
  }
}

/// A [MagicVaultService] whose [put] throws, reproducing secure storage being
/// unavailable (a browser with no storage backend, a locked keychain).
class _ThrowingPutVaultService extends MagicVaultService {
  _ThrowingPutVaultService() : super.forTesting();

  /// How many times [put] was attempted.
  int putAttempts = 0;

  @override
  Future<void> put(String key, String value) async {
    putAttempts++;

    throw MagicVaultException('vault write failed', 'disk full');
  }

  @override
  Future<String?> get(String key) async => null;
}

/// Every reading `pushPromptAdvice` can actually produce, as the pair the row
/// renders from.
///
/// Reachability alone does not name a presentation: `blocked` splits on
/// whether this platform can route the tap back to a setting.
const List<(PushReachability, PushPromptAction)> _everyState =
    <(PushReachability, PushPromptAction)>[
  (PushReachability.off, PushPromptAction.request),
  (PushReachability.blocked, PushPromptAction.openSettings),
  (PushReachability.blocked, PushPromptAction.instructions),
  (PushReachability.on, PushPromptAction.none),
  (PushReachability.unavailable, PushPromptAction.none),
];

void main() {
  setUpAll(() async {
    await initMagicForTests();

    Translator.instance.setLoader(const _MapTranslationLoader(_sentences));
    await Translator.instance.load(const Locale('en'));
  });

  setUp(() {
    NotificationManager().forgetDrivers();
    // Every test here mounts a widget that reads or writes the vault on
    // mount (`PushPromptHost`), so this is faked globally rather than per
    // group.
    Vault.fake();
  });

  tearDown(() {
    NotificationManager().forgetDrivers();
    Vault.unfake();
  });

  /// Registers [driver] as the app's push rail, the way a consumer swaps one.
  void usePushDriver(_RecordingPushDriver driver) {
    Notify.extend(driver.name, () => driver);
    addTearDown(Notify.forgetDrivers);
    addTearDown(driver.dispose);
  }

  /// Wraps [widget] in a [MaterialApp] with a default [WindTheme].
  Widget wrap(Widget widget) {
    return MaterialApp(
      home: WindTheme(
        data: WindThemeData(),
        child: Scaffold(body: SingleChildScrollView(child: widget)),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // The blocked state: an instruction, never a control
  // ---------------------------------------------------------------------------

  group('the blocked state', () {
    testWidgets('renders the instruction row and no control at all', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const PushPrompt(
            reachability: PushReachability.blocked,
            action: PushPromptAction.instructions,
            onEnable: null,
          ),
        ),
      );

      // A blocked permission cannot be re-prompted from inside the app.
      // Where nothing can route the tap either, a control is one that does
      // nothing, so the row says where the switch actually lives instead.
      expect(find.byKey(PushPrompt.blockedInstructionKey), findsOneWidget);
      expect(find.byType(WButton), findsNothing);
      expect(
        find.text(trans('notifications.push_prompt.enable')),
        findsNothing,
      );
    });

    testWidgets(
      'canOpenPlatformSettings offers a real action instead of an instruction',
      (tester) async {
        final _RecordingPushDriver driver = _RecordingPushDriver(
          permission: PushPermissionState.denied,
          opensPlatformSettings: true,
        );
        usePushDriver(driver);

        await tester.pumpWidget(
          wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.open_settings')),
          findsOneWidget,
        );
        expect(find.byKey(PushPrompt.blockedInstructionKey), findsNothing);

        await tester.tap(
          find.text(trans('notifications.push_prompt.open_settings')),
        );
        await tester.pumpAndSettle();

        // The same call the enable control makes: the driver hands it
        // `canOpenPlatformSettings`, and the SDK turns it into the settings
        // page.
        expect(driver.permissionRequests, 1);
      },
    );

    testWidgets('the instruction is real copy, not a raw key', (tester) async {
      await tester.pumpWidget(
        wrap(
          const PushPrompt(
            reachability: PushReachability.blocked,
            action: PushPromptAction.instructions,
          ),
        ),
      );

      final WText instruction = tester.widget<WText>(
        find.descendant(
          of: find.byKey(PushPrompt.blockedInstructionKey),
          matching: find.byType(WText),
        ),
      );

      expect(instruction.data, isNotEmpty);
      expect(instruction.data, isNot(startsWith('notifications.')));
    });
  });

  // ---------------------------------------------------------------------------
  // The soft prompt: a decline never reaches the platform
  // ---------------------------------------------------------------------------

  group('the soft prompt', () {
    testWidgets('a decline does not call requestPermission', (tester) async {
      final _RecordingPushDriver driver = _RecordingPushDriver();
      usePushDriver(driver);

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(trans('notifications.push_prompt.not_now')));
      await tester.pumpAndSettle();

      // The OS prompt fires once per install; burning it on a decline leaves
      // the user with no way back to push at all.
      expect(driver.permissionRequests, 0);
    });

    testWidgets('a decline is recorded and leaves an explicit enable control', (
      tester,
    ) async {
      usePushDriver(_RecordingPushDriver());

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(trans('notifications.push_prompt.not_now')));
      await tester.pumpAndSettle();

      expect(await Vault.get(_declinedVaultKey), isNotNull);
      expect(
        find.text(trans('notifications.push_prompt.not_now')),
        findsNothing,
      );
      expect(
        find.text(trans('notifications.push_prompt.enable')),
        findsOneWidget,
      );
    });

    testWidgets('the explicit enable control does reach the platform', (
      tester,
    ) async {
      final _RecordingPushDriver driver = _RecordingPushDriver();
      usePushDriver(driver);

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(trans('notifications.push_prompt.enable')));
      await tester.pumpAndSettle();

      expect(driver.permissionRequests, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // A stale read must not undo a decline that landed after it started
  // ---------------------------------------------------------------------------

  group('a read overtaken by a decline', () {
    testWidgets(
      'a read that started before the decline but answers after it does not '
      'reopen the ask row',
      (tester) async {
        final _RacePushDriver driver = _RacePushDriver();
        usePushDriver(driver);

        await tester.pumpWidget(
          wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.ask_title')),
          findsOneWidget,
        );

        // 1. Hold the platform read the next `_read()` will make, then fire
        //    that re-read the way a permission event does. Its vault read
        //    lands with `declinedAt: null`, because the decline below has
        //    not written anything yet.
        final Completer<PushPermissionState> heldRead =
            Completer<PushPermissionState>();
        driver.holdNextPermissionRead(heldRead);
        driver.announcePermissionChanged();
        await tester.pump();

        // 2. The decline runs to completion while the read above is still
        //    in flight: it writes the vault, re-reads (its own platform read
        //    is no longer held), and lands the compact row.
        await tester.tap(
          find.text(trans('notifications.push_prompt.not_now')),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.enable')),
          findsOneWidget,
          reason: 'the decline landed first and must be on screen',
        );
        expect(
          find.text(trans('notifications.push_prompt.not_now')),
          findsNothing,
        );

        // 3. The held read now answers, carrying the pre-decline state. A
        //    generation counter must drop it rather than let it undo the
        //    decline that finished while it was still in flight.
        heldRead.complete(PushPermissionState.notDetermined);
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.enable')),
          findsOneWidget,
          reason: 'the stale read must not reopen the ask row',
        );
        expect(
          find.text(trans('notifications.push_prompt.not_now')),
          findsNothing,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The reminder cadence: the host owns the decline TIMESTAMP
  // ---------------------------------------------------------------------------

  group('the reminder cadence', () {
    /// The interval these cases drive, in hours. Deliberately not read from
    /// any config default: an assertion that took its expectation from the
    /// same value the code reads would pass for any shipped number.
    const int repromptHours = 20;

    setUp(() {
      Config.set(NotificationManager.repromptAfterHoursKey, repromptHours);
    });

    tearDown(() {
      Config.forget(NotificationManager.repromptAfterHoursKey);
    });

    /// Records a decline [ago] before now, the way the host persists one.
    Future<void> declinedAgo(Duration ago) async {
      await Vault.put(
        _declinedVaultKey,
        DateTime.now().toUtc().subtract(ago).toIso8601String(),
      );
    }

    testWidgets('a decline older than the interval is asked again', (
      tester,
    ) async {
      usePushDriver(_RecordingPushDriver());
      await declinedAgo(const Duration(hours: repromptHours + 1));

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      // The full soft prompt, decline control and all: the interval has
      // elapsed, so this device is due to be asked again rather than left
      // with the compact row a fresh decline leaves behind.
      expect(
        find.text(trans('notifications.push_prompt.ask_title')),
        findsOneWidget,
      );
      expect(
        find.text(trans('notifications.push_prompt.not_now')),
        findsOneWidget,
      );
    });

    testWidgets('a decline younger than the interval is not', (tester) async {
      usePushDriver(_RecordingPushDriver());
      await declinedAgo(const Duration(hours: repromptHours - 1));

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.ask_title')),
        findsNothing,
      );
      expect(
        find.text(trans('notifications.push_prompt.not_now')),
        findsNothing,
      );
      expect(
        find.text(trans('notifications.push_prompt.enable')),
        findsOneWidget,
      );
    });

    testWidgets(
      'a value written in some other shape reads as never declined, not '
      'migrated',
      (tester) async {
        // This widget only reads an ISO-8601 instant; a value some other
        // build wrote in a different shape (a bare `'1'`, say) is the HOST's
        // migration to make before it ever hands this widget the key, not
        // this widget's to repair. See [PushPromptHost.declinedVaultKey].
        usePushDriver(_RecordingPushDriver());
        await Vault.put(_declinedVaultKey, '1');

        await tester.pumpWidget(
          wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.ask_title')),
          findsOneWidget,
        );
        expect(
          find.text(trans('notifications.push_prompt.not_now')),
          findsOneWidget,
        );

        // And it is NOT rewritten: this widget only ever reads a timestamp.
        expect(await Vault.get(_declinedVaultKey), '1');
      },
    );

    testWidgets('a fresh decline is recorded as a timestamp', (tester) async {
      usePushDriver(_RecordingPushDriver());

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(trans('notifications.push_prompt.not_now')));
      await tester.pumpAndSettle();

      final String? stored = await Vault.get(_declinedVaultKey);

      expect(DateTime.tryParse(stored ?? ''), isNotNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Two dropped futures on a boundary
  // ---------------------------------------------------------------------------

  group('a failing vault write on decline', () {
    testWidgets(
      'is handled, not an unhandled async error, and the decline is not '
      'reported as having worked',
      (tester) async {
        usePushDriver(_RecordingPushDriver());
        final _ThrowingPutVaultService throwingVault =
            _ThrowingPutVaultService();
        Magic.app.setInstance('vault', throwingVault);
        addTearDown(() => Magic.app.removeInstance('vault'));

        await tester.pumpWidget(
          wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.text(trans('notifications.push_prompt.not_now')),
        );
        await tester.pumpAndSettle();

        // The throwing put() must not escape as an unhandled async error.
        expect(tester.takeException(), isNull);
        expect(throwingVault.putAttempts, 1);

        // The decline never landed, so the row must not claim it did.
        expect(
          find.text(trans('notifications.push_prompt.not_now')),
          findsOneWidget,
        );
        expect(
          find.text(trans('notifications.push_prompt.ask_title')),
          findsOneWidget,
        );
      },
    );
  });

  group('an initial reachability read that throws', () {
    testWidgets(
      'is handled, not an unhandled async error, and the row does not stay '
      'blank',
      (tester) async {
        usePushDriver(_ThrowingReachabilityPushDriver());

        await tester.pumpWidget(
          wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(PushPrompt), findsOneWidget);
      },
    );
  });

  group('a failing requestPushPermission on enable', () {
    testWidgets('is handled and the row still refreshes', (tester) async {
      final _ThrowingRequestPushDriver driver = _ThrowingRequestPushDriver();
      usePushDriver(driver);

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      final int readsBeforeTap = driver.permissionStateReads;

      await tester.tap(find.text(trans('notifications.push_prompt.enable')));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(driver.permissionRequests, 1);

      // The row must have re-read the platform after the throw, proving it
      // did not get stuck on the spinner.
      expect(driver.permissionStateReads, greaterThan(readsBeforeTap));
    });
  });

  // ---------------------------------------------------------------------------
  // A config key that gates the whole prompt
  // ---------------------------------------------------------------------------

  group('notifications.soft_prompt.enabled', () {
    tearDown(() => Config.forget(NotificationManager.softPromptEnabledKey));

    testWidgets('false renders no prompt at all', (tester) async {
      Config.set(NotificationManager.softPromptEnabledKey, false);
      usePushDriver(_RecordingPushDriver());

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PushPrompt), findsNothing);
    });

    testWidgets('true (the default) still renders the prompt', (
      tester,
    ) async {
      Config.set(NotificationManager.softPromptEnabledKey, true);
      usePushDriver(_RecordingPushDriver());

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PushPrompt), findsOneWidget);
    });
  });

  // ---------------------------------------------------------------------------
  // The host reads reachability rather than declaring it
  // ---------------------------------------------------------------------------

  group('the host', () {
    testWidgets('renders the blocked row for a denied permission', (
      tester,
    ) async {
      usePushDriver(
        _RecordingPushDriver(permission: PushPermissionState.denied),
      );

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(PushPrompt.blockedInstructionKey), findsOneWidget);
    });

    testWidgets('renders the on row for a subscribed device', (tester) async {
      usePushDriver(
        _RecordingPushDriver(
          permission: PushPermissionState.authorized,
          optedIn: true,
          subscriptionId: 'sub-1',
        ),
      );

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.on_body')),
        findsOneWidget,
      );
      expect(find.byType(WButton), findsNothing);
    });

    testWidgets('a grant arriving out of band clears the ask row', (
      tester,
    ) async {
      final _LivePushDriver driver = _LivePushDriver();
      usePushDriver(driver);

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.ask_title')),
        findsOneWidget,
        reason: 'a device with no decision yet is asked',
      );

      driver.grantAndSubscribe('sub-1');
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.on_body')),
        findsOneWidget,
      );
      expect(
        find.text(trans('notifications.push_prompt.ask_title')),
        findsNothing,
      );
    });

    testWidgets('a failed permission read is logged, not thrown at the zone', (
      tester,
    ) async {
      final FakeLogManager log = Log.fake();
      final _LivePushDriver driver = _LivePushDriver(
        permissionNow: PushPermissionState.authorized,
        optedInNow: true,
        subscriptionIdNow: 'sub-1',
      );
      usePushDriver(driver);

      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      driver.failPermissionRead();
      await tester.pumpAndSettle();

      expect(
        log.entries
            .where(
              (FakeLogEntry entry) => entry.message.contains(
                '[PushPromptHost] permission stream failed',
              ),
            )
            .length,
        1,
      );
      expect(
        find.text(trans('notifications.push_prompt.on_body')),
        findsOneWidget,
      );
    });

    testWidgets('renders the unavailable row when the build has no driver', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.unavailable_body')),
        findsOneWidget,
      );
    });
  });

  // ---------------------------------------------------------------------------
  // A driver that resolves after the widget already mounted
  // ---------------------------------------------------------------------------

  group('a driver attached after mount', () {
    testWidgets(
      'PushPromptHost re-reads on onPushDriverAttached and then follows '
      'the new driver own streams',
      (tester) async {
        await tester.pumpWidget(
          wrap(const PushPromptHost(declinedVaultKey: _declinedVaultKey)),
        );
        await tester.pumpAndSettle();

        // No driver at mount: the row reads unavailable, not stuck blank.
        expect(
          find.text(trans('notifications.push_prompt.unavailable_body')),
          findsOneWidget,
        );

        final _LivePushDriver driver = _LivePushDriver();
        addTearDown(driver.dispose);
        Notify.manager.setPushDriver(driver);
        await tester.pumpAndSettle();

        // The late attachment is picked up without a remount.
        expect(
          find.text(trans('notifications.push_prompt.ask_title')),
          findsOneWidget,
        );

        // Proves the widget wired itself to THIS driver's own streams, not
        // only the one (absent) at initState.
        driver.grantAndSubscribe('sub-1');
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.on_body')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'PushOffNotice re-reads on onPushDriverAttached and then follows the '
      'new driver own streams',
      (tester) async {
        await tester.pumpWidget(wrap(PushOffNotice(onOpenPreferences: () {})));
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.shell_notice')),
          findsNothing,
        );

        final _LivePushDriver driver = _LivePushDriver();
        addTearDown(driver.dispose);
        Notify.manager.setPushDriver(driver);
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.shell_notice')),
          findsOneWidget,
        );

        driver.grantAndSubscribe('sub-1');
        await tester.pumpAndSettle();

        expect(
          find.text(trans('notifications.push_prompt.shell_notice')),
          findsNothing,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // The shell notice: push being off is visible OUTSIDE the settings screen
  // ---------------------------------------------------------------------------

  group('the shell notice', () {
    testWidgets('warns while the permission has not been granted', (
      tester,
    ) async {
      usePushDriver(_RecordingPushDriver());

      await tester.pumpWidget(wrap(PushOffNotice(onOpenPreferences: () {})));
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.shell_notice')),
        findsOneWidget,
      );
    });

    testWidgets('warns while the permission is blocked', (tester) async {
      usePushDriver(
        _RecordingPushDriver(permission: PushPermissionState.denied),
      );

      await tester.pumpWidget(wrap(PushOffNotice(onOpenPreferences: () {})));
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.shell_notice')),
        findsOneWidget,
      );
    });

    testWidgets('says nothing when push can reach this device', (tester) async {
      usePushDriver(
        _RecordingPushDriver(
          permission: PushPermissionState.authorized,
          optedIn: true,
          subscriptionId: 'sub-1',
        ),
      );

      await tester.pumpWidget(wrap(PushOffNotice(onOpenPreferences: () {})));
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.shell_notice')),
        findsNothing,
      );
    });

    testWidgets('says nothing when this build has no push at all', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(PushOffNotice(onOpenPreferences: () {})));
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.shell_notice')),
        findsNothing,
      );
    });

    testWidgets('the compact form carries the same accessible name', (
      tester,
    ) async {
      final SemanticsHandle semantics = tester.ensureSemantics();
      usePushDriver(_RecordingPushDriver());

      await tester.pumpWidget(
        wrap(PushOffNotice(compact: true, onOpenPreferences: () {})),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(trans('notifications.push_prompt.shell_notice')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(
          trans('notifications.push_prompt.shell_notice_a11y'),
        ),
        findsOneWidget,
      );

      semantics.dispose();
    });

    testWidgets('a tap calls onOpenPreferences exactly once', (tester) async {
      int calls = 0;
      usePushDriver(_RecordingPushDriver());

      await tester.pumpWidget(
        wrap(PushOffNotice(onOpenPreferences: () => calls++)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.text(trans('notifications.push_prompt.shell_notice')),
      );
      await tester.pumpAndSettle();

      expect(calls, 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Every state
  // ---------------------------------------------------------------------------

  testWidgets('every state lays out with no exception', (tester) async {
    for (final (PushReachability, PushPromptAction) state in _everyState) {
      await tester.pumpWidget(
        wrap(
          PushPrompt(
            reachability: state.$1,
            action: state.$2,
            onEnable: () async {},
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    }
  });
}
