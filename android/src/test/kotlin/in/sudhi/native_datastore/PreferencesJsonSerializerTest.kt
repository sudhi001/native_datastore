package `in`.sudhi.native_datastore

import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.byteArrayPreferencesKey
import androidx.datastore.preferences.core.doublePreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream

/**
 * The serializer only backs the multi-process store, which no unit test could
 * reach before — so a change to its type tags would have silently broken
 * cross-process reads until someone ran the app on a device.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class PreferencesJsonSerializerTest {

    private suspend fun roundTrip(
        prefs: androidx.datastore.preferences.core.Preferences,
    ): androidx.datastore.preferences.core.Preferences {
        val out = ByteArrayOutputStream()
        PreferencesJsonSerializer.writeTo(prefs, out)
        return PreferencesJsonSerializer.readFrom(ByteArrayInputStream(out.toByteArray()))
    }

    @Test
    fun `round-trips every type the plugin stores`() = runTest {
        val bytes = byteArrayOf(0, 1, 127, -128, -1)
        val restored = roundTrip(
            mutablePreferencesOf(
                stringPreferencesKey("s") to "hello",
                booleanPreferencesKey("b") to true,
                longPreferencesKey("l") to Long.MAX_VALUE,
                doublePreferencesKey("d") to -3.5,
                byteArrayPreferencesKey("ba") to bytes,
            ),
        )

        assertEquals("hello", restored[stringPreferencesKey("s")])
        assertEquals(true, restored[booleanPreferencesKey("b")])
        assertEquals(Long.MAX_VALUE, restored[longPreferencesKey("l")])
        assertEquals(-3.5, restored[doublePreferencesKey("d")]!!, 0.0)
        assertArrayEquals(bytes, restored[byteArrayPreferencesKey("ba")])
    }

    @Test
    fun `round-trips an empty byte payload`() = runTest {
        val restored = roundTrip(
            mutablePreferencesOf(byteArrayPreferencesKey("empty") to ByteArray(0)),
        )
        assertArrayEquals(ByteArray(0), restored[byteArrayPreferencesKey("empty")])
    }

    @Test
    fun `keeps bucket-prefixed names verbatim`() = runTest {
        // The bucket prefix is part of the stored name; mangling it here would
        // make every list, byte, date and map value unreadable cross-process.
        val restored = roundTrip(
            mutablePreferencesOf(
                stringPreferencesKey("__list__:tags") to """["a","b"]""",
            ),
        )
        assertEquals("""["a","b"]""", restored[stringPreferencesKey("__list__:tags")])
    }

    @Test
    fun `reads an empty file as empty preferences`() = runTest {
        val restored = PreferencesJsonSerializer.readFrom(ByteArrayInputStream(ByteArray(0)))
        assertTrue(restored.asMap().isEmpty())
    }

    @Test
    fun `drops values it has no type tag for rather than failing the whole file`() = runTest {
        // A single unrepresentable entry must not make the rest unreadable —
        // the corruption handler would otherwise wipe the store.
        val json = """{"good":{"t":"s","v":"kept"},"bad":{"t":"?","v":1}}"""
        val restored = PreferencesJsonSerializer.readFrom(
            ByteArrayInputStream(json.toByteArray()),
        )
        assertEquals("kept", restored[stringPreferencesKey("good")])
        assertNull(restored[stringPreferencesKey("bad")])
    }
}
