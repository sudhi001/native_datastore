package `in`.sudhi.native_datastore

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.byteArrayPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.AEADBadTagException
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// Backing files for the encrypted stores, kept apart from the regular store so
// a `clear()` on one can never wipe the other.
internal const val SECURE_FILE_NAME = "native_datastore_secure.preferences_pb"
internal const val SECURE_MP_FILE_NAME = "native_datastore_secure_mp.json"

/**
 * Resolves an encrypted store's backing file under `noBackupFilesDir`, moving
 * the copy versions <= 1.7.1 kept in `filesDir` if one is still there.
 *
 * `filesDir` is included in Android Auto Backup and device-to-device transfer
 * by default. The AndroidKeyStore key that decrypts these bytes is not, and by
 * design cannot be — so a restored install received ciphertext it had no key
 * for, and every secure call failed for the life of that install.
 * `noBackupFilesDir` is excluded from both mechanisms, which is the only way
 * to keep the two halves of the secret together.
 *
 * Both files use their own serializer's format unchanged, so relocating is a
 * plain move. Called from `produceFile`, which DataStore invokes lazily on its
 * IO dispatcher.
 */
internal fun secureFile(context: Context, name: String): File {
    val target = File(context.noBackupFilesDir, "datastore/$name")
    if (target.exists()) return target
    target.parentFile?.mkdirs()
    val legacy = File(context.filesDir, "datastore/$name")
    if (legacy.exists()) {
        // Both directories live on the same filesystem, so the rename is
        // atomic; the copy is a fallback for the cases where it is not.
        if (!legacy.renameTo(target)) {
            legacy.copyTo(target, overwrite = true)
            legacy.delete()
        }
    }
    return target
}

/**
 * Process-wide single-process encrypted store.
 *
 * A `Context` property delegate cannot be used here because the backing file
 * lives outside `filesDir`. It has to be a singleton for the same reason
 * [MultiProcessStores] does: DataStore rejects a second instance over the same
 * file, and a second `FlutterEngine` constructs a second plugin.
 */
internal object SecureStores {
    @Volatile
    private var store: DataStore<Preferences>? = null

    fun single(context: Context): DataStore<Preferences> = store ?: synchronized(this) {
        store ?: PreferenceDataStoreFactory.create(
            corruptionHandler = ReplaceFileCorruptionHandler {
                emptyPreferences()
            },
            produceFile = { secureFile(context, SECURE_FILE_NAME) },
        ).also { store = it }
    }
}

// Leading byte of a blob written since 1.8.0. Older blobs are bare
// `iv + ciphertext` with no header, so the marker is a hint rather than a
// guarantee — a legacy IV starts with this value once every 256 writes, and the
// read path falls back accordingly. What makes the guess safe is that GCM
// authenticates: a misread framing fails the tag rather than returning garbage.
internal const val SECURE_FORMAT_AAD: Byte = 1
internal const val SECURE_IV_LENGTH_BYTES = 12

/**
 * Whether [blob] carries the versioned header, and so should be read as
 * AAD-bound ciphertext before the unversioned form is tried.
 */
internal fun isVersionedSecureBlob(blob: ByteArray): Boolean =
    blob.size > 1 + SECURE_IV_LENGTH_BYTES && blob[0] == SECURE_FORMAT_AAD

/**
 * Thrown when the AndroidKeyStore key that wrote the encrypted store can no
 * longer read it — the system invalidated it, or the ciphertext came from a
 * device the key was never minted on. Reaches Dart as a
 * `PlatformException` with code `SecureKeyUnavailableException`.
 *
 * Data written under the lost key is unrecoverable by construction. The plugin
 * heals itself on the next process start (see
 * [SecureDatastorePlugin.verifyKeyMatchesStore]); a caller seeing this should
 * treat its secrets as gone and re-authenticate.
 */
class SecureKeyUnavailableException(message: String, cause: Throwable?) :
    Exception(message, cause)

/**
 * Wraps a hardware-backed (where available) AES-256-GCM key in the
 * AndroidKeyStore and encrypts/decrypts byte payloads with a fresh 96-bit IV
 * per write. The IV is prepended to the ciphertext on storage so reads are
 * stateless. Requires Android API 23+.
 *
 * All API-23-only types are confined to this class, which is instantiated only
 * behind `requireApi23`, so the plugin class itself stays verifiable on 21/22.
 */
internal class SecureCrypto(private val keyAlias: String) {

    companion object {
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH_BYTES = SECURE_IV_LENGTH_BYTES
        private const val GCM_TAG_LENGTH_BITS = 128
        private const val AES_KEY_SIZE_BITS = 256
    }

    // `Cipher.getInstance` walks the JCA provider list on every call. The
    // instance is stateful, so it cannot be shared across threads — but the
    // plugin's coroutines run on Dispatchers.IO, a bounded pool, so a
    // ThreadLocal keeps the lookup to once per worker thread. Each use
    // re-`init`s, which resets any prior state.
    private val cipherCache = ThreadLocal<Cipher>()

    private fun cipher(): Cipher =
        cipherCache.get() ?: Cipher.getInstance(TRANSFORMATION).also { cipherCache.set(it) }

    /**
     * Encrypts [plaintext], binding the result to [aad] — the name of the entry
     * it will be stored under.
     *
     * Without that binding the GCM tag only proves a blob was written by this
     * key, not *where*. Anyone able to write the store file could move the blob
     * under `__str__:role_user` to `__str__:role_admin`, or restore an old
     * value under its own name, and every check would still pass.
     */
    fun encrypt(plaintext: ByteArray, aad: ByteArray): ByteArray = withKeyRetry {
        val cipher = cipher()
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        cipher.updateAAD(aad)
        val iv = cipher.iv
        check(iv.size == IV_LENGTH_BYTES) { "Unexpected IV length: ${iv.size}" }
        byteArrayOf(SECURE_FORMAT_AAD) + iv + cipher.doFinal(plaintext)
    }

    /**
     * Decrypts [encrypted], which may be in either the AAD-bound form written
     * since 1.8.0 or the bare `iv + ciphertext` form written before it.
     *
     * The header byte picks the first attempt; GCM authentication decides. A
     * pre-1.8.0 blob whose IV happens to start with the marker fails the bound
     * read and is retried unbound, so upgrades keep working without a rewrite.
     */
    fun decrypt(encrypted: ByteArray, aad: ByteArray): ByteArray {
        if (isVersionedSecureBlob(encrypted)) {
            runCatching { open(encrypted, offset = 1, aad = aad) }
                .getOrNull()
                ?.let { return it }
        }
        return open(encrypted, offset = 0, aad = null)
    }

    private fun open(encrypted: ByteArray, offset: Int, aad: ByteArray?): ByteArray {
        // Outside the retry: a truncated blob is a caller/storage problem, not
        // a key problem, and re-running would only throw the same thing.
        require(encrypted.size > offset + IV_LENGTH_BYTES) {
            "Ciphertext too short (${encrypted.size} bytes)"
        }
        val iv = encrypted.copyOfRange(offset, offset + IV_LENGTH_BYTES)
        val ciphertext = encrypted.copyOfRange(offset + IV_LENGTH_BYTES, encrypted.size)
        return withKeyRetry {
            val cipher = cipher()
            cipher.init(
                Cipher.DECRYPT_MODE,
                getOrCreateKey(),
                GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv),
            )
            aad?.let { cipher.updateAAD(it) }
            cipher.doFinal(ciphertext)
        }
    }

    /**
     * Runs a crypto operation, separating the three ways the key can fail.
     *
     * Only one of them is retryable. Retrying the other two used to hide the
     * real cause behind a second identical failure — and, when the alias was
     * missing, quietly minted a replacement key that could never read anything
     * already stored.
     */
    private fun <T> withKeyRetry(operation: () -> T): T = try {
        operation()
    } catch (e: KeyPermanentlyInvalidatedException) {
        // The system destroyed the key (lock-screen or biometric change).
        // Drop the alias so the next write mints a usable one instead of
        // failing forever, and tell the caller its secrets are gone.
        deleteKey()
        throw SecureKeyUnavailableException(
            "The AndroidKeyStore key was invalidated by the system. " +
                "Secrets written under it are unrecoverable — call " +
                "clear() and re-authenticate.",
            e,
        )
    } catch (e: AEADBadTagException) {
        // Wrong key or a modified blob. A retry resolves the same key and
        // fails identically, so this is terminal.
        throw SecureKeyUnavailableException(
            "Stored ciphertext failed authentication: it was written by a " +
                "different key (an install restored from another device, " +
                "for example) or has been modified.",
            e,
        )
    } catch (e: GeneralSecurityException) {
        // A stale cached handle is the one case a retry can fix.
        invalidateKey()
        operation()
    }

    // Loading the AndroidKeyStore is an IPC to the keystore daemon, and paying
    // it on every encrypt AND decrypt was the dominant cost of a secure read.
    // The key handle is immutable and thread-safe, so it is resolved once and
    // reused. `@Volatile` + double-checked locking keeps concurrent first calls
    // from each minting a key.
    @Volatile
    private var cachedKey: SecretKey? = null

    private fun getOrCreateKey(): SecretKey {
        cachedKey?.let { return it }
        return synchronized(this) {
            cachedKey ?: loadOrCreateKey().also { cachedKey = it }
        }
    }

    /** Drops the cached handle so the next call re-resolves it. */
    fun invalidateKey() {
        synchronized(this) { cachedKey = null }
    }

    /**
     * Removes the alias entirely so the next call mints a fresh, usable key.
     * Used when the existing key is known to be unusable — keeping it would
     * fail every subsequent call with no way back.
     */
    fun deleteKey() {
        synchronized(this) {
            cachedKey = null
            runCatching {
                KeyStore.getInstance(ANDROID_KEY_STORE)
                    .apply { load(null) }
                    .deleteEntry(keyAlias)
            }
        }
    }

    private fun loadOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }

        // StrongBox puts the key in a separate secure element rather than the
        // TEE. Support is per-device and `generateKey` is where an unsupported
        // device reports it, so the request is made and then retried without.
        return runCatching { generateKey(strongBox = true) }
            .getOrElse { generateKey(strongBox = false) }
    }

    private fun generateKey(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            keyAlias,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(AES_KEY_SIZE_BITS)
            .setRandomizedEncryptionRequired(true)
            .apply {
                if (strongBox && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    setIsStrongBoxBacked(true)
                }
            }
            .build()
        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
        keyGen.init(spec)
        return keyGen.generateKey()
    }
}

/**
 * Pigeon host implementation for `SecureDatastoreApi`. Constructed by
 * `NativeDatastorePlugin.onAttachedToEngine` with the engine's
 * application context and a shared coroutine scope so cancellation cascades
 * to both APIs on detach.
 */
internal class SecureDatastorePlugin(
    private val context: Context,
    private val scope: CoroutineScope,
) : SecureDatastoreApi {

    companion object {
        private const val KEY_ALIAS = "in.sudhi.native_datastore.secure"

        // Per-type buckets so `setString("token", …)` and `setBytes("token", …)`
        // live in distinct DataStore entries.
        private const val STRING_BUCKET = "__str__:"
        private const val BYTES_BUCKET = "__bytes__:"
        private val TYPED_BUCKETS = listOf(STRING_BUCKET, BYTES_BUCKET)

        // Key-fingerprint sentinel. Deliberately outside TYPED_BUCKETS so it
        // can never collide with a user key, and filtered out of `getKeys`.
        private const val KEY_CHECK_ENTRY = "__keycheck__"
        private val KEY_CHECK_PLAINTEXT = "native_datastore".toByteArray(Charsets.UTF_8)
        private val KEY_CHECK_AAD = KEY_CHECK_ENTRY.toByteArray(Charsets.UTF_8)
    }

    private val crypto: SecureCrypto by lazy { SecureCrypto(KEY_ALIAS) }

    // Set by `configure`; selects which backing store operations use.
    @Volatile
    private var multiProcessEnabled = false

    /**
     * Returns the active backing store: the default single-process encrypted
     * store, or — when [configure] enabled multi-process mode — a
     * multi-process store in a separate file. The AndroidKeyStore key is
     * process-agnostic, so only the DataStore file backing changes.
     */
    private fun secureStore(): DataStore<Preferences> {
        if (!multiProcessEnabled) return SecureStores.single(context)
        return MultiProcessStores.get(SECURE_MP_FILE_NAME) {
            secureFile(context, SECURE_MP_FILE_NAME)
        }
    }

    private fun requireApi23() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            throw NativeDatastoreError(
                ErrorCode.UNSUPPORTED_PLATFORM_VERSION,
                "SecureDatastore requires Android API 23 (Marshmallow) or higher",
                null,
            )
        }
    }

    /** Same shape as `NativeDatastorePlugin.launchOnAttached` — guarantees the
     *  callback fires exactly once even under cancellation races. */
    private fun <T> launch(callback: (Result<T>) -> Unit, block: suspend () -> T) {
        val responded = AtomicBoolean(false)
        val job = scope.launch {
            try {
                requireApi23()
                val result = block()
                if (responded.compareAndSet(false, true)) {
                    callback(Result.success(result))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (responded.compareAndSet(false, true)) {
                    callback(Result.failure(toPigeonError(e)))
                }
            }
        }
        job.invokeOnCompletion { cause ->
            if (cause is CancellationException &&
                responded.compareAndSet(false, true)
            ) {
                callback(Result.failure(detachedError("SecureDatastorePlugin")))
            }
        }
    }

    private val keyCheckMutex = Mutex()

    @Volatile
    private var keyChecked = false

    /**
     * Returns the active store, having confirmed once per process that the key
     * currently in the AndroidKeyStore is the one that wrote it.
     *
     * A store whose key is gone — an install restored from another device, or
     * a key the system invalidated — is unreadable by construction. Left
     * alone, it threw on every call for the life of the install with no way
     * back. Since the data cannot be recovered either way, the store is
     * emptied and re-stamped so the app simply sees absent keys and can
     * re-authenticate.
     */
    private suspend fun store(): DataStore<Preferences> {
        val store = secureStore()
        if (keyChecked) return store
        keyCheckMutex.withLock {
            if (!keyChecked) {
                verifyKeyMatchesStore(store)
                keyChecked = true
            }
        }
        return store
    }

    private suspend fun verifyKeyMatchesStore(store: DataStore<Preferences>) {
        val prefs = store.data.first()
        val sentinel = rawValue(prefs, KEY_CHECK_ENTRY) as? ByteArray
        if (sentinel != null) {
            val readable = runCatching { crypto.decrypt(sentinel, KEY_CHECK_AAD) }
                .getOrNull()
                ?.contentEquals(KEY_CHECK_PLAINTEXT) == true
            // The ordinary path, taken on every launch after the first: the
            // store is stamped and the key still reads it. Returning here is
            // what keeps this off the cold-start write path.
            if (readable) return
            crypto.deleteKey()
            store.edit { it.clear() }
        } else if (!probeExistingEntry(prefs)) {
            // No stamp yet — a store written before 1.8.0 — and the current key
            // cannot read what is in it. That is an install already broken by a
            // restore; the upgrade is the first chance to notice and recover.
            crypto.deleteKey()
            store.edit { it.clear() }
        }
        // Reached only when the store has no usable stamp: fresh, upgraded, or
        // just emptied above. Encrypting outside `edit` keeps the transaction to
        // the write itself.
        val stamp = crypto.encrypt(KEY_CHECK_PLAINTEXT, KEY_CHECK_AAD)
        store.edit { it[byteArrayPreferencesKey(KEY_CHECK_ENTRY)] = stamp }
    }

    /**
     * Returns whether the current key can read what is already stored. An
     * empty store is trivially usable; otherwise one entry is decrypted as a
     * representative — every entry shares the one key.
     */
    private fun probeExistingEntry(prefs: Preferences): Boolean {
        val entry = prefs.asMap().entries.firstOrNull { (key, _) ->
            TYPED_BUCKETS.any { key.name.startsWith(it) }
        } ?: return true
        val encrypted = when (val raw = entry.value) {
            is ByteArray -> raw
            is String -> Base64.decode(raw, Base64.NO_WRAP)
            else -> return true
        }
        return runCatching {
            crypto.decrypt(encrypted, entry.key.name.toByteArray(Charsets.UTF_8))
        }.isSuccess
    }

    /**
     * Reads the entry named [name] without a type cast, or `null` if absent.
     *
     * `Preferences.get` casts unchecked, so a legacy Base64 `String` would come
     * back typed as `ByteArray`. `asMap()` is keyed by `Preferences.Key`, whose
     * equality is by name alone, so a String-typed probe is an O(1) lookup of
     * whatever type actually sits under that name.
     */
    private fun rawValue(prefs: Preferences, name: String): Any? =
        prefs.asMap()[stringPreferencesKey(name)]

    private suspend fun writeEncrypted(prefKey: String, plaintext: ByteArray) {
        // Resolve the store first: that is what runs the key check, and a lost
        // key has to be replaced before `encrypt` would fail on it.
        val store = store()
        val encrypted = crypto.encrypt(plaintext, prefKey.toByteArray(Charsets.UTF_8))
        store.edit { prefs ->
            // Ciphertext is stored as a native ByteArray rather than Base64.
            // `Preferences.Key` equality is by name, so this also replaces any
            // legacy Base64 String written under the same name.
            prefs[byteArrayPreferencesKey(prefKey)] = encrypted
        }
    }

    private suspend fun readEncrypted(prefKey: String): ByteArray? {
        val prefs = store().data.first()
        val encrypted = when (val raw = rawValue(prefs, prefKey)) {
            is ByteArray -> raw
            // Legacy Base64 form written by versions <= 1.6.2.
            is String -> Base64.decode(raw, Base64.NO_WRAP)
            else -> return null
        }
        return crypto.decrypt(encrypted, prefKey.toByteArray(Charsets.UTF_8))
    }

    // ---------- String ----------

    override fun getString(key: String, callback: (Result<String?>) -> Unit) {
        launch(callback) {
            val plaintext = readEncrypted(STRING_BUCKET + key) ?: return@launch null
            String(plaintext, Charsets.UTF_8)
        }
    }

    override fun setString(key: String, value: String, callback: (Result<Unit>) -> Unit) {
        launch(callback) {
            writeEncrypted(STRING_BUCKET + key, value.toByteArray(Charsets.UTF_8))
        }
    }

    // ---------- Bytes ----------

    override fun getBytes(key: String, callback: (Result<ByteArray?>) -> Unit) {
        launch(callback) {
            readEncrypted(BYTES_BUCKET + key)
        }
    }

    override fun setBytes(key: String, value: ByteArray, callback: (Result<Unit>) -> Unit) {
        launch(callback) {
            writeEncrypted(BYTES_BUCKET + key, value)
        }
    }

    // ---------- Lifecycle / introspection ----------

    override fun remove(key: String, callback: (Result<Boolean>) -> Unit) {
        launch(callback) {
            var removed = false
            store().edit { prefs ->
                // A String-typed probe matches whatever type is stored under
                // that name, so removal is an O(1) lookup per bucket.
                for (bucket in TYPED_BUCKETS) {
                    val probe = stringPreferencesKey(bucket + key)
                    if (prefs.contains(probe)) {
                        prefs.remove(probe)
                        removed = true
                    }
                }
            }
            removed
        }
    }

    override fun clear(callback: (Result<Unit>) -> Unit) {
        launch(callback) {
            store().edit { it.clear() }
        }
    }

    override fun getKeys(callback: (Result<List<String>>) -> Unit) {
        launch(callback) {
            val prefs = store().data.first()
            prefs.asMap().keys
                .map { it.name }
                .filter { it != KEY_CHECK_ENTRY }
                .map { name ->
                    TYPED_BUCKETS.firstOrNull { name.startsWith(it) }
                        ?.let { name.removePrefix(it) }
                        ?: name
                }
                .distinct()
        }
    }

    override fun containsKey(key: String, callback: (Result<Boolean>) -> Unit) {
        launch(callback) {
            val prefs = store().data.first()
            TYPED_BUCKETS.any { rawValue(prefs, it + key) != null }
        }
    }

    // ---------- Configuration ----------

    override fun configure(
        multiProcess: Boolean,
        appGroupId: String?,
        callback: (Result<Unit>) -> Unit,
    ) {
        // appGroupId is used as an iOS Keychain access group; ignored on Android.
        launch(callback) {
            multiProcessEnabled = multiProcess
            // The check is per store, and this just swapped which one is live.
            keyChecked = false
        }
    }
}
