package `in`.sudhi.native_datastore

/**
 * The stable failure codes both hosts report.
 *
 * Pigeon's fallback wrapper uses the exception's Java class name as the code on
 * Android and the error's description string on iOS, so `PlatformException.code`
 * carried nothing an app could portably match on. Throwing [NativeDatastoreError]
 * with one of these instead gives the Dart side the same vocabulary on both
 * platforms. Keep in sync with `NativeDatastoreException`'s code constants in
 * `lib/src/errors.dart` and the Swift `Errors.swift`.
 */
internal object ErrorCode {
    /** The plugin is not attached to a Flutter engine. */
    const val DETACHED = "plugin-detached"

    /** The key that encrypted the stored secrets can no longer read them. */
    const val SECURE_KEY_UNAVAILABLE = "secure-key-unavailable"

    /** The operation needs a newer OS than this device runs. */
    const val UNSUPPORTED_PLATFORM_VERSION = "unsupported-platform-version"

    /** A value was passed that the store cannot represent. */
    const val UNSUPPORTED_TYPE = "unsupported-type"
}

/**
 * Maps an internal failure to the stable code vocabulary where one applies,
 * and otherwise leaves it alone for Pigeon's default wrapping.
 */
internal fun toPigeonError(e: Throwable): Throwable = when (e) {
    is NativeDatastoreError -> e
    is SecureKeyUnavailableException ->
        NativeDatastoreError(ErrorCode.SECURE_KEY_UNAVAILABLE, e.message, null)
    else -> e
}

/** The failure reported when a call arrives with no engine attached. */
internal fun detachedError(component: String): NativeDatastoreError = NativeDatastoreError(
    ErrorCode.DETACHED,
    "$component is not attached to a Flutter engine",
    null,
)
