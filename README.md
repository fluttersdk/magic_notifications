<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/magic/master/.github/magic-logo.svg" width="120" alt="Magic Logo" />
</p>

<h1 align="center">Magic Notifications</h1>

<p align="center">
  <strong>Multi-channel notifications for the Magic Framework.</strong><br/>
  Database, Push & Mail — one unified API.
</p>

<p align="center">
  <a href="https://pub.dev/packages/magic_notifications"><img src="https://img.shields.io/pub/v/magic_notifications.svg" alt="pub.dev version" /></a>
  <a href="https://github.com/fluttersdk/magic_notifications/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/magic_notifications/ci.yml?branch=master&label=CI" alt="CI Status" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT" /></a>
  <a href="https://pub.dev/packages/magic_notifications/score"><img src="https://img.shields.io/pub/points/magic_notifications" alt="pub points" /></a>
  <a href="https://github.com/fluttersdk/magic_notifications/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/magic_notifications?style=flat" alt="GitHub Stars" /></a>
</p>

<p align="center">
  <a href="https://magic.fluttersdk.com/notifications">Website</a> ·
  <a href="https://magic.fluttersdk.com/packages/notifications/getting-started/installation">Docs</a> ·
  <a href="https://pub.dev/packages/magic_notifications">pub.dev</a> ·
  <a href="https://github.com/fluttersdk/magic_notifications/issues">Issues</a> ·
  <a href="https://github.com/fluttersdk/magic_notifications/discussions">Discussions</a>
</p>

---

> **Alpha** — `magic_notifications` is under active development. APIs may change between minor versions until `1.0.0`.

---

## Why Magic Notifications?

Managing notifications in Flutter means juggling multiple channels — database polling, platform-specific push setup for iOS/Android/Web, email delivery, and user preference logic scattered across your codebase. Every project reinvents the same boilerplate.

**Magic Notifications** gives you a single, unified API for every channel. One config file drives everything. One CLI command sets up your project. Channels and drivers are swappable — switch from OneSignal to another push provider without touching application code.

> **Config-driven notifications.** Define your channels, drivers, and preferences once. Magic Notifications handles the rest.

---

## Features

| | Feature | Description |
|---|---------|-------------|
| :bell: | **Multi-channel** | Database, Push, and Mail channels through one API |
| :iphone: | **OneSignal Push** | iOS, Android, and Web push via `onesignal_flutter` |
| :arrows_counterclockwise: | **Real-time Polling** | Background polling with pause/resume/stop lifecycle |
| :dart: | **User Preferences** | Global and per-type channel preference management |
| :hammer_and_wrench: | **CLI Tools** | Interactive install, configure, doctor, test, and more |
| :gear: | **Config-Driven** | All settings in one Dart config file via `ConfigRepository` |
| :speech_balloon: | **Soft Prompt** | Custom permission dialog before OS prompt |
| :globe_with_meridians: | **Web Support** | Full web push via conditional JS interop |

---

## Quick Start

### 1. Add the dependency

```yaml
dependencies:
  magic_notifications: ^0.0.1
```

### 2. Install configuration

```bash
dart run magic_notifications install
```

This generates `lib/config/notifications.dart`, injects `NotificationServiceProvider` into `lib/config/app.dart`, wires the `notificationConfig` factory into `lib/main.dart`, and configures platform-specific setup for your selected platforms.

### 3. Boot the provider

The `NotificationServiceProvider` is automatically registered during install. On app boot, it:

- Creates the configured channels (database, push, mail)
- Initializes the push driver with your config
- Sets up background polling for database notifications
- Registers notification preferences

That's it — notifications now work across all configured channels.

---

## Configuration

After running the install command, edit `lib/config/notifications.dart`:

```dart
Map<String, dynamic> get notificationConfig => {
  'notifications': {
    'push': {
      'driver': 'onesignal',
      'app_id': const String.fromEnvironment('ONESIGNAL_APP_ID'),
      'notify_button_enabled': false,
    },
    'database': {
      'enabled': true,
      'polling_interval': 30, // seconds
    },
    'mail': {
      'enabled': false,
    },
    'soft_prompt': {
      'enabled': true,
      'title': 'Stay Updated',
      'message': 'Get notified about important events.',
    },
  },
};
```

Add to `.env`:

```
ONESIGNAL_APP_ID=your-onesignal-app-id-here
```

All values are read at runtime via `ConfigRepository` — no hardcoded strings scattered across your codebase.

---

## Usage

### Initialize Push After Login

```dart
import 'package:magic_notifications/magic_notifications.dart';

Future<void> onLoginSuccess(User user) async {
  await Notify.requestPushPermission();
  await Notify.initializePush('user_${user.id}');
  Notify.startPolling();
}
```

> **External ID Format**: Always use a prefix like `user_` before the user ID. OneSignal blocks simple numeric values as external_id.

### Display Notifications in UI

```dart
NotificationDropdownWithStream(
  notificationStream: Notify.notifications(),
  onMarkAsRead: (id) => Notify.markAsRead(id),
  onMarkAllAsRead: () => Notify.markAllAsRead(),
  onNavigate: (path) => MagicRoute.to(path),
)
```

### Clean Up on Logout

```dart
Future<void> onLogout() async {
  Notify.stopPolling();
  await Notify.logoutPush();
}
```

---

## CLI Tools

All commands use the single entry point `dart run magic_notifications [command]`:

| Command | Description |
|---------|-------------|
| `install` | Interactive wizard to set up notifications |
| `configure` | Update notification configuration |
| `doctor` | Check installation and configuration health |
| `test` | Send test notifications to verify setup |
| `channels` | List all channels and their status |
| `publish` | Copy config stub to your project |
| `uninstall` | Remove plugin integration |

See the [CLI Reference](https://magic.fluttersdk.com/packages/notifications/basics/cli) for all flags and options.

---

## Architecture

```
App launch → NotificationServiceProvider.boot()
  → reads config via ConfigRepository
  → creates channels (database, push, mail)
  → initializes OneSignalDriver
  → Notify facade delegates to NotificationManager
  → DatabaseChannel: stream + polling lifecycle
  → PushChannel: permission → initializePush → OneSignal
```

**Key patterns:**

| Pattern | Implementation |
|---------|---------------|
| Singleton Manager | `NotificationManager` — central orchestrator |
| Strategy (Driver) | `OneSignalDriver` implements push driver contract |
| Facade | `Notify` — static API over `NotificationManager` |
| Service Provider | Two-phase bootstrap: `register()` (sync) → `boot()` (async) |
| IoC Container | All bindings via `app.singleton()` / `app.make()` |

---

## Documentation

| Document | Description |
|----------|-------------|
| [Installation](https://magic.fluttersdk.com/packages/notifications/getting-started/installation) | Adding the package and running the installer |
| [Configuration](https://magic.fluttersdk.com/packages/notifications/getting-started/configuration) | Config file reference and options |
| [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels) | Database, Push, and Mail channel details |
| [Drivers](https://magic.fluttersdk.com/packages/notifications/basics/drivers) | Push driver contract and OneSignal implementation |
| [Preferences](https://magic.fluttersdk.com/packages/notifications/basics/preferences) | User notification preference management |
| [CLI Tools](https://magic.fluttersdk.com/packages/notifications/basics/cli) | All CLI commands and flags |
| [Laravel Backend](https://magic.fluttersdk.com/packages/notifications/basics/laravel-backend-setup) | Laravel backend implementation guide |
| [Notification Manager](https://magic.fluttersdk.com/packages/notifications/architecture/notification-manager) | Manager singleton and dispatch flow |
| [Service Provider](https://magic.fluttersdk.com/packages/notifications/architecture/service-provider) | Bootstrap lifecycle and IoC bindings |

---

## Contributing

Contributions are welcome! Please see the [issues page](https://github.com/fluttersdk/magic_notifications/issues) for open tasks or to report bugs.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests following the [TDD flow](#) — red, green, refactor
4. Ensure all checks pass: `flutter test`, `dart analyze`, `dart format .`
5. Submit a pull request

---

## License

Magic Notifications is open-sourced software licensed under the [MIT License](LICENSE).

---

<p align="center">
  Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a><br/>
  <sub>If Magic Notifications helps your project, consider giving it a <a href="https://github.com/fluttersdk/magic_notifications">star on GitHub</a>.</sub>
</p>
