package `in`.sudhi.native_datastore

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
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

    private fun getOrCreateKey(): SecretKey {
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

    private suspend fun writeEncrypted(prefKey: String, plaintext: ByteArray) {
        val encrypted = crypto.encrypt(plaintext)
        val encoded = Base64.encodeToString(encrypted, Base64.NO_WRAP)
        context.secureDataStore.edit { prefs ->
            prefs[stringPreferencesKey(prefKey)] = encoded
        }
    }

    private suspend fun readEncrypted(prefKey: String): ByteArray? {
        val prefs = context.secureDataStore.data.first()
        val encoded = prefs[stringPreferencesKey(prefKey)] ?: return null
        val encrypted = Base64.decode(encoded, Base64.NO_WRAP)
        return crypto.decrypt(encrypted)
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
            context.secureDataStore.edit { prefs ->
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
            context.secureDataStore.edit { it.clear() }
        }
    }

    override fun getKeys(callback: (Result<List<String>>) -> Unit) {
        launch(callback) {
            val prefs = context.secureDataStore.data.first()
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
            val prefs = context.secureDataStore.data.first()
            val candidates = TYPED_BUCKETS.map { it + key }.toSet()
            prefs.asMap().keys.any { it.name in candidates }
        }
    }
}
