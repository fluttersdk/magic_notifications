import 'dart:async';

/// Polls for notifications at regular intervals.
///
/// Usage:
/// ```dart
/// final poller = NotificationPoller(NotificationManager());
/// poller.start(); // Begin 30-second polling
///
/// // Pause when app goes to background
/// poller.pause();
///
/// // Resume when app comes to foreground
/// poller.resume();
///
/// // Fetch immediately without waiting for next interval
/// await poller.refresh();
///
/// // Stop polling completely
/// poller.stop();
/// ```
class NotificationPoller {
  final dynamic _manager;
  final Duration _interval;

  Timer? _timer;
  bool _isPaused = false;

  /// Create a notification poller.
  ///
  /// Accepts any object with a `fetchNotifications()` method.
  /// [interval] defaults to 30 seconds if not specified.
  NotificationPoller(
    this._manager, {
    Duration interval = const Duration(seconds: 30),
  }) : _interval = interval;

  /// Whether polling is currently active.
  bool get isActive => _timer != null && _timer!.isActive && !_isPaused;

  /// Whether polling is paused.
  bool get isPaused => _isPaused;

  /// Start polling for notifications.
  ///
  /// If already started, does nothing (idempotent).
  void start() {
    if (_timer != null && _timer!.isActive) {
      return; // Already started
    }

    _isPaused = false;

    // Fetch immediately on start
    _manager.fetchNotifications();

    // Then poll at regular intervals
    _timer = Timer.periodic(_interval, (_) {
      if (!_isPaused) {
        _manager.fetchNotifications();
      }
    });
  }

  /// Stop polling completely.
  ///
  /// Timer is canceled and must be restarted with [start()].
  void stop() {
    _timer?.cancel();
    _timer = null;
    _isPaused = false;
  }

  /// Pause polling temporarily.
  ///
  /// Timer continues running but fetch calls are skipped.
  /// Use [resume()] to continue polling.
  void pause() {
    _isPaused = true;
  }

  /// Resume polling after [pause()].
  ///
  /// Fetches immediately and continues periodic polling.
  void resume() {
    if (!_isPaused) {
      return; // Not paused
    }

    _isPaused = false;

    // Fetch immediately on resume
    _manager.fetchNotifications();
  }

  /// Fetch notifications immediately without affecting polling state.
  ///
  /// This does not start, stop, or interfere with the periodic polling.
  Future<void> refresh() async {
    await _manager.fetchNotifications();
  }
}
