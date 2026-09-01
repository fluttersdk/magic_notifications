import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('PushPermissionState', () {
    test('has all expected values', () {
      expect(
          PushPermissionState.values,
          containsAll([
            PushPermissionState.notDetermined,
            PushPermissionState.denied,
            PushPermissionState.authorized,
            PushPermissionState.provisional,
          ]));
    });
  });

  group('PushReachability', () {
    test('has all expected values', () {
      expect(
          PushReachability.values,
          containsAll([
            PushReachability.unavailable,
            PushReachability.blocked,
            PushReachability.off,
            PushReachability.on,
          ]));
    });

    test('separates a blocked device from one that was never asked', () {
      // The whole point of the enum: both are unreachable today, but only one
      // of them can still be turned on by a prompt.
      expect(PushReachability.blocked, isNot(PushReachability.off));
    });
  });

  group('PushSubscription', () {
    test('defaults to not opted in', () {
      final sub = PushSubscription();
      expect(sub.optedIn, isFalse);
    });

    test('stores subscription details', () {
      final sub = PushSubscription(
        subscriptionId: 'sub-123',
        token: 'token-abc',
        optedIn: true,
        permissionState: PushPermissionState.authorized,
      );

      expect(sub.subscriptionId, 'sub-123');
      expect(sub.token, 'token-abc');
      expect(sub.optedIn, isTrue);
      expect(sub.permissionState, PushPermissionState.authorized);
    });
  });
}
