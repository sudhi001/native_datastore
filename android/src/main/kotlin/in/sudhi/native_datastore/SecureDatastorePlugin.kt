package `in`.sudhi.native_datastore

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.core.MultiProcessDataStoreFactory
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.byteArrayPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.preferencesDataStore
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.util.concurrent.atomic.AtomicBoolean
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

// Dedicated DataStore file for encrypted values so a `clear()` on the regular
// store can never wipe secrets and vice versa.
private val Context.secureDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "native_datastore_secure",
    corruptionHandler = ReplaceFileCorruptionHandler(
        produceNewData = { emptyPreferences() }
    )
)

/**
 * Wraps a hardware-backed (where available) AES-256-GCM key in the
 * AndroidKeyStore and encrypts/decrypts byte payloads with a fresh 96-bit IV
 * per write. The IV is prepended to the ciphertext on storage so reads are
 * stateless. Requires Android API 23+.
 */
internal class SecureCrypto(private val keyAlias: String) {

    companion object {
        private const val ANDROID_KEY_STORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_LENGTH_BYTES = 12
        private const val GCM_TAG_LENGTH_BITS = 128
        private const val AES_KEY_SIZE_BITS = 256
    }

    fun encrypt(plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, getOrCreateKey())
        val iv = cipher.iv
        check(iv.size == IV_LENGTH_BYTES) { "Unexpected IV length: ${iv.size}" }
        val ciphertext = cipher.doFinal(plaintext)
        return iv + ciphertext
    }

    fun decrypt(encrypted: ByteArray): ByteArray {
        require(encrypted.size > IV_LENGTH_BYTES) {
            "Ciphertext too short (${encrypted.size} bytes)"
        }
        val iv = encrypted.copyOfRange(0, IV_LENGTH_BYTES)
        val ciphertext = encrypted.copyOfRange(IV_LENGTH_BYTES, encrypted.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            getOrCreateKey(),
            GCMParameterSpec(GCM_TAG_LENGTH_BITS, iv)
        )
        return cipher.doFinal(ciphertext)
    }

    // Loading the AndroidKeyStore is an IPC to the keystore daemon, and the
    // previous code paid it on every encrypt AND decrypt — the dominant cost of
    // a secure read. The key handle itself is immutable and thread-safe, so it
    // is resolved once and reused. `@Volatile` + double-checked locking keeps
    // concurrent first calls from each minting a key.
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

    private fun loadOrCreateKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEY_STORE).apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }

        val keyGen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEY_STORE)
        keyGen.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(AES_KEY_SIZE_BITS)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
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
    }

    private val crypto: SecureCrypto by lazy { SecureCrypto(KEY_ALIAS) }

    // Set by `configure`; selects which backing store operations use.
    @Volatile
    private var multiProcessEnabled = false

    // Lazily-created multi-process store, kept in its own file so enabling
    // multi-process mode never touches the default single-process secrets.
    @Volatile
    private var mpStore: DataStore<Preferences>? = null

    /**
     * Returns the active backing store: the default single-process encrypted
     * DataStore, or — when [configure] enabled multi-process mode — a
     * [MultiProcessDataStoreFactory] store in a separate file. The AndroidKeyStore
     * key is process-agnostic, so only the DataStore file backing changes.
     */
    private fun secureStore(): DataStore<Preferences> {
        if (!multiProcessEnabled) return context.secureDataStore
        return mpStore ?: synchronized(this) {
            mpStore ?: MultiProcessDataStoreFactory.create(
                serializer = PreferencesJsonSerializer,
                corruptionHandler = ReplaceFileCorruptionHandler {
                    emptyPreferences()
                },
                produceFile = {
                    File(context.filesDir, "datastore/native_datastore_secure_mp.json")
                }
            ).also { mpStore = it }
        }
    }

    private fun requireApi23() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            throw UnsupportedOperationException(
                "SecureDatastore requires Android API 23 (Marshmallow) or higher"
            )
        }
    }

    /** Same shape as `NativeDatastorePlugin.launchOnAttached` — guarantees the
     *  callback fires exactly once even under cancellation races. */
    private fun <T> launch(
        callback: (Result<T>) -> Unit,
        block: suspend () -> T
    ) {
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
                    callback(Result.failure(e))
                }
            }
        }
        job.invokeOnCompletion { cause ->
            if (cause is CancellationException &&
                responded.compareAndSet(false, true)
            ) {
                callback(
                    Result.failure(
                        IllegalStateException("SecureDatastorePlugin was detached")
                    )
                )
            }
        }
    }

    /**
     * Runs a crypto operation, dropping the cached key handle and retrying once
     * if the KeyStore reports it unusable. The handle is cached for the process
     * lifetime, so without this a key invalidated out from under us (device
     * lock-setting change, restored backup) would fail every subsequent call.
     */
    private fun <T> withKeyRetry(operation: () -> T): T {
        return try {
            operation()
        } catch (e: GeneralSecurityException) {
            crypto.invalidateKey()
            operation()
        }
    }

    private suspend fun writeEncrypted(prefKey: String, plaintext: ByteArray) {
        val encrypted = withKeyRetry { crypto.encrypt(plaintext) }
        secureStore().edit { prefs ->
            // Ciphertext is stored as a native ByteArray rather than Base64.
            // `Preferences.Key` equality is by name, so this also replaces any
            // legacy Base64 String written under the same name.
            prefs[byteArrayPreferencesKey(prefKey)] = encrypted
        }
    }

    private suspend fun readEncrypted(prefKey: String): ByteArray? {
        val prefs = secureStore().data.first()
        // Branch on the runtime type: `Preferences.get` casts unchecked, so a
        // legacy Base64 String would otherwise come back typed as ByteArray.
        val raw = prefs.asMap().entries.firstOrNull { it.key.name == prefKey }?.value
        val encrypted = when (raw) {
            is ByteArray -> raw
            is String -> Base64.decode(raw, Base64.NO_WRAP)
            else -> return null
        }
        return withKeyRetry { crypto.decrypt(encrypted) }
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
            val candidates = TYPED_BUCKETS.map { it + key }.toSet()
            var removed = false
            secureStore().edit { prefs ->
                val matching = prefs.asMap().keys.filter { it.name in candidates }
                for (prefKey in matching) {
                    @Suppress("UNCHECKED_CAST")
                    prefs.remove(prefKey as Preferences.Key<Any>)
                    removed = true
                }
            }
            removed
        }
    }

    override fun clear(callback: (Result<Unit>) -> Unit) {
        launch(callback) {
            secureStore().edit { it.clear() }
        }
    }

    override fun getKeys(callback: (Result<List<String>>) -> Unit) {
        launch(callback) {
            val prefs = secureStore().data.first()
            prefs.asMap().keys
                .map { prefKey ->
                    var realKey = prefKey.name
                    for (bucket in TYPED_BUCKETS) {
                        if (prefKey.name.startsWith(bucket)) {
                            realKey = prefKey.name.removePrefix(bucket)
                            break
                        }
                    }
                    realKey
                }
                .distinct()
        }
    }

    override fun containsKey(key: String, callback: (Result<Boolean>) -> Unit) {
        launch(callback) {
            val prefs = secureStore().data.first()
            val candidates = TYPED_BUCKETS.map { it + key }.toSet()
            prefs.asMap().keys.any { it.name in candidates }
        }
    }

    // ---------- Configuration ----------

    override fun configure(
        multiProcess: Boolean,
        appGroupId: String?,
        callback: (Result<Unit>) -> Unit
    ) {
        // appGroupId is used as an iOS Keychain access group; ignored on Android.
        launch(callback) {
            multiProcessEnabled = multiProcess
        }
    }
}
