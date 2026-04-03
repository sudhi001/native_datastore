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
      errorClassName: 'DatastoreError',
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
  bool clear();

  @async
  Map<String, Object> getAll();

  @async
  List<String> getKeys();

  @async
  bool containsKey(String key);
}
