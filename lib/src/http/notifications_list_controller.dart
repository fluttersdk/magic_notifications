import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:magic/magic.dart';

import '../facades/notify.dart';
import '../models/paginated_notifications.dart';
import '../support/notification_log.dart';

/// Controller behind the notification list screen.
///
/// Holds the page the user is on and the rows that page carries, reading them
/// through [Notify.fetchPaginatedNotifications]. Registered as a Magic
/// singleton, so the screen comes back on the page it was showing after a
/// remount and a host (or a test) can reach its state through the container
/// rather than through a widget state nothing can address.
class NotificationsListController extends MagicController
    with MagicStateMixin<bool> {
  /// Singleton accessor.
  static NotificationsListController get instance =>
      Magic.findOrPut(NotificationsListController.new);

  /// The page currently on screen, or `null` before the first read lands.
  ///
  /// The rows live here rather than in the [MagicStateMixin] state because
  /// `setLoading()` clears that state: paging forward would empty the table on
  /// every chevron tap and flash a spinner between two pages the screen
  /// already had rows for.
  final pageNotifier = ValueNotifier<PaginatedNotifications?>(null);

  /// Rows requested per page.
  ///
  /// The view publishes its own `perPage` here when it mounts, so a reload
  /// after a mark-as-read keeps the page size the host asked for instead of
  /// falling back to this default.
  int perPage = 15;

  int _currentPage = 1;

  /// The page number the last successful read landed on.
  int get currentPage => _currentPage;

  /// Drops the previous person's rows when the session ends.
  ///
  /// This controller is a `Magic.findOrPut` singleton and magic's controller
  /// registry is process-lifetime, so sign-out disposes nothing here: without
  /// this subscription, B signs in on a shared device, opens the list, and
  /// `build` paints A's incident titles out of [pageNotifier] before `onInit`'s
  /// refresh lands. [loadPage]'s catch then deliberately leaves the rows up, so
  /// a refresh that fails leaves A's rows on B's screen indefinitely.
  late final StreamSubscription<void> _sessionCleared =
      Notify.manager.onSessionCleared.listen((_) => _clearSession());

  @override
  void onInit() {
    // Touched so the late field initialises: the subscription has to exist from
    // the moment the controller does, not from the first sign-out after
    // something happened to read it.
    _sessionCleared;
    super.onInit();
  }

  /// The session a read belongs to.
  ///
  /// Clearing what is on screen is only half of it, which is the same lesson
  /// `NotificationManager` already learned for the bell: a read issued for the
  /// person who just signed out is still in the air and answers with THEIR
  /// rows. `fetchPaginatedNotifications` carries no epoch of its own, and
  /// `logoutPush` clears before its first await, so without this the order is
  /// clear, then A's page lands, then B's first frame paints it. The window is
  /// narrow and it is also the refresh that runs whenever the list is opened,
  /// so "sign out while the spinner is up" reaches it.
  int _session = 0;

  /// Forget the page held for the session that just ended.
  void _clearSession() {
    _session++;
    _currentPage = 1;
    pageNotifier.value = null;

    // `setEmpty`, not `setSuccess(false)`: the argument to `setSuccess` is the
    // DATA, so that call left the status reading success, which claims a load
    // that answered nothing rather than a screen holding nothing yet.
    setEmpty();
  }

  /// Read [page] from the backend and publish it.
  ///
  /// Deliberately NOT guarded against a second call while one is in flight.
  /// The guard the preference matrix needed had to be keyed per cell for the
  /// same reason: an unkeyed one here would turn a second chevron tap into a
  /// tap that visibly does nothing, with no spinner and no message.
  ///
  /// The catch is what puts the screen in its error state, and it now covers
  /// every way the read can fail: [Notify.fetchPaginatedNotifications] raises
  /// a dropped connection, a non-2xx answer and an undecodable body alike
  /// rather than absorbing them into an empty page. The rows already on
  /// screen are left alone, so a failed reload shows the failure without
  /// throwing away what the user was reading.
  ///
  /// The report goes through [NotificationLog] rather than [Log], because a
  /// host that bound no logging provider would otherwise have `Log.error`
  /// throw here and lose the error state this catch exists to set.
  Future<void> loadPage(int page) async {
    final int session = _session;

    setLoading();

    try {
      final result = await Notify.fetchPaginatedNotifications(
        page: page,
        perPage: perPage,
      );

      // The session ended while this was in the air, so the rows belong to
      // whoever asked for them and not to whoever is holding the device now.
      if (session != _session) return;

      _currentPage = page;
      pageNotifier.value = result;
      setSuccess(true);
    } catch (e, stackTrace) {
      NotificationLog.error(
        '[NotificationsListController.loadPage] $e\n$stackTrace',
      );

      // Guarded too: a read that failed for the PREVIOUS person must not drop
      // the next one's freshly cleared screen into an error state they have no
      // way to explain.
      if (session != _session) return;

      setError(trans('notifications.load_failed'));
    }
  }

  /// Re-read the page currently on screen.
  ///
  /// This is what every mutation on the screen (mark as read, mark all as
  /// read, delete) follows with, so the user stays where they were.
  Future<void> refresh() => loadPage(_currentPage);

  @override
  void dispose() {
    _sessionCleared.cancel();
    pageNotifier.dispose();
    super.dispose();
  }
}
