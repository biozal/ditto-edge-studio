package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class QueryResultJsonTest {

    @Test
    fun `serializes nested documents with all value kinds`() {
        val docs = listOf(
            mapOf<String, Any?>(
                "_id" to "a",
                "name" to "ford",
                "year" to 2020,
                "price" to 12.5,
                "active" to true,
                "deleted" to null,
                "tags" to listOf("x", 1),
                "meta" to mapOf("n" to "v"),
            ),
        )
        val json = queryDocumentsToJson(docs)
        assertTrue(json.startsWith("["))
        assertTrue(json.contains("\"year\": 2020"))
        assertTrue(json.contains("\"price\": 12.5"))
        assertTrue(json.contains("\"active\": true"))
        assertTrue(json.contains("\"deleted\": null"))
        assertTrue(json.contains("\"x\""))
        assertTrue(json.contains("\"n\": \"v\""))
    }

    @Test
    fun `empty list serializes as empty array`() {
        assertEquals("[]", queryDocumentsToJson(emptyList()))
    }
}
