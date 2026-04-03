/// A modern Flutter plugin for persistent key-value storage.
///
/// Uses [Jetpack DataStore](https://developer.android.com/topic/libraries/architecture/datastore)
/// on Android and [UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)
/// on iOS. Provides a familiar async API similar to `shared_preferences`,
/// backed by modern platform-native storage solutions.
///
/// ## Quick Start
///
/// ```dart
/// import 'package:native_datastore/native_datastore.dart';
///
/// final datastore = NativeDatastore();
///
/// // Write
/// await datastore.setString('username', 'sudhi');
///
/// // Read
/// final username = await datastore.getString('username');
///
/// // Delete
/// await datastore.remove('username');
/// ```
library;

export 'src/native_datastore_plugin.dart';
