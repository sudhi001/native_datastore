package `in`.sudhi.native_datastore

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The header byte decides which framing a stored blob is read with. Getting it
 * wrong on a pre-1.8.0 store would make every existing secret unreadable, so
 * the boundary conditions are pinned here rather than left to a device test.
 */
class SecureBlobFormatTest {

    private fun blob(first: Byte, size: Int) = ByteArray(size).also { if (size > 0) it[0] = first }

    @Test
    fun `recognises a blob written with the versioned header`() {
        // 1 header byte + 12 IV bytes + at least one byte of ciphertext.
        assertTrue(isVersionedSecureBlob(blob(SECURE_FORMAT_AAD, 14)))
    }

    @Test
    fun `rejects a blob whose first byte is not the marker`() {
        assertFalse(isVersionedSecureBlob(blob(0, 14)))
        assertFalse(isVersionedSecureBlob(blob(2, 14)))
    }

    @Test
    fun `rejects anything too short to hold a header, an IV and ciphertext`() {
        // Exactly header + IV leaves no ciphertext, so it cannot be versioned.
        assertFalse(isVersionedSecureBlob(blob(SECURE_FORMAT_AAD, 13)))
        assertFalse(isVersionedSecureBlob(blob(SECURE_FORMAT_AAD, 12)))
        assertFalse(isVersionedSecureBlob(ByteArray(0)))
    }

    @Test
    fun `a legacy blob whose IV starts with the marker is still claimed`() {
        // Roughly one pre-1.8.0 blob in 256 looks versioned. The marker is only
        // a hint — the read path falls back to the unversioned framing when GCM
        // authentication rejects the bound interpretation — so this must be
        // true, not false, or that fallback would never be reached.
        assertTrue(isVersionedSecureBlob(blob(SECURE_FORMAT_AAD, 40)))
    }
}
