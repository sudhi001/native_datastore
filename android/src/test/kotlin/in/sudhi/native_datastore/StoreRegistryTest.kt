package `in`.sudhi.native_datastore

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * DataStore records every backing file in a global `activeFiles` set and throws
 * `IllegalStateException: There are multiple DataStores active for the same
 * file` when a second instance opens one. Plugin instances are per-engine, so
 * caching these stores on the instance crashed the second `FlutterEngine`
 * (add-to-app, `FlutterEngineGroup`, a background isolate).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class StoreRegistryTest {

    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun `multi-process store is shared process-wide, not per plugin instance`() {
        val file = { File(context.filesDir, "datastore/registry_test.json") }

        val first = MultiProcessStores.get("registry_test.json", file)
        val second = MultiProcessStores.get("registry_test.json", file)

        assertSame("a second engine must reuse the store, not open another", first, second)
    }

    @Test
    fun `distinct files get distinct stores`() {
        val a = MultiProcessStores.get("registry_a.json") {
            File(context.filesDir, "datastore/registry_a.json")
        }
        val b = MultiProcessStores.get("registry_b.json") {
            File(context.filesDir, "datastore/registry_b.json")
        }

        assertNotSame(a, b)
    }

    @Test
    fun `single-process secure store is shared process-wide`() {
        assertSame(SecureStores.single(context), SecureStores.single(context))
    }
}
