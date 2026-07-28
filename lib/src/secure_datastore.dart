import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'messages.g.dart';
import 'native_datastore_plugin.dart';

/// Internal namespace markers used by the native side to distinguish strings
/// from bytes. Keep in sync with the Swift `KeychainStore.*Bucket` constants
/// and the Kotlin `SecureDatastorePlugin.*_BUCKET` constants.
class _SecureBucket {
  static const String string = '__str__:';
  static const String bytes = '__bytes__:';
  static const List<String> all = <String>[string, bytes];
}

const int _maxSecureBlobBytes = 1024 * 1024;

/// Persistent key-value storage that encrypts data at rest using platform key
/// management.
///
/// On iOS the values are stored as Keychain items (`kSecClassGenericPassword`)
/// with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — readable after
/// the user unlocks the device once per boot, including from background work,
/// and never migrated to a new device.
///
/// On Android each value is encrypted with AES-256-GCM using a key minted in
/// the AndroidKeyStore (hardware-backed where available), then stored in a
/// dedicated DataStore file. Requires Android API 23 (Marshmallow) or higher.
///
/// Use this for secrets — auth tokens, refresh tokens, encryption keys.
/// For non-sensitive preferences use [NativeDatastore], which is faster and
/// has a richer typed API.
///
/// {@tool snippet}
/// ```dart
/// final secure = SecureDatastore();
///
/// await secure.setString('refresh_token', tokenJwt);
/// final token = await secure.getString('refresh_token');
/// ```
/// {@end-tool}
class SecureDatastore {
  /// Creates a [SecureDatastore] that communicates with the platform-specific
  /// implementation via Pigeon.
  SecureDatastore() : _api = SecureDatastoreApi();

  /// Creates a [SecureDatastore] backed by the given [api]. For unit testing.
  @visibleForTesting
  SecureDatastore.withApi(SecureDatastoreApi api) : _api = api;

  final SecureDatastoreApi _api;

  static void _validateKey(String key) {
    if (key.isEmpty) {
      throw const NativeDatastoreException('Key must not be empty');
    }
    for (final prefix in _SecureBucket.all) {
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

  /// Reads a [String] value previously written with [setString].
  ///
  /// Returns `null` if [key] does not exist (or was last written as bytes).
  ///
  /// Throws [NativeDatastoreException] if [key] is empty, starts with a
  /// reserved prefix, or the platform call fails (e.g., Android < 23,
  /// Keychain access denied while the device is locked).
  Future<String?> getString(String key) {
    _validateKey(key);
    return _guard('secure getString("$key")', () => _api.getString(key));
  }

  /// Writes a [String] [value] to secure storage under [key].
  ///
  /// Throws [NativeDatastoreException] if [key] is empty, [value] is larger
  /// than 1 MiB, or the platform call fails.
  Future<void> setString(String key, String value) {
    _validateKey(key);
    if (value.length > _maxSecureBlobBytes) {
      throw NativeDatastoreException(
        'secure setString value too large: ${value.length} bytes '
        '(max $_maxSecureBlobBytes)',
      );
    }
    return _guard(
      'secure setString("$key")',
      () => _api.setString(key, value),
    );
  }

  /// Reads a [Uint8List] previously written with [setBytes].
  ///
  /// Returns `null` if [key] does not exist (or was last written as string).
  ///
  /// Throws [NativeDatastoreException] if [key] is empty, starts with a
  /// reserved prefix, or the platform call fails.
  Future<Uint8List?> getBytes(String key) {
    _validateKey(key);
    return _guard('secure getBytes("$key")', () => _api.getBytes(key));
  }

  /// Writes a [Uint8List] [value] to secure storage under [key].
  ///
  /// Throws [NativeDatastoreException] if [key] is empty, [value] exceeds
  /// 1 MiB, or the platform call fails.
  Future<void> setBytes(String key, Uint8List value) {
    _validateKey(key);
    if (value.lengthInBytes > _maxSecureBlobBytes) {
      throw NativeDatastoreException(
        'secure setBytes value too large: ${value.lengthInBytes} bytes '
        '(max $_maxSecureBlobBytes)',
      );
    }
    return _guard(
      'secure setBytes("$key")',
      () => _api.setBytes(key, value),
    );
  }

  /// Removes every value previously stored under [key]. Returns `true` if
  /// anything was removed.
  ///
  /// Throws [NativeDatastoreException] if [key] is empty or the platform call
  /// fails.
  Future<bool> remove(String key) {
    _validateKey(key);
    return _guard('secure remove("$key")', () => _api.remove(key));
  }

  /// Removes every value in the secure store. Does *not* delete the
  /// platform-managed encryption key.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<void> clear() {
    return _guard('secure clear', _api.clear);
  }

  /// Returns the user-facing keys currently stored. A key written as both a
  /// string and bytes is reported once.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<List<String>> getKeys() {
    return _guard('secure getKeys', _api.getKeys);
  }

  /// Returns `true` if anything is stored under [key].
  ///
  /// Throws [NativeDatastoreException] if [key] is empty or the platform call
  /// fails.
  Future<bool> containsKey(String key) {
    _validateKey(key);
    return _guard('secure containsKey("$key")', () => _api.containsKey(key));
  }

  /// Configures the secure storage backend for cross-process access. Call once
  /// at startup, before any read or write.
  ///
  /// * [multiProcess] (Android) opens the encrypted store in multi-process mode
  ///   so it can be safely accessed from more than one process. Because it uses
  ///   a separate file, existing secrets in the default store are *not* visible
  ///   through it. Ignored on iOS.
  /// * [appGroupId] (iOS) is used as the Keychain access group so app extensions
  ///   and other processes sharing the group can read the same secrets. Requires
  ///   the "Keychain Sharing" capability enabled in Xcode; note this is a
  ///   Keychain access group string, which differs from the App Group suite used
  ///   by [NativeDatastore]. Ignored on Android.
  ///
  /// Both default off, leaving the standard single-process store in place.
  ///
  /// Throws [NativeDatastoreException] if the platform call fails.
  Future<void> configure({bool multiProcess = false, String? appGroupId}) {
    return _guard(
      'secure configure',
      () => _api.configure(multiProcess, appGroupId),
    );
  }
}
