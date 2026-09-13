# Shipping push in a release build

Everything in [Installation](../getting-started/installation.md) gets push working on a device you
build to from your own machine. A release build is a different set of
conditions, and each of the four below is silent: nothing errors, nothing logs,
and the first evidence is a notification nobody receives.

All four were found in one app's first TestFlight submission, after a
development build had been delivering pushes for days.

---

## 1. Release signs against a different APNs environment

A development provisioning profile carries `aps-environment: development`. A
distribution profile carries `production`. They are not interchangeable, so one
entitlements file cannot serve both and the project needs two:

```
ios/Runner/Runner.entitlements         aps-environment  development   Debug, Profile
ios/Runner/RunnerRelease.entitlements  aps-environment  production    Release
```

**`notifications:install` writes both and points each configuration at its
own**, so a project installed with this version or later starts out correct.
The Release twin is a copy of the development file, because every OTHER key
has to be identical between them.

Three cases it declines, and prints what to do instead:

- **A project that already names a different entitlements file.** Moving some
  configurations and not the rest is worse than moving none, so nothing is
  repointed. That includes every project a previous version of this installer
  touched: both files are written there, and the Release build setting is
  yours to point.
- **A project whose configurations are none of Debug, Profile or Release.**
  Flavours ARE handled, by base name, so `Release-production` gets the twin.
  A name outside that shape is left alone, since nothing here can tell which
  profile it signs with.
- **A file it cannot read.** An entitlements plist with no root `<dict>` or one
  that does not parse, and a `project.pbxproj` the editor will not rewrite
  byte for byte. The install itself still succeeds and exits 0; only the
  entitlement wiring is left to you.

None of the three ends the install. They print a warning naming what stopped
them and the manual step that clears it, because by the time this runs the
rest of the install has already landed.

To do it by hand, set `CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements`
on the Release configuration (Xcode: select the Runner target, Build Settings,
Code Signing Entitlements, expand the row, edit the Release line).

The trap that makes this worth a section: Xcode's Signing and Capabilities tab
writes to whichever configuration is selected, and that is Debug, so a
capability added the obvious way reaches every build except the one that ships.

`notifications:doctor` reads the value each configuration signs against and
names the ones a profile cannot use:

```
IOS: ✗ Needs attention
    the Release configuration signs against ios/Runner/Runner.entitlements,
    which declares aps-environment development where a distribution
    provisioning profile carries production
```

Flavours are read by base name, so `Release-production` and `Release-staging`
are both judged as a Release: the suffix carries no weight of its own, because
`aps-environment` follows the provisioning profile and every flavour of a
release build signs with a distribution one. A configuration whose name is
neither a Debug, a Profile nor a Release is named as unchecked rather than
passed over, since nothing here can tell which environment it needs, and it is
named even when its siblings were checked.

What it costs to get wrong: the export fails with an opaque signing error, or
it succeeds and the app registers a sandbox APNs token. OneSignal then marks
the subscription `notification_types: -30` (an APNs error) and every send to
that device goes nowhere.

---

## 2. `.env` is compiled into the app

The installer registers `.env` as a Flutter asset, which is what lets
`flutter_dotenv` read it at runtime. It also means whatever sits in that file
at BUILD time is baked into the binary, and there is no later chance to
correct it.

A development `.env` usually points at a local API. On a phone `localhost` is
the phone, so the app reaches nothing, and if your Sentry DSN lives in the same
file then the failure is also unreported.

`Magic.init` takes the filename, so select it by build mode:

```dart
await Magic.init(
  envFileName: kReleaseMode ? '.env.production' : '.env',
  configFactories: [...],
);
```

Register both files as assets in `pubspec.yaml` when you do. The alternative is
a release script that swaps the file in, builds, restores it, and then reads
the built artifact back to confirm what actually shipped; either way the point
is that no gate catches this on your behalf.

---

## 3. The APNs key has to be on the OneSignal side

Creating the `.p8` in the Apple Developer portal is step one of two. Until it
is uploaded to OneSignal (Settings, Platforms, Apple iOS), OneSignal cannot
authenticate to APNs and marks every token it tries as invalid.

One key covers Sandbox and Production, it is team-wide, and it downloads
exactly once. A key created for development work is the same key a release
build needs; there is nothing to redo.

No CLI can check this for you: it is dashboard state behind an authenticated
API, and `notifications:doctor` reads your repository.

---

## 4. On the web, the dashboard's site type decides whether your worker config is read

`notifications.push.service_worker_path` and `service_worker_scope` are sent to
the Web SDK as `serviceWorkerPath` and `serviceWorkerParam`. OneSignal's own
documentation states that `serviceWorkerPath` does not apply to a **Typical
Site** app; it applies to **Custom Code**. A dashboard app left on Typical Site
ignores both, registers its worker at the root scope, and then whichever of it
and `flutter_service_worker.js` registers second wins.

If web push works intermittently, or the app's own service worker stops
updating, check the site type before the config.

---

## Before you submit

- `dart run <app>:artisan notifications:doctor` is clean, including the iOS
  configuration rows.
- The `.env` inside the built artifact is the production one. Unzip the `.ipa`
  and read `Payload/*.app/Frameworks/App.framework/flutter_assets/.env`.
- The signed binary carries the production entitlement:
  `codesign -d --entitlements :- Payload/*.app` reports
  `aps-environment: production`.
- A push sent to the build's own subscription arrives on a device that
  installed it from TestFlight, not from Xcode.
