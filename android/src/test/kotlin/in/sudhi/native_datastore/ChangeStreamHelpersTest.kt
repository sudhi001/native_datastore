package `in`.sudhi.native_datastore

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Covers the diffing helpers behind the `watch*` change stream. */
class ChangeStreamHelpersTest {

    @Test
    fun `byte payloads compare by content, not identity`() {
        // Kotlin's `==` on ByteArray is referential, and the multi-process
        // store hands back a freshly parsed array on every emission — so the
        // referential form reported every byte-valued key as changed on every
        // single write.
        assertTrue(valuesEqual(byteArrayOf(1, 2, 3), byteArrayOf(1, 2, 3)))
        assertFalse(valuesEqual(byteArrayOf(1, 2, 3), byteArrayOf(1, 2, 4)))
        assertFalse(valuesEqual(byteArrayOf(1, 2, 3), byteArrayOf(1, 2)))
        assertTrue(valuesEqual(ByteArray(0), ByteArray(0)))
    }

    @Test
    fun `non-byte values keep ordinary equality`() {
        assertTrue(valuesEqual("a", "a"))
        assertFalse(valuesEqual("a", "b"))
        assertTrue(valuesEqual(1L, 1L))
        assertTrue(valuesEqual(null, null))
        assertFalse(valuesEqual(null, 1L))
        assertFalse(valuesEqual(byteArrayOf(1), "1"))
    }

    @Test
    fun `strips every bucket prefix a stored key can carry`() {
        assertEquals("tags", toUserFacingKey("__list__:tags"))
        assertEquals("avatar", toUserFacingKey("__bytes__:avatar"))
        assertEquals("lastSeen", toUserFacingKey("__datetime__:lastSeen"))
        assertEquals("profile", toUserFacingKey("__map__:profile"))
        assertEquals("username", toUserFacingKey("username"))
    }

    @Test
    fun `only strips a prefix at the start of the name`() {
        assertEquals("a__list__:b", toUserFacingKey("a__list__:b"))
    }

    @Test
    fun `the change-stream bucket list matches the plugin's own`() {
        // These two lists are separate copies in the same file, and the change
        // stream silently reports raw keys if they drift apart.
        assertEquals(
            listOf("__list__:", "__bytes__:", "__datetime__:", "__map__:"),
            CHANGE_STREAM_BUCKETS,
        )
    }
}
