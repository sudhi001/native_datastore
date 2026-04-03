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

    private lateinit var context: Context
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        DatastoreApi.setUp(binding.binaryMessenger, this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DatastoreApi.setUp(binding.binaryMessenger, null)
        scope.cancel()
    }

    // ---------- Getters ----------

    override fun getString(key: String, callback: (Result<String?>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val value = prefs[stringPreferencesKey(key)]
                callback(Result.success(value))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getBool(key: String, callback: (Result<Boolean?>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val value = prefs[booleanPreferencesKey(key)]
                callback(Result.success(value))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getInt(key: String, callback: (Result<Long?>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val value = prefs[longPreferencesKey(key)]
                callback(Result.success(value))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getDouble(key: String, callback: (Result<Double?>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val value = prefs[doublePreferencesKey(key)]
                callback(Result.success(value))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getStringList(key: String, callback: (Result<List<String>?>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val json = prefs[stringPreferencesKey("__list__:$key")]
                if (json == null) {
                    callback(Result.success(null))
                } else {
                    val jsonArray = JSONArray(json)
                    val list = mutableListOf<String>()
                    for (i in 0 until jsonArray.length()) {
                        list.add(jsonArray.getString(i))
                    }
                    callback(Result.success(list))
                }
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    // ---------- Setters ----------

    override fun setString(key: String, value: String, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                context.dataStore.edit { prefs ->
                    prefs[stringPreferencesKey(key)] = value
                }
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun setBool(key: String, value: Boolean, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                context.dataStore.edit { prefs ->
                    prefs[booleanPreferencesKey(key)] = value
                }
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun setInt(key: String, value: Long, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                context.dataStore.edit { prefs ->
                    prefs[longPreferencesKey(key)] = value
                }
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun setDouble(key: String, value: Double, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                context.dataStore.edit { prefs ->
                    prefs[doublePreferencesKey(key)] = value
                }
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun setStringList(key: String, value: List<String>, callback: (Result<Unit>) -> Unit) {
        scope.launch {
            try {
                val jsonArray = JSONArray(value)
                context.dataStore.edit { prefs ->
                    prefs[stringPreferencesKey("__list__:$key")] = jsonArray.toString()
                }
                callback(Result.success(Unit))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    // ---------- Remove / Clear ----------

    override fun remove(key: String, callback: (Result<Boolean>) -> Unit) {
        scope.launch {
            try {
                var removed = false
                context.dataStore.edit { prefs ->
                    val allKeys = prefs.asMap().keys
                    val keysToRemove = allKeys.filter {
                        it.name == key || it.name == "__list__:$key"
                    }
                    for (k in keysToRemove) {
                        @Suppress("UNCHECKED_CAST")
                        prefs.remove(k as Preferences.Key<Any>)
                        removed = true
                    }
                }
                callback(Result.success(removed))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun clear(callback: (Result<Boolean>) -> Unit) {
        scope.launch {
            try {
                context.dataStore.edit { it.clear() }
                callback(Result.success(true))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    // ---------- Query ----------

    override fun getAll(callback: (Result<Map<String, Any>>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val result = mutableMapOf<String, Any>()
                for ((key, value) in prefs.asMap()) {
                    if (key.name.startsWith("__list__:")) {
                        val realKey = key.name.removePrefix("__list__:")
                        val jsonArray = JSONArray(value as String)
                        val list = mutableListOf<String>()
                        for (i in 0 until jsonArray.length()) {
                            list.add(jsonArray.getString(i))
                        }
                        result[realKey] = list
                    } else {
                        result[key.name] = value
                    }
                }
                callback(Result.success(result))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun getKeys(callback: (Result<List<String>>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val keys = prefs.asMap().keys.map { key ->
                    if (key.name.startsWith("__list__:")) {
                        key.name.removePrefix("__list__:")
                    } else {
                        key.name
                    }
                }.distinct()
                callback(Result.success(keys))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }

    override fun containsKey(key: String, callback: (Result<Boolean>) -> Unit) {
        scope.launch {
            try {
                val prefs = context.dataStore.data.first()
                val found = prefs.asMap().keys.any {
                    it.name == key || it.name == "__list__:$key"
                }
                callback(Result.success(found))
            } catch (e: Exception) {
                callback(Result.failure(e))
            }
        }
    }
}
