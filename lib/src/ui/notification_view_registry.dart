import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Builds a view widget for a registry key.
typedef NotificationViewBuilder = Widget Function();

/// Builds a layout widget wrapping [child] for a registry key.
typedef NotificationLayoutBuilder = Widget Function(Widget child);

/// Builds a modal widget for a registry key.
typedef NotificationModalBuilder = Widget Function();

/// Slot builder receives the current [BuildContext] and returns a widget.
typedef NotificationSlotBuilder = Widget Function(BuildContext context);

/// Registry for notification view builders.
///
/// Allows overriding the shipped screens (the notification list, the
/// preference matrix) by string key, and injecting widgets into the named
/// slots those screens expose. Reachable as `Notify.view`.
///
/// The API is deliberately the same shape as the starter kit's own view
/// registry, so an adopter who knows one knows the other:
///
/// ```dart
/// Notify.view.register('notifications.list', () => const MyOwnListView());
/// Notify.view.slot('notifications.preferences', 'header', (context) {
///   return const WText('Alerts reach you here first.');
/// });
/// ```
class NotificationViewRegistry {
  /// The view key every notification type-icon slot is registered under.
  ///
  /// The slot NAME is the notification type, so an adopter says what one of
  /// its own types looks like without this package carrying a vocabulary that
  /// belongs to one product:
  ///
  /// ```dart
  /// Notify.view.slot(NotificationViewRegistry.typeIconSlotView, 'order_shipped',
  ///     (context) => WIcon(Icons.local_shipping, className: 'text-lg text-green-500'));
  /// ```
  static const String typeIconSlotView = 'notifications.icon';

  /// The type-icon slot name consulted when the notification's own type has no
  /// slot, so an adopter can answer for every remaining type at once.
  static const String typeIconFallbackSlot = 'default';

  final Map<String, NotificationViewBuilder> _builders =
      <String, NotificationViewBuilder>{};
  final Map<String, NotificationLayoutBuilder> _layouts =
      <String, NotificationLayoutBuilder>{};
  final Map<String, NotificationModalBuilder> _modals =
      <String, NotificationModalBuilder>{};

  /// Slot builders keyed by `'view.slot'` (e.g. `'notifications.list.header'`).
  final Map<String, NotificationSlotBuilder> _slots =
      <String, NotificationSlotBuilder>{};

  /// Keys currently holding a builder this PACKAGE seeded, not one a caller
  /// registered.
  ///
  /// `has(key)` cannot answer "is this screen spoken for", because the two
  /// screens this package ships are seeded into every registry the moment
  /// `Notify.view` is first read, so the answer is yes before anybody has
  /// chosen anything. A caller deciding whether to install its own default
  /// needs [hasOverride] instead.
  final Set<String> _defaults = <String>{};

  /// Register a builder under the given key.
  void register(String key, NotificationViewBuilder builder) {
    _builders[key] = builder;
    _defaults.remove(key);
  }

  /// Register a builder this package ships, which [hasOverride] does not count.
  ///
  /// `Notify.view` seeds the two screens through this so a downstream package
  /// can tell them apart from a deliberate choice. A later [register] on the
  /// same key promotes it to an override.
  ///
  /// `@internal` rather than private, because Dart's privacy is library-level
  /// and `notify.dart` has to call it. The annotation is the only thing that
  /// can say so: this class is exported from the barrel, so a host CAN reach
  /// this method, and a host that uses it inverts the guarantee the method
  /// exists to provide. Its screen would be marked a default, [hasOverride]
  /// would answer false for it, and the next downstream package gating on
  /// [hasOverride] would overwrite the choice the host had made. Use [register].
  @internal
  void registerDefault(String key, NotificationViewBuilder builder) {
    _builders[key] = builder;
    _defaults.add(key);
  }

  /// Whether [key] holds a builder somebody CHOSE, rather than one this package
  /// seeded.
  ///
  /// This is the question a downstream package asks before installing its own
  /// default. `magic_starter` mounts the two screens wrapped in the host's page
  /// geometry, and it has to lose to an app that registered its own screen
  /// while still winning over the bare defaults this package seeds: gating that
  /// on [has] means it always loses, and the wrap it exists to apply never
  /// reaches the screen.
  bool hasOverride(String key) =>
      _builders.containsKey(key) && !_defaults.contains(key);

  /// Register a layout builder under the given key.
  void registerLayout(String key, NotificationLayoutBuilder builder) {
    _layouts[key] = builder;
  }

  /// Returns true when a builder exists for [key].
  bool has(String key) => _builders.containsKey(key);

  /// Returns true when a layout builder exists for [key].
  bool hasLayout(String key) => _layouts.containsKey(key);

  /// Build a widget by [key].
  ///
  /// Throws [StateError] when the key is not registered.
  Widget make(String key) {
    final builder = _builders[key];

    if (builder == null) {
      throw StateError('No view builder registered for key "$key".');
    }

    return builder();
  }

  /// Build a layout by [key] wrapping [child].
  ///
  /// Throws [StateError] when the key is not registered.
  Widget makeLayout(String key, {required Widget child}) {
    final builder = _layouts[key];

    if (builder == null) {
      throw StateError('No layout builder registered for key "$key".');
    }

    return builder(child);
  }

  /// Register a modal builder under the given key.
  void registerModal(String key, NotificationModalBuilder builder) {
    _modals[key] = builder;
  }

  /// Returns true when a modal builder exists for [key].
  bool hasModal(String key) => _modals.containsKey(key);

  /// Build a modal widget by [key].
  ///
  /// Throws [StateError] when the key is not registered.
  Widget makeModal(String key) {
    final builder = _modals[key];

    if (builder == null) {
      throw StateError('No modal builder registered for key "$key".');
    }

    return builder();
  }

  // -------------------------------------------------------------------------
  // Slot API
  // -------------------------------------------------------------------------

  /// Register a slot builder for a named slot within a view.
  ///
  /// [viewKey] is the view identifier (e.g. `'notifications.list'`).
  /// [slotName] is the slot name (e.g. `'header'`, `'footer'`).
  /// [builder] receives [BuildContext] and returns the injected widget.
  ///
  /// ```dart
  /// Notify.view.slot('notifications.list', 'header', (context) {
  ///   return WText('Everything we sent you', className: 'text-2xl font-bold');
  /// });
  /// ```
  void slot(String viewKey, String slotName, NotificationSlotBuilder builder) {
    _slots['$viewKey.$slotName'] = builder;
  }

  /// Returns true when a slot builder is registered for [viewKey] + [slot].
  bool hasSlot(String viewKey, String slot) =>
      _slots.containsKey('$viewKey.$slot');

  /// Build the slot widget for [viewKey] + [slot], or `null` when not registered.
  ///
  /// ```dart
  /// final headerSlot = Notify.view.buildSlot('notifications.list', 'header', context);
  /// if (headerSlot != null) ...[headerSlot, const WSpacer(className: 'h-4')],
  /// ```
  Widget? buildSlot(String viewKey, String slot, BuildContext context) {
    final builder = _slots['$viewKey.$slot'];
    return builder?.call(context);
  }

  /// Build the leading icon an adopter registered for a notification [type],
  /// or `null` when it registered neither that type nor a fallback.
  ///
  /// This is the package's ONE answer to "what does this notification type look
  /// like": both the dropdown and the list view read it, and it replaces the
  /// hardcoded type-to-icon map those screens carried in. A caller renders its
  /// own neutral icon when this answers null.
  Widget? buildTypeIcon(String type, BuildContext context) {
    return buildSlot(typeIconSlotView, type, context) ??
        buildSlot(typeIconSlotView, typeIconFallbackSlot, context);
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  /// Remove all builders (useful for tests).
  void clear() {
    _builders.clear();
    _defaults.clear();
    _layouts.clear();
    _modals.clear();
    _slots.clear();
  }
}
