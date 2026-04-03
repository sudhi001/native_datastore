# native_datastore

A modern Flutter plugin for **persistent key-value storage**, built on top of the latest platform-native storage APIs.

- **Android**: [Jetpack DataStore](https://developer.android.com/topic/libraries/architecture/datastore) (Preferences)
- **iOS**: [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)

## Why native_datastore?

### The Problem with SharedPreferences on Android

If you're still using `SharedPreferences` (or Flutter's `shared_preferences` plugin which wraps it), you're relying on a **legacy Android API** that Google has been actively moving away from. `SharedPreferences` has well-known issues:

| Issue | SharedPreferences | Jetpack DataStore |
|---|---|---|
| **Thread Safety** | Not safe to call on UI thread; can cause ANRs | Fully asynchronous with Kotlin Coroutines; never blocks the main thread |
| **Error Handling** | No mechanism to signal errors; fails silently | Proper error signaling via Kotlin Flow |
| **Runtime Exceptions** | Parsing errors can cause runtime crashes | Will not throw runtime exceptions from parsing errors |
| **Synchronous API on Disk I/O** | Blocking `commit()` / fire-and-forget `apply()` | Transactional, consistent async API |
| **Type Safety** | Returns default values on type mismatch | Typed keys with compile-time safety |
| **Consistency** | No transactional guarantees | Full transactional support with atomic read-modify-write |

> **Google's official recommendation:** *"Prefer DataStore over SharedPreferences. SharedPreferences has several drawbacks including a synchronous API that can appear safe to call on the UI thread, no mechanism for signaling errors, and more."*
>
> -- [Android Developers Documentation](https://developer.android.com/topic/libraries/architecture/datastore)

### What native_datastore Offers

- **Modern Android Storage** -- Uses Jetpack DataStore (Preferences), Google's officially recommended replacement for SharedPreferences. Your app gets async, non-blocking, coroutine-based I/O out of the box.
- **Familiar API** -- If you've used `shared_preferences`, you already know how to use this. Same getter/setter pattern, zero learning curve.
- **Type-Safe Platform Communication** -- Built with [Pigeon](https://pub.dev/packages/pigeon) for compile-time type safety between Dart and native code. No hand-written method channels, no string-based lookups, no runtime surprises.
- **Cross-Platform** -- Same Dart API on Android and iOS. Android uses DataStore, iOS uses UserDefaults.
- **Lightweight** -- No platform interface layer, no abstractions-on-abstractions. Just a thin, clean bridge to the native APIs.

## Installation

```yaml
dependencies:
  native_datastore: ^0.0.1
```

```bash
flutter pub get
```

## Quick Start

```dart
import 'package:native_datastore/native_datastore.dart';

final datastore = NativeDatastore();

// Write
await datastore.setString('username', 'sudhi');
await datastore.setBool('darkMode', true);
await datastore.setInt('loginCount', 42);
await datastore.setDouble('rating', 4.8);
await datastore.setStringList('tags', ['flutter', 'dart', 'mobile']);

// Read
final username = await datastore.getString('username');   // "sudhi"
final darkMode = await datastore.getBool('darkMode');     // true
final count = await datastore.getInt('loginCount');       // 42
final rating = await datastore.getDouble('rating');       // 4.8
final tags = await datastore.getStringList('tags');       // ["flutter", "dart", "mobile"]

// Query
final allKeys = await datastore.getKeys();                // ["username", "darkMode", ...]
final allData = await datastore.getAll();                 // {username: sudhi, darkMode: true, ...}
final exists = await datastore.containsKey('username');   // true

// Delete
await datastore.remove('username');                       // Remove single key
await datastore.clear();                                  // Remove all data
```

## API Reference

| Method | Return Type | Description |
|---|---|---|
| `getString(key)` | `Future<String?>` | Read a string value |
| `getBool(key)` | `Future<bool?>` | Read a boolean value |
| `getInt(key)` | `Future<int?>` | Read an integer value |
| `getDouble(key)` | `Future<double?>` | Read a double value |
| `getStringList(key)` | `Future<List<String>?>` | Read a string list |
| `setString(key, value)` | `Future<void>` | Write a string value |
| `setBool(key, value)` | `Future<void>` | Write a boolean value |
| `setInt(key, value)` | `Future<void>` | Write an integer value |
| `setDouble(key, value)` | `Future<void>` | Write a double value |
| `setStringList(key, value)` | `Future<void>` | Write a string list |
| `remove(key)` | `Future<bool>` | Remove a key (returns true if existed) |
| `clear()` | `Future<bool>` | Remove all stored data |
| `getAll()` | `Future<Map<String, Object>>` | Get all key-value pairs |
| `getKeys()` | `Future<List<String>>` | Get all stored keys |
| `containsKey(key)` | `Future<bool>` | Check if a key exists |

## Migrating from shared_preferences

Switching is straightforward -- the API is intentionally similar:

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

Key differences:
- No `getInstance()` -- just create a `NativeDatastore()` directly
- All reads are `Future`-based (async) -- because that's how modern storage should work
- On Android, your data is stored in Jetpack DataStore instead of SharedPreferences

## Platform Details

### Android
- Uses `androidx.datastore:datastore-preferences` with Kotlin Coroutines
- All operations run on `Dispatchers.IO` -- never blocks the UI thread
- Data stored in: `data/data/<package>/files/datastore/native_datastore_prefs.preferences_pb`
- Minimum SDK: 21 (Android 5.0)

### iOS
- Uses `UserDefaults.standard`
- All keys are namespaced with `in.sudhi.native_datastore.` prefix to avoid collisions
- String lists stored natively as arrays (no JSON encoding overhead)
- Minimum iOS: 12.0

## Requirements

| Platform | Minimum Version |
|---|---|
| Flutter | 3.3.0+ |
| Dart | 3.11.4+ |
| Android | API 21 (Android 5.0) |
| iOS | 12.0 |

## License

This project is licensed under the BSD 3-Clause License - see the [LICENSE](LICENSE) file for details.
