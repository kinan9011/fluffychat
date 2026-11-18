// Modified by Contributors to FluffyChat (2026): content:// shares are copied into a fresh
// cache sub-directory under a sanitised name (fluffychat#197, upstream issues #181, #411, #417).
// PATCHES.md in the plugin root lists every hunk against upstream 1.9.0.
package com.kasem.receive_sharing_intent

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.util.Date
import java.util.UUID

object FileDirectory {

    const val SHARE_DIR = "receive_sharing_intent"
    const val MAX_COPY_BYTES = 512L * 1024 * 1024
    private const val MAX_NAME_CHARS = 80
    private const val MAX_EXTENSION_CHARS = 16
    private const val TAG = "FileDirectory"

    /**
     * Copies a content:// uri to a fresh directory below the cache and returns the copy's path.
     * Returns null for any other scheme, for providers of this very app, when the copy fails and
     * when the stream is longer than [MAX_COPY_BYTES]. Raw paths are never returned.
     */
    fun getAbsolutePath(context: Context, uri: Uri): String? {
        if (!"content".equals(uri.scheme, ignoreCase = true)) return null
        if (isOwnProvider(context, uri)) return null
        val path = try {
            copyToShareDir(context, uri)
        } catch (e: Exception) {
            null
        }
        if (path == null) Log.w(TAG, "Unable to copy the shared file")
        return path
    }

    internal fun newShareDir(cacheDir: File): File {
        val dir = File(File(cacheDir, SHARE_DIR), UUID.randomUUID().toString())
        check(dir.mkdirs() && dir.isDirectory) { "Unable to create the share directory" }
        return dir
    }

    internal fun safeFileName(raw: String?, fallback: String): String {
        if (raw == null) return fallback
        val lastSegment = raw.substringAfterLast('/').substringAfterLast('\\')
        val cleaned = lastSegment
            .filter { c ->
                !Character.isISOControl(c) &&
                    Character.getType(c) != Character.FORMAT.toInt() &&
                    c != ':'
            }
            .trim()
            .trimStart('.')
        if (cleaned.isEmpty()) return fallback
        if (cleaned.length <= MAX_NAME_CHARS) return cleaned
        val extension = cleaned.substringAfterLast('.', "")
        val keepExtension = extension.length in 1..MAX_EXTENSION_CHARS
        val suffix = if (keepExtension) ".$extension" else ""
        var base = cleaned.take(MAX_NAME_CHARS - suffix.length)
        if (base.isNotEmpty() && Character.isHighSurrogate(base.last())) base = base.dropLast(1)
        return base + suffix
    }

    internal fun authorityOf(raw: String?): String? =
        raw?.substringAfterLast('@')?.substringBefore(':')

    /** Returns false as soon as more than [max] bytes were read. */
    internal fun copyCapped(input: InputStream, output: OutputStream, max: Long): Boolean {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) return true
            total += read
            if (total > max) return false
            output.write(buffer, 0, read)
        }
    }

    private fun isOwnProvider(context: Context, uri: Uri): Boolean {
        val authority = authorityOf(uri.authority) ?: return true
        val info = context.packageManager.resolveContentProvider(authority, 0) ?: return false
        return info.packageName == context.packageName
    }

    private fun displayName(context: Context, uri: Uri): String? {
        return try {
            context.contentResolver.query(
                uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
            )?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun fallbackName(context: Context, uri: Uri): String {
        val mimeType = context.contentResolver.getType(uri)
        val prefix = with(mimeType ?: "") {
            when {
                startsWith("image") -> "IMG"
                startsWith("video") -> "VID"
                else -> "FILE"
            }
        }
        val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mimeType)
            ?.filter { it.code < 128 && it.isLetterOrDigit() }
            .orEmpty()
        val suffix = if (extension.isEmpty()) "" else ".$extension"
        return "${prefix}_${Date().time}$suffix"
    }

    private fun copyToShareDir(context: Context, uri: Uri): String? {
        val name = safeFileName(displayName(context, uri), fallbackName(context, uri))
        val dir = newShareDir(context.cacheDir)
        return copyInto(dir, name, { context.contentResolver.openInputStream(uri) })
    }

    /** Copies [open]'s stream to [dir]/[name]; on any failure deletes [dir] and returns null. */
    internal fun copyInto(
        dir: File,
        name: String,
        open: () -> InputStream?,
        max: Long = MAX_COPY_BYTES,
    ): String? {
        try {
            val target = File(dir, name)
            check(target.canonicalFile.parentFile == dir.canonicalFile) { "Unexpected share path" }
            check(target.createNewFile()) { "Share file exists" }
            val input = open() ?: throw IllegalStateException("No stream")
            val complete = input.use { stream ->
                FileOutputStream(target).use { out -> copyCapped(stream, out, max) }
            }
            check(complete) { "Shared file is too large" }
            return target.path
        } catch (e: Exception) {
            dir.deleteRecursively()
            return null
        }
    }
}
