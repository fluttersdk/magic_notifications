# Changelog

## [Unreleased]

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
