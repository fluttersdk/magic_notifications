import 'package:magic/magic.dart';

/// The state axis key shared by the three push-prompt recipes.
///
/// Its values are the four presentations the prompt has, which are NOT the
/// four `PushReachability` values: `off` splits into `ask` (the soft prompt)
/// and the compact enable row a resolved ask leaves behind, and both of those
/// carry the same container tokens.
const String kPushPromptStateAxis = 'state';

/// The `ask` presentation: the soft prompt, and the compact enable row.
const String kPushPromptStateAsk = 'ask';

/// The `blocked` presentation: the platform will not prompt again.
const String kPushPromptStateBlocked = 'blocked';

/// The `on` presentation: this device is reachable.
const String kPushPromptStateOn = 'on';

/// The `unavailable` presentation: this build has no push at all.
const String kPushPromptStateUnavailable = 'unavailable';

/// Builds the push-prompt container [WindRecipe].
///
/// Emission order: `base ++ state-variant ++ caller`.
///
/// State -> token mapping:
/// - ask:         `bg-surface-container` on `border-color-border`
/// - blocked:     `bg-warning/10` (the warning role tinted, see below), the
///                same border as `ask`
/// - on:          `bg-surface-container` on the hairline border
/// - unavailable: the same, quieter still
///
/// The 17-key semantic alias contract (`design:sync`'s `_aliasMappings`) ships
/// `bg-warning` as a solid fill only; there is no `warning`-tinted container
/// alias the way `destructive` gets one (`bg-destructive-container`). The
/// opacity modifier is the tool this package already reaches for in that gap:
/// `notification_preferences_view.dart`'s `enabled:bg-primary/10` and
/// `notification_dropdown.dart`'s `unread:bg-primary/5` both tint an aliased
/// background this same way, and `bg-warning/10` is the same trick applied to
/// the warning role.
const WindRecipe pushPromptRecipe = WindRecipe(
  base: 'w-full flex flex-row items-start gap-3 rounded-xl border p-4',
  variants: {
    kPushPromptStateAxis: {
      kPushPromptStateAsk: 'border-color-border bg-surface-container',
      kPushPromptStateBlocked: 'border-color-border bg-warning/10',
      kPushPromptStateOn: 'border-color-border-subtle bg-surface-container',
      kPushPromptStateUnavailable:
          'border-color-border-subtle bg-surface-container',
    },
  },
  defaultVariants: {kPushPromptStateAxis: kPushPromptStateAsk},
);

/// Builds the glyph tile [WindRecipe] that leads every push-prompt row.
///
/// Emission order: `base ++ state-variant ++ caller`.
///
/// State -> token mapping:
/// - ask:         `bg-primary-container`, the standard tinted-brand tile
/// - blocked:     `bg-warning`, solid
/// - on:          `bg-success`, solid
/// - unavailable: `bg-surface-container-high`
///
/// `blocked` and `on` are solid rather than tinted for the same reason the
/// container above is not: `success` and `warning` carry no `-container`
/// alias to tint with. A solid tile paired with a `text-white` glyph
/// ([pushPromptIconRecipe]) is the pairing `toast.recipe.dart` already
/// establishes for these two roles in this package, so the tile follows the
/// same precedent rather than inventing a second one.
const WindRecipe pushPromptTileRecipe = WindRecipe(
  base: 'size-8 shrink-0 flex items-center justify-center rounded-lg',
  variants: {
    kPushPromptStateAxis: {
      kPushPromptStateAsk: 'bg-primary-container',
      kPushPromptStateBlocked: 'bg-warning',
      kPushPromptStateOn: 'bg-success',
      kPushPromptStateUnavailable: 'bg-surface-container-high',
    },
  },
  defaultVariants: {kPushPromptStateAxis: kPushPromptStateAsk},
);

/// Builds the glyph [WindRecipe] for the icon inside the tile.
///
/// Separate from [pushPromptTileRecipe] because the colour rides the glyph and
/// the fill rides the tile, and Wind emits one className per widget.
///
/// Emission order: `base ++ state-variant ++ caller`.
///
/// State -> token mapping:
/// - ask:         `text-primary`
/// - blocked:     `text-white`, on the solid `bg-warning` tile
/// - on:          `text-white`, on the solid `bg-success` tile
/// - unavailable: `text-fg-disabled`
///
/// `text-white` rather than an aliased foreground: the 17-key contract has no
/// `text-on-warning` / `text-on-success` the way it has `text-on-destructive`,
/// and a fixed white glyph on a fixed solid fill needs no `dark:` pair, the
/// same choice `toast.recipe.dart` already made for the identical pairing.
const WindRecipe pushPromptIconRecipe = WindRecipe(
  base: 'text-lg',
  variants: {
    kPushPromptStateAxis: {
      kPushPromptStateAsk: 'text-primary',
      kPushPromptStateBlocked: 'text-white',
      kPushPromptStateOn: 'text-white',
      kPushPromptStateUnavailable: 'text-fg-disabled',
    },
  },
  defaultVariants: {kPushPromptStateAxis: kPushPromptStateAsk},
);

/// The "enable push" button's className.
///
/// `border-transparent` reserves the same box `focus:border-primary` fills,
/// so the focus state adds no layout shift; `hover:`/`focus:` share the
/// tinted brand surface [pushPromptTileRecipe] already uses for the `ask`
/// tile. `px-4 py-3`, not a smaller box: on a phone this may be the only
/// control that fixes a device push cannot reach, and 4px of vertical padding
/// around `text-sm` is roughly a 30px target against a 44dp floor.
const String pushPromptEnableButtonClassName =
    'rounded-md border border-transparent px-4 py-3 text-sm font-medium '
    'text-primary transition-colors hover:bg-primary-container '
    'focus:border-primary focus:bg-primary-container';

/// The decline ("not now") button's className.
///
/// The same `px-4 py-3` box as [pushPromptEnableButtonClassName] beside it,
/// deliberately: the two sit on one row, so a smaller box here renders two
/// controls of visibly different height, and the 44dp touch floor the enable
/// button's padding exists for applies to a decline made on a phone too.
const String pushPromptDeclineButtonClassName =
    'rounded-md border border-transparent px-4 py-3 text-sm font-medium '
    'text-fg-muted transition-colors hover:bg-surface-container '
    'hover:text-fg focus:border-color-border focus:bg-surface-container '
    'focus:text-fg';

/// The single-button and two-button actions row shared by every action state.
///
/// `wrap`, not `flex-row`: the `ask` state offers two buttons, and a locale
/// whose labels run longer than English can overflow a fixed-width row before
/// wrapping ever gets a chance to fire. A wrap flows the second button onto
/// its own line instead. The single-button states share it deliberately: the
/// same long-label pressure applies to one button in a narrow card, and a
/// second token here would be a second thing to get wrong.
const String pushPromptActionsClassName = 'wrap items-center gap-4';

/// The density axis key for the shell notice.
///
/// Its two values are two SHELL SHAPES a host may need this marker in, not two
/// sizes of one thing: a sidebar column has room for a sentence, a mobile top
/// bar does not.
const String kPushOffNoticeDensityAxis = 'density';

/// The sidebar form: a glyph and a line, sized like a nav row.
const String kPushOffNoticeDensityFull = 'full';

/// The mobile top-bar form: the glyph alone, sized like an account avatar.
const String kPushOffNoticeDensityCompact = 'compact';

/// Builds the shell notice's [WindRecipe].
///
/// Emission order: `base ++ density-variant ++ caller`.
///
/// The base carries no colour of its own; the warning lives entirely in the
/// glyph ([pushOffNoticeIconClassName]) so the marker reads as one of a
/// shell's secondary controls rather than as an alert. Both variants reuse
/// the `hover:bg-surface-container` affordance an app's other shell controls
/// typically carry, and both own their outer spacing, so a hidden notice
/// costs no layout at all.
///
/// Density -> token mapping:
/// - full:    a full-width row inset to match a sidebar's `px-3` nav column
/// - compact: a 36px round tap target, an account avatar's usual footprint
const WindRecipe pushOffNoticeRecipe = WindRecipe(
  base: 'flex flex-row items-center rounded-md hover:bg-surface-container',
  variants: {
    kPushOffNoticeDensityAxis: {
      kPushOffNoticeDensityFull: 'w-full gap-2 mx-3 mb-2 px-2 py-2',
      kPushOffNoticeDensityCompact:
          'w-9 h-9 shrink-0 justify-center rounded-full',
    },
  },
  defaultVariants: {kPushOffNoticeDensityAxis: kPushOffNoticeDensityFull},
);

/// The shell notice's glyph className.
///
/// `text-fg-muted` rather than a warning tint: the 17-key alias contract has
/// no `text-warning` (only `bg-warning`, a background-only role; see
/// [pushPromptIconRecipe]), and pairing a bare glyph with no background tile
/// against `text-white` would be illegible on a transparent surface. A host
/// wanting a stronger signal here wraps this marker in its own tinted tile;
/// this package does not invent an alias the shared contract does not define.
const String pushOffNoticeIconClassName = 'text-[16px] text-fg-muted';

/// The shell notice's label className, matching a sidebar's secondary rows.
const String pushOffNoticeLabelClassName = 'truncate text-xs text-fg-muted';
