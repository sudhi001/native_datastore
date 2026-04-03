import 'dart:async';

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

  /// Validates that [key] is a non-empty string.
  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw const NativeDatastoreException(
        'Key must not be empty',
      );
    }
  }

  /// Wraps a platform call with error handling.
  ///
  /// Catches [PlatformException] and rethrows as [NativeDatastoreException]
  /// with context about which [operation] failed.
  Future<T> _guard<T>(String operation, Future<T> Function() fn) async {
    try {
      return await fn();
    } on PlatformException catch (e) {
      throw NativeDatastoreException(
        'Failed to $operation: ${e.message ?? e.code}',
        cause: e,
      );
    }
  }

  /// Reads a [String] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<String?> getString(String key) {
    _validateKey(key);
    return _guard('getString("$key")', () => _api.getString(key));
  }

  /// Reads a [bool] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<bool?> getBool(String key) {
    _validateKey(key);
    return _guard('getBool("$key")', () => _api.getBool(key));
  }

  /// Reads an [int] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<int?> getInt(String key) {
    _validateKey(key);
    return _guard('getInt("$key")', () => _api.getInt(key));
  }

  /// Reads a [double] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<double?> getDouble(String key) {
    _validateKey(key);
    return _guard('getDouble("$key")', () => _api.getDouble(key));
  }

  /// Reads a [List] of [String] values from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<List<String>?> getStringList(String key) {
    _validateKey(key);
    return _guard('getStringList("$key")', () => _api.getStringList(key));
  }

  /// Writes a [String] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<void> setString(String key, String value) {
    _validateKey(key);
    return _guard('setString("$key")', () => _api.setString(key, value));
  }

  /// Writes a [bool] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<void> setBool(String key, bool value) {
    _validateKey(key);
    return _guard('setBool("$key")', () => _api.setBool(key, value));
  }

  /// Writes an [int] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<void> setInt(String key, int value) {
    _validateKey(key);
    return _guard('setInt("$key")', () => _api.setInt(key, value));
  }

  /// Writes a [double] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<void> setDouble(String key, double value) {
    _validateKey(key);
    return _guard('setDouble("$key")', () => _api.setDouble(key, value));
  }

  /// Writes a [List] of [String] values to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<void> setStringList(String key, List<String> value) {
    _validateKey(key);
    return _guard(
      'setStringList("$key")',
      () => _api.setStringList(key, value),
    );
  }

  /// Removes the value associated with the given [key] from the data store.
  ///
  /// Returns `true` if the [key] existed and was removed, `false` otherwise.
  ///
  /// Throws [NativeDatastoreException] if the [key] is empty or
  /// the platform call fails.
  Future<bool> remove(String key) {
    _validateKey(key);
    return _guard('remove("$key")', () => _api.remove(key));
  }

  /// Removes all key-value pairs from the data store.
  ///
  /// Returns `true` if the operation was successful.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<bool> clear() {
    return _guard('clear', _api.clear);
  }

  /// Returns all key-value pairs currently stored in the data store.
  ///
  /// The returned map contains the key as a [String] and the value as
  /// an [Object] which can be a [String], [int], [double], [bool],
  /// or [List] of [String].
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<Map<String, Object>> getAll() {
    return _guard('getAll', _api.getAll);
  }

  /// Returns a list of all keys currently stored in the data store.
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
}
