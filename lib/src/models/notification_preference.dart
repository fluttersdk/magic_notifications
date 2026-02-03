/// Model for user notification preferences.
///
/// Stores global channel enablement (push/email/in_app) and per-type
/// channel preferences.
class NotificationPreference {
  /// Whether push notifications are enabled globally
  final bool pushEnabled;

  /// Whether email notifications are enabled globally
  final bool emailEnabled;

  /// Whether in-app notifications are enabled globally
  final bool inAppEnabled;

  /// Per-notification-type channel preferences
  final Map<String, ChannelPreference> typePreferences;

  /// Creates a new [NotificationPreference] instance.
  const NotificationPreference({
    this.pushEnabled = true,
    this.emailEnabled = true,
    this.inAppEnabled = true,
    this.typePreferences = const {},
  });

  /// Creates a [NotificationPreference] from API response map.
  factory NotificationPreference.fromMap(Map<String, dynamic> map) {
    final typePrefsMap = map['type_preferences'] as Map<String, dynamic>? ?? {};
    final typePreferences = <String, ChannelPreference>{};

    for (final entry in typePrefsMap.entries) {
      final prefMap = entry.value as Map<String, dynamic>;
      typePreferences[entry.key] = ChannelPreference.fromMap(prefMap);
    }

    return NotificationPreference(
      pushEnabled: map['push_enabled'] as bool? ?? true,
      emailEnabled: map['email_enabled'] as bool? ?? true,
      inAppEnabled: map['in_app_enabled'] as bool? ?? true,
      typePreferences: typePreferences,
    );
  }

  /// Converts this preference to a map for API requests.
  Map<String, dynamic> toMap() {
    final typePrefsMap = <String, dynamic>{};

    for (final entry in typePreferences.entries) {
      typePrefsMap[entry.key] = entry.value.toMap();
    }

    return {
      'push_enabled': pushEnabled,
      'email_enabled': emailEnabled,
      'in_app_enabled': inAppEnabled,
      'type_preferences': typePrefsMap,
    };
  }

  /// Checks if a notification type is enabled for a specific channel.
  ///
  /// Returns `false` if either:
  /// - The global channel setting is disabled, OR
  /// - The type-specific channel setting is disabled
  ///
  /// Returns `true` (default) if no type-specific preference exists.
  bool isEnabled(String notificationType, String channel) {
    // Check global setting first
    final globalEnabled = _isGlobalChannelEnabled(channel);
    if (!globalEnabled) return false;

    // Check type-specific preference
    final typePref = typePreferences[notificationType];
    if (typePref == null) return true; // Default to enabled

    return _isTypeChannelEnabled(typePref, channel);
  }

  bool _isGlobalChannelEnabled(String channel) {
    switch (channel) {
      case 'push':
        return pushEnabled;
      case 'mail':
      case 'email':
        return emailEnabled;
      case 'database':
      case 'in_app':
        return inAppEnabled;
      default:
        return false;
    }
  }

  bool _isTypeChannelEnabled(ChannelPreference pref, String channel) {
    switch (channel) {
      case 'push':
        return pref.push;
      case 'mail':
      case 'email':
        return pref.email;
      case 'database':
      case 'in_app':
        return pref.inApp;
      default:
        return false;
    }
  }

  /// Creates a copy of this preference with updated values.
  NotificationPreference copyWith({
    bool? pushEnabled,
    bool? emailEnabled,
    bool? inAppEnabled,
    Map<String, ChannelPreference>? typePreferences,
  }) {
    return NotificationPreference(
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
      inAppEnabled: inAppEnabled ?? this.inAppEnabled,
      typePreferences: typePreferences ?? this.typePreferences,
    );
  }
}

/// Channel-specific preferences for a notification type.
class ChannelPreference {
  /// Whether push is enabled for this notification type
  final bool push;

  /// Whether email is enabled for this notification type
  final bool email;

  /// Whether in-app is enabled for this notification type
  final bool inApp;

  /// Creates a new [ChannelPreference] instance.
  const ChannelPreference({
    this.push = true,
    this.email = true,
    this.inApp = true,
  });

  /// Creates a [ChannelPreference] from API response map.
  factory ChannelPreference.fromMap(Map<String, dynamic> map) {
    return ChannelPreference(
      push: map['push'] as bool? ?? true,
      email: map['email'] as bool? ?? true,
      inApp: map['in_app'] as bool? ?? true,
    );
  }

  /// Converts this preference to a map for API requests.
  Map<String, dynamic> toMap() {
    return {
      'push': push,
      'email': email,
      'in_app': inApp,
    };
  }
}
