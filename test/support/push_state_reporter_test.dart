import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

import '../test_helper.dart';

/// A push driver whose permission, subscription and identity a test moves by
/// hand, announcing each move the way the platform SDK does.
class _ReportingPushDriver extends PushDriver {
  /// The two change streams the reporter watches. Broadcast because the
  /// manager attaches to them at registration and the reporter attaches
  /// beside it.
  final StreamController<PushPermissionState> _permissionChanges =
      StreamController<PushPermissionState>.broadcast();
  final StreamController<PushIdentityChange> _identityChanges =
      StreamController<PushIdentityChange>.broadcast();

  /// When true, every `login` throws the way a failed SDK call does, so the
  /// device keeps carrying nobody.
  bool failLogin = false;

  /// The platform permission this device currently holds.
  PushPermissionState permission = PushPermissionState.authorized;

  /// The subscription id the platform holds, or null for a device with no
  /// address at all.
  String? subscriptionId = 'sub-phone';

  /// The external id this fake device carries, read back the way a real SDK
  /// does so the manager's reconcile is not fooled.
  String? _externalId;

  /// Reports a permission change the way the OS does with the app open.
  void changePermission(PushPermissionState next) {
    permission = next;
    _permissionChanges.add(next);
  }

  /// Reports the SDK swapping this device's push subscription.
  void changeSubscription(String? next) {
    subscriptionId = next;
    _identityChanges.add(PushIdentityChange(subscriptionId: next));
  }

  /// Closes both controllers, so a stream does not outlive its test.
  Future<void> dispose() async {
    await _permissionChanges.close();
    await _identityChanges.close();
  }

  @override
  String get name => 'onesignal';

  @override
  bool get isSupported => true;

  @override
  bool get isOptedIn => true;

  @override
  Future<PushPermissionState> permissionState() async => permission;

  @override
  Future<void> initialize(Map<String, dynamic> config) async {}

  @override
  Future<void> login(String externalId) async {
    if (failLogin) throw StateError('the SDK refused the login');

    _externalId = externalId;
  }

  @override
  Future<void> logout() async {
    _externalId = null;
  }

  @override
  Future<String?> currentExternalId() async => _externalId;

  @override
  Future<String?> currentSubscriptionId() async => subscriptionId;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> optIn() async {}

  @override
  Future<void> optOut() async {}

  @override
  Future<void> setTags(Map<String, String> tags) async {}

  @override
  Future<void> removeTag(String key) async {}

  @override
  Stream<PushNotificationEvent> get onNotificationReceived =>
      const Stream<PushNotificationEvent>.empty();

  @override
  Stream<PushNotificationEvent> get onNotificationClicked =>
      const Stream<PushNotificationEvent>.empty();

  @override
  Stream<PushPermissionState> get onPermissionChanged =>
      _permissionChanges.stream;

  @override
  Stream<PushIdentityChange> get onIdentityChanged => _identityChanges.stream;
}

/// A user model the fake auth guard can hold.
class _User extends Model with Authenticatable {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';

  @override
  List<String> get fillable => <String>['id'];
}

void main() {
  /// The endpoint a report is posted to, as the app configures it.
  const String reportPath = '/devices/push-state';

  /// The endpoint a sign-out releases this device through.
  const String releasePath = '/devices/push-state/release';

  setUpAll(() async {
    await initMagicForTests();
  });

  setUp(() {
    Notify.forgetDrivers();
    Config.set('notifications.push_state.report_path', reportPath);
    Config.set('notifications.push_state.release_path', releasePath);
    Config.set('notifications.push_state.external_id_prefix', null);
  });

  tearDown(() {
    Notify.forgetDrivers();
    Auth.unfake();
  });

  /// Installs [driver] as the push rail.
  _ReportingPushDriver useDriver([_ReportingPushDriver? driver]) {
    final _ReportingPushDriver installed = driver ?? _ReportingPushDriver();
    Notify.manager.setPushDriver(installed);
    addTearDown(installed.dispose);

    return installed;
  }

  /// A persisted user carrying [id].
  _User makeUser(String id) {
    return _User()
      ..fill(<String, dynamic>{'id': id})
      ..exists = true;
  }

  /// Signs [id] in on a fresh fake guard.
  void signIn(String id) {
    Auth.fake(user: makeUser(id));
  }

  /// Every report this device has posted, in order. Matched on the END of the
  /// url because the release path extends this one.
  List<Map<String, dynamic>> reports(FakeNetworkDriver network) {
    return network.recorded
        .where((entry) => entry.$1.url.endsWith(reportPath))
        .map((entry) => entry.$1.data as Map<String, dynamic>)
        .toList();
  }

  /// Every release this device has posted, in order.
  List<Map<String, dynamic>> releases(FakeNetworkDriver network) {
    return network.recorded
        .where((entry) => entry.$1.url.endsWith(releasePath))
        .map((entry) => entry.$1.data as Map<String, dynamic>)
        .toList();
  }

  /// Declares [externalId] again, which is what a starter kit does on every
  /// auth bump, and lets the reconcile pass behind it settle.
  Future<void> redeclare(String externalId) async {
    await Notify.initializePush(externalId);
    await pumpEventQueue();
  }

  /// Signs `u1` in, arms the watch and lets the declaration settle.
  Future<void> declareIdentity() async {
    signIn('u1');
    Notify.pushState.watch();
    await redeclare('user_u1');
  }

  group('configuration', () {
    test('both paths set reads as configured', () {
      expect(Notify.pushState.isConfigured, isTrue);
    });

    test('an absent report path reads as not configured', () {
      Config.set('notifications.push_state.report_path', null);

      expect(Notify.pushState.isConfigured, isFalse);
    });

    test('a blank report path reads as not configured', () {
      Config.set('notifications.push_state.report_path', '  ');

      expect(Notify.pushState.isConfigured, isFalse);
    });

    test('an absent report path sends nothing at all', () async {
      // No default path: an app whose backend has no such endpoint must not
      // be posting a 404 on every sign-in.
      Config.set('notifications.push_state.report_path', null);
      Config.set('notifications.push_state.release_path', null);
      final FakeNetworkDriver network = Http.fake();
      useDriver();

      await declareIdentity();
      await Notify.pushState.release();

      expect(
        network.recorded.where((entry) => entry.$1.url.contains('push-state')),
        isEmpty,
      );
    });

    test('an absent release path releases nothing', () async {
      Config.set('notifications.push_state.release_path', null);
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Notify.pushState.release();

      expect(reports(network), hasLength(1));
      expect(
        network.recorded.where((entry) => entry.$1.url.endsWith('release')),
        isEmpty,
      );
    });

    test('the report is posted to the configured path, verbatim', () async {
      Config.set('notifications.push_state.report_path', '/me/device');
      final FakeNetworkDriver network = Http.fake();
      useDriver();

      await declareIdentity();

      expect(network.recorded.single.$1.url, '/me/device');
    });

    test('a configured prefix decides which pass is the signed-in person',
        () async {
      Config.set('notifications.push_state.external_id_prefix', 'member_');
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      signIn('u1');
      Notify.pushState.watch();

      await redeclare('user_u1');
      expect(reports(network), isEmpty);

      await redeclare('member_u1');
      expect(reports(network).single['external_id'], 'member_u1');
    });
  });

  group('the report follows a reconcile pass for the signed-in person', () {
    test('a pass reconciled towards user_<current id> posts one report',
        () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      signIn('u1');
      Notify.pushState.watch();

      await redeclare('user_u1');

      expect(reports(network), hasLength(1));
      expect(reports(network).single['external_id'], 'user_u1');
    });

    test('a pass reconciled towards somebody else posts nothing', () async {
      // The server refuses a report under an alias that is not the session's,
      // so posting would buy a 422 and nothing else.
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      signIn('u1');
      Notify.pushState.watch();

      await redeclare('user_u2');

      expect(reports(network), isEmpty);
    });

    test('a pass that declares nobody posts nothing', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      signIn('u1');
      Notify.pushState.watch();

      await Notify.logoutPush();
      await pumpEventQueue();

      expect(reports(network), isEmpty);
    });

    test('a failed pass still reports', () async {
      // A converged-only trigger would leave the server vouching for
      // whatever it held before.
      final FakeNetworkDriver network = Http.fake();
      useDriver(_ReportingPushDriver()..failLogin = true);
      signIn('u1');
      Notify.pushState.watch();

      await redeclare('user_u1');

      expect(reports(network), hasLength(1));
      expect(reports(network).single['external_id'], isNull);
    });
  });

  group('the wire shape', () {
    test('a signed-in device posts the package shape, not a second one',
        () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();

      await declareIdentity();

      expect(reports(network), hasLength(1));
      final Map<String, dynamic> body = reports(network).single;
      expect(body.keys.toSet(), <String>{
        'external_id',
        'subscription_id',
        'reachability',
        'captured_at',
      });
      expect(body['reachability'], 'on');
      expect(body['external_id'], 'user_u1');
      expect(body['subscription_id'], 'sub-phone');
      expect(DateTime.tryParse(body['captured_at'] as String), isNotNull);
    });

    test('a sign-out names this device, and nothing else about it', () async {
      // The person comes from the SESSION on the server side, so a body naming
      // one would be a second, weaker answer to a question the token settles.
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Notify.pushState.release();

      expect(releases(network), hasLength(1));
      expect(releases(network).single, <String, dynamic>{
        'subscription_id': 'sub-phone',
      });
    });
  });

  group('the memo goes with the session', () {
    test('a device whose state has not moved does not post again', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();

      await declareIdentity();
      await redeclare('user_u1');

      expect(reports(network), hasLength(1));
    });

    test('a report the server refused is made again, not remembered', () async {
      final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
        reportPath: Http.response(<String, dynamic>{'message': 'nope'}, 500),
      });
      useDriver();

      await declareIdentity();
      await redeclare('user_u1');

      expect(reports(network), hasLength(2));
    });

    test('a sign-out lets the next person report an identical device state',
        () async {
      // Two people share one handset, and a failing SDK leaves the device
      // carrying nobody for both, so their states are byte-identical. The
      // reset hangs off `AuthLogout`, which every sign-out path dispatches.
      final FakeNetworkDriver network = Http.fake();
      useDriver(_ReportingPushDriver()..failLogin = true);
      Auth.fake();
      Notify.pushState.watch();

      signIn('u1');
      await redeclare('user_u1');

      await Auth.logout();
      await pumpEventQueue();

      signIn('u2');
      await redeclare('user_u2');

      expect(reports(network), hasLength(2));
    });

    test('the next person on a shared device reports for themselves', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Auth.logout();
      await Notify.logoutPush();
      await pumpEventQueue();

      signIn('u2');
      await redeclare('user_u2');

      expect(reports(network), hasLength(2));
      expect(reports(network).last['external_id'], 'user_u2');
    });

    test('forget() lets an identical state be reported again', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      Notify.pushState.forget();
      await redeclare('user_u1');

      expect(reports(network), hasLength(2));
    });

    test('a signed-out device reports nothing', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Auth.logout();
      await Notify.logoutPush();
      await pumpEventQueue();

      expect(reports(network), hasLength(1));
    });
  });

  group('a device with no push driver at all', () {
    test('a signed-in session posts exactly one report, marked unavailable',
        () async {
      // The package emits no reconcile pass for a driver-less build, so
      // without this the device reports nothing for the whole session.
      final FakeNetworkDriver network = Http.fake();
      signIn('u1');
      Notify.pushState.watch();
      await pumpEventQueue();

      expect(reports(network), hasLength(1));
      expect(reports(network).single['reachability'], 'unavailable');
    });

    test('a second notifier bump posts nothing, the memo holds', () async {
      final FakeNetworkDriver network = Http.fake();
      signIn('u1');
      Notify.pushState.watch();
      await pumpEventQueue();

      Auth.stateNotifier.value++;
      await pumpEventQueue();

      expect(reports(network), hasLength(1));
    });

    test('a signed-out session posts nothing', () async {
      final FakeNetworkDriver network = Http.fake();
      Auth.fake();
      Notify.pushState.watch();
      await pumpEventQueue();

      expect(reports(network), isEmpty);
    });

    test('a sign-in after the watch was armed signed-out reports', () async {
      final FakeNetworkDriver network = Http.fake();
      Auth.fake();
      Notify.pushState.watch();
      await pumpEventQueue();

      // Through the same guard, so the bump lands on the notifier the watch
      // is listening to, which is what a real sign-in does.
      await Auth.login(
        <String, dynamic>{'token': 'token-u1'},
        makeUser('u1'),
      );
      await pumpEventQueue();

      expect(reports(network), hasLength(1));
      expect(reports(network).single['reachability'], 'unavailable');
    });
  });

  group('the device change streams are watched on their own', () {
    test(
        'a driver attached after the watch is armed reports a revoked '
        'permission', () async {
      final FakeNetworkDriver network = Http.fake();
      signIn('u1');
      Notify.pushState.watch();
      await pumpEventQueue();

      final _ReportingPushDriver driver = useDriver();
      await pumpEventQueue();

      driver.changePermission(PushPermissionState.denied);
      await pumpEventQueue();

      expect(reports(network), hasLength(2));
      expect(reports(network).first['reachability'], 'unavailable');
      expect(reports(network).last['reachability'], 'blocked');
    });

    test(
        'once a driver attaches, the next reconcile pass reports the real '
        'state', () async {
      final FakeNetworkDriver network = Http.fake();
      await declareIdentity();

      expect(reports(network), hasLength(1));
      expect(reports(network).single['reachability'], 'unavailable');

      useDriver();
      await Notify.manager.reconcilePushIdentity();
      await pumpEventQueue();

      expect(reports(network), hasLength(2));
      expect(reports(network).last['reachability'], 'on');
      expect(reports(network).last['external_id'], 'user_u1');
      expect(reports(network).last['subscription_id'], 'sub-phone');
    });

    test('a driver that was already there is watched from the arming read',
        () async {
      final FakeNetworkDriver network = Http.fake();
      signIn('u1');
      final _ReportingPushDriver driver = useDriver();
      await pumpEventQueue();

      Notify.pushState.watch();
      driver.changePermission(PushPermissionState.denied);
      await pumpEventQueue();

      expect(reports(network), hasLength(1));
      expect(reports(network).single['reachability'], 'blocked');
    });

    test('a revoked permission reports itself with nobody asking', () async {
      final FakeNetworkDriver network = Http.fake();
      final _ReportingPushDriver driver = useDriver();
      await declareIdentity();

      driver.changePermission(PushPermissionState.denied);
      await pumpEventQueue();

      expect(reports(network), hasLength(2));
      expect(reports(network).last['reachability'], 'blocked');
    });

    test('a swapped subscription reports itself', () async {
      final FakeNetworkDriver network = Http.fake();
      final _ReportingPushDriver driver = useDriver();
      await declareIdentity();

      driver.changeSubscription('sub-reinstalled');
      await pumpEventQueue();

      expect(reports(network), hasLength(2));
      expect(reports(network).last['subscription_id'], 'sub-reinstalled');
    });

    test('arming twice reports a pass once', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      signIn('u1');
      Notify.pushState.watch();
      Notify.pushState.watch();

      await redeclare('user_u1');

      expect(reports(network), hasLength(1));
    });

    test('the reporter creates no periodic timer', () {
      // A poll would put one write per device per interval on the backend for
      // a fact that changes when the OS says so. Structural, because proving
      // an absence by advancing a fake clock hangs on the real event queue
      // every helper here waits on.
      final String source = File(
        'lib/src/support/push_state_reporter.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('Timer.periodic')));
    });
  });

  group('release', () {
    test('a sign-in followed by a release posts once', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Notify.pushState.release();
      await Notify.pushState.release();

      expect(releases(network), hasLength(1));
    });

    test('two releases in the same breath post once', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Future.wait(<Future<void>>[
        Notify.pushState.release(),
        Notify.pushState.release(),
      ]);

      expect(releases(network), hasLength(1));
    });

    test('a sign-out with no device to name posts nothing', () async {
      // A build with no push at all reports `unavailable` with no subscription
      // id and has therefore never vouched for anybody.
      final FakeNetworkDriver network = Http.fake();
      await declareIdentity();

      await Notify.pushState.release();

      expect(releases(network), isEmpty);
    });

    test('a driver that has stopped answering still releases its row',
        () async {
      final FakeNetworkDriver network = Http.fake();
      final _ReportingPushDriver driver = useDriver();
      await declareIdentity();

      // Assigned rather than announced, which would fire a report of its own.
      driver.subscriptionId = null;

      await Notify.pushState.release();

      expect(releases(network).single['subscription_id'], 'sub-phone');
    });

    test('a signed-out session releases nothing', () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();
      await Auth.logout();

      await Notify.pushState.release();

      expect(releases(network), isEmpty);
    });

    test('a released device is reported from scratch, not remembered',
        () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Notify.pushState.release();
      await redeclare('user_u1');

      expect(reports(network), hasLength(2));
      expect(reports(network).last['subscription_id'], 'sub-phone');
    });

    test('a device reported again after a release can be released again',
        () async {
      final FakeNetworkDriver network = Http.fake();
      useDriver();
      await declareIdentity();

      await Notify.pushState.release();
      await redeclare('user_u1');
      await Notify.pushState.release();

      expect(releases(network), hasLength(2));
    });

    test('a refused release leaves the memo describing what the server has',
        () async {
      final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
        releasePath: Http.response(<String, dynamic>{'message': 'nope'}, 500),
      });
      useDriver();
      await declareIdentity();

      await Notify.pushState.release();
      await redeclare('user_u1');

      expect(releases(network), hasLength(1));
      expect(reports(network), hasLength(1));
    });

    test('a refused release can be tried again', () async {
      final FakeNetworkDriver network = Http.fake(<String, MagicResponse>{
        releasePath: Http.response(<String, dynamic>{'message': 'nope'}, 500),
      });
      useDriver();
      await declareIdentity();

      await Notify.pushState.release();
      await Notify.pushState.release();

      expect(releases(network), hasLength(2));
    });
  });
}
