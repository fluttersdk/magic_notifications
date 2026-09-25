import 'package:flutter/foundation.dart' show immutable;

/// The outcome of one push identity reconcile pass that had a driver to act
/// on.
///
/// A host that reports device state per person (posting who this device is
/// subscribed as) needs to know when a pass RAN, not only when one converges:
/// a pass that throws, or reads back a mismatch, still has to be reported so
/// the host does not keep announcing state for an intent the device never
/// took on. See [NotificationManager.onPushIdentityReconciled].
@immutable
class PushIdentityReconciled {
  /// The intent this pass reconciled against, captured when the pass started.
  ///
  /// Not necessarily what the device holds now: on failure, or on a mismatch
  /// the read-back caught, the device may still carry whoever it had before.
  final String? intent;

  /// Whether the device carried [intent] by the end of the pass.
  final bool converged;

  /// The failure the pass raised, or `null` when it did not throw.
  ///
  /// A `false` [converged] with a `null` error means the SDK call was issued
  /// and the read-back simply did not agree; a non-null error means the call
  /// itself failed.
  final Object? error;

  /// Creates one reconcile outcome.
  const PushIdentityReconciled({
    required this.intent,
    required this.converged,
    this.error,
  });
}
