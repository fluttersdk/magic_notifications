# CLI Reference

## Table of Contents

- <a name="toc-overview"></a>[Overview](#overview)
- <a name="toc-install"></a>[install](#install)
- <a name="toc-configure"></a>[configure](#configure)
- <a name="toc-doctor"></a>[doctor](#doctor)
- <a name="toc-test"></a>[test](#test)
- <a name="toc-channels"></a>[channels](#channels)
- <a name="toc-uninstall"></a>[uninstall](#uninstall)
- <a name="toc-publish"></a>[publish](#publish)

---

## <a name="overview"></a>Overview

All Magic Notifications CLI commands are run via a single entry point:

```bash
dart run magic_notifications <command> [options]
```

The CLI is implemented with `magic_cli` and automatically detects your Flutter project root from `pubspec.yaml`. Every command that reads or writes project files operates on the detected root, so commands should be run from the project directory or any subdirectory.

---

## <a name="install"></a>install

Interactive wizard that sets up the full integration: config file, platform files, provider injection, and config factory injection.

```bash
dart run magic_notifications install
```

### Flags and Options

| Flag / Option | Short | Type | Default | Description |
|---------------|-------|------|---------|-------------|
| `--non-interactive` | | flag | `false` | Skip all prompts; all required values must be supplied via flags |
| `--app-id` | | option | — | OneSignal App ID (UUID format, required in non-interactive mode) |
| `--platforms` | | option | `android,ios,web` | Comma-separated list of target platforms |
| `--soft-prompt` / `--no-soft-prompt` | | flag | `true` | Enable or disable the soft prompt dialog |
| `--safari-web-id` | | option | — | Safari Web Push ID (web only, optional) |
| `--notify-button` | | flag | `false` | Enable the floating OneSignal notify button on web |
| `--force` | `-f` | flag | `false` | Overwrite existing `lib/config/notifications.dart` |

### Examples

```bash
# Interactive mode — guided wizard
dart run magic_notifications install

# CI/CD — minimal non-interactive
dart run magic_notifications install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012

# CI/CD — full non-interactive with web extras
dart run magic_notifications install \
  --non-interactive \
  --app-id 12345678-1234-1234-1234-123456789012 \
  --platforms android,ios,web \
  --safari-web-id web.onesignal.auto.xxx \
  --notify-button \
  --force

# Disable soft prompt
dart run magic_notifications install --no-soft-prompt
```

### What Install Produces

1. Creates `lib/config/notifications.dart` with your App ID and preferences
2. Adds `magic_notifications` to `pubspec.yaml`
3. Android: adds `POST_NOTIFICATIONS` permission to `AndroidManifest.xml`
4. Web: writes `web/OneSignalSDKWorker.js`, injects SDK `<script>` into `web/index.html`
5. Injects `NotificationServiceProvider` into `lib/config/app.dart`
6. Injects `() => notificationConfig` into `lib/main.dart`

> [!NOTE]
> iOS setup cannot be automated — the wizard prints instructions but does not modify Xcode project files.

---

## <a name="configure"></a>configure

Read or update individual settings in `lib/config/notifications.dart` without re-running the full install wizard.

```bash
dart run magic_notifications configure [options]
```

### Flags and Options

| Flag / Option | Short | Type | Default | Description |
|---------------|-------|------|---------|-------------|
| `--show` | | flag | `false` | Print current configuration values and exit |
| `--app-id` | | option | — | Replace the OneSignal App ID |
| `--polling-interval` | | option | — | Set polling interval in seconds (valid range: 5–600) |
| `--soft-prompt` | | flag | — | Enable soft prompt |
| `--no-soft-prompt` | | flag | — | Disable soft prompt |

### Examples

```bash
# Show current config
dart run magic_notifications configure --show

# Update the App ID
dart run magic_notifications configure --app-id 12345678-1234-1234-1234-123456789012

# Change polling to 60 seconds
dart run magic_notifications configure --polling-interval 60

# Disable soft prompt
dart run magic_notifications configure --no-soft-prompt
```

> [!NOTE]
> `configure` requires `lib/config/notifications.dart` to already exist. Run `install` or `publish` first if the file is absent.

---

## <a name="doctor"></a>doctor

Comprehensive health check that validates plugin installation, configuration, and platform setup. Exits with code `0` when all checks pass, `1` if any check fails.

```bash
dart run magic_notifications doctor
```

### Flags and Options

| Flag | Short | Type | Default | Description |
|------|-------|------|---------|-------------|
| `--verbose` | `-v` | flag | `false` | Show file paths, required keys, and per-platform issue details |

### Examples

```bash
# Basic health check
dart run magic_notifications doctor

# Verbose — shows paths and details
dart run magic_notifications doctor --verbose
```

### Checks Performed

| Check | Pass Condition |
|-------|---------------|
| Plugin installed | `magic_notifications` present in `pubspec.yaml` dependencies |
| Config file exists | `lib/config/notifications.dart` present |
| App ID format | UUID format `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, non-empty, non-placeholder |
| Polling interval | Integer in range 5–600 |
| `soft_prompt` section | Present in config file |
| Android | `POST_NOTIFICATIONS` in `AndroidManifest.xml` |
| iOS | `Info.plist` present (manual Xcode steps noted) |
| Web | `web/OneSignalSDKWorker.js` present |

---

## <a name="test"></a>test

Send test notifications to verify setup without modifying production data.

```bash
dart run magic_notifications test [options]
```

### Flags and Options

| Flag / Option | Short | Type | Default | Description |
|---------------|-------|------|---------|-------------|
| `--dry-run` | | flag | `false` | Preview notification payload without sending; exits with code `0` |
| `--title` | `-t` | option | `'Test Notification'` | Notification title |
| `--body` | `-b` | option | `'This is a test notification from the CLI'` | Notification body |
| `--channel` | `-c` | option | `'database'` | Target channel: `database`, `push`, or `mail` |
| `--api-url` | | option | — | Backend API base URL (required for push channel to send) |

### Examples

```bash
# Preview the notification payload (no send)
dart run magic_notifications test --dry-run

# Send a custom database notification
dart run magic_notifications test \
  --title "Hello" \
  --body "World" \
  --channel database

# Send push notification via backend
dart run magic_notifications test \
  --channel push \
  --api-url http://localhost:8000

# Test all channels
dart run magic_notifications test --channel database
dart run magic_notifications test --channel push
dart run magic_notifications test --channel mail
```

> [!TIP]
> Start with `--dry-run` to inspect the payload structure before sending to a real backend.

---

## <a name="channels"></a>channels

Display all notification channels and their current configuration status from `lib/config/notifications.dart`.

```bash
dart run magic_notifications channels
```

This command has no flags. It prints:

- **push**: driver name, masked App ID (`first8chars...`), notify button status
- **database**: enabled status, polling interval in seconds
- **mail**: enabled status

> [!NOTE]
> `channels` requires `lib/config/notifications.dart` to exist. Run `install` first.

---

## <a name="uninstall"></a>uninstall

Remove Magic Notifications integration from the project. Reverses the changes made by `install`.

```bash
dart run magic_notifications uninstall
```

### Flags and Options

| Flag | Short | Type | Default | Description |
|------|-------|------|---------|-------------|
| `--force` | `-f` | flag | `false` | Skip the confirmation prompt |

### Examples

```bash
# Interactive — shows removal summary and asks for confirmation
dart run magic_notifications uninstall

# Skip confirmation
dart run magic_notifications uninstall --force
```

### What Uninstall Removes

| Artifact | Action |
|----------|--------|
| `lib/config/notifications.dart` | Deleted |
| `magic_notifications` in `pubspec.yaml` | Dependency entry removed |
| `NotificationServiceProvider` in `lib/config/app.dart` | Import + provider line removed |
| `notificationConfig` in `lib/main.dart` | Import + factory line removed |

> [!NOTE]
> Platform files are **not** reverted automatically. You must manually remove:
> - `android.permission.POST_NOTIFICATIONS` from `AndroidManifest.xml`
> - OneSignal `<script>` tags from `web/index.html`
> - `web/OneSignalSDKWorker.js`

---

## <a name="publish"></a>publish

Laravel `vendor:publish` equivalent — copies the default config stub to `lib/config/notifications.dart` without running any wizard or platform setup.

```bash
dart run magic_notifications publish
```

### Flags and Options

| Flag | Short | Type | Default | Description |
|------|-------|------|---------|-------------|
| `--force` | `-f` | flag | `false` | Overwrite an existing `lib/config/notifications.dart` |

### Examples

```bash
# Publish config stub (skips if file already exists)
dart run magic_notifications publish

# Overwrite existing config
dart run magic_notifications publish --force
```

The published file contains `YOUR_ONESIGNAL_APP_ID` as a placeholder. After publishing:

1. Replace `YOUR_ONESIGNAL_APP_ID` with your actual OneSignal App ID (or use `String.fromEnvironment`)
2. Run `dart run magic_notifications install` to inject providers and set up platforms

> [!TIP]
> Use `publish` when you want full control over config contents before running `install`. Use `install` directly when you want everything done end-to-end.

---

**Related**

- [Installation](https://magic.fluttersdk.com/packages/notifications/getting-started/installation)
- [Configuration](https://magic.fluttersdk.com/packages/notifications/getting-started/configuration)
- [Channels](https://magic.fluttersdk.com/packages/notifications/basics/channels)
