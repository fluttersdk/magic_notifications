import 'package:flutter/foundation.dart' show immutable;

import 'push_subscription.dart';

/// What an app's own push reminder can actually accomplish right now.
///
/// The reminder is one widget with several jobs, and picking the wrong one is
/// how a control ends up doing nothing visible. Each value names the outcome
/// of a tap, not a presentation: the package does not own UI.
enum PushPromptAction {
  /// Nothing to offer. The device is already subscribed, or this build has no
  /// push at all, so any control would be decoration.
  none,

  /// Raising the platform permission request will put a real dialog in front
  /// of the user.
  request,

  /// The platform request is spent, but a request raised here still routes the
  /// user to the app's own settings page, where the permission can be turned
  /// back on. This is the mobile `fallbackToSettings` capability, which a
  /// driver declares through `PushDriver.canOpenPlatformSettings`.
  openSettings,

  /// The platform request is spent and this platform offers no route back, so
  /// the reminder can only say where the switch lives. A browser is the case:
  /// no web API opens the site settings panel from a page.
  instructions,
}

/// **Whether the app may remind somebody about push, and what the reminder
/// can do about it.**
///
/// Two cadences live behind this answer and they are not the same question.
/// Raising the OS permission request is a one-shot: on a device that has
/// already answered, `requestPermission()` resolves immediately and shows
/// nothing. Showing the APP'S OWN reminder is not a one-shot at all, because
/// it is our UI and we choose when it appears, which is why a denied device
/// still gets one: on mobile its action lands on the app's settings page.
///
/// Both are answered here so a consumer cannot get the combination wrong. The
/// caller supplies the one fact this package refuses to own, the moment the
/// operator last turned the reminder down, and gets back a decision that has
/// already weighed reachability, the configured interval, and the platform's
/// route back.
///
/// ### Example Usage:
///
/// ```dart
/// final advice = await Notify.manager.pushPromptAdvice(
///   declinedAt: await myVault.readDeclinedAt(),
/// );
///
/// if (!advice.show) return const SizedBox.shrink();
///
/// return switch (advice.action) {
///   PushPromptAction.request ||
///   PushPromptAction.openSettings => MyEnablePushRow(advice.reachability),
///   PushPromptAction.instructions => MyBlockedInstructionRow(),
///   PushPromptAction.none => const SizedBox.shrink(),
/// };
/// ```
@immutable
class PushPromptAdvice {
  /// Whether the app may put its reminder in front of the user right now.
  ///
  /// False is not necessarily a permanent answer: it is false while the
  /// configured interval since the operator last turned the reminder down has
  /// not elapsed, and true again once it has.
  final bool show;

  /// Why the answer is what it is, and what the reminder should render.
  ///
  /// Carried even when [show] is false, because a screen the user opened
  /// deliberately (a notification preferences page) still wants to state the
  /// device's status without interrupting anybody.
  final PushReachability reachability;

  /// What the reminder's control can accomplish on this platform, in this
  /// state.
  final PushPromptAction action;

  /// Creates advice for one reading of the device's state.
  const PushPromptAdvice({
    required this.show,
    required this.reachability,
    required this.action,
  });
}
