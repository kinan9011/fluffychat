// Added by Contributors to FluffyChat (2026): tests for the Dirty Stream fix (fluffychat#197).
package com.kasem.receive_sharing_intent

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.nio.file.Files
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FileDirectoryTest {
    private val fallback = "FILE_1.bin"

    private fun name(raw: String?) = FileDirectory.safeFileName(raw, fallback)

    @Test
    fun k1TraversalIsReducedToTheLastSegment() {
        assertEquals(
            "FlutterSharedPreferences.xml",
            name("../shared_prefs/FlutterSharedPreferences.xml"),
        )
        assertEquals("x", name("..\\..\\x"))
        assertEquals("x", name("/data/data/im.fluffychat/files/x"))
    }

    @Test
    fun k2DotOnlyAndBlankNamesUseTheFallback() {
        for (raw in listOf("..", ".", "...", "   ", "", "a/", "../")) {
            assertEquals("for '$raw'", fallback, name(raw))
        }
    }

    @Test
    fun k3ControlAndFormatCharactersAreRemoved() {
        assertEquals("atxt.exe", name("a\u202Etxt.exe"))
        assertEquals("ab", name("a\u0000b"))
        assertEquals("ab", name("a\nb"))
        assertEquals("x", name("\u2066x"))
        assertEquals("ab", name("a\u200Eb"))
    }

    @Test
    fun k4ColonIsRemoved() {
        assertEquals("Cevil", name("C:evil"))
    }

    @Test
    fun k5NullUsesTheFallback() {
        assertEquals(fallback, name(null))
    }

    @Test
    fun k6LongNamesAreCappedAndKeepTheExtension() {
        val long = "é".repeat(300) + ".pdf"
        val result = name(long)
        assertTrue(result.length <= 80)
        assertTrue(result.endsWith(".pdf"))
    }

    @Test
    fun k6bCapDoesNotLeaveALoneSurrogate() {
        val result = name("a".repeat(79) + "😀")
        assertTrue(result.length <= 80)
        assertFalse(Character.isHighSurrogate(result.last()))
    }

    @Test
    fun k7ShareDirsAreFreshAndBelowTheShareRoot() {
        val cache = Files.createTempDirectory("t197-cache").toFile()
        try {
            val a = FileDirectory.newShareDir(cache)
            val b = FileDirectory.newShareDir(cache)
            assertNotEquals(a, b)
            for (dir in listOf(a, b)) {
                assertTrue(dir.isDirectory)
                assertEquals(File(cache, FileDirectory.SHARE_DIR).canonicalFile, dir.parentFile.canonicalFile)
                assertTrue(
                    Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}").matches(dir.name),
                )
            }
        } finally {
            cache.deleteRecursively()
        }
    }

    @Test
    fun k8CopyCappedStopsAboveTheLimit() {
        val ten = ByteArray(10)
        assertTrue(FileDirectory.copyCapped(ByteArrayInputStream(ten), ByteArrayOutputStream(), 10))
        assertFalse(FileDirectory.copyCapped(ByteArrayInputStream(ByteArray(11)), ByteArrayOutputStream(), 10))
    }

    @Test
    fun k9CopyCappedAcceptsAnEmptyStream() {
        assertTrue(FileDirectory.copyCapped(ByteArrayInputStream(ByteArray(0)), ByteArrayOutputStream(), 10))
    }

    @Test
    fun k10CopyCappedHandlesMoreThanOneBuffer() {
        val big = ByteArray(200 * 1024) { 7 }
        val out = ByteArrayOutputStream()
        assertTrue(FileDirectory.copyCapped(ByteArrayInputStream(big), out, big.size.toLong()))
        assertEquals(big.size, out.size())
        assertFalse(
            FileDirectory.copyCapped(ByteArrayInputStream(big), ByteArrayOutputStream(), big.size - 1L),
        )
    }

    @Test
    fun k11AuthorityDropsUserInfoAndPort() {
        assertEquals("im.fluffychat.flutter.image_provider", FileDirectory.authorityOf("0@im.fluffychat.flutter.image_provider"))
        assertEquals("a.b", FileDirectory.authorityOf("u:p@a.b:8080"))
        assertEquals("a.b", FileDirectory.authorityOf("a.b"))
        assertEquals(null, FileDirectory.authorityOf(null))
    }

    private fun shareDirIn(cache: File) = FileDirectory.newShareDir(cache)

    @Test
    fun k12OversizeStreamFailsAndDeletesTheDirectory() {
        val cache = Files.createTempDirectory("t197-cache").toFile()
        try {
            val dir = shareDirIn(cache)
            val result = FileDirectory.copyInto(dir, "big.bin", { ByteArrayInputStream(ByteArray(11)) }, 10)
            assertEquals(null, result)
            assertFalse(dir.exists())
        } finally {
            cache.deleteRecursively()
        }
    }

    @Test
    fun k13StreamThrowingMidCopyDeletesTheDirectory() {
        val cache = Files.createTempDirectory("t197-cache").toFile()
        try {
            val dir = shareDirIn(cache)
            val failing = object : InputStream() {
                private var served = false
                override fun read(): Int = throw IOException("boom")
                override fun read(b: ByteArray, off: Int, len: Int): Int {
                    if (served) throw IOException("boom")
                    served = true
                    b[off] = 1
                    return 1
                }
            }
            val result = FileDirectory.copyInto(dir, "x.bin", { failing }, 10)
            assertEquals(null, result)
            assertFalse(dir.exists())
        } finally {
            cache.deleteRecursively()
        }
    }

    @Test
    fun k14NoStreamDeletesTheDirectory() {
        val cache = Files.createTempDirectory("t197-cache").toFile()
        try {
            val dir = shareDirIn(cache)
            assertEquals(null, FileDirectory.copyInto(dir, "x.bin", { null }, 10))
            assertFalse(dir.exists())
        } finally {
            cache.deleteRecursively()
        }
    }

    @Test
    fun k15SuccessfulCopyKeepsTheFileInsideTheDirectory() {
        val cache = Files.createTempDirectory("t197-cache").toFile()
        try {
            val dir = shareDirIn(cache)
            val path = FileDirectory.copyInto(dir, "ok.bin", { ByteArrayInputStream(byteArrayOf(1, 2, 3)) }, 10)
            assertEquals(File(dir, "ok.bin").path, path)
            assertEquals(3L, File(path!!).length())
        } finally {
            cache.deleteRecursively()
        }
    }
}
