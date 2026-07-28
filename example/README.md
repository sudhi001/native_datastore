# native_datastore — Example App

A small, runnable Flutter app that shows off everything the
[`native_datastore`](https://pub.dev/packages/native_datastore) plugin can do. If you're
learning the plugin, **run this first** — it's the fastest way to see how storage behaves on a
real device.

> New to the plugin itself? Start with the [main README](../README.md), then come back here to
> see it in action.

---

## What this app demonstrates

The app has **two tabs** (switch between them using the bar at the bottom):

| Tab | What it shows |
|-----|---------------|
| 🗄️ **Regular** | Reading and writing all **8 supported data types** (`String`, `bool`, `int`, `double`, `List<String>`, `Uint8List`, `DateTime`, `Map`) using `NativeDatastore`. Pick a type, tap **Set**, then **Get** — the stored value appears at the bottom. |
| 🔒 **Secure** | Storing secrets (tokens, API keys) **encrypted at rest** using `SecureDatastore`. Save a sample secret, list the keys, remove them, and flip the **Multi-process access** switch to call `configure(multiProcess:)` live. |

The single best thing to try: **write a value, then fully close and reopen the app.** The data
is still there — that's the whole point of persistent storage.

---

## Prerequisites

You need the Flutter SDK installed. To check, run:

```bash
flutter --version
```

If that fails, follow the official [Flutter install guide](https://docs.flutter.dev/get-started/install)
first. You'll also need a place to run the app: an **Android emulator**, an **iOS simulator**
(macOS only), or a **physical device** plugged in.

Check that Flutter can see a device:

```bash
flutter devices
```

---

## Run it

From the repository root:

```bash
cd example
flutter pub get     # download dependencies (first time only)
flutter run         # build and launch on your selected device
```

If more than one device is connected, Flutter will ask which one to use — or you can pick one
directly, e.g. `flutter run -d chrome` is **not** supported (this plugin is Android/iOS only), so
choose an Android or iOS target.

While the app is running, press `r` in the terminal for a hot reload or `q` to quit.

---

## Where to look in the code

Everything lives in one file so it's easy to read top-to-bottom:

- **[`lib/main.dart`](lib/main.dart)** — the whole demo.
  - `RegularTab` — how to call `NativeDatastore()` for each of the 8 types.
  - `SecureTab` — how to call `SecureDatastore()` for encrypted values, including catching
    `NativeDatastoreException`.

Read these two classes and you've seen essentially the entire public API in use.

---

## Extra entrypoints

Alternate `main()` files you can launch with `flutter run -t <file>`:

| Entrypoint | What it does |
|-----------|--------------|
| [`lib/selftest_main.dart`](lib/selftest_main.dart) | Runs the `SecureDatastore` round-trip in single-process **and** multi-process mode on the device and prints `SELFTEST PASS/FAIL` lines (plus an on-screen summary). A quick on-device smoke test. |
| [`lib/benchmark_main.dart`](lib/benchmark_main.dart) | Times set/get for the regular vs secure store and prints a Markdown results table. |
| [`lib/demo_main.dart`](lib/demo_main.dart) | Self-driving Secure Storage demo (real encrypted operations on a loop) — used to record the README GIF. |

```bash
cd example
flutter run -t lib/selftest_main.dart   # on-device functional check
flutter run -t lib/benchmark_main.dart  # latency numbers
```

---

## Run the tests

This example also contains an **integration test** that drives the plugin against the real
platform storage (not a mock) — a good reference for how to test code that uses the plugin. It
covers the regular store, the secure store in **single- and multi-process** modes, atomic
operations, and reactive `watch`.

```bash
# From the example/ folder, with a device or emulator running:
flutter test integration_test/plugin_integration_test.dart
```

> On some headless/CI setups the `integration_test` VM-service handshake can hang. If it does,
> the `selftest_main.dart` entrypoint above is a reliable alternative — it exercises the same
> paths and streams its results over `flutter run`.

There's also a basic widget test:

```bash
flutter test
```

---

## Troubleshooting

- **"No devices found"** — start an emulator/simulator, or connect a phone with USB debugging
  enabled, then re-run `flutter devices`.
- **Secure tab shows an error on older Android** — the secure store requires **Android API 23
  (6.0)** or higher; older devices get a clear `UnsupportedOperationException`. The Regular tab
  still works everywhere (API 21+).
- **Build errors after pulling changes** — run `flutter clean` then `flutter pub get` and try
  again.
