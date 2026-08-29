import 'package:flutter/services.dart';

// Imported for the [NativeDatastore] doc reference below.
import 'native_datastore_plugin.dart';

/// Exception thrown when a [NativeDatastore] operation fails.
///
/// Wraps platform-specific errors with a human-readable [message], a stable
/// [code] where the platform reported one, and the original [cause].
class NativeDatastoreException implements Exception {
  /// Creates a [NativeDatastoreException].
  const NativeDatastoreException(this.message, {this.cause, this.code});

  /// A human-readable description of what went wrong.
  final String message;

  /// The underlying platform exception, if any.
  final Object? cause;

  /// A stable identifier for the failure, or `null` when the failure was
  /// raised in Dart or the platform reported no code.
  ///
  /// The two hosts deliberately use the same vocabulary, so a `switch` on this
  /// behaves the same on Android and iOS:
  ///
  /// | Code | Meaning |
  /// |------|---------|
  /// | [detachedCode] | The plugin is not attached to a Flutter engine. Retry after the engine is running. |
  /// | [secureKeyUnavailableCode] | The key that encrypted the stored secrets can no longer read them — the system invalidated it, or the data was restored from another device. The secure store clears itself on the next launch; treat the secrets as lost and re-authenticate. |
  /// | [unsupportedPlatformVersionCode] | The operation needs a newer OS than this device runs. `SecureDatastore` needs Android 6.0 (API 23). |
  /// | [unsupportedTypeCode] | A value was passed that the store cannot represent. |
  /// | [keychainCode] | An iOS Keychain call failed; [message] carries the `OSStatus`. |
  /// | [encodingCode] | A string could not be encoded as UTF-8. |
  ///
  /// Anything else comes straight from the platform and is not part of the
  /// plugin's contract — match on it only for logging.
  final String? code;

  /// See [code].
  static const String detachedCode = 'plugin-detached';

  /// See [code].
  static const String secureKeyUnavailableCode = 'secure-key-unavailable';

  /// See [code].
  static const String unsupportedPlatformVersionCode =
      'unsupported-platform-version';

  /// See [code].
  static const String unsupportedTypeCode = 'unsupported-type';

  /// See [code].
  static const String keychainCode = 'keychain-error';

  /// See [code].
  static const String encodingCode = 'encoding-error';

  @override
  String toString() {
    final label = code == null ? '' : ' [$code]';
    if (cause != null) {
      return 'NativeDatastoreException$label: $message (cause: $cause)';
    }
    return 'NativeDatastoreException$label: $message';
  }
}

/// Rejects a key the store cannot represent, before any platform call.
///
/// An empty key is meaningless, and a key that starts with one of
/// [reservedPrefixes] would land in a namespace the plugin uses to keep typed
/// values from colliding — it would read back as somebody else's value.
///
/// Throws synchronously rather than returning a failed future: this is a
/// programming error, not a storage failure.
void validateKey(String key, List<String> reservedPrefixes) {
  if (key.isEmpty) {
    throw const NativeDatastoreException('Key must not be empty');
  }
  for (final prefix in reservedPrefixes) {
    if (key.startsWith(prefix)) {
      throw NativeDatastoreException(
        'Key must not start with reserved prefix "$prefix"',
      );
    }
  }
}

/// Runs [action], translating whatever the platform throws into a
/// [NativeDatastoreException] that names the [operation] that failed.
///
/// `Error.throwWithStackTrace` rather than a plain `throw`: the platform call's
/// own stack is the only record of which call site failed, and rethrowing
/// normally replaced it with this frame.
Future<T> guard<T>(String operation, Future<T> Function() action) async {
  try {
    return await action();
  } on NativeDatastoreException {
    rethrow;
  } on PlatformException catch (e, stackTrace) {
    Error.throwWithStackTrace(
      NativeDatastoreException(
        'Failed to $operation: ${e.message ?? e.code}',
        cause: e,
        code: e.code,
      ),
      stackTrace,
    );
  } catch (e, stackTrace) {
    Error.throwWithStackTrace(
      NativeDatastoreException('Failed to $operation: $e', cause: e),
      stackTrace,
    );
  }
}
