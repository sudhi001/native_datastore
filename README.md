# native_datastore

[![Pub Version](https://img.shields.io/pub/v/native_datastore)](https://pub.dev/packages/native_datastore)
[![Pub Points](https://img.shields.io/pub/points/native_datastore)](https://pub.dev/packages/native_datastore/score)
[![Pub Likes](https://img.shields.io/pub/likes/native_datastore)](https://pub.dev/packages/native_datastore)
[![Pub Popularity](https://img.shields.io/pub/popularity/native_datastore)](https://pub.dev/packages/native_datastore)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/platform-android%20%7C%20iOS-brightgreen)](https://flutter.dev)
[![GitHub issues](https://img.shields.io/github/issues/sudhi001/native_datastore)](https://github.com/sudhi001/native_datastore/issues)
[![GitHub stars](https://img.shields.io/github/stars/sudhi001/native_datastore)](https://github.com/sudhi001/native_datastore/stargazers)
[![Wiki](https://img.shields.io/badge/docs-wiki-blue)](https://github.com/sudhi001/native_datastore/wiki)
[![Website](https://img.shields.io/badge/site-sudhi001.github.io-00919e)](https://sudhi001.github.io/native_datastore/)

A modern Flutter plugin for **persistent key-value storage**, powered by platform-native APIs.

> 🌐 **[sudhi001.github.io/native_datastore](https://sudhi001.github.io/native_datastore/)** — the
> project site: a live demo of the store, the benchmarks, and the generated
> [API reference](https://sudhi001.github.io/native_datastore/api/).
>
> 📖 **Task-focused guides live in the [Wiki](https://github.com/sudhi001/native_datastore/wiki)** —
> [Getting Started](https://github.com/sudhi001/native_datastore/wiki/Getting-Started),
> [Secure Storage](https://github.com/sudhi001/native_datastore/wiki/Secure-Storage),
> [Multi-Process Access](https://github.com/sudhi001/native_datastore/wiki/Multi-Process-Access),
> [Troubleshooting](https://github.com/sudhi001/native_datastore/wiki/Troubleshooting). This README
> stays the canonical, full API reference.

**New here? In plain English:** this plugin lets you **save small pieces of data under a name
(a "key") and read them back later — even after the app is closed and reopened.** Think of it
as a tiny dictionary that survives app restarts. You give it a key like `"username"` and a value
like `"sudhi"`, and it remembers.

Under the hood it uses each platform's own recommended storage. You don't need to understand
these — the plugin gives you **one simple Dart API** that works the same on both:

| Platform | Backend (the native tech doing the work) |
|----------|---------|
| Android  | [Jetpack DataStore](https://developer.android.com/topic/libraries/architecture/datastore) (Preferences) |
| iOS      | [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults) |

![How native_datastore works: one Dart API bridged via Pigeon to Jetpack DataStore on Android and UserDefaults on iOS](https://raw.githubusercontent.com/sudhi001/native_datastore/main/doc/assets/architecture.gif)

### When should I use this?

✅ **Great for** small values you read and write often: user settings, feature flags, theme
choice, "has the user finished onboarding?", a saved username, a login count, timestamps.

❌ **Not for** large data, lists of records, or anything you need to search or filter. Reach for
a database like [`sqflite`](https://pub.dev/packages/sqflite),
[`drift`](https://pub.dev/packages/drift), or [`isar`](https://pub.dev/packages/isar) instead.

> 🔒 **Storing secrets** (auth tokens, passwords, encryption keys)? Use the
> [`SecureDatastore`](#-secure-storage) class instead — it encrypts values at rest. The regular
> `NativeDatastore` does **not** encrypt, so don't put secrets in it.

---

## Table of Contents

- [Features](#features)
- [Supported Types](#supported-types)
- [Why not SharedPreferences?](#why-not-sharedpreferences)
- [Getting Started](#getting-started) — install and your first read/write
- [See it in action](#see-it-in-action) — the example app running
- [Cheat Sheet](#cheat-sheet) — the whole API at a glance
- [Full Example](#full-example) — a complete, copy-paste app
- [Error Handling](#error-handling)
- [Handling Null Values](#handling-null-values)
- [API Reference](#api-reference)
- [Reactive Observation (`watch`)](#reactive-observation-watch) — rebuild on change
- [Atomic Operations](#atomic-operations) — counters, flags, compare-and-set
- [Which method should I use?](#which-method-should-i-use) — quick decision guide
- [🔒 Secure Storage](#-secure-storage) — for tokens and secrets
- [⚡ Benchmarks](#-benchmarks) — regular vs secure, and how to run your own
- [Storage Details](#storage-details)
- [Migrating from shared_preferences](#migrating-from-shared_preferences)
- [Platform Details](#platform-details)
- [Requirements](#requirements)
- [FAQ](#faq) — common questions & gotchas
- [Advanced Topics](#advanced-topics) — resilience & multi-process caveats (safe to skip at first)
- [Contributing](#contributing)

---

## Features

- **Jetpack DataStore on Android** -- Google's officially recommended replacement for SharedPreferences. Async, non-blocking, coroutine-based I/O.
- **8 supported data types** -- `String`, `bool`, `int`, `double`, `List<String>`, `Uint8List`, `DateTime`, and `Map<String, dynamic>`.
- **Drop-in replacement** -- Same getter/setter pattern as `shared_preferences`. Zero learning curve.
- **Type-safe platform communication** -- Built with [Pigeon](https://pub.dev/packages/pigeon). No hand-written method channels, no string-based lookups.
- **Cross-platform** -- One Dart API for Android and iOS.
- **Reactive** -- `watch*` any key as a `Stream` and rebuild your UI on change.
- **Atomic** -- Transaction-safe `increment`, `toggle`, and `compareAndSet`.
- **Migration** -- One-call import from `shared_preferences`.
- **Multi-process ready** -- Opt-in multi-process (Android) / App Group (iOS) support.
- **Lightweight** -- No platform interface layer. A thin, clean bridge to native APIs.

---

## Supported Types

| Dart Type | Getter | Setter | Nullable |
|-----------|--------|--------|----------|
| `String` | `getString(key)` | `setString(key, value)` | Yes |
| `bool` | `getBool(key)` | `setBool(key, value)` | Yes |
| `int` | `getInt(key)` | `setInt(key, value)` | Yes |
| `double` | `getDouble(key)` | `setDouble(key, value)` | Yes |
| `List<String>` | `getStringList(key)` | `setStringList(key, value)` | Yes |
| `Uint8List` | `getBytes(key)` | `setBytes(key, value)` | Yes |
| `DateTime` | `getDateTime(key)` | `setDateTime(key, value)` | Yes |
| `Map<String, dynamic>` | `getMap(key)` | `setMap(key, value)` | Yes |

> All getters return `null` when the key does not exist.

---

## Why not SharedPreferences?

If you're using `SharedPreferences` (or Flutter's `shared_preferences` which wraps it), you're relying on a **legacy Android API** that Google has been actively deprecating.

| Concern | SharedPreferences | Jetpack DataStore |
|---------|-------------------|-------------------|
| Thread safety | Not safe on UI thread; can cause ANRs | Fully async with Kotlin Coroutines |
| Error handling | Fails silently | Proper error signaling via Flow |
| Runtime exceptions | Parsing errors cause crashes | No runtime exceptions from parsing |
| Disk I/O | Blocking `commit()` / fire-and-forget `apply()` | Consistent async API |
| Type safety | Returns defaults on type mismatch | Typed keys with compile-time safety |
| Consistency | No transactional guarantees | Atomic read-modify-write |

> **Jargon check —** *ANR* means "Application Not Responding": the freeze dialog Android shows
> (and may kill your app for) when the UI thread is blocked too long. Doing disk work
> asynchronously, as this plugin does, avoids it.

> **Google's recommendation:** *"Prefer DataStore over SharedPreferences."*
> -- [Android Developers Docs](https://developer.android.com/topic/libraries/architecture/datastore)

---

## Getting Started

### 1. Install

The easiest way — run this in your project folder:

```bash
flutter pub add native_datastore
```

Or add it to your `pubspec.yaml` manually and run `flutter pub get`:

```yaml
dependencies:
  native_datastore: ^1.4.0
```

> No extra setup needed — no changes to `AndroidManifest.xml`, `Info.plist`, or Gradle files.
> It works out of the box on Android and iOS.

### 2. Import

```dart
import 'package:native_datastore/native_datastore.dart';

// Only needed if you use setBytes / getBytes (binary data):
import 'dart:typed_data';
```

### 3. Use

> **Important for beginners:** every read and write is **asynchronous** — it returns a `Future`,
> so you must `await` it (inside an `async` function). This is what keeps your UI smooth. If you
> forget `await`, you'll get a `Future` object instead of your value.

```dart
final datastore = NativeDatastore();  // create it once; reuse it anywhere

// -- Write --
await datastore.setString('username', 'sudhi');
await datastore.setBool('darkMode', true);
await datastore.setInt('loginCount', 42);
await datastore.setDouble('rating', 4.8);
await datastore.setStringList('tags', ['flutter', 'dart', 'mobile']);
await datastore.setBytes('avatar', Uint8List.fromList([0x89, 0x50, 0x4E]));
await datastore.setDateTime('lastLogin', DateTime.now());
await datastore.setMap('profile', {'name': 'sudhi', 'level': 5});

// -- Read --
final username  = await datastore.getString('username');       // "sudhi"
final darkMode  = await datastore.getBool('darkMode');         // true
final count     = await datastore.getInt('loginCount');        // 42
final rating    = await datastore.getDouble('rating');         // 4.8
final tags      = await datastore.getStringList('tags');       // ["flutter", "dart", "mobile"]
final avatar    = await datastore.getBytes('avatar');          // Uint8List [0x89, 0x50, 0x4E]
final lastLogin = await datastore.getDateTime('lastLogin');    // DateTime (UTC)
final profile   = await datastore.getMap('profile');           // {"name": "sudhi", "level": 5}

// -- Query --
final allKeys  = await datastore.getKeys();                   // ["username", "darkMode", ...]
final allData  = await datastore.getAll();                    // {username: sudhi, darkMode: true, ...}
final exists   = await datastore.containsKey('username');     // true

// -- Delete --
await datastore.remove('username');   // Remove a single key
await datastore.clear();              // Remove all data
```

---

## See it in action

The bundled [example app](example/) exercising both stores on a device — writing
every type on the **Regular** tab, then saving encrypted secrets on the
**Secure** tab:

![Screen recording of the example app: Set All Types then Get All on the Regular tab, then Save Sample Secrets and Refresh Keys on the Secure tab](https://raw.githubusercontent.com/sudhi001/native_datastore/main/doc/assets/example-demo.gif)

---

## Cheat Sheet

The whole API at a glance — copy, paste, adapt:

```dart
final ds = NativeDatastore();

// ── Write / read (8 types; getters return null if the key is absent) ──
await ds.setString('name', 'sudhi');
final name = await ds.getString('name');          // 'sudhi'
await ds.setBool('dark', true);
await ds.setInt('count', 42);
await ds.setDouble('rating', 4.8);
await ds.setStringList('tags', ['a', 'b']);
await ds.setBytes('avatar', bytes);               // Uint8List, ≤ 1 MiB
await ds.setDateTime('lastSeen', DateTime.now()); // stored as UTC
await ds.setMap('profile', {'level': 5});         // JSON-able map

// ── Observe changes as a Stream (auto-rebuild your UI) ──
ds.watchInt('count').listen((v) => print('count = $v'));

// ── Atomic updates (safe under concurrency — no lost writes) ──
await ds.incrementInt('count');                   // +1, returns the new value
await ds.decrementInt('lives');                   // -1
await ds.toggleBool('dark');
await ds.compareAndSetString('status',
    expected: 'pending', value: 'done');          // swaps only if it matched

// ── Query / delete ──
await ds.containsKey('name');                     // bool
await ds.getKeys();                               // List<String>
await ds.getAll();                                // Map<String, Object>
await ds.remove('name');
await ds.clear();

// ── One-time import from the shared_preferences package ──
await ds.migrateFromSharedPreferences();

// ── Secrets — encrypted at rest (Keychain / AndroidKeyStore) ──
final secure = SecureDatastore();
await secure.setString('token', jwt);
final token = await secure.getString('token');
```

---

## Full Example

![Save a value, fully close the app, reopen it, and the value is still there — read back from on-device disk](https://raw.githubusercontent.com/sudhi001/native_datastore/main/doc/assets/survives-restart.gif)

A complete, runnable app you can paste into `lib/main.dart`. It saves a counter that
**survives app restarts** — close the app fully, reopen it, and the number is still there.

```dart
import 'package:flutter/material.dart';
import 'package:native_datastore/native_datastore.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: CounterPage());
}

class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> {
  final _datastore = NativeDatastore();
  int _count = 0;

  @override
  void initState() {
    super.initState();
    _loadCount(); // read the saved value when the screen opens
  }

  Future<void> _loadCount() async {
    // getInt returns null if the key was never saved, so default to 0.
    final saved = await _datastore.getInt('count') ?? 0;
    setState(() => _count = saved);
  }

  Future<void> _increment() async {
    final next = _count + 1;
    await _datastore.setInt('count', next); // save it (persists to disk)
    setState(() => _count = next);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('native_datastore demo')),
      body: Center(
        child: Text('Count: $_count', style: const TextStyle(fontSize: 32)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _increment,
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

> A larger example (every data type, secure storage, error handling) lives in the
> [`example/`](example/) folder of the repository.

---

## Error Handling

All operations throw `NativeDatastoreException` on failure. The exception wraps the underlying platform error with context:

```dart
try {
  await datastore.getString('key');
} on NativeDatastoreException catch (e) {
  print(e.message);  // Human-readable description
  print(e.cause);    // Original PlatformException (if any)
}
```

**Empty keys** are rejected immediately:

```dart
await datastore.getString('');  // Throws NativeDatastoreException: Key must not be empty
```

### Telling failures apart

Every failure arrives as a `NativeDatastoreException`. Its `code` is the same on
both platforms, so you can branch on it rather than on the message:

```dart
try {
  final token = await SecureDatastore().getString('refresh_token');
  // ...
} on NativeDatastoreException catch (e) {
  switch (e.code) {
    case NativeDatastoreException.secureKeyUnavailableCode:
      // The key that encrypted this device's secrets is gone — restored from
      // another device, or invalidated by the system. The store clears itself
      // on the next launch; send the user back through sign-in.
      await signInAgain();
    case NativeDatastoreException.unsupportedPlatformVersionCode:
      // SecureDatastore needs Android 6.0 (API 23).
      useUnencryptedFallback();
    default:
      rethrow;
  }
}
```

| Code | Meaning |
|------|---------|
| `plugin-detached` | The plugin is not attached to a Flutter engine. Retry once it is running. |
| `secure-key-unavailable` | The key that encrypted the stored secrets can no longer read them. Treat the secrets as lost. |
| `unsupported-platform-version` | The operation needs a newer OS than the device runs. |
| `unsupported-type` | A value was passed that the store cannot represent. |
| `keychain-error` | An iOS Keychain call failed; the message carries the `OSStatus`. |
| `encoding-error` | A string could not be encoded as UTF-8. |

`code` is `null` when the failure was raised in Dart — an empty key, a reserved
prefix, an oversized payload. Anything not in the table came straight from the
platform and is not part of the plugin's contract; match on it only for logging.

---

## Handling Null Values

All getters return `null` when the key does not exist. Use null-aware operators or provide defaults:

```dart
// With default values
final username = await datastore.getString('username') ?? 'Guest';
final count = await datastore.getInt('loginCount') ?? 0;

// With null checks
final lastLogin = await datastore.getDateTime('lastLogin');
if (lastLogin != null) {
  print('Last login: ${lastLogin.toIso8601String()}');
}

// Check before reading
if (await datastore.containsKey('profile')) {
  final profile = await datastore.getMap('profile');
  // Use profile...
}
```

### Reading a key back at the wrong type

`String`, `bool`, `int` and `double` share one key space, so a key holds
whichever of them was written last. Reading it as a different type gives `null`,
the same as an absent key — it does not throw:

```dart
await datastore.setDouble('threshold', 1.5);
await datastore.getInt('threshold');    // null, not 1
await datastore.getDouble('threshold'); // 1.5
```

`getDouble` is the one exception: it widens a stored `int`, so `setInt('n', 5)`
followed by `getDouble('n')` gives `5.0`. `increment*` and `toggleBool` treat a
wrong-typed value as absent and overwrite it; `compareAndSet*` simply fails to
match and returns `false`.

The typed containers — `List<String>`, `Uint8List`, `DateTime` and `Map` — each
live in their own namespace, so they never collide with a scalar or with each
other.

> Before 1.8.0 a cross-type read on Android threw instead of returning `null`.

---

## API Reference

### Read operations

| Method | Return Type | Description |
|--------|-------------|-------------|
| `getString(key)` | `Future<String?>` | Read a string value |
| `getBool(key)` | `Future<bool?>` | Read a boolean value |
| `getInt(key)` | `Future<int?>` | Read an integer value |
| `getDouble(key)` | `Future<double?>` | Read a double value |
| `getStringList(key)` | `Future<List<String>?>` | Read a string list |
| `getBytes(key)` | `Future<Uint8List?>` | Read binary data |
| `getDateTime(key)` | `Future<DateTime?>` | Read a date/time (stored as UTC millis) |
| `getMap(key)` | `Future<Map<String, dynamic>?>` | Read a JSON-compatible map |

### Write operations

| Method | Return Type | Description |
|--------|-------------|-------------|
| `setString(key, value)` | `Future<void>` | Write a string value |
| `setBool(key, value)` | `Future<void>` | Write a boolean value |
| `setInt(key, value)` | `Future<void>` | Write an integer value |
| `setDouble(key, value)` | `Future<void>` | Write a double value |
| `setStringList(key, value)` | `Future<void>` | Write a string list |
| `setBytes(key, value)` | `Future<void>` | Write binary data (`Uint8List`) |
| `setDateTime(key, value)` | `Future<void>` | Write a date/time (stored as UTC millis) |
| `setMap(key, value)` | `Future<void>` | Write a JSON-compatible map |

### Query operations

| Method | Return Type | Description |
|--------|-------------|-------------|
| `getAll()` | `Future<Map<String, Object>>` | Get all key-value pairs |
| `getKeys()` | `Future<List<String>>` | Get all stored keys |
| `containsKey(key)` | `Future<bool>` | Check if a key exists |

### Delete operations

| Method | Return Type | Description |
|--------|-------------|-------------|
| `remove(key)` | `Future<bool>` | Remove a key (returns `true` if it existed) |
| `clear()` | `Future<bool>` | Remove all stored data |

---

## Reactive Observation (`watch`)

![A write to a key flows through the store and is pushed to a watchInt() Stream, which rebuilds the UI automatically](https://raw.githubusercontent.com/sudhi001/native_datastore/main/doc/assets/reactive-watch.gif)

Instead of reading a value once, you can **watch** a key and rebuild your UI
automatically whenever it changes. Each `watch*` method returns a `Stream` that
emits the current value immediately, then a new value on every change (and
`null` when the key is removed).

```dart
final datastore = NativeDatastore();

// Rebuild whenever "darkMode" changes — great with StreamBuilder.
StreamBuilder<bool?>(
  stream: datastore.watchBool('darkMode'),
  builder: (context, snapshot) {
    final dark = snapshot.data ?? false;
    return Text(dark ? '🌙 Dark' : '☀️ Light');
  },
);
```

There's a `watch*` for every type — `watchString`, `watchBool`, `watchInt`,
`watchDouble`, `watchStringList`, `watchBytes`, `watchDateTime`, `watchMap` —
plus `watchChanges()`, which emits the list of keys that changed if you want to
observe the whole store.

> This is the reactive `Flow`-style API DataStore is known for: on Android it is
> backed by `DataStore.data`, and on iOS by `UserDefaults` change
> notifications. Cancel the stream subscription (or let `StreamBuilder` do it)
> when you're done.

---

## Atomic Operations

![Two writers each add +1: manual read-then-write ends at 6 (one update lost), while incrementInt() is atomic and ends at 7](https://raw.githubusercontent.com/sudhi001/native_datastore/main/doc/assets/atomic-no-lost-updates.gif)

When several parts of your app update the same value, a plain
read-then-write can lose updates. These operations run as a **single native
transaction**, so they're safe under concurrency:

```dart
// Counters — a missing value is treated as 0.
final views = await datastore.incrementInt('views');       // +1, returns new value
await datastore.incrementInt('views', 10);                 // +10
await datastore.decrementInt('retries');                   // -1
await datastore.incrementDouble('balance', 4.50);

// Flags — missing is treated as false, so the first toggle yields true.
final enabled = await datastore.toggleBool('featureX');

// Compare-and-set — only writes if the current value matches [expected].
// null expected = "only if absent"; null value = "remove".
final ok = await datastore.compareAndSetString(
  'status',
  expected: 'pending',
  value: 'done',
); // false if 'status' wasn't 'pending'
```

Available: `incrementInt`, `decrementInt`, `incrementDouble`, `toggleBool`, and
`compareAndSetString` / `compareAndSetInt` / `compareAndSetDouble` /
`compareAndSetBool`.

---

## Which method should I use?

| I want to… | Use |
|------------|-----|
| Read a value once | `getString` / `getInt` / `getBool` / … |
| React to changes and rebuild my UI | `watchString` / `watchInt` / … (a `Stream`) |
| Overwrite a value | `setString` / `setInt` / … |
| Safely add to a number (counter) | `incrementInt` / `decrementInt` / `incrementDouble` |
| Safely flip a flag | `toggleBool` |
| Write only if the value hasn't changed | `compareAndSet{String,Int,Double,Bool}` |
| Store a **secret** (token, password, key) | **`SecureDatastore`** — encrypted at rest |
| Store settings, flags, small values | **`NativeDatastore`** — fast, *not* encrypted |
| Store large blobs or queryable records | ❌ not this — use a database (`sqflite`, `drift`, `isar`) |
| Share data across processes / an app extension | `configure(multiProcess: …)` / `configure(appGroupId: …)` |
| Move off the `shared_preferences` package | `migrateFromSharedPreferences()` once at startup |

---

## 🔒 Secure Storage

![Animated diagram: a plaintext token leaves your Dart code, is encrypted with an AES-256-GCM key held in the AndroidKeyStore / iOS Keychain, and only ciphertext lands on disk; with configure() a second process reads the same encrypted store](https://raw.githubusercontent.com/sudhi001/native_datastore/main/doc/assets/secure-storage.gif)

For secrets (auth tokens, refresh tokens, encryption keys) use the
`SecureDatastore` class, which encrypts values at rest using platform key
management:

- **iOS** — Keychain Services (`kSecClassGenericPassword`) with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Values are readable after
  the first device unlock following a boot (including from background work),
  never migrated to a new device or restored from backup.
- **Android** — AES-256-GCM with a key minted in the AndroidKeyStore
  (hardware-backed where the device supports it), encrypting values into a
  dedicated DataStore file. Each write uses a fresh 96-bit IV. Requires
  Android API 23 (Marshmallow) or higher; older devices throw
  `UnsupportedOperationException` from the secure API.

```dart
import 'package:native_datastore/native_datastore.dart';

final secure = SecureDatastore();

await secure.setString('refresh_token', tokenJwt);
final token = await secure.getString('refresh_token');

await secure.setBytes('symmetric_key', encryptionKey);
final key = await secure.getBytes('symmetric_key');

await secure.remove('refresh_token');
await secure.clear(); // wipes every value in the secure store
```

Surface is intentionally minimal: `String` and `Uint8List` only, plus
`remove` / `clear` / `getKeys` / `containsKey`. Values are capped at 1 MiB —
callers needing larger payloads should encrypt themselves and store via the
filesystem. Errors flow through the same `NativeDatastoreException` used by
`NativeDatastore`.

### The secure store in action

![Screen recording of the demo: enabling multi-process access, saving encrypted secrets, adding one more, and clearing — keys are listed but values stay encrypted at rest](https://raw.githubusercontent.com/sudhi001/native_datastore/main/doc/assets/secure-demo.gif)

*Real `SecureDatastore` operations, auto-played from
[`example/lib/demo_main.dart`](example/lib/demo_main.dart) — run it with
`flutter run -t lib/demo_main.dart`.*

### Sharing secrets across processes

`SecureDatastore` supports the same opt-in `configure` as `NativeDatastore` for
background services and app extensions — see
[Multi-process access](#multi-process-access-opt-in):

```dart
await SecureDatastore().configure(
  multiProcess: true,                  // Android: multi-process encrypted store
  appGroupId: 'TEAMID.com.you.shared', // iOS: Keychain access group
);
```

### What it protects (and what it doesn't)

- ✅ **At-rest confidentiality.** Values are encrypted with a
  hardware-backed key (Android) or held in the system Keychain (iOS), so a
  filesystem/backup dump does not reveal them.
- ✅ **Not in backups / not device-migrated.** iOS uses `…ThisDeviceOnly`. On
  Android the key lives in the AndroidKeyStore and never leaves the device, and
  since 1.8.0 the encrypted file lives in `noBackupFilesDir` so the *ciphertext*
  does not travel either. Before 1.8.0 it sat in `filesDir`, which Auto Backup
  and device-to-device transfer copy — a restored install then held ciphertext
  it had no key for.
- ✅ **Each value is bound to its key.** The entry name is authenticated
  alongside the ciphertext (GCM additional authenticated data), so an attacker
  with write access to the store file cannot move one secret's blob under
  another secret's name, or restore an older value, without the read failing.
- ℹ️ **If the key goes away, the secrets go with it.** Restoring onto a new
  device, or a system key invalidation, leaves data no key can read. The plugin
  detects this on the next launch, clears the unreadable store, and continues —
  so calls return `null` rather than failing forever. Treat that as "the user
  must sign in again", and keep anything you cannot re-derive somewhere else.
- ⚠️ **Not a substitute for auth.** While the app is unlocked and running, it
  can read its own secrets — as it must. This guards data at rest, not a
  compromised or rooted/jailbroken runtime.
- ⚠️ **No biometric gate by default.** Access is not tied to a fresh Face ID /
  fingerprint check. If you need per-read user presence, gate the call in your
  app.
- ℹ️ **Hardware backing is best-effort.** Android asks for a StrongBox-backed
  key and falls back to the TEE on devices without a secure element.

---

## ⚡ Benchmarks

Both stores go through a typed Pigeon channel to native code. The regular store
is a thin call over DataStore / UserDefaults; the secure store adds
encrypt/decrypt (AndroidKeyStore AES-GCM) or a Keychain round-trip. The numbers
below show that shape — reads are cheap, and secure writes cost the most.

> **These are illustrative, not a spec.** Measured on an **iOS simulator**
> (iPhone 17 Pro, debug build) over 300 iterations per op after warm-up. Real
> devices, release builds, and Android hardware will differ — often
> substantially. Treat them as *relative* (secure vs regular, read vs write),
> and re-run on your own targets before quoting.

| Operation | Mean per op (µs) | Ops/sec |
| --- | ---: | ---: |
| regular setString | 171.6 | 5,828 |
| regular getString | 39.9 | 25,044 |
| regular setInt | 189.7 | 5,272 |
| regular getInt | 40.6 | 24,616 |
| secure setString | 636.9 | 1,570 |
| secure getString | 210.5 | 4,750 |
| secure setBytes | 545.6 | 1,833 |
| secure getBytes | 201.1 | 4,972 |

**Takeaways:** reads are the cheapest calls (~40 µs regular / ~200 µs secure);
writes cost more than reads on both stores. Encryption is not free — a secure
write runs ~3–4× a regular write (AES-GCM + AndroidKeyStore / Keychain), and a
secure read ~5× a regular read. All eight cases clear thousands of ops/sec, so
for typical secret access (a handful of tokens) the overhead is negligible;
reserve the secure store for actual secrets and keep hot, high-frequency
key-value traffic on the regular store.

Run it yourself on any connected device or simulator:

```bash
cd example
flutter run -t lib/benchmark_main.dart -d <device-id>
# read the BENCHMARK_TABLE_START / _END block from the console
```

---

## Storage Details

Understanding how each type is stored on each platform:

| Dart Type | Android (DataStore) | iOS (UserDefaults) |
|-----------|--------------------|--------------------|
| `String` | `stringPreferencesKey` | `string(forKey:)` |
| `bool` | `booleanPreferencesKey` | `bool(forKey:)` |
| `int` | `longPreferencesKey` | `integer(forKey:)` |
| `double` | `doublePreferencesKey` | `double(forKey:)` |
| `List<String>` | JSON-encoded string | Native string array |
| `Uint8List` | Base64-encoded string | Native `Data` |
| `DateTime` | `Long` (millis since epoch UTC) | `Int64` (millis since epoch UTC) |
| `Map<String, dynamic>` | JSON-encoded string | JSON-encoded string |

> **Note:** `DateTime` values are always stored and retrieved in **UTC**. If you pass a local `DateTime`, it is converted to UTC before storage. The returned `DateTime` is always UTC -- use `.toLocal()` if you need local time.

---

## Migrating from shared_preferences

The API is intentionally similar -- switching is a one-line change:

```dart
// Before (shared_preferences)
final prefs = await SharedPreferences.getInstance();
await prefs.setString('key', 'value');
final value = prefs.getString('key');

// After (native_datastore)
final datastore = NativeDatastore();
await datastore.setString('key', 'value');
final value = await datastore.getString('key');
```

**Key differences:**

| | shared_preferences | native_datastore |
|-|-------------------|-----------------|
| Initialization | `SharedPreferences.getInstance()` | `NativeDatastore()` |
| Reads | Synchronous (cached) | `Future`-based (async) |
| Android backend | SharedPreferences | Jetpack DataStore |
| Extra types | -- | `Uint8List`, `DateTime`, `Map` |

**Already have data in `shared_preferences`?** Import it in one call so your
users don't lose anything on upgrade:

```dart
// Copies existing shared_preferences values into native_datastore.
// Safe to call on every launch — with overwrite: false it imports nothing
// the second time. Returns the number of keys imported.
final imported = await datastore.migrateFromSharedPreferences();
```

Scalars (`String`, `bool`, `int`, `double`) and string lists are migrated.

---

## Platform Details

### Android

- Uses `androidx.datastore:datastore-preferences` with Kotlin Coroutines
- All operations run on `Dispatchers.IO` -- never blocks the UI thread
- Data location: `data/data/<package>/files/datastore/native_datastore_prefs.preferences_pb`
- A `ReplaceFileCorruptionHandler` is installed so a half-written prefs file
  (caused by the OS killing the process mid-write) recovers as empty
  instead of throwing `CorruptionException` on every subsequent call.
- Minimum SDK: **21** (Android 5.0)

### iOS

- Uses `UserDefaults.standard`
- Keys are namespaced with `native_datastore.` prefix to avoid collisions
- String lists stored natively as arrays (no JSON encoding overhead)
- Binary data (`Uint8List`) stored natively as `Data`
- Numeric getters (`getBool`, `getInt`, `getDouble`, `getDateTime`) are
  strict: they return `null` when the stored value's underlying type does
  not match (no silent coercion across types).
- Minimum iOS: **13.0**
- Ships both a **Swift Package Manager** manifest (`Package.swift`) and a
  **CocoaPods** `podspec`, so it works whether or not your app has enabled
  Flutter's Swift Package Manager integration — no configuration needed.
- Includes a **privacy manifest** (`PrivacyInfo.xcprivacy`) declaring the
  `UserDefaults` required-reason API for App Store submission.

---

## Requirements

| Dependency | Minimum Version |
|------------|-----------------|
| Flutter    | 3.3.0           |
| Dart SDK   | 3.11.4          |
| Android    | API 21 (5.0)    |
| iOS        | 13.0            |

---

## Advanced Topics

> **You do not need to read this to use the plugin.** These sections explain how
> `native_datastore` behaves under difficult real-world conditions. If you're just getting
> started, skip ahead to [Contributing](#contributing) — come back when you're shipping to
> production or investigating a tricky data-loss report.

### Surviving aggressive app-killing (Android)

Some Android phone brands (Xiaomi/MIUI, OPPO/ColorOS, Vivo/OriginOS, HyperOS, Realme UI,
etc.) aggressively shut down apps in the background to save memory and battery — sometimes
mid-write. A naive storage layer can lose or corrupt data when this happens.
`native_datastore` is built to survive it:

- **Atomic writes.** Each write goes through Jetpack DataStore, which uses
  the filesystem's atomic rename to replace the prefs file. A process kill
  mid-write either commits the full new file or leaves the previous file
  intact -- never a half-merged record.
- **Durable acknowledgements.** `await datastore.setX(...)` only resolves
  after the write has been flushed to physical disk (an `fsync`), so once your
  `await` returns, the value is genuinely saved — not just queued in memory.
- **Auto-recovery from corruption.** If a kill lands inside the fsync
  window and the file ends up unreadable, the corruption handler replaces
  it with empty preferences on the next read. The app keeps working --
  at worst losing the single write that was interrupted, never bricked.
- **Clean detach.** When the Flutter engine is destroyed, in-flight
  coroutines are cancelled before the Pigeon channel is torn down, so the
  plugin never replies on a dead channel.

### Multi-process access (opt-in)

**By default** the plugin uses single-process storage, and the default store
is *not* safe to access from more than one process at a time. If you need
multi-process access, opt in once at startup with `configure` — this is
non-destructive and leaves the default store untouched:

```dart
// Call once, before the first read/write.
await NativeDatastore().configure(
  multiProcess: true,           // Android: open a MultiProcessDataStore
  appGroupId: 'group.com.you.app', // iOS: share via an App Group suite
);
```

- **Android** (`multiProcess: true`) opens a `MultiProcessDataStore` in its own
  file, safe for concurrent access from multiple processes. Because it uses a
  separate file, values are not shared with the default single-process store.
- **iOS** (`appGroupId`) backs storage with `UserDefaults(suiteName:)` so an app
  extension or other process in the same App Group sees the same data. You must
  enable the App Group capability in Xcode.

#### SecureDatastore

`SecureDatastore` exposes the same `configure` method for cross-process access
to encrypted secrets:

```dart
await SecureDatastore().configure(
  multiProcess: true,              // Android: multi-process encrypted DataStore
  appGroupId: 'TEAMID.com.you.shared', // iOS: Keychain access group
);
```

- **Android** (`multiProcess: true`) opens the encrypted store with
  `MultiProcessDataStore` in its own file (`native_datastore_secure_mp.json`).
  The AndroidKeyStore key is already process-agnostic, so only the file backing
  changes. As with the regular store, secrets in the default file are **not**
  migrated into the multi-process file.
- **iOS** (`appGroupId`) is used as the **Keychain access group**
  (`kSecAttrAccessGroup`), letting an app and its extensions share secrets. This
  requires enabling the **Keychain Sharing** capability in Xcode. Note this is a
  Keychain access group string (typically team-prefixed, e.g.
  `$(AppIdentifierPrefix)com.you.shared`) — **not** the same as the App Group
  suite name used by the regular `NativeDatastore`.

### ⚠️ The default (single-process) store

Without `configure`, the Android backend uses single-process Preferences
DataStore. **It is not safe to use the default store from more than one process
at a time.** This matters if your app declares any of the following in
`AndroidManifest.xml`:

- A `<service>`, `<receiver>`, or `<activity>` with `android:process=":foo"`
- A vendor push SDK (Xiaomi, OPPO, Vivo, Huawei, FCM in a separate process,
  Tencent TPNS, etc.) that runs in its own process
- A `ContentProvider` configured with a separate process

Symptoms of multi-process misuse: silently lost writes, "old" values
reappearing after an app upgrade, or in the worst case repeated
`CorruptionException`s (which the corruption handler will swallow by
resetting the file to empty -- i.e., data loss).

**Recommended pattern:** either call `native_datastore` only from the main
process (the one Flutter runs in), or opt into multi-process mode above if a
secondary process genuinely needs shared access.

---

### Library Size

The library is lightweight with a minimal footprint:

| Layer | Hand-written | Generated (Pigeon) | Total |
|-------|-------------|-------------------|-------|
| Dart | 358 lines | 463 lines | 821 lines |
| Kotlin (Android) | 301 lines | 509 lines | 810 lines |
| Swift (iOS) | 277 lines | 480 lines | 757 lines |
| **Total** | **936 lines** | **1,452 lines** | **2,388 lines** |

- ~61% is auto-generated [Pigeon](https://pub.dev/packages/pigeon) code (message channel boilerplate)
- ~39% is hand-written plugin logic (~300 lines per platform)
- Total source size: **~87 KB** across 7 files
- No external dependencies beyond Flutter SDK and platform-native APIs

---

## FAQ

**Do I need to initialize it?**
No. Just `final ds = NativeDatastore();` and start calling — there's no
`getInstance()`, no `await` setup, nothing to add to `main()`.

**What does a getter return if the key doesn't exist?**
`null`. Use `?? defaultValue` or check with `containsKey`.

**Why is everything `async` / `Future`-based?**
Reads and writes touch disk. Doing that asynchronously keeps work off the UI
thread, so your app never janks or triggers an ANR. Even a `watch*` stream
delivers its first value asynchronously.

**Is it safe to write the same key from many places at once?**
Writes are serialized natively, so they don't corrupt each other. For
read-then-write logic (like a counter) use the **atomic** methods
(`incrementInt`, `compareAndSet*`) so a concurrent update is never lost.

**How much can I store?**
Small values only — this is for preferences, not bulk data. `setBytes` and
`setMap` reject payloads over **1 MiB**. For anything large or queryable, use a
database.

**Is my data encrypted?**
`NativeDatastore` is **not** encrypted (it's plain UserDefaults / DataStore).
For secrets use [`SecureDatastore`](#-secure-storage) — Keychain on iOS,
AndroidKeyStore-backed AES-256-GCM on Android.

**Does it work from a background isolate or a second process?**
Use it from the main isolate/process by default. For a separate process (a
background service, or an iOS app extension), opt in with
`configure(multiProcess: true)` (Android) or `configure(appGroupId: …)` (iOS).
`SecureDatastore` supports the same `configure` for cross-process secrets — on
iOS `appGroupId` is used as the Keychain access group (Keychain Sharing
capability required).

**Which platforms are supported?**
Android and iOS. (Not web or desktop.)

**Do I need to change `AndroidManifest.xml` / `Info.plist`?**
No — it works out of the box. The only exception is iOS App Groups, which
require enabling the App Group capability in Xcode if you use `appGroupId`.

---

## Contributing

Contributions are welcome! Please open an [issue](https://github.com/sudhi001/native_datastore/issues) or submit a pull request.

### Regenerating platform bindings

The Dart/Kotlin/Swift message channel bindings are generated with
[Pigeon](https://pub.dev/packages/pigeon). Always regenerate them with:

```bash
./tool/generate_pigeon.sh
```

Do **not** run `dart run pigeon` directly. The Android package
(`in.sudhi.native_datastore`) starts with `in`, a reserved Kotlin keyword that
Pigeon does not escape, so the raw output fails to compile. The wrapper runs
Pigeon and then backtick-escapes the `package` declaration automatically.

---

## Releasing

Releases are automated via [`.github/workflows/release.yml`](.github/workflows/release.yml).
Pushing a tag that matches `v*` runs tests and, on pass, publishes to pub.dev
(via OIDC — no API key in the repo) and creates a matching GitHub Release.

```bash
# 1. Bump pubspec.yaml version (e.g. 1.3.0 → 1.3.1)
# 2. Commit and push the version bump
git commit -am "Release 1.3.1"
git push

# 3. Tag and push the tag — this triggers the workflow
git tag v1.3.1
git push origin v1.3.1
```

The workflow verifies the pushed tag matches `v{pubspec.version}` and aborts
if they disagree. If a publish fails partway, either bump the patch version
and push a new tag, or delete the bad tag locally and on the remote and retry:

```bash
git tag -d v1.3.1
git push --delete origin v1.3.1
```

---

## License

Licensed under the **Apache License, Version 2.0** -- see the [LICENSE](LICENSE) and
[NOTICE](NOTICE) files for details. The Apache-2.0 license is permissive (free for commercial
and personal use, modification, and redistribution) and includes an explicit patent grant,
making it safe for enterprise adoption.

Copyright 2026 Sudhi S ([sudhi.in](https://sudhi.in)).
