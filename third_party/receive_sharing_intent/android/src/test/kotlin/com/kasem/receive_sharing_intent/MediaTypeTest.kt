// Added by Contributors to FluffyChat (2026): tests for the Dirty Stream fix (fluffychat#197).
package com.kasem.receive_sharing_intent

import com.kasem.receive_sharing_intent.ReceiveSharingIntentPlugin.MediaType
import org.junit.Assert.assertEquals
import org.junit.Test

class MediaTypeTest {
    @Test
    fun m5TextFallbackIsTypedTextWhateverTheIntentMimeType() {
        assertEquals(MediaType.TEXT, MediaType.forShare(null, "image/png"))
        assertEquals(MediaType.TEXT, MediaType.forShare(null, null))
    }

    @Test
    fun m5CopiedFilesKeepTheirMimeBasedType() {
        assertEquals(MediaType.IMAGE, MediaType.forShare("/c/a.png", "image/png"))
        assertEquals(MediaType.VIDEO, MediaType.forShare("/c/a.mp4", "video/mp4"))
        assertEquals(MediaType.FILE, MediaType.forShare("/c/a.pdf", "application/pdf"))
    }
}
