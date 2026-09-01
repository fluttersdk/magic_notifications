// NotificationDropdown has no variant axes, so this file carries no
// `WindRecipe`. It holds the component's default classNames instead: the exact
// strings the widget used to inline, lifted out so each one can be named,
// documented, and handed to a caller as the default of an optional parameter.
// Overriding a parameter REPLACES the constant below rather than appending to
// it, so a caller that changes a palette token has to re-supply the layout
// tokens sitting next to it. That is deliberate: appending would leave the
// default's `dark:` token alive under a light-only override, because Wind's
// last-wins is per family and `bg-*` and `dark:bg-*` are two families.

/// The default className of the popover panel (the dropdown surface).
///
/// Carries the panel width and radius as well as its palette, so an adopter
/// overriding it must re-supply `w-80` unless it wants a different width.
const String kNotificationDropdownPanelClassName = '''
  w-80
  bg-white dark:bg-gray-800
  border border-gray-200 dark:border-gray-700
  rounded-xl shadow-xl
''';

/// The default className of the trigger surface (the box around the bell).
///
/// The hover and active tones are part of it, so an override that drops them
/// drops the trigger's feedback with them.
const String kNotificationDropdownTriggerClassName = '''
  p-2 rounded-lg duration-150
  bg-transparent hover:bg-gray-100 dark:hover:bg-gray-800
  active:bg-gray-100 dark:active:bg-gray-800
''';

/// The default className of the trigger glyph (the bell itself).
///
/// `text-2xl` is the glyph SIZE, not only its color; an adopter fitting the
/// bell to a smaller control box overrides this rather than the surface.
const String kNotificationDropdownTriggerIconClassName =
    'text-2xl text-gray-500 dark:text-gray-400';

/// The default className of the unread badge pill.
///
/// The height is fixed (`h-[14px]`) while the width only has a floor
/// (`min-w-[14px]` plus `px-1`), so the pill grows sideways for a second digit
/// but never grows taller. That asymmetry is what
/// [kNotificationDropdownBadgeMaxTextScaleFactor] exists to protect.
///
/// The dark peer lightens the pill (`red-400`) because the panel it sits on is
/// `dark:bg-gray-800`: a light-mode `red-500` against that surface loses most
/// of the contrast step it has against white, and the unread count is the one
/// element of this component that has to read at a glance. It matters more
/// here than in the other defaults because an override REPLACES this string
/// rather than appending to it, so an adopter who overrides the pill inherits
/// nothing and this default is the only chance to ship the pair.
const String kNotificationDropdownBadgeClassName = '''
  min-w-[14px] h-[14px] px-1 rounded-full
  bg-red-500 dark:bg-red-400
  flex items-center justify-center
''';

/// The default className of the unread count inside the badge pill.
///
/// The dark peer follows the pill: on the lighter `dark:bg-red-400` fill a
/// near-black red reads far better than white does.
const String kNotificationDropdownBadgeTextClassName =
    'text-[9px] font-bold text-white dark:text-red-950';

/// The ceiling this component clamps the unread count's text scale to.
///
/// The badge pill is a FIXED 14px high (see
/// [kNotificationDropdownBadgeClassName]) holding a 9px line (see
/// [kNotificationDropdownBadgeTextClassName]), so an OS accessibility text
/// scale grows the digit while the box it sits in does not, and the digit is
/// clipped. This is not hypothetical: an adopter hit it on a real iOS device at
/// a large system text size and had to wrap the badge in its own
/// `MediaQuery.withClampedTextScaling` to stop it, on a pill LARGER than this
/// one. That adopter's value was 1.3, which makes 1.3 the ceiling for this
/// smaller pill rather than its target.
///
/// The value here is measured, not chosen: rendering the digit into this pill
/// and reading the paragraph's intrinsic height gives 13.0px at scale 1.0,
/// 14.0px at 1.1 and 15.0px at 1.2, so 1.1 is the largest factor whose line
/// still provably fits the 14px box. Anything above it clips.
///
/// Do not raise this without changing the pill's height in the same edit, and
/// do not delete it as a magic number: nothing in a widget test at the default
/// text scale will fail when it goes, only a device at a large system size.
const double kNotificationDropdownBadgeMaxTextScaleFactor = 1.1;
