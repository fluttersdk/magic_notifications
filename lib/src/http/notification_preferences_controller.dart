import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

/// Controller behind the notification preference matrix.
///
/// Holds the type x channel matrix the backend publishes at
/// `/notification-preferences` and writes a single toggle back optimistically.
/// Registered as a Magic singleton, so the screen survives a remount with the
/// matrix it already fetched.
class NotificationPreferencesController extends MagicController
    with MagicStateMixin<bool> {
  /// Singleton accessor.
  static NotificationPreferencesController get instance =>
      Magic.findOrPut(NotificationPreferencesController.new);

  /// Preference matrix from the backend.
  ///
  /// Structure:
  /// `{ "type_key": { "label": "...", "channels": { "channel": { "enabled": bool, "locked": bool } } } }`
  final matrixNotifier = ValueNotifier<Map<String, dynamic>>({});

  /// Whether the backend reports its push integration as provisioned, read
  /// from the preference responses' `meta.push_provisioned`.
  ///
  /// A push preference is offered as soon as the backend enables its push
  /// feature flag, but without a configured OneSignal `app_id` the channel is
  /// dropped at send time, so a `false` here means the toggle cannot deliver
  /// yet. Starts `true` and only moves on a response that actually carries the
  /// flag, so a backend that predates it (or a degraded payload) never renders
  /// a false "not configured" claim.
  final pushProvisionedNotifier = ValueNotifier<bool>(true);

  bool _isFetching = false;
  bool _isSaving = false;

  /// Fetch the notification preference matrix from the API.
  Future<void> fetchPreferences() async {
    if (_isFetching) return;
    _isFetching = true;
    setLoading();

    try {
      // 1. Fetch the current notification preference matrix.
      final response = await Http.get('/notification-preferences');

      // 2. Stop early when the backend returns an unsuccessful response.
      if (!response.successful) {
        setError(trans('notifications.fetch_error'));
        return;
      }

      // 3. Publish the push-provisioning flag the same response carries.
      _publishPushProvisioned(response);

      // 4. Normalize and publish the matrix for reactive UI updates.
      final data = response.data['data'];
      if (data is Map) {
        matrixNotifier.value = _normalizeMap(data);
      }
      setSuccess(true);
    } catch (e, stackTrace) {
      Log.error(
        '[NotificationPreferencesController.fetchPreferences] $e\n$stackTrace',
      );
      setError(trans('errors.unexpected'));
    } finally {
      _isFetching = false;
    }
  }

  /// Publish `meta.push_provisioned` from [response] into
  /// [pushProvisionedNotifier], leaving the last known value untouched when the
  /// payload does not carry the flag as a bool.
  ///
  /// A missing flag is a backend that predates it or a degraded payload, not a
  /// statement that push became unconfigured, so it must never flip the value.
  void _publishPushProvisioned(MagicResponse response) {
    final data = response.data;
    if (data is! Map) return;

    final meta = data['meta'];
    if (meta is! Map) return;

    final provisioned = meta['push_provisioned'];
    if (provisioned is bool) {
      pushProvisionedNotifier.value = provisioned;
    }
  }

  /// Normalize dynamic map payloads to `Map<String, dynamic>` recursively.
  Map<String, dynamic> _normalizeMap(Map<dynamic, dynamic> source) {
    return source.map(
      (key, value) =>
          MapEntry(key.toString(), value is Map ? _normalizeMap(value) : value),
    );
  }

  /// Update a single channel preference with an optimistic UI update.
  ///
  /// 1. Snapshot the current matrix as rollback state.
  /// 2. Apply the optimistic update locally.
  /// 3. Send the PUT request to the backend.
  /// 4. Revert to the snapshot on failure.
  Future<void> updateTypePreference(
    String type,
    String channel,
    bool isEnabled,
  ) async {
    if (_isSaving) return;
    _isSaving = true;

    // 1. Snapshot for rollback.
    final oldMatrix = Map<String, dynamic>.from(matrixNotifier.value);

    try {
      // 2. Apply the optimistic update.
      final newMatrix = Map<String, dynamic>.from(matrixNotifier.value);
      if (newMatrix.containsKey(type)) {
        final typeData = Map<String, dynamic>.from(
          newMatrix[type] as Map<String, dynamic>,
        );
        if (typeData.containsKey('channels')) {
          final channelsData = Map<String, dynamic>.from(
            typeData['channels'] as Map<String, dynamic>,
          );
          if (channelsData.containsKey(channel)) {
            final channelData = Map<String, dynamic>.from(
              channelsData[channel] as Map<String, dynamic>,
            );
            channelData['enabled'] = isEnabled;
            channelsData[channel] = channelData;
          }
          typeData['channels'] = channelsData;
        }
        newMatrix[type] = typeData;
      }
      matrixNotifier.value = newMatrix;

      // 3. Send to the backend.
      final response = await Http.put(
        '/notification-preferences',
        data: {'type': type, 'channel': channel, 'is_enabled': isEnabled},
      );

      // 4. Revert on failure.
      if (!response.successful) {
        matrixNotifier.value = oldMatrix;
        Log.error(
          '[NotificationPreferencesController.updateTypePreference] '
          'PUT failed: ${response.statusCode}',
        );

        return;
      }

      // 5. The write response republishes the provisioning flag, so a save
      // keeps the heads-up in sync without a second fetch.
      _publishPushProvisioned(response);
    } catch (e, stackTrace) {
      matrixNotifier.value = oldMatrix;
      Log.error(
        '[NotificationPreferencesController.updateTypePreference] '
        '$e\n$stackTrace',
      );
    } finally {
      _isSaving = false;
    }
  }

  @override
  void dispose() {
    matrixNotifier.dispose();
    pushProvisionedNotifier.dispose();
    super.dispose();
  }
}
