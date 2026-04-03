import 'package:flutter/foundation.dart';

import 'messages.g.dart';

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

  /// Reads a [String] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  Future<String?> getString(String key) => _api.getString(key);

  /// Reads a [bool] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  Future<bool?> getBool(String key) => _api.getBool(key);

  /// Reads an [int] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  Future<int?> getInt(String key) => _api.getInt(key);

  /// Reads a [double] value from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  Future<double?> getDouble(String key) => _api.getDouble(key);

  /// Reads a [List] of [String] values from the data store for the given [key].
  ///
  /// Returns `null` if the [key] does not exist.
  Future<List<String>?> getStringList(String key) => _api.getStringList(key);

  /// Writes a [String] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  Future<void> setString(String key, String value) =>
      _api.setString(key, value);

  /// Writes a [bool] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  Future<void> setBool(String key, bool value) => _api.setBool(key, value);

  /// Writes an [int] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  Future<void> setInt(String key, int value) => _api.setInt(key, value);

  /// Writes a [double] [value] to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  Future<void> setDouble(String key, double value) =>
      _api.setDouble(key, value);

  /// Writes a [List] of [String] values to the data store for the given [key].
  ///
  /// If the [key] already exists, its value is overwritten.
  Future<void> setStringList(String key, List<String> value) =>
      _api.setStringList(key, value);

  /// Removes the value associated with the given [key] from the data store.
  ///
  /// Returns `true` if the [key] existed and was removed, `false` otherwise.
  Future<bool> remove(String key) => _api.remove(key);

  /// Removes all key-value pairs from the data store.
  ///
  /// Returns `true` if the operation was successful.
  Future<bool> clear() => _api.clear();

  /// Returns all key-value pairs currently stored in the data store.
  ///
  /// The returned map contains the key as a [String] and the value as
  /// an [Object] which can be a [String], [int], [double], [bool],
  /// or [List] of [String].
  Future<Map<String, Object>> getAll() => _api.getAll();

  /// Returns a list of all keys currently stored in the data store.
  Future<List<String>> getKeys() => _api.getKeys();

  /// Returns `true` if the data store contains the given [key].
  Future<bool> containsKey(String key) => _api.containsKey(key);
}
