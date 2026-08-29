import Foundation

/// The stable failure codes both hosts report.
///
/// Pigeon's fallback wrapper uses the error's description string as the code on
/// iOS and the exception's Java class name on Android, so `PlatformException.code`
/// carried nothing an app could portably match on. Throwing `NativeDatastoreError`
/// with one of these instead gives the Dart side the same vocabulary on both
/// platforms. Keep in sync with `NativeDatastoreException`'s code constants in
/// `lib/src/errors.dart` and the Kotlin `Errors.kt`.
enum ErrorCode {
  /// The plugin is not attached to a Flutter engine.
  static let detached = "plugin-detached"

  /// A value was passed that the store cannot represent.
  static let unsupportedType = "unsupported-type"

  /// A Keychain call failed; the message carries the `OSStatus`.
  static let keychain = "keychain-error"

  /// A string could not be encoded as UTF-8.
  static let encoding = "encoding-error"
}
