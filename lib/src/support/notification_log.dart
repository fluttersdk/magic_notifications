import 'package:magic/magic.dart';

/// The one place this package writes a diagnostic from.
///
/// [Log] resolves `log` out of magic's container and THROWS when nothing bound
/// it. Every diagnostic in this package sits inside a `catch` or on a
/// degradation path, which is the worst possible place for a call that can
/// raise: handling a failure would itself fail, and a handled error would reach
/// the host as an unhandled one. A package must not require its consumer to
/// have bound a service the package chose to use for diagnostics, and an app
/// that registers no logging provider is a legitimate build, not only a test.
///
/// It ASKS rather than catching. `try { Log.error(...) } catch (_) {}` reaches
/// the same outcome and hides everything else with it: a broken log channel, a
/// driver that throws on write, a message that was never delivered. [Magic.bound]
/// answers the one question actually being asked, "is there a log here", and
/// anything that goes wrong past that point still propagates.
///
/// A host that HAS bound `log` is unaffected: it receives every message it
/// received before, at the same level, through the same facade.
///
/// ```dart
/// } catch (e) {
///   NotificationLog.error('Failed to fetch notifications: $e');
/// }
/// ```
class NotificationLog {
  /// Not instantiable: a namespace over [Log], not a service of its own.
  const NotificationLog._();

  /// The container key magic binds its log manager under.
  static const String _binding = 'log';

  /// Whether this host has a log to write to.
  static bool get _hasLog => Magic.bound(_binding);

  /// Report [message] at error level, when the host has a log to report to.
  static void error(String message) {
    if (!_hasLog) return;

    Log.error(message);
  }

  /// Report [message] at debug level, when the host has a log to report to.
  static void debug(String message) {
    if (!_hasLog) return;

    Log.debug(message);
  }
}
