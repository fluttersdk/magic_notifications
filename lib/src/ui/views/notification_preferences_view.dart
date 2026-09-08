import 'package:flutter/material.dart' show Icons, CircularProgressIndicator;
import 'package:flutter/widgets.dart';
import 'package:magic/magic.dart';

import '../../facades/notify.dart';
import '../../http/notification_preferences_controller.dart';

/// The notification preference screen.
///
/// Renders the type x channel matrix loaded by
/// [NotificationPreferencesController]: one card per notification type, one
/// switch per channel it offers. Registered as `notifications.preferences`, so
/// a host replaces or wraps it through `Notify.view`.
class NotificationPreferencesView
    extends MagicStatefulView<NotificationPreferencesController> {
  const NotificationPreferencesView({
    super.key,
    this.pushProvisioned,
    this.backRoute,
  });

  /// Host override for the push-provisioning state, or `null` (the default) to
  /// read it from the backend.
  ///
  /// The preference responses carry `meta.push_provisioned`, so the controller
  /// already knows whether the app configured its push `app_id`; when that is
  /// `false`, a subtle "push not yet configured" hint renders beneath the push
  /// channel toggle so the user understands it cannot deliver yet. Pass a bool
  /// here only to force the hint on or off (a host that resolves push
  /// provisioning some other way, or a test).
  final bool? pushProvisioned;

  /// The route the header's back control returns to, or `null` (the default)
  /// for no back affordance at all.
  ///
  /// This package cannot know where an adopter parks its settings hub, and a
  /// control with no destination is worse than no control, so the host passes
  /// its own route at the mount point:
  ///
  /// ```dart
  /// Notify.view.register('notifications.preferences', () {
  ///   return NotificationPreferencesView(backRoute: MyConfig.settingsRoute());
  /// });
  /// ```
  final String? backRoute;

  @override
  State<NotificationPreferencesView> createState() =>
      _NotificationPreferencesViewState();
}

class _NotificationPreferencesViewState extends MagicStatefulViewState<
    NotificationPreferencesController, NotificationPreferencesView> {
  static const _iconLocked = Icons.lock_outline;
  static const _iconBack = Icons.chevron_left;

  /// The bulk card's heading glyph: sliders, for "this row sets several at
  /// once", rather than a bell, which every row below it already is.
  static const _iconBulk = Icons.tune_outlined;
  static const _channelIcons = <String, IconData>{
    'mail': Icons.mail_outline,
    'database': Icons.inbox_outlined,
    'push': Icons.notifications_outlined,
  };
  static const _defaultChannelIcon = Icons.circle_notifications_outlined;

  @override
  void initState() {
    // Put the controller before `MagicStatefulViewState.initState` resolves it
    // with `Magic.find`, which throws when nothing has put it. Doing it here
    // rather than at the mount point keeps the view mountable from anywhere:
    // the registry default, a host route, a test.
    NotificationPreferencesController.instance;

    super.initState();
  }

  @override
  void onInit() {
    super.onInit();
    controller.fetchPreferences();
  }

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) {
      return const WDiv(
        className: 'py-12 flex items-center justify-center',
        child: CircularProgressIndicator(),
      );
    }

    final headerSlot = Notify.view.buildSlot(
      'notifications.preferences',
      'header',
      context,
    );
    final footerSlot = Notify.view.buildSlot(
      'notifications.preferences',
      'footer',
      context,
    );

    // The page surface wraps the scroll view so the surface token paints the
    // whole content viewport rather than only the content height.
    return WDiv(
      className: 'w-full min-h-full bg-surface',
      child: SingleChildScrollView(
        // Own the implicit scroll controller: the host shell may already hold
        // the ambient PrimaryScrollController, and two claimants contend.
        primary: false,
        child: SafeArea(
          top: false,
          bottom: false,
          child: WDiv(
            className: 'w-full flex flex-col p-4 lg:p-6',
            children: [
              _buildHeader(),
              WDiv(
                className: 'mt-6 flex flex-col gap-6',
                children: [
                  if (headerSlot != null) headerSlot,
                  _buildMatrixSettings(),
                  if (footerSlot != null) footerSlot,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the page header: an optional back control, the title and subtitle.
  Widget _buildHeader() {
    final backRoute = widget.backRoute;

    return WDiv(
      className: 'w-full flex flex-row items-center gap-3',
      children: [
        if (backRoute != null)
          WAnchor(
            // The control is a chevron and nothing else, so its accessible
            // name has to come from here or assistive technology announces an
            // unnamed button.
            semanticLabel: trans('common.back'),
            onTap: () => MagicRoute.to(backRoute),
            child: const WDiv(
              className: 'p-2 rounded-lg hover:bg-surface-container',
              child: WIcon(_iconBack, className: 'text-fg-muted'),
            ),
          ),
        WDiv(
          className: 'flex flex-col gap-1 flex-initial min-w-0',
          children: [
            WText(
              trans('notifications.preferences_title'),
              className: 'text-2xl font-semibold text-fg',
            ),
            WText(
              trans('notifications.preferences_description'),
              className: 'text-sm text-fg-muted',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMatrixSettings() {
    // Both the matrix and the push-provisioning flag are published by the same
    // preference response, so one merged listenable rebuilds the toggles and
    // their heads-up together.
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.matrixNotifier,
        controller.pushProvisionedNotifier,
        controller.bulkSavingNotifier,
      ]),
      builder: (context, _) {
        final Map<String, dynamic> matrix = controller.matrixNotifier.value;

        if (matrix.isEmpty) {
          return WDiv(
            className: _cardClassName,
            child: WDiv(
              className:
                  'w-full py-12 flex flex-col items-center justify-center gap-3',
              children: [
                WIcon(
                  Icons.notifications_off_outlined,
                  className: 'text-4xl text-fg-disabled',
                ),
                WText(
                  trans('notifications.no_preferences'),
                  className: 'text-sm text-fg-muted',
                ),
              ],
            ),
          );
        }

        final types = matrix.keys.toList();

        return WDiv(
          className: 'flex flex-col gap-6',
          children: [
            _buildBulkCard(matrix),
            for (var i = 0; i < types.length; i++)
              _buildNotificationType(
                types[i],
                matrix[types[i]] as Map<String, dynamic>,
              ),
          ],
        );
      },
    );
  }

  /// The card shell every section renders in.
  ///
  /// Full-bleed (`overflow-hidden`, no body padding) because the channel rows
  /// span edge to edge and carry their own `px-6`.
  static const String _cardClassName =
      'w-full bg-surface-container border border-color-border '
      'rounded-2xl overflow-hidden flex flex-col';

  /// The bulk card's shell: [_cardClassName] one surface step up.
  ///
  /// `surface-container-high` is the token the theme already reserves for a
  /// panel nested inside another, which is what this is against the matrix it
  /// summarises. Its rows are deliberately identical to the per-type rows, so
  /// the surface is the only thing carrying "these are shortcuts".
  static const String _bulkCardClassName =
      'w-full bg-surface-container-high border border-color-border '
      'rounded-2xl overflow-hidden flex flex-col';

  /// The glyph tile in the bulk card's heading.
  ///
  /// The per-type cards head with text alone, so a tile here is a second signal
  /// costing no vertical space: the heading row already reserves this height for
  /// its two lines of text.
  static const String _bulkTileClassName =
      'size-9 shrink-0 flex items-center justify-center rounded-lg '
      'bg-primary-container';

  /// The card above the matrix: one switch per channel, applying to every type.
  ///
  /// The matrix is the precise control and this is the fast one. A team that
  /// silences push on a phone it cannot hear does not want to walk eight
  /// notification types to do it, and eight taps is eight chances to leave one
  /// on.
  Widget _buildBulkCard(Map<String, dynamic> matrix) {
    // The channels that have at least one cell this card could WRITE, not every
    // channel the matrix mentions. A matrix whose only channel is locked
    // everywhere would otherwise render a heading and a subtitle over an empty
    // body, and `isLast` computed over the pre-collapse list would leave a
    // hairline along the card's clipped bottom edge.
    final List<String> channels = _channelsAcrossTypes(matrix)
        .where((channel) => _writableStates(matrix, channel).isNotEmpty)
        .toList();

    if (channels.isEmpty) {
      return const SizedBox.shrink();
    }

    return WDiv(
      // Keyed, and the per-type card below is too: both render the same row
      // shell with the same channel labels, so without a handle neither a test
      // nor an E2E driver can say which card it is looking at.
      key: const ValueKey('notifications.bulk'),
      // Its own surface, one step up from the per-type cards below, and a solid
      // border where they carry the hairline. The rows inside are identical to
      // theirs by design (same control, same touch target, same semantics), so
      // the card is the only thing that can say "this one is a shortcut and the
      // real settings are underneath". Rendered in the same tokens as those
      // cards, it read as the first of them.
      className: _bulkCardClassName,
      children: [
        WDiv(
          className: 'px-6 pt-6 pb-3 flex flex-row items-start gap-3',
          children: [
            WDiv(
              className: _bulkTileClassName,
              child: WIcon(_iconBulk, className: 'text-[18px] text-primary'),
            ),
            WDiv(
              className: 'min-w-0 flex-1 flex flex-col gap-1',
              children: [
                WText(
                  trans('notifications.bulk_title'),
                  className: 'text-lg font-semibold text-fg',
                ),
                WText(
                  trans('notifications.bulk_description'),
                  className: 'text-sm text-fg-muted',
                ),
              ],
            ),
          ],
        ),
        WDiv(
          className: 'flex flex-col',
          children: [
            for (var i = 0; i < channels.length; i++)
              _buildBulkToggle(
                matrix,
                channels[i],
                isLast: i == channels.length - 1,
              ),
          ],
        ),
      ],
    );
  }

  /// Every channel any type in [matrix] offers, in the order they first appear.
  ///
  /// Insertion order rather than sorted: the backend publishes its channels in
  /// the order it means them to read, and the per-type cards below already
  /// render them that way. Sorting here would put the bulk card in a different
  /// order from the cards it summarises.
  List<String> _channelsAcrossTypes(Map<String, dynamic> matrix) {
    final channels = <String>{};

    for (final Object? typeData in matrix.values) {
      if (typeData is! Map) continue;

      final Object? channelsData = typeData['channels'];
      if (channelsData is! Map) continue;

      channels.addAll(channelsData.keys.map((key) => key.toString()));
    }

    return channels.toList();
  }

  /// One bulk row: [channel]'s state across every type, and the switch that
  /// writes it to all of them.
  Widget _buildBulkToggle(
    Map<String, dynamic> matrix,
    String channel, {
    required bool isLast,
  }) {
    // The state of the cells this row would WRITE, not of every cell that
    // exists: counting a locked cell would let the switch claim a channel is
    // fully on while the tap that follows can only reach part of it. The caller
    // has already dropped a channel with no writable cell at all.
    final bool isEnabled = _writableStates(
      matrix,
      channel,
    ).every((enabled) => enabled);

    // Disabled while its own batch is out. One tap writes several cells, so a
    // second tap mid-flight would send a second batch over the same cells and
    // the two would settle in an order neither of them chose.
    final bool isSaving = controller.bulkSavingNotifier.value.contains(channel);

    return _buildToggleRow(
      key: ValueKey('notifications.bulk.$channel'),
      channel: channel,
      isEnabled: isEnabled,
      isLocked: false,
      isBusy: isSaving,
      showPushHint: false,
      isLast: isLast,
      onChanged: (newValue) {
        controller.updateChannelAcrossTypes(channel, newValue);
      },
    );
  }

  /// The `enabled` flag of every UNLOCKED cell [channel] has across [matrix].
  List<bool> _writableStates(Map<String, dynamic> matrix, String channel) {
    final states = <bool>[];

    for (final Object? typeData in matrix.values) {
      if (typeData is! Map) continue;

      final Object? channelsData = typeData['channels'];
      if (channelsData is! Map) continue;

      final Object? channelData = channelsData[channel];
      if (channelData is! Map) continue;
      if (channelData['locked'] == true) continue;

      states.add(channelData['enabled'] as bool? ?? false);
    }

    return states;
  }

  Widget _buildNotificationType(String typeKey, Map<String, dynamic> typeData) {
    final title = typeData['label']?.toString() ?? typeKey;
    final channels = typeData['channels'] as Map<String, dynamic>? ?? {};
    final channelKeys = channels.keys.toList();

    return WDiv(
      key: ValueKey('notifications.type.$typeKey'),
      className: _cardClassName,
      children: [
        WDiv(
          className: 'px-6 pt-6 pb-3',
          child: WText(title, className: 'text-lg font-semibold text-fg'),
        ),
        WDiv(
          className: 'flex flex-col',
          children: [
            for (var i = 0; i < channelKeys.length; i++)
              _buildChannelToggle(
                typeKey,
                channelKeys[i],
                channels[channelKeys[i]] as Map<String, dynamic>,
                // Wind implements no structural pseudo-variants, so the row
                // cannot answer "am I last?" from its className: an unknown
                // prefix like `last:` is read as a state name nothing ever
                // activates, the class silently never fires, and the card's
                // `rounded-2xl overflow-hidden` then clips a hairline that was
                // supposed to be gone. The index is the only thing that knows.
                isLast: i == channelKeys.length - 1,
              ),
          ],
        ),
      ],
    );
  }

  /// The channel row shell, carrying the separator to the row below it.
  static const String _rowClassName =
      'px-6 py-4 flex items-center justify-between '
      'border-b border-color-border-subtle';

  /// The channel row shell for the last row of a card, which has no row below
  /// it to be separated from.
  static const String _lastRowClassName =
      'px-6 py-4 flex items-center justify-between';

  /// The channel icon chip, tinted through the `enabled:` state.
  ///
  /// One string for both tints rather than an interpolated pair: an
  /// interpolation is a second parser cache key per row, and the state prefix
  /// says what the row actually means. `enabled` is a custom state name here
  /// deliberately, because `active:` is one of the three prefixes `WDiv` reads
  /// as "this element is interactive" and wraps in a `WAnchor` for.
  static const String _channelChipClassName =
      'w-10 h-10 rounded-full flex items-center justify-center '
      'bg-surface-container-high enabled:bg-primary/10 '
      'dark:enabled:bg-primary/10';

  /// The chip's glyph, tinted by the same state as the chip.
  static const String _channelChipIconClassName =
      'text-[18px] text-fg-muted enabled:text-primary';

  Widget _buildChannelToggle(
    String type,
    String channel,
    Map<String, dynamic> channelData, {
    required bool isLast,
  }) {
    final bool isEnabled = channelData['enabled'] as bool? ?? false;
    final bool isLocked = channelData['locked'] as bool? ?? false;
    // The push channel toggle cannot deliver until the app provisions its push
    // integration; surface a subtle heads-up beneath its label when it has not.
    // The backend-reported flag drives it, unless the host forced a value.
    final bool pushProvisioned =
        widget.pushProvisioned ?? controller.pushProvisionedNotifier.value;
    final bool showPushHint =
        channel.toLowerCase() == 'push' && !pushProvisioned;

    return _buildToggleRow(
      channel: channel,
      isEnabled: isEnabled,
      isLocked: isLocked,
      showPushHint: showPushHint,
      isLast: isLast,
      onChanged: (newValue) {
        controller.updateTypePreference(type, channel, newValue);
      },
    );
  }

  /// The row both the matrix and the bulk card render: a chip, a label, an
  /// optional hint, and the switch that writes it.
  ///
  /// Shared rather than copied, because the two callers differ only in what the
  /// switch DOES: one writes a cell, the other writes a column. The chip
  /// states, the semantics exclusion, the shrink behaviour and the separator
  /// are the same problem in both, and a copy would drift the moment one of
  /// them is fixed.
  Widget _buildToggleRow({
    required String channel,
    required bool isEnabled,
    required bool isLocked,
    required bool showPushHint,
    required bool isLast,
    required ValueChanged<bool> onChanged,
    bool isBusy = false,
    Key? key,
  }) {
    final icon = _channelIcon(channel);
    final Set<String> chipStates = {if (isEnabled && !isLocked) 'enabled'};

    return WDiv(
      className: isLast ? _lastRowClassName : _rowClassName,
      children: [
        WDiv(
          // `flex-1 min-w-0` so the icon-plus-text half yields to the switch
          // instead of demanding its intrinsic width. Without it the row
          // overflowed on any channel carrying the push hint below, because a
          // two-line text column is wider than a one-line one and nothing told
          // it to shrink.
          className: 'flex-1 min-w-0 flex items-center gap-4',
          children: [
            WDiv(
              states: chipStates,
              className: _channelChipClassName,
              child: WIcon(
                isLocked ? _iconLocked : icon,
                states: chipStates,
                className: _channelChipIconClassName,
              ),
            ),
            WDiv(
              // `min-w-0` so the label and the hint can wrap rather than force
              // the row wider than its container.
              className: 'flex-1 min-w-0 flex flex-col gap-1',
              children: [
                // The switch below carries this same text as its semanticLabel,
                // so exclude the visible copy from semantics: otherwise the row
                // exposes TWO nodes with the same name (this paragraph AND the
                // switch) and a getByLabel / E2E lookup resolves the
                // non-interactive text first, landing the tap on the label
                // instead of the toggle. The hint below stays OUT of the
                // exclusion: it carries information the switch label does not,
                // so a screen reader has to announce it.
                ExcludeSemantics(
                  child: WText(
                    _channelLabel(channel),
                    className: 'text-sm font-medium text-fg',
                  ),
                ),
                if (showPushHint)
                  WText(
                    trans('notifications.channel_push_unconfigured'),
                    className: 'text-xs text-fg-muted',
                  ),
              ],
            ),
          ],
        ),
        WSwitch(
          key: key,
          value: isEnabled,
          // `isLocked` is the backend refusing the cell and draws a padlock;
          // `isBusy` is this row's own write being out and draws nothing. Both
          // stop a tap, and conflating them put a padlock on a row that was
          // merely saving.
          disabled: isLocked || isBusy,
          // Label the toggle with its visible channel name: the channel text is
          // a sibling WText, so without this the switch had no accessible name
          // (a screen reader announced a bare "switch") and no stable handle
          // for an E2E driver to resolve.
          semanticLabel: _channelLabel(channel),
          className: 'w-11 h-6 rounded-full px-0.5 '
              'flex items-center justify-start checked:justify-end '
              'bg-surface-container-high checked:bg-primary '
              'disabled:opacity-50',
          thumbClassName: 'w-5 h-5 rounded-full bg-surface shadow',
          onChanged: onChanged,
        ),
      ],
    );
  }

  /// Returns the appropriate icon for a notification channel.
  IconData _channelIcon(String channel) {
    return _channelIcons[channel.toLowerCase()] ?? _defaultChannelIcon;
  }

  /// Returns a user-friendly label for a notification channel.
  ///
  /// `sms` is a named arm rather than a fallback case because
  /// `magic-starter-laravel` offers it in the matrix out of the box, so the
  /// fallback was reachable on a default install: it rendered the machine name
  /// with its first letter raised ("Sms"), which is neither the right casing
  /// nor translated, sitting beside three properly localised siblings.
  String _channelLabel(String channel) {
    return switch (channel.toLowerCase()) {
      'mail' => trans('notifications.channel_email'),
      'database' => trans('notifications.channel_in_app'),
      'push' => trans('notifications.channel_push'),
      'sms' => trans('notifications.channel_sms'),
      _ => _capitalize(channel),
    };
  }

  /// Last-resort label for a channel this package has no name for.
  ///
  /// Reached only by a channel a host registered itself, where the machine
  /// name is the only thing available to show.
  String _capitalize(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).replaceAll('_', ' ');
  }
}
