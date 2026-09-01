// NotificationDropdown component — folder-local barrel.

export 'notification_dropdown.dart' show NotificationDropdown;

// The defaults behind the widget's five className parameters. Exported because
// an override REPLACES its default: an adopter changing one palette token has
// to re-supply the layout tokens sitting next to it, and reading the constant
// beats restating it from a docblock.
export 'notification_dropdown.recipe.dart'
    show
        kNotificationDropdownBadgeClassName,
        kNotificationDropdownBadgeTextClassName,
        kNotificationDropdownPanelClassName,
        kNotificationDropdownTriggerClassName,
        kNotificationDropdownTriggerIconClassName;
