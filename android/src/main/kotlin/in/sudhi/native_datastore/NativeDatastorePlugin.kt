package `in`.sudhi.native_datastore

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Base64
import androidx.datastore.core.DataStore
import androidx.datastore.core.MultiProcessDataStoreFactory
import androidx.datastore.core.Serializer
import androidx.datastore.core.handlers.ReplaceFileCorruptionHandler
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.byteArrayPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONArray
import org.json.JSONObject

// Serializes a Preferences snapshot to type-tagged JSON so it can back a
// MultiProcessDataStore. The plugin stores String, Boolean, Long, Double and —
// since 1.7.0, for byte payloads — ByteArray preference values (lists/dates/maps
// live in String or Long buckets), so those five types cover everything.
internal object PreferencesJsonSerializer : Serializer<Preferences> {
    override val defaultValue: Preferences = emptyPreferences()

    override suspend fun readFrom(input: InputStream): Preferences {
        val text = input.readBytes().decodeToString()
        if (text.isEmpty()) return emptyPreferences()
        val obj = JSONObject(text)
        val prefs = mutablePreferencesOf()
        for (name in obj.keys()) {
            val entry = obj.getJSONObject(name)
            when (entry.getString("t")) {
                "s" -> prefs[stringPreferencesKey(name)] = entry.getString("v")
                "b" -> prefs[booleanPreferencesKey(name)] = entry.getBoolean("v")
                "l" -> prefs[longPreferencesKey(name)] = entry.getLong("v")
                "d" -> prefs[doublePreferencesKey(name)] = entry.getDouble("v")
                // Byte payloads must still be Base64 here: this store is a JSON
                // file, so there is no native binary slot to use.
                "ba" -> prefs[byteArrayPreferencesKey(name)] =
                    Base64.decode(entry.getString("v"), Base64.DEFAULT)
            }
        }
        return prefs
    }

    override suspend fun writeTo(t: Preferences, output: OutputStream) {
        val obj = JSONObject()
        for ((key, value) in t.asMap()) {
            val entry = JSONObject()
            when (value) {
                is String -> entry.put("t", "s").put("v", value)
                is Boolean -> entry.put("t", "b").put("v", value)
                is Long -> entry.put("t", "l").put("v", value)
                is Double -> entry.put("t", "d").put("v", value)
                is ByteArray ->
                    entry.put("t", "ba")
                        .put("v", Base64.encodeToString(value, Base64.NO_WRAP))
                else -> continue
            }
            obj.put(key.name, entry)
        }
        output.write(obj.toString().encodeToByteArray())
    }
}

// Event channel that streams the list of user-facing keys changed on each
// store mutation. Hand-written (Pigeon models request/response, not streams).
private const val CHANGES_CHANNEL = "in.sudhi.native_datastore/changes"

// Bucket prefixes duplicated for the top-level change-stream helper so it can
// map raw stored keys back to user-facing keys. Keep in sync with the
// companion constants of NativeDatastorePlugin.
private val CHANGE_STREAM_BUCKETS =
    listOf("__list__:", "__bytes__:", "__datetime__:", "__map__:")

private fun toUserFacingKey(rawKey: String): String {
    for (bucket in CHANGE_STREAM_BUCKETS) {
        if (rawKey.startsWith(bucket)) return rawKey.removePrefix(bucket)
    }
    return rawKey
}

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

        // shared_preferences tags list- and BigInteger-encoded strings with
        // these base64 markers ("This is the prefix for a list." etc.).
        // Importing such a value as a plain string would corrupt it.
        private const val SP_LIST_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBhIGxpc3Qu"
        private const val SP_BIGINT_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBCaWdJbnRlZ2Vy"
    }

    // Set by `configure`; selects which backing store operations use.
    @Volatile
    private var multiProcessEnabled = false

    // Lazily-created multi-process store, kept in its own file so enabling
    // multi-process mode never touches the default single-process data.
    @Volatile
    private var mpStore: DataStore<Preferences>? = null

    /**
     * Returns the active backing store: the default single-process
     * Preferences DataStore, or — when [configure] enabled multi-process
     * mode — a [MultiProcessDataStoreFactory] store in a separate file.
     */
    private fun storeFor(ctx: Context): DataStore<Preferences> {
        if (!multiProcessEnabled) return ctx.dataStore
        return mpStore ?: synchronized(this) {
            mpStore ?: MultiProcessDataStoreFactory.create(
                serializer = PreferencesJsonSerializer,
                corruptionHandler = ReplaceFileCorruptionHandler {
                    emptyPreferences()
                },
                produceFile = {
                    File(ctx.filesDir, "datastore/native_datastore_mp.json")
                }
            ).also { mpStore = it }
        }
    }

    @Volatile
    private var context: Context? = null

    @Volatile
    private var scope: CoroutineScope? = null

    // Held strongly so the Pigeon handler closure isn't the only owner — gives
    // a deterministic place to drop it during teardown.
    private var securePlugin: SecureDatastorePlugin? = null

    private var changesChannel: EventChannel? = null
    private var changesHandler: ChangesStreamHandler? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val ctx = binding.applicationContext
        val sc = CoroutineScope(Dispatchers.IO + SupervisorJob())
        context = ctx
        scope = sc
        DatastoreApi.setUp(binding.binaryMessenger, this)
        val secure = SecureDatastorePlugin(ctx, sc)
        securePlugin = secure
        SecureDatastoreApi.setUp(binding.binaryMessenger, secure)

        val channel = EventChannel(binding.binaryMessenger, CHANGES_CHANNEL)
        val handler = ChangesStreamHandler(sc) { storeFor(ctx) }
        channel.setStreamHandler(handler)
        changesChannel = channel
        changesHandler = handler
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Cancel pending coroutines first so any in-flight work observes the
        // cancellation before we tear down the Pigeon channel they would reply on.
        scope?.cancel()
        DatastoreApi.setUp(binding.binaryMessenger, null)
        SecureDatastoreApi.setUp(binding.binaryMessenger, null)
        changesChannel?.setStreamHandler(null)
        changesHandler?.dispose()
        changesChannel = null
        changesHandler = null
        securePlugin = null
        scope = null
        context = null
    }

    /**
     * Streams the set of user-facing keys that changed on each DataStore
     * emission. DataStore emits the whole snapshot on any write, so we diff
     * against the previous snapshot to compute which keys actually changed.
     * The first emission only establishes the baseline (no event) — callers
     * read the initial value themselves via the typed getters.
     */
    private class ChangesStreamHandler(
        private val scope: CoroutineScope,
        private val storeProvider: () -> DataStore<Preferences>
    ) : EventChannel.StreamHandler {
        private val mainHandler = Handler(Looper.getMainLooper())
        private var job: Job? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            val sink = events ?: return
            job = scope.launch {
                var previous: Map<String, Any?>? = null
                storeProvider().data.collect { prefs ->
                    val current =
                        prefs.asMap().entries.associate { it.key.name to it.value }
                    val prev = previous
                    if (prev != null) {
                        val changedRaw = (current.keys + prev.keys).filter {
                            current[it] != prev[it]
                        }
                        if (changedRaw.isNotEmpty()) {
                            val userKeys =
                                changedRaw.map { toUserFacingKey(it) }.distinct()
                            mainHandler.post { sink.success(userKeys) }
                        }
                    }
                    previous = current
                }
            }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
            job = null
        }

        fun dispose() {
            job?.cancel()
            job = null
        }
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
            val prefs = storeFor(ctx).data.first()
            prefs[stringPreferencesKey(key)]
        }
    }

    override fun getBool(key: String, callback: (Result<Boolean?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
            prefs[booleanPreferencesKey(key)]
        }
    }

    override fun getInt(key: String, callback: (Result<Long?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
            prefs[longPreferencesKey(key)]
        }
    }

    override fun getDouble(key: String, callback: (Result<Double?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
            prefs[doublePreferencesKey(key)]
        }
    }

    override fun getStringList(key: String, callback: (Result<List<String>?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
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
            storeFor(ctx).edit { prefs ->
                prefs[stringPreferencesKey(key)] = value
            }
        }
    }

    override fun setBool(key: String, value: Boolean, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            storeFor(ctx).edit { prefs ->
                prefs[booleanPreferencesKey(key)] = value
            }
        }
    }

    override fun setInt(key: String, value: Long, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            storeFor(ctx).edit { prefs ->
                prefs[longPreferencesKey(key)] = value
            }
        }
    }

    override fun setDouble(key: String, value: Double, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            storeFor(ctx).edit { prefs ->
                prefs[doublePreferencesKey(key)] = value
            }
        }
    }

    override fun setStringList(key: String, value: List<String>, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val jsonArray = JSONArray(value)
            storeFor(ctx).edit { prefs ->
                prefs[stringPreferencesKey(LIST_BUCKET + key)] = jsonArray.toString()
            }
        }
    }

    // ---------- Remove / Clear ----------

    override fun remove(key: String, callback: (Result<Boolean>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val candidates = bucketCandidates(key)
            var removed = false
            storeFor(ctx).edit { prefs ->
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
            storeFor(ctx).edit { it.clear() }
        }
    }

    // ---------- Batch ----------

    /**
     * Decodes one stored entry back to the value shape the Dart side expects,
     * mirroring [getAll]'s per-bucket handling.
     */
    private fun decodeStored(bucket: String?, value: Any): Any = when (bucket) {
        LIST_BUCKET -> {
            val jsonArray = JSONArray(value as String)
            List(jsonArray.length()) { i -> jsonArray.getString(i) }
        }
        // Native ByteArray since 1.7.0; String is the legacy Base64 form.
        BYTES_BUCKET -> if (value is ByteArray) {
            value
        } else {
            Base64.decode(value as String, Base64.DEFAULT)
        }
        else -> value
    }

    override fun getMany(keys: List<String>, callback: (Result<Map<String, Any>>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            // One snapshot for the whole batch instead of one per key.
            val prefs = storeFor(ctx).data.first()
            val wanted = keys.toHashSet()
            val result = mutableMapOf<String, Any>()
            for ((prefKey, value) in prefs.asMap()) {
                val (realKey, bucket) = stripBucket(prefKey.name)
                if (realKey in wanted) {
                    result[realKey] = decodeStored(bucket, value)
                }
            }
            result
        }
    }

    /** A value already converted to the exact form the store holds. */
    private data class PreparedWrite(val name: String, val value: Any)

    override fun setMany(entries: Map<String, Any>, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            // Convert outside the transaction so an unsupported value fails
            // before anything is written, keeping the batch all-or-nothing.
            val prepared = entries.map { (key, value) -> prepareWrite(key, value) }
            // A single edit{} means a single whole-file rewrite for the batch,
            // rather than one per key.
            storeFor(ctx).edit { prefs ->
                for (write in prepared) {
                    when (val v = write.value) {
                        is String -> prefs[stringPreferencesKey(write.name)] = v
                        is Boolean -> prefs[booleanPreferencesKey(write.name)] = v
                        is Long -> prefs[longPreferencesKey(write.name)] = v
                        is Double -> prefs[doublePreferencesKey(write.name)] = v
                        else -> throw IllegalArgumentException(
                            "setMany: unexpected prepared type ${v.javaClass.name}"
                        )
                    }
                }
            }
        }
    }

    /**
     * Converts an incoming batch value to its stored form, resolving the
     * bucket-prefixed key name. Throws [IllegalArgumentException] for types the
     * batch path cannot represent.
     */
    private fun prepareWrite(key: String, value: Any): PreparedWrite = when (value) {
        is String -> PreparedWrite(key, value)
        is Boolean -> PreparedWrite(key, value)
        // Pigeon narrows small ints to Int on the wire; the store uses Long.
        is Int -> PreparedWrite(key, value.toLong())
        is Long -> PreparedWrite(key, value)
        is Double -> PreparedWrite(key, value)
        is List<*> -> PreparedWrite(
            LIST_BUCKET + key,
            JSONArray(value.map { it as? String ?: it.toString() }).toString()
        )
        else -> throw IllegalArgumentException(
            "setMany: unsupported value type for key \"$key\": ${value.javaClass.name}"
        )
    }

    override fun removeMany(keys: List<String>, callback: (Result<Long>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val candidates = keys.flatMapTo(HashSet()) { bucketCandidates(it) }
            var removed = 0L
            storeFor(ctx).edit { prefs ->
                val matching = prefs.asMap().keys.filter { it.name in candidates }
                for (prefKey in matching) {
                    @Suppress("UNCHECKED_CAST")
                    prefs.remove(prefKey as Preferences.Key<Any>)
                    removed++
                }
            }
            removed
        }
    }

    // ---------- Query ----------

    override fun getAll(callback: (Result<Map<String, Any>>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
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
                        result[realKey] = decodeStored(BYTES_BUCKET, value)
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
            val prefs = storeFor(ctx).data.first()
            prefs.asMap().keys.map { prefKey -> stripBucket(prefKey.name).first }.distinct()
        }
    }

    override fun containsKey(key: String, callback: (Result<Boolean>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
            val candidates = bucketCandidates(key)
            prefs.asMap().keys.any { it.name in candidates }
        }
    }

    // ---------- Bytes (Uint8List) ----------

    /**
     * Reads a byte payload, preferring the native `ByteArray` slot and falling
     * back to the legacy Base64 string written by versions <= 1.6.2.
     *
     * Base64 inflated every blob by ~33% on disk and, because the JVM holds
     * strings as UTF-16, roughly 2.7x in memory on top of the byte array
     * itself — the dominant cost of a large `setBytes`/`getBytes`.
     */
    private fun readBytes(prefs: Preferences, key: String): ByteArray? {
        val name = BYTES_BUCKET + key
        // Read the raw entry and branch on its runtime type. `Preferences.get`
        // casts unchecked, so asking for a ByteArray key when a legacy Base64
        // String is stored would hand back a String typed as ByteArray.
        val raw = prefs.asMap().entries.firstOrNull { it.key.name == name }?.value
        return when (raw) {
            is ByteArray -> raw
            is String -> Base64.decode(raw, Base64.DEFAULT)
            else -> null
        }
    }

    override fun getBytes(key: String, callback: (Result<ByteArray?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            readBytes(storeFor(ctx).data.first(), key)
        }
    }

    override fun setBytes(key: String, value: ByteArray, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            storeFor(ctx).edit { prefs ->
                // `Preferences.Key` equality is by name alone, so writing the
                // ByteArray replaces any legacy Base64 String under the same
                // name. Removing the String key here would delete this write.
                prefs[byteArrayPreferencesKey(BYTES_BUCKET + key)] = value
            }
        }
    }

    // ---------- DateTime (millis since epoch) ----------

    override fun getDateTime(key: String, callback: (Result<Long?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
            prefs[longPreferencesKey(DATETIME_BUCKET + key)]
        }
    }

    override fun setDateTime(key: String, value: Long, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            storeFor(ctx).edit { prefs ->
                prefs[longPreferencesKey(DATETIME_BUCKET + key)] = value
            }
        }
    }

    // ---------- JSON Map ----------

    override fun getMap(key: String, callback: (Result<String?>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            val prefs = storeFor(ctx).data.first()
            prefs[stringPreferencesKey(MAP_BUCKET + key)]
        }
    }

    override fun setMap(key: String, value: String, callback: (Result<Unit>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            storeFor(ctx).edit { prefs ->
                prefs[stringPreferencesKey(MAP_BUCKET + key)] = value
            }
        }
    }

    // ---------- Atomic read-modify-write ----------
    // DataStore's `edit { }` runs its block as a single serialized transaction,
    // so read-then-write inside it is atomic with respect to other writers.

    override fun incrementInt(key: String, delta: Long, callback: (Result<Long>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            var newValue = 0L
            storeFor(ctx).edit { prefs ->
                newValue = (prefs[longPreferencesKey(key)] ?: 0L) + delta
                prefs[longPreferencesKey(key)] = newValue
            }
            newValue
        }
    }

    override fun incrementDouble(key: String, delta: Double, callback: (Result<Double>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            var newValue = 0.0
            storeFor(ctx).edit { prefs ->
                newValue = (prefs[doublePreferencesKey(key)] ?: 0.0) + delta
                prefs[doublePreferencesKey(key)] = newValue
            }
            newValue
        }
    }

    override fun toggleBool(key: String, callback: (Result<Boolean>) -> Unit) {
        launchOnAttached(callback) { ctx ->
            var newValue = false
            storeFor(ctx).edit { prefs ->
                newValue = !(prefs[booleanPreferencesKey(key)] ?: false)
                prefs[booleanPreferencesKey(key)] = newValue
            }
            newValue
        }
    }

    override fun compareAndSetString(
        key: String,
        expected: String?,
        value: String?,
        callback: (Result<Boolean>) -> Unit
    ) {
        launchOnAttached(callback) { ctx ->
            val prefKey = stringPreferencesKey(key)
            var swapped = false
            storeFor(ctx).edit { prefs ->
                if (prefs[prefKey] == expected) {
                    if (value == null) prefs.remove(prefKey) else prefs[prefKey] = value
                    swapped = true
                }
            }
            swapped
        }
    }

    override fun compareAndSetInt(
        key: String,
        expected: Long?,
        value: Long?,
        callback: (Result<Boolean>) -> Unit
    ) {
        launchOnAttached(callback) { ctx ->
            val prefKey = longPreferencesKey(key)
            var swapped = false
            storeFor(ctx).edit { prefs ->
                if (prefs[prefKey] == expected) {
                    if (value == null) prefs.remove(prefKey) else prefs[prefKey] = value
                    swapped = true
                }
            }
            swapped
        }
    }

    override fun compareAndSetDouble(
        key: String,
        expected: Double?,
        value: Double?,
        callback: (Result<Boolean>) -> Unit
    ) {
        launchOnAttached(callback) { ctx ->
            val prefKey = doublePreferencesKey(key)
            var swapped = false
            storeFor(ctx).edit { prefs ->
                if (prefs[prefKey] == expected) {
                    if (value == null) prefs.remove(prefKey) else prefs[prefKey] = value
                    swapped = true
                }
            }
            swapped
        }
    }

    override fun compareAndSetBool(
        key: String,
        expected: Boolean?,
        value: Boolean?,
        callback: (Result<Boolean>) -> Unit
    ) {
        launchOnAttached(callback) { ctx ->
            val prefKey = booleanPreferencesKey(key)
            var swapped = false
            storeFor(ctx).edit { prefs ->
                if (prefs[prefKey] == expected) {
                    if (value == null) prefs.remove(prefKey) else prefs[prefKey] = value
                    swapped = true
                }
            }
            swapped
        }
    }

    // ---------- Migration from shared_preferences ----------

    override fun migrateFromSharedPreferences(
        overwrite: Boolean,
        callback: (Result<Long>) -> Unit
    ) {
        launchOnAttached(callback) { ctx ->
            // The Flutter shared_preferences plugin stores everything in a
            // SharedPreferences file named "FlutterSharedPreferences" with keys
            // prefixed "flutter.". `all` returns the decoded Java types, so we
            // import by runtime type rather than guessing the on-disk encoding.
            val sp = ctx.getSharedPreferences(
                "FlutterSharedPreferences",
                Context.MODE_PRIVATE
            )
            val existing = storeFor(ctx).data.first()
            var imported = 0L
            storeFor(ctx).edit { prefs ->
                for ((rawKey, value) in sp.all) {
                    if (!rawKey.startsWith("flutter.")) continue
                    val key = rawKey.removePrefix("flutter.")
                    if (key.isEmpty()) continue
                    val alreadyHere = bucketCandidates(key).any { cand ->
                        existing.asMap().keys.any { it.name == cand }
                    }
                    if (alreadyHere && !overwrite) continue
                    when (value) {
                        is Boolean -> prefs[booleanPreferencesKey(key)] = value
                        is Long -> prefs[longPreferencesKey(key)] = value
                        is Int -> prefs[longPreferencesKey(key)] = value.toLong()
                        is Float -> prefs[doublePreferencesKey(key)] = value.toDouble()
                        is Double -> prefs[doublePreferencesKey(key)] = value
                        is String -> {
                            // shared_preferences encodes List<String> and
                            // BigInteger as tagged strings; importing those raw
                            // would corrupt them, so skip specially-tagged values.
                            if (value.startsWith(SP_LIST_PREFIX) ||
                                value.startsWith(SP_BIGINT_PREFIX)
                            ) {
                                continue
                            }
                            prefs[stringPreferencesKey(key)] = value
                        }
                        is Set<*> -> {
                            val list = value.filterIsInstance<String>()
                            prefs[stringPreferencesKey(LIST_BUCKET + key)] =
                                JSONArray(list).toString()
                        }
                        else -> continue
                    }
                    imported++
                }
            }
            imported
        }
    }

    // ---------- Configuration ----------

    override fun configure(
        multiProcess: Boolean,
        appGroupId: String?,
        callback: (Result<Unit>) -> Unit
    ) {
        // appGroupId is an iOS-only concept; ignored on Android.
        launchOnAttached(callback) { _ ->
            multiProcessEnabled = multiProcess
        }
    }
}
