# native_datastore

[![Pub Version](https://img.shields.io/pub/v/native_datastore)](https://pub.dev/packages/native_datastore)
[![Pub Points](https://img.shields.io/pub/points/native_datastore)](https://pub.dev/packages/native_datastore/score)
[![Pub Likes](https://img.shields.io/pub/likes/native_datastore)](https://pub.dev/packages/native_datastore)
[![Pub Popularity](https://img.shields.io/pub/popularity/native_datastore)](https://pub.dev/packages/native_datastore)
[![License: BSD-3](https://img.shields.io/badge/license-BSD--3-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/platform-android%20%7C%20iOS-brightgreen)](https://flutter.dev)
[![GitHub issues](https://img.shields.io/github/issues/sudhi001/native_datastore)](https://github.com/sudhi001/native_datastore/issues)
[![GitHub stars](https://img.shields.io/github/stars/sudhi001/native_datastore)](https://github.com/sudhi001/native_datastore/stargazers)

A modern Flutter plugin for **persistent key-value storage**, powered by platform-native APIs.

| Platform | Backend |
|----------|---------|
| Android  | [Jetpack DataStore](https://developer.android.com/topic/libraries/architecture/datastore) (Preferences) |
| iOS      | [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults) |

---

## Features

- **Jetpack DataStore on Android** -- Google's officially recommended replacement for SharedPreferences. Async, non-blocking, coroutine-based I/O.
- **Drop-in replacement** -- Same getter/setter pattern as `shared_preferences`. Zero learning curve.
- **Type-safe platform communication** -- Built with [Pigeon](https://pub.dev/packages/pigeon). No hand-written method channels, no string-based lookups.
- **Cross-platform** -- One Dart API for Android and iOS.
- **Lightweight** -- No platform interface layer. A thin, clean bridge to native APIs.

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

> **Google's recommendation:** *"Prefer DataStore over SharedPreferences."*
> -- [Android Developers Docs](https://developer.android.com/topic/libraries/architecture/datastore)

---

## Getting Started

### 1. Install

Add to your `pubspec.yaml`:

```yaml
dependencies:
  native_datastore: ^0.0.1
```

Then run:

```bash
flutter pub get
```

### 2. Import

```dart
import 'package:native_datastore/native_datastore.dart';
```

### 3. Use

```dart
final datastore = NativeDatastore();

// -- Write --
await datastore.setString('username', 'sudhi');
await datastore.setBool('darkMode', true);
await datastore.setInt('loginCount', 42);
await datastore.setDouble('rating', 4.8);
await datastore.setStringList('tags', ['flutter', 'dart', 'mobile']);

// -- Read --
final username = await datastore.getString('username');       // "sudhi"
final darkMode = await datastore.getBool('darkMode');         // true
final count    = await datastore.getInt('loginCount');        // 42
final rating   = await datastore.getDouble('rating');         // 4.8
final tags     = await datastore.getStringList('tags');       // ["flutter", "dart", "mobile"]

// -- Query --
final allKeys  = await datastore.getKeys();                   // ["username", "darkMode", ...]
final allData  = await datastore.getAll();                    // {username: sudhi, darkMode: true, ...}
final exists   = await datastore.containsKey('username');     // true

// -- Delete --
await datastore.remove('username');   // Remove a single key
await datastore.clear();              // Remove all data
```

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

### Write operations

| Method | Return Type | Description |
|--------|-------------|-------------|
| `setString(key, value)` | `Future<void>` | Write a string value |
| `setBool(key, value)` | `Future<void>` | Write a boolean value |
| `setInt(key, value)` | `Future<void>` | Write an integer value |
| `setDouble(key, value)` | `Future<void>` | Write a double value |
| `setStringList(key, value)` | `Future<void>` | Write a string list |

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

---

## Platform Details

### Android

- Uses `androidx.datastore:datastore-preferences` with Kotlin Coroutines
- All operations run on `Dispatchers.IO` -- never blocks the UI thread
- Data location: `data/data/<package>/files/datastore/native_datastore_prefs.preferences_pb`
- Minimum SDK: **21** (Android 5.0)

### iOS

- Uses `UserDefaults.standard`
- Keys are namespaced with `in.sudhi.native_datastore.` prefix to avoid collisions
- String lists stored natively as arrays (no JSON encoding overhead)
- Minimum iOS: **12.0**

---

## Requirements

| Dependency | Minimum Version |
|------------|-----------------|
| Flutter    | 3.3.0           |
| Dart SDK   | 3.11.4          |
| Android    | API 21 (5.0)    |
| iOS        | 12.0            |

---

## Contributing

Contributions are welcome! Please open an [issue](https://github.com/sudhi001/native_datastore/issues) or submit a pull request.

---

## License

BSD 3-Clause License -- see the [LICENSE](LICENSE) file for details.
