# Changelog

## [Unreleased]

### Added
- **Notification state can arrive over a socket instead of being polled for.** `Notify.startRealtime(channel: ...)` subscribes to the notifiable's private broadcast channel and applies each `notification.created` frame straight to the stream, so a new notification shows up when the server sends it rather than up to 30 seconds later. The frame carries the whole row in the same shape `GET /notifications` returns, so no HTTP follows it.
- `Notify.stopRealtime()`, `Notify.isRealtime` and `Notify.isPolling`.

### Changed
- **`startPolling()` is a no-op while realtime is live.** A consumer keeps wiring it to auth state and does not have to know whether a socket happens to be up: with one, the 30-second timer is waste on top of a connection that already delivers every row; without one, nothing changes. `stopRealtime()` or a dropped connection restores the timer.
- **`magic` constraint bumped to `^0.0.6`.** `Echo.connection` (the public driver accessor) is the floor for the realtime path: without it there is no way to tell an already-open connection from a closed one, and magic's Reverb driver opens a SECOND WebSocket on a redundant `connect()` instead of refusing it. A `0.0.z` caret pins the patch digit, so `^0.0.5` resolved exactly 0.0.5, which has no such accessor.

### Fixed
- **A socket frame that arrived while `fetchNotifications()` was in flight was clobbered by the read.** The frame prepended to the cached list and the server's list was then assigned over the top, so the notification vanished until something fetched again. The window is small and entirely real, because `startRealtime()` subscribes and THEN fetches, which is the exact moment a backlog is most likely to be publishing. Frames received during a read are now merged back on top, keyed by id.
- **`startRealtime()`'s idempotence key now includes the event name.** Keyed on the channel alone, a caller that changed the event for the same channel hit the early return, so the manager silently kept handling the old event name and delivered nothing, with no error.

### Notes
- Realtime is opt-in and degrades in both directions. `startRealtime()` returns `false` and changes nothing when no broadcast driver is configured (a `BROADCAST_CONNECTION=null` deployment), and a socket that drops falls back to polling until it returns, at which point the fallback is dropped and the list is refetched once to cover what Reverb cannot replay.
- The channel name is the caller's to supply (`App.Models.User.{id}` by Laravel's default): this package has no user model and cannot know whose notifications it is receiving. See `doc/basics/laravel-backend-setup.md` for the server half.

## [0.0.2] - 2026-07-26

### Changed
- **`magic` constraint bumped to `^0.0.5`.** Tracks the magic 0.0.5 release (the `Model.save()` 422 validation-error surface and the auth-state redirect refresh). Under pub's `0.0.z` caret semantics every bump of magic's patch digit is an upper-bound break, so a plugin left on `^0.0.4` makes a shared resolution with any consumer on magic 0.0.5 unsolvable. This release exists to keep that graph solvable; there is no behavior change in this package.

## [0.0.1] - 2026-06-24

### Breaking Changes
- **Removed `bin/magic_notifications.dart` entrypoint**: CLI commands now surface via host app's artisan binary (`dart run <app>:artisan notifications:<cmd>`), not as a standalone `dart run magic_notifications <cmd>`. Update your scripts and CI workflows accordingly.
- **Removed `magic_cli` dependency**: Install now uses `fluttersdk_artisan`'s manifest-driven model, not magic_cli's imperative Kernel.

### Changed
- **Install now manifest-driven**: `install.yaml` declares the static slice (provider injection only); dynamic logic (UUID validation, platform conditionals, placeholder-rendered config, arbitrary file writes) lives in `InstallCommand`'s fluent override.
- **CLI architecture**: Commands contributed via `MagicNotificationsArtisanProvider` registered in host's `artisan.providers` config.

### Added
- **MCP tools**: `notifications_doctor` and `notifications_channels` are now read-only tools available to AI agents via MCP.

### 📚 Documentation
- **README**: Rewrite to match Magic ecosystem format
- **doc/ folder**: Add comprehensive documentation
- **CLAUDE.md**: Add project guidance for AI-assisted development

## [0.0.1-alpha.1] - 2026-03-25

### ✨ Core Features
- **Multi-channel notifications**: Database (in-app), Push (OneSignal), Mail (contract)
- **Notify facade**: Static API for sending, fetching, polling, preferences
- **NotificationManager**: Singleton dispatcher with channel/driver orchestration
- **NotificationPoller**: Timer-based background polling with pause/resume/stop
- **User preferences**: Global channel toggles + per-type channel preferences
- **Optimistic updates**: markAsRead, markAllAsRead, delete with API rollback

### 🔔 Push Notifications
- **OneSignalDriver**: iOS/Android push via onesignal_flutter ^5.4.0
- **OneSignalWebDriver**: Web push via JS interop with conditional imports
- **PushPromptDialog**: Soft prompt widget before OS permission request
- **Push subscription**: Permission state tracking, opt-in/opt-out

### 🔧 CLI Tools
- **install**: Interactive wizard, config, pubspec, platform files, OneSignal setup
- **configure**: Show/update notification settings
- **doctor**: Health check with exit codes
- **test**: Send test notifications (dry-run, database, push, mail)
- **channels**: List channel status
- **uninstall**: Remove plugin integration
- **publish**: Copy config stub to consumer project

### 🏗️ Architecture
- **Contract-first design**: Notification, NotificationChannel, Notifiable abstractions
- **Service Provider**: Two-phase bootstrap (register + boot) with IoC bindings
- **Driver abstraction**: Swappable push providers (OneSignal, FCM, etc.)
- **Config-driven**: All settings via Magic ConfigRepository
