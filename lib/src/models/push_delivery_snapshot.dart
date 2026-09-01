import 'package:flutter/foundation.dart' show immutable;

import 'push_subscription.dart';

/// **Whether a push can reach this device, in a shape a server can store.**
///
/// A responder's phone that cannot receive a push is a page nobody hears, and
/// only the DEVICE knows that: the permission, the opt-in flag and the
/// subscription id all live on the client. An escalation policy that has this
/// can move on to the next responder immediately instead of waiting out an
/// acknowledgement that was never going to arrive.
///
/// This package deliberately ships no transport for it. It has no idea what a
/// consumer's API looks like, and an endpoint invented here would be one more
/// thing to keep in sync with a backend it cannot see. What it does own is the
/// SHAPE, so two consumers posting the same fact cannot describe it two ways.
///
/// ### What it deliberately does not carry
///
/// Nothing that identifies a person beyond [externalId], which is the id the
/// server itself handed out and already addresses pushes to. No device name,
/// no token, no platform fingerprint: the question is "can this be paged",
/// and none of those help answer it.
///
/// ### Example Usage:
///
/// ```dart
/// final snapshot = await Notify.manager.pushDeliverySnapshot();
///
/// await Http.post('/api/v1/devices/push-state', data: snapshot.toMap());
/// ```
@immutable
class PushDeliverySnapshot {
  /// Whether push can reach this device right now, as the driver derives it.
  ///
  /// The REASON behind [canReceive], kept because a server that only knows
  /// "no" cannot tell an operator whether to fix a setting or wait for a
  /// subscription that has not landed yet.
  final PushReachability reachability;

  /// The external id the device reports being subscribed as, or `null`.
  ///
  /// Read back from the platform rather than taken from the intent this
  /// package holds: the intent is what the app WANTS, and a server deciding
  /// whether it can page this device needs what the device actually carries.
  final String? externalId;

  /// The subscription id the platform holds, or `null` when it has none.
  ///
  /// The address a push is delivered to. Without one there is nothing to
  /// address, whatever the permission says.
  final String? subscriptionId;

  /// When this was read, in UTC.
  ///
  /// A stored snapshot is a claim about a moment, and every one of these facts
  /// can change while the app is closed. A server weighing an escalation has
  /// to be able to say how old the claim is.
  final DateTime capturedAt;

  /// Creates a snapshot of this device's push delivery state.
  const PushDeliverySnapshot({
    required this.reachability,
    required this.capturedAt,
    this.externalId,
    this.subscriptionId,
  });

  /// Whether a push sent now could actually be delivered.
  ///
  /// Only [PushReachability.on] qualifies, and it already implies a permitted,
  /// opted-in device holding a subscription id.
  bool get canReceive => reachability == PushReachability.on;

  /// The snapshot as a JSON-ready map, keyed the way a backend reads.
  ///
  /// Nulls are KEPT rather than dropped. "This device holds no subscription
  /// id" is the fact being reported, and a key that disappears is
  /// indistinguishable from a client too old to send it.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'external_id': externalId,
      'subscription_id': subscriptionId,
      'reachability': reachability.name,
      'captured_at': capturedAt.toUtc().toIso8601String(),
    };
  }
}
