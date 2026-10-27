/// What OneSignal's web service worker does with an open tab of the app when
/// a push is clicked.
///
/// The SDK's own defaults are `exact` and `navigate`. With `exact`, an open tab
/// is reused only when its url is the notification's launch url to the
/// character. Any other open tab is ignored, and the worker opens a new tab.
/// That new tab is a cold page load: no Dart is running in it yet to receive
/// the click, so `NotificationManager.onPushClicked` never fires. The handler
/// that subscribes to it never routes the push either, and it is the one that
/// knows the push's tenant.
///
/// With `origin` and `focus`, the worker focuses any open tab on the app's
/// origin and hands it the click. The page's own listener then republishes it
/// on `onPushClicked`, so the open tab routes the push. `navigate` is not used
/// here: it calls `WindowClient.navigate`, which only works on a tab that the
/// worker controls. OneSignal's worker is registered under its own scope,
/// next to Flutter's, so it does not control any app tab. When no tab is open,
/// the worker opens the push's launch url (`web_url`) exactly as before.
///
/// A dashboard ("Typical site") integration ignores these init options and
/// reads its click behaviour from OneSignal's settings instead.
///
/// Source: OneSignal-Website-SDK `src/shared/helpers/init.ts` (persists both
/// options, defaulting to `exact` and `navigate`) and
/// `src/sw/serviceWorker/ServiceWorker.ts` (`onNotificationClicked`).
library;

/// How an open tab is matched against a clicked push's launch url.
const String oneSignalClickMatch = 'origin';

/// What the worker does with the open tab it matched.
const String oneSignalClickAction = 'focus';
