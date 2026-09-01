import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../facades/notify.dart';
import '../support/notification_log.dart';

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

  /// Drops the previous person's preference matrix when the session ends.
  ///
  /// This controller is a `Magic.findOrPut` singleton and magic's controller
  /// registry is process-lifetime, so sign-out disposes nothing here. Without
  /// this subscription, B signs in on a shared device and the preferences
  /// screen paints A's per-type channel matrix out of [matrixNotifier] until a
  /// fresh read lands, and a read that fails leaves it there.
  late final StreamSubscription<void> _sessionCleared =
      Notify.manager.onSessionCleared.listen((_) => _clearSession());

  @override
  void onInit() {
    // Touched so the late field initialises: the subscription has to exist from
    // the moment the controller does.
    _sessionCleared;
    super.onInit();
  }

  /// Forget the matrix held for the session that just ended.
  ///
  /// [pushProvisionedNotifier] goes back to `true` rather than to the last
  /// value read, for the reason its own doc gives: it is a claim about the
  /// BACKEND, and the honest state before any read for this session is "no
  /// reason to say otherwise" rather than a false "not configured".
  void _clearSession() {
    _saving.clear();
    _isFetching = false;
    matrixNotifier.value = <String, dynamic>{};
    pushProvisionedNotifier.value = true;
    setSuccess(false);
  }

  /// The cells with a write in flight, keyed by type and channel.
  ///
  /// One flag across the whole matrix made a second toggle during an in-flight
  /// PUT a tap that visibly does nothing: the early return neither queues the
  /// edit nor reports it, and `WSwitch.value` reads the stored data the return
  /// never touched, so there is no spinner, no snap-back and no message. An
  /// operator silencing two noisy channels in a row keeps being paged by the
  /// second one with nothing on screen saying why.
  final Set<String> _saving = <String>{};

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
      NotificationLog.error(
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
  /// 1. Take the guard for THIS cell, so an edit to another one is not blocked.
  /// 2. Snapshot the cell's current value as rollback state.
  /// 3. Apply the optimistic update locally.
  /// 4. Send the PUT request to the backend.
  /// 5. Revert that one cell on failure.
  Future<void> updateTypePreference(
    String type,
    String channel,
    bool isEnabled,
  ) async {
    final String cell = '$type.$channel';
    if (!_saving.add(cell)) return;

    // 1. Snapshot the CELL, not the matrix: a neighbouring cell can now be
    //    written at the same time, and restoring a whole-matrix snapshot taken
    //    before that edit would undo a write the backend accepted, with nothing
    //    re-applying it. The switch would then read enabled while the channel
    //    is silenced, which is the failure this method exists to prevent.
    final bool? previous = _channelEnabled(matrixNotifier.value, type, channel);

    try {
      // 2. Apply the optimistic update.
      matrixNotifier.value = _withChannelEnabled(
        matrixNotifier.value,
        type,
        channel,
        isEnabled,
      );

      // 3. Send to the backend.
      final response = await Http.put(
        '/notification-preferences',
        data: {'type': type, 'channel': channel, 'is_enabled': isEnabled},
      );

      // 4. Revert on failure.
      if (!response.successful) {
        _revertChannel(type, channel, previous);
        NotificationLog.error(
          '[NotificationPreferencesController.updateTypePreference] '
          'PUT failed: ${response.statusCode}',
        );

        return;
      }

      // 5. The write response republishes the provisioning flag, so a save
      // keeps the heads-up in sync without a second fetch.
      _publishPushProvisioned(response);
    } catch (e, stackTrace) {
      _revertChannel(type, channel, previous);
      NotificationLog.error(
        '[NotificationPreferencesController.updateTypePreference] '
        '$e\n$stackTrace',
      );
    } finally {
      _saving.remove(cell);
    }
  }

  /// The `enabled` flag [type]'s [channel] currently carries, or `null` when
  /// the matrix does not describe that cell.
  bool? _channelEnabled(
    Map<String, dynamic> matrix,
    String type,
    String channel,
  ) {
    final Object? typeData = matrix[type];
    if (typeData is! Map) return null;

    final Object? channelsData = typeData['channels'];
    if (channelsData is! Map) return null;

    final Object? channelData = channelsData[channel];
    if (channelData is! Map) return null;

    final Object? enabled = channelData['enabled'];

    return enabled is bool ? enabled : null;
  }

  /// [matrix] with [type]'s [channel] carrying [isEnabled], and [matrix] itself
  /// when it does not describe that cell.
  ///
  /// Rebuilt rather than mutated in place, because [matrixNotifier] only
  /// notifies on a new instance.
  Map<String, dynamic> _withChannelEnabled(
    Map<String, dynamic> matrix,
    String type,
    String channel,
    bool isEnabled,
  ) {
    final Object? typeData = matrix[type];
    if (typeData is! Map) return matrix;

    final Object? channelsData = typeData['channels'];
    if (channelsData is! Map) return matrix;

    final Object? channelData = channelsData[channel];
    if (channelData is! Map) return matrix;

    return <String, dynamic>{
      ...matrix,
      type: <String, dynamic>{
        ..._normalizeMap(typeData),
        'channels': <String, dynamic>{
          ..._normalizeMap(channelsData),
          channel: <String, dynamic>{
            ..._normalizeMap(channelData),
            'enabled': isEnabled,
          },
        },
      },
    };
  }

  /// Puts [previous] back on one cell after its write failed.
  ///
  /// A `null` [previous] is a cell the matrix never described, which the
  /// optimistic update left untouched too, so there is nothing to put back.
  void _revertChannel(String type, String channel, bool? previous) {
    if (previous == null) return;

    matrixNotifier.value = _withChannelEnabled(
      matrixNotifier.value,
      type,
      channel,
      previous,
    );
  }

  @override
  void dispose() {
    _sessionCleared.cancel();
    matrixNotifier.dispose();
    pushProvisionedNotifier.dispose();
    super.dispose();
  }
}
