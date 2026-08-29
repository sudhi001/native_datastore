import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    input: 'pigeons/messages.dart',
    dartOut: 'lib/src/messages.g.dart',
    dartPackageName: 'native_datastore',
    kotlinOut:
        'android/src/main/kotlin/in/sudhi/native_datastore/Messages.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'in.sudhi.native_datastore',
      errorClassName: 'NativeDatastoreError',
    ),
    swiftOut: 'ios/native_datastore/Sources/native_datastore/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'NativeDatastoreError'),
  ),
)
@HostApi()
abstract class DatastoreApi {
  @async
  String? getString(String key);

  @async
  bool? getBool(String key);

  @async
  int? getInt(String key);

  @async
  double? getDouble(String key);

  @async
  List<String>? getStringList(String key);

  @async
  void setString(String key, String value);

  @async
  void setBool(String key, bool value);

  @async
  void setInt(String key, int value);

  @async
  void setDouble(String key, double value);

  @async
  void setStringList(String key, List<String> value);

  @async
  bool remove(String key);

  @async
  void clear();

  @async
  Map<String, Object> getAll();

  @async
  List<String> getKeys();

  @async
  bool containsKey(String key);

  @async
  Uint8List? getBytes(String key);

  @async
  void setBytes(String key, Uint8List value);

  @async
  int? getDateTime(String key);

  @async
  void setDateTime(String key, int value);

  @async
  String? getMap(String key);

  @async
  void setMap(String key, String value);

  // ---- Batch ----
  // One platform round trip for many keys. Reading N keys individually costs N
  // channel hops and N full-snapshot materialisations; writing N keys
  // individually costs N whole-file rewrites on Android. These collapse both.

  /// Reads [keys] in a single call. Absent keys are omitted from the result,
  /// so the caller can distinguish "missing" from "stored null".
  @async
  Map<String, Object> getMany(List<String> keys);

  /// Writes every entry of [entries] in a single native transaction. Values
  /// must be String, bool, int, double, Uint8List, or a List whose elements are
  /// all String. DateTime and Map are excluded: their wire forms are an int and
  /// a String, so the host cannot tell which namespace to write them to.
  @async
  void setMany(Map<String, Object> entries);

  /// Removes [keys] in a single native transaction, returning how many were
  /// actually present.
  @async
  int removeMany(List<String> keys);

  // ---- Atomic read-modify-write ----
  // Each runs as a single native transaction (DataStore `updateData` on
  // Android, the serial queue on iOS), so concurrent callers never race on a
  // read-then-write across the platform boundary.

  /// Atomically adds [delta] to the int at [key] (treating a missing value as
  /// 0) and returns the new value.
  @async
  int incrementInt(String key, int delta);

  /// Atomically adds [delta] to the double at [key] (treating a missing value
  /// as 0.0) and returns the new value.
  @async
  double incrementDouble(String key, double delta);

  /// Atomically flips the bool at [key] (treating a missing value as false)
  /// and returns the new value.
  @async
  bool toggleBool(String key);

  /// Atomically sets [key] to [value] only if its current value equals
  /// [expected] (a null [expected] means "only if absent", a null [value]
  /// means "remove"). Returns true if the swap happened.
  @async
  bool compareAndSetString(String key, String? expected, String? value);

  @async
  bool compareAndSetInt(String key, int? expected, int? value);

  @async
  bool compareAndSetDouble(String key, double? expected, double? value);

  @async
  bool compareAndSetBool(String key, bool? expected, bool? value);

  // ---- Migration ----

  /// Copies existing values written by the `shared_preferences` plugin into
  /// this store. When [overwrite] is false, keys already present here are
  /// left untouched. Returns the number of keys imported.
  @async
  int migrateFromSharedPreferences(bool overwrite);

  // ---- Configuration ----

  /// Configures the storage backend. Must be called before the first read or
  /// write. When [multiProcess] is true (Android) the store is opened in
  /// multi-process mode; [appGroupId], when non-null (iOS), backs storage with
  /// an App Group suite so extensions/processes sharing the group see the same
  /// data. Both default off, leaving the single-process store untouched.
  @async
  void configure(bool multiProcess, String? appGroupId);
}

/// Secure-storage host API. Implementations encrypt data at rest using
/// platform key management (Keychain on iOS, AndroidKeyStore-backed AES-GCM
/// over DataStore on Android). Only string and bytes are supported — callers
/// that need richer types should serialize first.
@HostApi()
abstract class SecureDatastoreApi {
  @async
  String? getString(String key);

  @async
  void setString(String key, String value);

  @async
  Uint8List? getBytes(String key);

  @async
  void setBytes(String key, Uint8List value);

  @async
  bool remove(String key);

  @async
  void clear();

  @async
  List<String> getKeys();

  @async
  bool containsKey(String key);

  // ---- Configuration ----

  /// Configures the secure storage backend. Must be called before the first
  /// read or write. When [multiProcess] is true (Android) the encrypted store
  /// is opened in multi-process mode; [appGroupId], when non-null (iOS), is
  /// used as the Keychain access group so extensions/processes sharing it see
  /// the same secrets. Both default off, leaving the single-process store
  /// untouched.
  @async
  void configure(bool multiProcess, String? appGroupId);
}
