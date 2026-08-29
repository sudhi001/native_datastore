package `in`.sudhi.native_datastore

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.File

/**
 * Pins the fix for the encrypted store being carried into Android Auto Backup
 * and device-to-device transfer.
 *
 * `filesDir` is backed up; the AndroidKeyStore key that decrypts its contents
 * is not, and cannot be. A restored install therefore held ciphertext it had no
 * key for, and every secure call failed for the life of that install.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class SecureFileTest {

    private lateinit var context: Context

    private val legacy: File
        get() = File(context.filesDir, "datastore/$SECURE_FILE_NAME")

    private val target: File
        get() = File(context.noBackupFilesDir, "datastore/$SECURE_FILE_NAME")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        legacy.delete()
        target.delete()
    }

    @Test
    fun `resolves to a directory excluded from backup`() {
        val resolved = secureFile(context, SECURE_FILE_NAME)

        assertEquals(target, resolved)
        assertTrue(
            "the store must sit under noBackupFilesDir, not filesDir",
            resolved.absolutePath.startsWith(context.noBackupFilesDir.absolutePath),
        )
    }

    @Test
    fun `moves an existing pre-1_7_2 store out of the backed-up directory`() {
        val contents = byteArrayOf(9, 8, 7)
        legacy.parentFile!!.mkdirs()
        legacy.writeBytes(contents)

        val resolved = secureFile(context, SECURE_FILE_NAME)

        assertEquals(target, resolved)
        assertArrayEquals("secrets must survive the move", contents, resolved.readBytes())
        assertFalse("the backed-up copy must not be left behind", legacy.exists())
    }

    @Test
    fun `leaves an already-relocated store untouched`() {
        target.parentFile!!.mkdirs()
        target.writeBytes(byteArrayOf(1))
        // A stale legacy file must never overwrite the live one — that would
        // resurrect secrets the app already replaced.
        legacy.parentFile!!.mkdirs()
        legacy.writeBytes(byteArrayOf(2))

        val resolved = secureFile(context, SECURE_FILE_NAME)

        assertArrayEquals(byteArrayOf(1), resolved.readBytes())
    }

    @Test
    fun `relocates the multi-process store too`() {
        val mpLegacy = File(context.filesDir, "datastore/$SECURE_MP_FILE_NAME")
        mpLegacy.parentFile!!.mkdirs()
        mpLegacy.writeBytes(byteArrayOf(4, 2))

        val resolved = secureFile(context, SECURE_MP_FILE_NAME)

        assertEquals(File(context.noBackupFilesDir, "datastore/$SECURE_MP_FILE_NAME"), resolved)
        assertArrayEquals(byteArrayOf(4, 2), resolved.readBytes())
        assertFalse(mpLegacy.exists())
    }
}
