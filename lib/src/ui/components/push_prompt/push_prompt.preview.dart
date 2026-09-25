import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../../models/push_prompt_advice.dart';
import '../../../models/push_subscription.dart' show PushReachability;
import 'push_prompt.dart';

/// Static preview for [PushPrompt] and [PushOffNotice].
///
/// Renders [PushPrompt] across every `(reachability, action)` pair it can
/// actually be handed (including both arms of a blocked device, which
/// `reachability` alone cannot distinguish), plus the declined and busy
/// variants of the `ask` state, and both [PushOffNotice] densities.
/// [PushPromptHost] is not previewed here: it reads a live
/// `Notify.manager.pushDriverOrNull`, which a static catalogue page has none
/// of, and [PushPrompt] already exercises every visual state it would render.
/// One preview class per file.
class PushPromptPreview extends StatelessWidget {
  /// Creates a [PushPromptPreview].
  const PushPromptPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return WDiv(
      className: 'flex flex-col gap-6 p-6 max-w-md',
      children: [
        _labelled(
          'off / request',
          const PushPrompt(
            reachability: PushReachability.off,
            action: PushPromptAction.request,
          ),
        ),
        _labelled(
          'off / request, declined',
          const PushPrompt(
            reachability: PushReachability.off,
            action: PushPromptAction.request,
            declined: true,
          ),
        ),
        _labelled(
          'off / request, busy',
          const PushPrompt(
            reachability: PushReachability.off,
            action: PushPromptAction.request,
            busy: true,
          ),
        ),
        _labelled(
          'blocked / openSettings',
          const PushPrompt(
            reachability: PushReachability.blocked,
            action: PushPromptAction.openSettings,
          ),
        ),
        _labelled(
          'blocked / instructions',
          const PushPrompt(
            reachability: PushReachability.blocked,
            action: PushPromptAction.instructions,
          ),
        ),
        _labelled(
          'on / none',
          const PushPrompt(
            reachability: PushReachability.on,
            action: PushPromptAction.none,
          ),
        ),
        _labelled(
          'unavailable / none',
          const PushPrompt(
            reachability: PushReachability.unavailable,
            action: PushPromptAction.none,
          ),
        ),
        _labelled(
          'PushOffNotice, full',
          PushOffNotice(onOpenPreferences: () {}),
        ),
        _labelled(
          'PushOffNotice, compact',
          PushOffNotice(compact: true, onOpenPreferences: () {}),
        ),
      ],
    );
  }

  /// A caption above [child], so the catalogue page reads which variant it is
  /// looking at without opening this file.
  Widget _labelled(String label, Widget child) {
    return WDiv(
      className: 'flex flex-col gap-2',
      children: [
        WText(label, className: 'text-xs font-mono text-fg-muted'),
        child,
      ],
    );
  }
}
