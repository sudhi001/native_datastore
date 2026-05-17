package `in`.sudhi.native_datastore

import android.content.Context
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONArray

// Aggressive memory-management OEMs (MIUI, ColorOS, OriginOS, HyperOS, etc.)
// frequently kill processes mid-write, which can leave the prefs file
// half-written. Without a corruption handler, DataStore would throw
// CorruptionException on every subsequent call. The handler recovers by
// replacing the unreadable file with empty preferences so the app keeps
// working instead of being permanently broken.
//
// The receiver MUST stay `binding.applicationContext` — switching to an
// Activity context would leak the activity for the lifetime of the process.
private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(
    name = "native_datastore_prefs",
    corruptionHandler = ReplaceFileCorruptionHandler(
        produceNewData = { emptyPreferences() }
    )
)

class NativeDatastorePlugin : FlutterPlugin, DatastoreApi {

    companion object {
        // Per-type buckets sharing the flat DataStore key space. Keep these
        // in sync with the Dart `_BucketPrefix` and Swift `*Bucket` constants.
        private const val LIST_BUCKET = "__list__:"
        private const val BYTES_BUCKET = "__bytes__:"
        private const val DATETIME_BUCKET = "__datetime__:"
        private const val MAP_BUCKET = "__map__:"
        private val TYPED_BUCKETS =
            listOf(LIST_BUCKET, BYTES_BUCKET, DATETIME_BUCKET, MAP_BUCKET)
    }

    @Volatile
    private var context: Context? = null

    @Volatile
    private var scope: CoroutineScope? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
        DatastoreApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Cancel pending coroutines first so any in-flight work observes the
        // cancellation before we tear down the Pigeon channel they would reply on.
        scope?.cancel()
        DatastoreApi.setUp(binding.binaryMessenger, null)
        scope = null
        context = null
    }

    /**
     * Launches a coroutine on the plugin scope and guarantees `callback` is
     * invoked exactly once:
     *   - if the plugin is not attached, fails the callback immediately;
     *   - if `block` succeeds, succeeds the callback with its result;
     *   - if `block` throws a regular exception, fails the callback with it;
     *   - if `block` is cancelled (including before it runs), fails the
     *     callback with a detached-state error so the Dart-side Future never
     *     hangs in `BinaryMessenger`'s pending-replies map.
     */
    private fun <T> launchOnAttached(
        callback: (Result<T>) -> Unit,
        block: suspend (Context) -> T
    ) {
        val currentScope = scope
        val currentContext = context
        if (currentScope == null || currentContext == null) {
            callback(
                Result.failure(
                    IllegalStateException(
                        "NativeDatastorePlugin is not attached to a Flutter engine"
                    )
                )
            )
            return
        }
        val responded = AtomicBoolean(false)
        val job = currentScope.launch {
            try {
                val result = block(currentContext)
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
            // Without this, a cancellation that fires before `block` runs
            // (the scope-was-cancelled-between-capture-and-launch race) would
            // leave the Dart-side Completer hanging forever.
            if (cause is CancellationException &&
                responded.compareAndSet(false, true)
            ) {
                callback(
                    Result.failure(
                        IllegalStateException("NativeDatastorePlugin was detached")
                    )
                )
            }
        }
    }

    /**
     * Splits a stored key name into the user-facing key and the bucket prefix
     * it was stored under (or `null` for scalar storage).
     */
    private fun stripBucket(rawKey: String): Pair<String, String?> {
        for (bucket in TYPED_BUCKETS) {
            if (rawKey.startsWith(bucket)) {
                return rawKey.removePrefix(bucket) to bucket
            }
        }
        return rawKey to null
    }

    private fun bucketCandidates(key: String): Set<String> {
        val candidates = mutableSetOf(key)
        for (bucket in TYPED_BUCKETS) {
            candidates += bucket + key
        }
        return candidates
    }

    // ---------- Getters ----------

    override fun getString(key: String, callback: (Result<String?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[stringPreferencesKey(key)]
        }
    }

    override fun getBool(key: String, callback: (Result<Boolean?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[booleanPreferencesKey(key)]
        }
    }

    override fun getInt(key: String, callback: (Result<Long?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[longPreferencesKey(key)]
        }
    }

    override fun getDouble(key: String, callback: (Result<Double?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[doublePreferencesKey(key)]
        }
    }

    override fun getStringList(key: String, callback: (Result<List<String>?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            val json = prefs[stringPreferencesKey(LIST_BUCKET + key)]
            if (json == null) {
                null
            } else {
                val jsonArray = JSONArray(json)
                List(jsonArray.length()) { i -> jsonArray.getString(i) }
            }
        }
    }

    // ---------- Setters ----------

    override fun setString(key: String, value: String, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[stringPreferencesKey(key)] = value
            }
        }
    }

    override fun setBool(key: String, value: Boolean, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[booleanPreferencesKey(key)] = value
            }
        }
    }

    override fun setInt(key: String, value: Long, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[longPreferencesKey(key)] = value
            }
        }
    }

    override fun setDouble(key: String, value: Double, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[doublePreferencesKey(key)] = value
            }
        }
    }

    override fun setStringList(key: String, value: List<String>, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val jsonArray = JSONArray(value)
            ctx.dataStore.edit { prefs ->
                prefs[stringPreferencesKey(LIST_BUCKET + key)] = jsonArray.toString()
            }
        }
    }

    // ---------- Remove / Clear ----------

    override fun remove(key: String, callback: (Result<Boolean>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val candidates = bucketCandidates(key)
            var removed = false
            ctx.dataStore.edit { prefs ->
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
        launchOnAttached(callback) { ctx ->
            ctx.dataStore.edit { it.clear() }
        }
    }

    // ---------- Query ----------

    override fun getAll(callback: (Result<Map<String, Any>>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            val result = mutableMapOf<String, Any>()
            for ((prefKey, value) in prefs.asMap()) {
                val (realKey, bucket) = stripBucket(prefKey.name)
                when (bucket) {
                    LIST_BUCKET -> {
                        val jsonArray = JSONArray(value as String)
                        val list = List(jsonArray.length()) { i -> jsonArray.getString(i) }
                        result[realKey] = list
                    }
                    BYTES_BUCKET -> {
                        result[realKey] = Base64.decode(value as String, Base64.DEFAULT)
                    }
                    else -> {
                        result[realKey] = value
                    }
                }
            }
            result
        }
    }

    override fun getKeys(callback: (Result<List<String>>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs.asMap().keys.map { prefKey -> stripBucket(prefKey.name).first }.distinct()
        }
    }

    override fun containsKey(key: String, callback: (Result<Boolean>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            val candidates = bucketCandidates(key)
            prefs.asMap().keys.any { it.name in candidates }
        }
    }

    // ---------- Bytes (Uint8List) ----------

    override fun getBytes(key: String, callback: (Result<ByteArray?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            val encoded = prefs[stringPreferencesKey(BYTES_BUCKET + key)]
            if (encoded == null) null
            else Base64.decode(encoded, Base64.DEFAULT)
        }
    }

    override fun setBytes(key: String, value: ByteArray, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val encoded = Base64.encodeToString(value, Base64.DEFAULT)
            ctx.dataStore.edit { prefs ->
                prefs[stringPreferencesKey(BYTES_BUCKET + key)] = encoded
            }
        }
    }

    // ---------- DateTime (millis since epoch) ----------

    override fun getDateTime(key: String, callback: (Result<Long?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[longPreferencesKey(DATETIME_BUCKET + key)]
        }
    }

    override fun setDateTime(key: String, value: Long, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[longPreferencesKey(DATETIME_BUCKET + key)] = value
            }
        }
    }

    // ---------- JSON Map ----------

    override fun getMap(key: String, callback: (Result<String?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[stringPreferencesKey(MAP_BUCKET + key)]
        }
    }

    override fun setMap(key: String, value: String, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[stringPreferencesKey(MAP_BUCKET + key)] = value
            }
        }
    }
}
