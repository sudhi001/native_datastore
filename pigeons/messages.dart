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
    swiftOut: 'ios/Classes/Messages.g.swift',
    swiftOptions: SwiftOptions(
      errorClassName: 'NativeDatastoreError',
    ),
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
}
