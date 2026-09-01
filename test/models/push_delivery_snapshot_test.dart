import 'package:flutter_test/flutter_test.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  group('PushDeliverySnapshot', () {
    test('only a subscribed device reports that it can be paged', () {
      const List<PushReachability> unreachable = <PushReachability>[
        PushReachability.unavailable,
        PushReachability.blocked,
        PushReachability.off,
      ];

      for (final PushReachability reachability in unreachable) {
        expect(
          PushDeliverySnapshot(
            reachability: reachability,
            capturedAt: DateTime.utc(2026, 9, 1),
          ).canReceive,
          isFalse,
          reason: '$reachability cannot be paged',
        );
      }

      expect(
        PushDeliverySnapshot(
          reachability: PushReachability.on,
          externalId: 'user_a1b2',
          subscriptionId: 'sub-1',
          capturedAt: DateTime.utc(2026, 9, 1),
        ).canReceive,
        isTrue,
      );
    });

    test('serialises the four facts a server needs, and nothing else', () {
      final PushDeliverySnapshot snapshot = PushDeliverySnapshot(
        reachability: PushReachability.on,
        externalId: 'user_a1b2',
        subscriptionId: 'sub-1',
        capturedAt: DateTime.utc(2026, 9, 1, 12, 30),
      );

      // Asserted as a WHOLE map rather than key by key. The shape is the
      // contract two consumers have to share, and the privacy rule is a
      // statement about what is NOT in it: a field added here without a reason
      // fails this test rather than reaching somebody's server unnoticed.
      expect(snapshot.toMap(), <String, dynamic>{
        'external_id': 'user_a1b2',
        'subscription_id': 'sub-1',
        'reachability': 'on',
        'captured_at': '2026-09-01T12:30:00.000Z',
      });
    });

    test('a device with no subscription still names its state', () {
      final PushDeliverySnapshot snapshot = PushDeliverySnapshot(
        reachability: PushReachability.blocked,
        capturedAt: DateTime.utc(2026, 9, 1, 12, 30),
      );

      // The nulls are kept rather than omitted: "we hold no subscription id"
      // is the fact the server is being told, and a key that vanishes reads as
      // a client too old to report it.
      expect(snapshot.toMap(), <String, dynamic>{
        'external_id': null,
        'subscription_id': null,
        'reachability': 'blocked',
        'captured_at': '2026-09-01T12:30:00.000Z',
      });
    });

    test('the timestamp is posted in UTC whatever the device clock says', () {
      final PushDeliverySnapshot snapshot = PushDeliverySnapshot(
        reachability: PushReachability.off,
        capturedAt: DateTime(2026, 9, 1, 12, 30),
      );

      // A device set to a local timezone would otherwise post a wall clock the
      // server cannot compare against anything, and freshness is the whole
      // reason the timestamp is in here.
      expect(snapshot.toMap()['captured_at'], endsWith('Z'));
      expect(
        DateTime.parse(snapshot.toMap()['captured_at'] as String)
            .isAtSameMomentAs(DateTime(2026, 9, 1, 12, 30)),
        isTrue,
      );
    });
  });
}
