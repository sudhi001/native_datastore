package `in`.sudhi.native_datastore

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import io.flutter.embedding.engine.plugins.FlutterPlugin
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import org.json.JSONArray

private val Context.dataStore: DataStore<Preferences> by preferencesDataStore(
    name = "native_datastore_prefs"
)

class NativeDatastorePlugin : FlutterPlugin, DatastoreApi {

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
        DatastoreApi.setUp(binding.binaryMessenger, null)
        scope?.cancel()
        scope = null
        context = null
    }

    /**
     * Safely launches a coroutine on the plugin scope.
     * If the plugin is not attached, the callback receives an error immediately.
     */
    private fun <T> launchSafe(
        callback: (Result<T>) -> Unit,
        block: suspend (Context) -> T
    ) {
        val currentScope = scope
        val currentContext = context
        if (currentScope == null || currentContext == null) {
            callback(Result.failure(
                IllegalStateException("NativeDatastorePlugin is not attached to a Flutter engine")
            ))
            return
        }
        currentScope.launch {
            try {
                val result = block(currentContext)
                callback(Result.success(result))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    // ---------- Getters ----------

    override fun getString(key: String, callback: (Result<String?>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[stringPreferencesKey(key)]
        }
    }

    override fun getBool(key: String, callback: (Result<Boolean?>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[booleanPreferencesKey(key)]
        }
    }

    override fun getInt(key: String, callback: (Result<Long?>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[longPreferencesKey(key)]
        }
    }

    override fun getDouble(key: String, callback: (Result<Double?>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs[doublePreferencesKey(key)]
        }
    }

    override fun getStringList(key: String, callback: (Result<List<String>?>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            val json = prefs[stringPreferencesKey("__list__:$key")]
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
        launchSafe(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[stringPreferencesKey(key)] = value
            }
        }
    }

    override fun setBool(key: String, value: Boolean, callback: (Result<Unit>) -> Unit) {
        launchSafe(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[booleanPreferencesKey(key)] = value
            }
        }
    }

    override fun setInt(key: String, value: Long, callback: (Result<Unit>) -> Unit) {
        launchSafe(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[longPreferencesKey(key)] = value
            }
        }
    }

    override fun setDouble(key: String, value: Double, callback: (Result<Unit>) -> Unit) {
        launchSafe(callback) { ctx ->
            ctx.dataStore.edit { prefs ->
                prefs[doublePreferencesKey(key)] = value
            }
        }
    }

    override fun setStringList(key: String, value: List<String>, callback: (Result<Unit>) -> Unit) {
        launchSafe(callback) { ctx ->
            val jsonArray = JSONArray(value)
            ctx.dataStore.edit { prefs ->
                prefs[stringPreferencesKey("__list__:$key")] = jsonArray.toString()
            }
        }
    }

    // ---------- Remove / Clear ----------

    override fun remove(key: String, callback: (Result<Boolean>) -> Unit) {
        launchSafe(callback) { ctx ->
            var removed = false
            ctx.dataStore.edit { prefs ->
                val keysToRemove = prefs.asMap().keys.filter {
                    it.name == key || it.name == "__list__:$key"
                }
                for (k in keysToRemove) {
                    @Suppress("UNCHECKED_CAST")
                    prefs.remove(k as Preferences.Key<Any>)
                    removed = true
                }
            }
            removed
        }
    }

    override fun clear(callback: (Result<Boolean>) -> Unit) {
        launchSafe(callback) { ctx ->
            ctx.dataStore.edit { it.clear() }
            true
        }
    }

    // ---------- Query ----------

    override fun getAll(callback: (Result<Map<String, Any>>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            val result = mutableMapOf<String, Any>()
            for ((key, value) in prefs.asMap()) {
                if (key.name.startsWith("__list__:")) {
                    val realKey = key.name.removePrefix("__list__:")
                    val jsonArray = JSONArray(value as String)
                    val list = List(jsonArray.length()) { i -> jsonArray.getString(i) }
                    result[realKey] = list
                } else {
                    result[key.name] = value
                }
            }
            result
        }
    }

    override fun getKeys(callback: (Result<List<String>>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs.asMap().keys.map { key ->
                if (key.name.startsWith("__list__:")) {
                    key.name.removePrefix("__list__:")
                } else {
                    key.name
                }
            }.distinct()
        }
    }

    override fun containsKey(key: String, callback: (Result<Boolean>) -> Unit) {
        launchSafe(callback) { ctx ->
            val prefs = ctx.dataStore.data.first()
            prefs.asMap().keys.any {
                it.name == key || it.name == "__list__:$key"
            }
        }
    }
}
