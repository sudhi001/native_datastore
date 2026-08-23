import 'dart:async';
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
      throw const NativeDatastoreException('Key must not be empty');
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
      throw NativeDatastoreException('Failed to $operation: $e', cause: e);
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

  // ---- Batch ----

  /// Reads [keys] in a single platform round trip.
  ///
  /// Reading keys one at a time costs one channel hop each, and on Android
  /// each hop materialises the whole store snapshot — measurably ~90x slower
  /// than one batched call for 200 keys. Prefer this when loading several
  /// preferences at once (app startup, settings screens).
  ///
  /// Absent keys are omitted from the result rather than mapped to `null`, so
  /// a missing key is distinguishable from a stored one. Values come back in
  /// the same shapes as [getAll].
  ///
  /// Throws [NativeDatastoreException] if any key is empty or the platform
  /// call fails.
  Future<Map<String, Object>> getMany(List<String> keys) {
    for (final key in keys) {
      _validateKey(key);
    }
    if (keys.isEmpty) {
      return Future<Map<String, Object>>.value(<String, Object>{});
    }
    return _guard('getMany(${keys.length} keys)', () => _api.getMany(keys));
  }

  /// Writes every entry of [entries] in a single native transaction.
  ///
  /// On Android each individual write rewrites the whole preferences file, so
  /// batching N writes turns N rewrites into one. The batch is atomic: either
  /// every entry lands or none does.
  ///
  /// Values must be [String], [bool], [int], [double] or [List]<[String]>.
  /// For [Uint8List], [DateTime] or [Map] values use the dedicated setters —
  /// they carry type information this batch path does not.
  ///
  /// Throws [NativeDatastoreException] if a key is empty, a value has an
  /// unsupported type, or the platform call fails.
  Future<void> setMany(Map<String, Object> entries) {
    for (final entry in entries.entries) {
      _validateKey(entry.key);
      final value = entry.value;
      if (value is! String &&
          value is! bool &&
          value is! int &&
          value is! double &&
          value is! List<String>) {
        throw NativeDatastoreException(
          'setMany: unsupported value type for key "${entry.key}": '
          '${value.runtimeType}. Use the typed setter instead.',
        );
      }
    }
    if (entries.isEmpty) {
      return Future<void>.value();
    }
    return _guard(
      'setMany(${entries.length} keys)',
      () => _api.setMany(entries),
    );
  }

  /// Removes [keys] in a single native transaction, returning how many were
  /// actually present.
  ///
  /// Throws [NativeDatastoreException] if any key is empty or the platform
  /// call fails.
  Future<int> removeMany(List<String> keys) {
    for (final key in keys) {
      _validateKey(key);
    }
    if (keys.isEmpty) {
      return Future<int>.value(0);
    }
    return _guard(
      'removeMany(${keys.length} keys)',
      () => _api.removeMany(keys),
    );
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
      return json != null ? (jsonDecode(json) as Map<String, dynamic>) : null;
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

  // ---- Atomic read-modify-write ----

  /// Atomically adds [delta] to the [int] stored at [key] and returns the new
  /// value. A missing value is treated as `0`. The read-modify-write happens as
  /// a single native transaction, so concurrent callers never lose an update.
  ///
  /// {@macro native_datastore.setter}
  Future<int> incrementInt(String key, [int delta = 1]) {
    _validateKey(key);
    return _guard('incrementInt("$key")', () => _api.incrementInt(key, delta));
  }

  /// Atomically subtracts [amount] from the [int] stored at [key] and returns
  /// the new value. Convenience for [incrementInt] with a negative delta.
  ///
  /// {@macro native_datastore.setter}
  Future<int> decrementInt(String key, [int amount = 1]) =>
      incrementInt(key, -amount);

  /// Atomically adds [delta] to the [double] stored at [key] and returns the
  /// new value. A missing value is treated as `0.0`.
  ///
  /// {@macro native_datastore.setter}
  Future<double> incrementDouble(String key, [double delta = 1.0]) {
    _validateKey(key);
    return _guard(
      'incrementDouble("$key")',
      () => _api.incrementDouble(key, delta),
    );
  }

  /// Atomically flips the [bool] stored at [key] and returns the new value.
  /// A missing value is treated as `false` (so the first toggle yields `true`).
  ///
  /// {@macro native_datastore.setter}
  Future<bool> toggleBool(String key) {
    _validateKey(key);
    return _guard('toggleBool("$key")', () => _api.toggleBool(key));
  }

  /// {@template native_datastore.cas}
  /// Atomically sets [key] to [value] only if its current value equals
  /// [expected]. A null [expected] means "only if the key is currently absent";
  /// a null [value] means "remove the key". Returns `true` if the swap was
  /// applied, `false` if the current value did not match [expected].
  ///
  /// {@macro native_datastore.setter}
  /// {@endtemplate}
  Future<bool> compareAndSetString(
    String key, {
    String? expected,
    String? value,
  }) {
    _validateKey(key);
    return _guard(
      'compareAndSetString("$key")',
      () => _api.compareAndSetString(key, expected, value),
    );
  }

  /// {@macro native_datastore.cas}
  Future<bool> compareAndSetInt(String key, {int? expected, int? value}) {
    _validateKey(key);
    return _guard(
      'compareAndSetInt("$key")',
      () => _api.compareAndSetInt(key, expected, value),
    );
  }

  /// {@macro native_datastore.cas}
  Future<bool> compareAndSetDouble(
    String key, {
    double? expected,
    double? value,
  }) {
    _validateKey(key);
    return _guard(
      'compareAndSetDouble("$key")',
      () => _api.compareAndSetDouble(key, expected, value),
    );
  }

  /// {@macro native_datastore.cas}
  Future<bool> compareAndSetBool(String key, {bool? expected, bool? value}) {
    _validateKey(key);
    return _guard(
      'compareAndSetBool("$key")',
      () => _api.compareAndSetBool(key, expected, value),
    );
  }

  // ---- Reactive observation ----

  /// Broadcast stream of change notifications from the platform. Each event is
  /// the list of user-facing keys whose value changed (or was removed) since
  /// the previous notification. Shared across every `watch*` subscriber so the
  /// native side only maintains a single observer.
  static const EventChannel _changesChannel = EventChannel(
    'in.sudhi.native_datastore/changes',
  );
  static Stream<List<String>>? _changesBroadcast;
  static Stream<List<String>> get _changes =>
      _changesBroadcast ??= _changesChannel.receiveBroadcastStream().map(
        (Object? event) => (event as List<Object?>).cast<String>(),
      );

  /// Drops the cached change-notification stream so the next `watch*` call
  /// re-subscribes to the platform channel. Only needed in tests that swap the
  /// mocked [EventChannel] handler between cases.
  @visibleForTesting
  static void debugResetChangeStream() => _changesBroadcast = null;

  /// Emits the current value of [key] immediately, then a fresh value every
  /// time the platform reports that [key] changed. [read] re-fetches the typed
  /// value on each change.
  ///
  /// Built on an explicit [StreamController] rather than an `async*` body: a
  /// generator parked in `await for` cannot be resumed by a cancellation, so
  /// `subscription.cancel()` would not complete — and the underlying platform
  /// observer would stay registered — until the next change event arrived.
  Stream<T?> _watch<T>(String key, Future<T?> Function() read) {
    _validateKey(key);
    late final StreamController<T?> controller;
    // ignore: cancel_subscriptions — cancelled from the controller's onCancel.
    StreamSubscription<List<String>>? changes;
    // Reads are chained so overlapping notifications cannot deliver a stale
    // value after a fresher one.
    var reads = Future<void>.value();

    void scheduleRead() {
      reads = reads.then((_) async {
        if (controller.isClosed) {
          return;
        }
        try {
          final value = await read();
          if (!controller.isClosed) {
            controller.add(value);
          }
        } catch (error, stackTrace) {
          if (!controller.isClosed) {
            controller.addError(error, stackTrace);
          }
        }
      });
    }

    controller = StreamController<T?>(
      onListen: () {
        // Subscribe before the first read so a change racing that read is not
        // dropped.
        changes = _changes.listen(
          (List<String> changedKeys) {
            if (changedKeys.contains(key)) {
              scheduleRead();
            }
          },
          onError: controller.addError,
          onDone: controller.close,
        );
        scheduleRead();
      },
      onCancel: () {
        final subscription = changes;
        changes = null;
        return subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// Watches the [String] at [key]. Emits the current value on subscription,
  /// then a new value whenever it changes. Emits `null` when the key is absent
  /// or removed.
  ///
  /// {@macro native_datastore.getter}
  Stream<String?> watchString(String key) => _watch(key, () => getString(key));

  /// Watches the [bool] at [key]. See [watchString].
  Stream<bool?> watchBool(String key) => _watch(key, () => getBool(key));

  /// Watches the [int] at [key]. See [watchString].
  Stream<int?> watchInt(String key) => _watch(key, () => getInt(key));

  /// Watches the [double] at [key]. See [watchString].
  Stream<double?> watchDouble(String key) => _watch(key, () => getDouble(key));

  /// Watches the [List]<[String]> at [key]. See [watchString].
  Stream<List<String>?> watchStringList(String key) =>
      _watch(key, () => getStringList(key));

  /// Watches the [Uint8List] at [key]. See [watchString].
  Stream<Uint8List?> watchBytes(String key) => _watch(key, () => getBytes(key));

  /// Watches the [DateTime] at [key]. See [watchString].
  Stream<DateTime?> watchDateTime(String key) =>
      _watch(key, () => getDateTime(key));

  /// Watches the [Map] at [key]. See [watchString].
  Stream<Map<String, dynamic>?> watchMap(String key) =>
      _watch(key, () => getMap(key));

  /// Emits the list of user-facing keys that changed on every store mutation.
  /// Useful for observing the whole store rather than a single key.
  Stream<List<String>> watchChanges() => _changes;

  // ---- Migration ----

  /// Imports values previously written by the `shared_preferences` plugin into
  /// this data store, returning the number of keys imported.
  ///
  /// Scalar types (`String`, `bool`, `int`, `double`) and string lists are
  /// migrated. When [overwrite] is `false` (the default), keys already present
  /// here are left untouched. Safe to call on every launch — a second call
  /// with `overwrite: false` imports nothing new.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<int> migrateFromSharedPreferences({bool overwrite = false}) {
    return _guard(
      'migrateFromSharedPreferences',
      () => _api.migrateFromSharedPreferences(overwrite),
    );
  }

  // ---- Configuration ----

  /// Configures the storage backend. Call once at startup, before any read or
  /// write.
  ///
  /// * [multiProcess] (Android) opens the store in multi-process mode so it can
  ///   be safely accessed from more than one process. Ignored on iOS.
  /// * [appGroupId] (iOS) backs storage with the given App Group suite so app
  ///   extensions and other processes sharing the group observe the same data.
  ///   Ignored on Android.
  ///
  /// Both default off, leaving the standard single-process store in place.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<void> configure({bool multiProcess = false, String? appGroupId}) {
    return _guard('configure', () => _api.configure(multiProcess, appGroupId));
  }
}
