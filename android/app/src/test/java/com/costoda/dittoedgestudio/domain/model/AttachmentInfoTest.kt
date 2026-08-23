package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AttachmentInfoTest {
    @Test fun `detects token with id len metadata triplet`() {
        val doc: Map<String, Any?> = mapOf(
            "_id" to "doc-1",
            "photo" to mapOf(
                "id" to "att-1",
                "len" to 12345,
                "metadata" to mapOf("type" to "image/png"),
            ),
        )
        val found = AttachmentInfo.detectTokens(doc)
        assertEquals(1, found.size)
        val a = found.first()
        assertEquals("att-1", a.id)
        assertEquals(12_345L, a.len)
        assertEquals("photo", a.fieldName)
        assertEquals("image/png", a.metadata["type"])
    }
    @Test fun `ignores fields that are partial matches`() {
        val doc: Map<String, Any?> = mapOf(
            "photo" to mapOf("id" to "x", "len" to 0),  // no metadata
            "name" to "regular",
        )
        assertTrue(AttachmentInfo.detectTokens(doc).isEmpty())
    }
    @Test fun `handles len as long and as int`() {
        val asInt = mapOf("a" to mapOf("id" to "1", "len" to 5, "metadata" to mapOf<String, String>()))
        val asLong = mapOf("a" to mapOf("id" to "1", "len" to 5L, "metadata" to mapOf<String, String>()))
        assertEquals(5L, AttachmentInfo.detectTokens(asInt).first().len)
        assertEquals(5L, AttachmentInfo.detectTokens(asLong).first().len)
    }
}
