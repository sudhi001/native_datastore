import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'messages.g.dart';

/// Exception thrown when a [NativeDatastore] operation fails.
///
/// Wraps platform-specific errors with a human-readable [message]
/// and the original [cause] when available.
class NativeDatastoreException implements Exception {
  /// Creates a [NativeDatastoreException].
  const NativeDatastoreException(this.message, {this.cause});

  /// A human-readable description of what went wrong.
  final String message;

  /// The underlying platform exception, if any.
  final Object? cause;

  @override
  String toString() {
    if (cause != null) {
      return 'NativeDatastoreException: $message (cause: $cause)';
    }
    return 'NativeDatastoreException: $message';
  }
}

/// Prefixes the native side uses internally to namespace typed storage so
/// `setStringList`/`setBytes`/`setDateTime`/`setMap` cannot collide with the
/// scalar getters/setters that share the same flat key-value store.
///
/// Keep these in sync with the Swift and Kotlin constants of the same names.
class _BucketPrefix {
  static const String list = '__list__:';
  static const String bytes = '__bytes__:';
  static const String dateTime = '__datetime__:';
  static const String map = '__map__:';

  static const List<String> all = <String>[list, bytes, dateTime, map];
}

/// Upper bound on `setBytes` / `setMap` payloads. UserDefaults and DataStore
/// are designed for small preference values; storing larger blobs degrades
/// app launch time and can trigger OS-level warnings. Callers that need bulk
/// storage should use a database or the filesystem instead.
const int _maxBlobBytes = 1024 * 1024;

/// A Flutter plugin for native persistent key-value storage.
///
/// On Android, this plugin uses [Jetpack DataStore](https://developer.android.com/topic/libraries/architecture/datastore)
/// (Preferences), Google's recommended modern replacement for SharedPreferences.
/// On iOS, it uses [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults).
///
/// Provides a familiar async key-value API similar to `shared_preferences`,
/// backed by the latest platform-native storage solutions.
///
/// {@tool snippet}
/// ```dart
/// final datastore = NativeDatastore();
///
/// await datastore.setString('username', 'sudhi');
/// final username = await datastore.getString('username');
/// ```
/// {@end-tool}
class NativeDatastore {
  /// Creates an instance of [NativeDatastore] that communicates with the
  /// platform-specific implementation via Pigeon.
  NativeDatastore() : _api = DatastoreApi();

  /// Creates an instance of [NativeDatastore] with a given [api].
  ///
  /// This is useful for unit testing where you can inject a mock
  /// implementation of [DatastoreApi].
  @visibleForTesting
  NativeDatastore.withApi(DatastoreApi api) : _api = api;

  final DatastoreApi _api;

  /// {@template native_datastore.getter}
  /// Returns `null` if [key] does not exist.
  ///
  /// Throws [NativeDatastoreException] if [key] is empty, starts with a
  /// reserved prefix, or the platform call fails.
  /// {@endtemplate}
  ///
  /// {@template native_datastore.setter}
  /// If [key] already exists, its value is overwritten.
  ///
  /// Throws [NativeDatastoreException] if [key] is empty, starts with a
  /// reserved prefix, or the platform call fails.
  /// {@endtemplate}
  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw const NativeDatastoreException(
        'Key must not be empty',
      );
    }
    for (final prefix in _BucketPrefix.all) {
      if (key.startsWith(prefix)) {
        throw NativeDatastoreException(
          'Key must not start with reserved prefix "$prefix"',
        );
      }
    }
  }

  Future<T> _guard<T>(String operation, Future<T> Function() action) async {
    try {
      return await action();
    } on NativeDatastoreException {
      rethrow;
    } on PlatformException catch (e) {
      throw NativeDatastoreException(
        'Failed to $operation: ${e.message ?? e.code}',
        cause: e,
      );
    } catch (e) {
      throw NativeDatastoreException(
        'Failed to $operation: $e',
        cause: e,
      );
    }
  }

  /// Reads a [String] value from the data store for the given [key].
  ///
  /// {@macro native_datastore.getter}
  Future<String?> getString(String key) {
    _validateKey(key);
    return _guard('getString("$key")', () => _api.getString(key));
  }

  /// Reads a [bool] value from the data store for the given [key].
  ///
  /// {@macro native_datastore.getter}
  Future<bool?> getBool(String key) {
    _validateKey(key);
    return _guard('getBool("$key")', () => _api.getBool(key));
  }

  /// Reads an [int] value from the data store for the given [key].
  ///
  /// {@macro native_datastore.getter}
  Future<int?> getInt(String key) {
    _validateKey(key);
    return _guard('getInt("$key")', () => _api.getInt(key));
  }

  /// Reads a [double] value from the data store for the given [key].
  ///
  /// {@macro native_datastore.getter}
  Future<double?> getDouble(String key) {
    _validateKey(key);
    return _guard('getDouble("$key")', () => _api.getDouble(key));
  }

  /// Reads a [List] of [String] values from the data store for the given [key].
  ///
  /// {@macro native_datastore.getter}
  Future<List<String>?> getStringList(String key) {
    _validateKey(key);
    return _guard('getStringList("$key")', () => _api.getStringList(key));
  }

  /// Writes a [String] [value] to the data store for the given [key].
  ///
  /// {@macro native_datastore.setter}
  Future<void> setString(String key, String value) {
    _validateKey(key);
    return _guard('setString("$key")', () => _api.setString(key, value));
  }

  /// Writes a [bool] [value] to the data store for the given [key].
  ///
  /// {@macro native_datastore.setter}
  Future<void> setBool(String key, bool value) {
    _validateKey(key);
    return _guard('setBool("$key")', () => _api.setBool(key, value));
  }

  /// Writes an [int] [value] to the data store for the given [key].
  ///
  /// {@macro native_datastore.setter}
  Future<void> setInt(String key, int value) {
    _validateKey(key);
    return _guard('setInt("$key")', () => _api.setInt(key, value));
  }

  /// Writes a [double] [value] to the data store for the given [key].
  ///
  /// {@macro native_datastore.setter}
  Future<void> setDouble(String key, double value) {
    _validateKey(key);
    return _guard('setDouble("$key")', () => _api.setDouble(key, value));
  }

  /// Writes a [List] of [String] values to the data store for the given [key].
  ///
  /// {@macro native_datastore.setter}
  Future<void> setStringList(String key, List<String> value) {
    _validateKey(key);
    return _guard(
      'setStringList("$key")',
      () => _api.setStringList(key, value),
    );
  }

  /// Removes the value associated with the given [key] from the data store.
  ///
  /// Returns `true` if the [key] existed and was removed, `false` if no
  /// value was stored under [key].
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<bool> remove(String key) {
    _validateKey(key);
    return _guard('remove("$key")', () => _api.remove(key));
  }

  /// Removes every key-value pair from the data store.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<void> clear() {
    return _guard('clear', _api.clear);
  }

  /// Returns a snapshot of every key-value pair currently stored.
  ///
  /// The map's values are a heterogeneous union of the runtime types
  /// produced by each setter:
  ///
  ///   * `setString` → [String]
  ///   * `setBool`   → [bool]
  ///   * `setInt`    → [int]
  ///   * `setDouble` → [double]
  ///   * `setStringList` → [List]<[String]>
  ///   * `setBytes`  → [Uint8List]
  ///   * `setDateTime` → [int] (milliseconds since epoch, UTC) — *not* a [DateTime]
  ///   * `setMap`    → [String] (the underlying JSON payload) — *not* a [Map]
  ///
  /// Use the typed getters when you need a [DateTime] or [Map] back.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<Map<String, Object>> getAll() {
    return _guard('getAll', _api.getAll);
  }

  /// Returns the user-facing keys currently stored. Each typed setter is
  /// reported under its bare key (internal prefixes are stripped), and a key
  /// stored via multiple setters appears once.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<List<String>> getKeys() {
    return _guard('getKeys', _api.getKeys);
  }

  /// Returns `true` if the data store contains the given [key].
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<bool> containsKey(String key) {
    _validateKey(key);
    return _guard('containsKey("$key")', () => _api.containsKey(key));
  }

  /// Reads a [Uint8List] (binary data) from the data store for the given [key].
  ///
  /// {@macro native_datastore.getter}
  Future<Uint8List?> getBytes(String key) {
    _validateKey(key);
    return _guard('getBytes("$key")', () => _api.getBytes(key));
  }

  /// Writes a [Uint8List] (binary data) to the data store for the given [key].
  ///
  /// {@macro native_datastore.setter}
  ///
  /// Throws [NativeDatastoreException] if [value] exceeds 1 MiB. The
  /// underlying platform stores are designed for small preference values;
  /// larger payloads should use a database or filesystem.
  Future<void> setBytes(String key, Uint8List value) {
    _validateKey(key);
    if (value.lengthInBytes > _maxBlobBytes) {
      throw NativeDatastoreException(
        'setBytes value too large: ${value.lengthInBytes} bytes '
        '(max $_maxBlobBytes)',
      );
    }
    return _guard('setBytes("$key")', () => _api.setBytes(key, value));
  }

  /// Reads a [DateTime] from the data store for the given [key].
  ///
  /// The value is stored as milliseconds since epoch (UTC).
  ///
  /// {@macro native_datastore.getter}
  Future<DateTime?> getDateTime(String key) {
    _validateKey(key);
    return _guard('getDateTime("$key")', () async {
      final millis = await _api.getDateTime(key);
      return millis != null
          ? DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true)
          : null;
    });
  }

  /// Writes a [DateTime] to the data store for the given [key].
  ///
  /// The value is stored as milliseconds since epoch (UTC).
  ///
  /// {@macro native_datastore.setter}
  Future<void> setDateTime(String key, DateTime value) {
    _validateKey(key);
    return _guard(
      'setDateTime("$key")',
      () => _api.setDateTime(key, value.toUtc().millisecondsSinceEpoch),
    );
  }

  /// Reads a [Map] from the data store for the given [key].
  ///
  /// The value is stored as a JSON string internally.
  ///
  /// {@macro native_datastore.getter}
  Future<Map<String, dynamic>?> getMap(String key) {
    _validateKey(key);
    return _guard('getMap("$key")', () async {
      final json = await _api.getMap(key);
      return json != null
          ? (jsonDecode(json) as Map<String, dynamic>)
          : null;
    });
  }

  /// Writes a [Map] to the data store for the given [key].
  ///
  /// The value is stored as a JSON string internally.
  ///
  /// {@macro native_datastore.setter}
  ///
  /// Throws [NativeDatastoreException] if the encoded JSON exceeds 1 MiB
  /// or [value] contains objects that cannot be JSON-encoded.
  Future<void> setMap(String key, Map<String, dynamic> value) {
    _validateKey(key);
    return _guard('setMap("$key")', () async {
      final json = jsonEncode(value);
      if (json.length > _maxBlobBytes) {
        throw NativeDatastoreException(
          'setMap value too large: ${json.length} bytes (max $_maxBlobBytes)',
        );
      }
      await _api.setMap(key, json);
    });
  }
}
