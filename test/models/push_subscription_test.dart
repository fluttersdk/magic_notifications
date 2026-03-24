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
