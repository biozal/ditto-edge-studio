package com.costoda.dittoedgestudio.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [toSortedPrettyJson] — the EXPLAIN-output serializer used for
 * Query Metrics records (mirrors SwiftUI's prettyPrinted + sortedKeys JSON).
 */
class ToSortedPrettyJsonTest {

    @Test
    fun `flat map is pretty-printed with sorted keys`() {
        val out = toSortedPrettyJson(mapOf("b" to 2, "a" to 1))
        assertEquals("{\n  \"a\": 1,\n  \"b\": 2\n}", out)
    }

    @Test
    fun `nested maps and lists are indented recursively`() {
        val out = toSortedPrettyJson(
            mapOf("plan" to mapOf("ops" to listOf("scan", "seek")), "ms" to 3),
        )
        assertEquals(
            """
            {
              "ms": 3,
              "plan": {
                "ops": [
                  "scan",
                  "seek"
                ]
              }
            }
            """.trimIndent(),
            out,
        )
    }

    @Test
    fun `nulls booleans and strings serialize as JSON literals`() {
        val out = toSortedPrettyJson(mapOf("n" to null, "f" to false, "s" to "x"))
        assertEquals("{\n  \"f\": false,\n  \"n\": null,\n  \"s\": \"x\"\n}", out)
    }

    @Test
    fun `empty containers and top-level scalars`() {
        assertEquals("{}", toSortedPrettyJson(emptyMap<String, Any?>()))
        assertEquals("[]", toSortedPrettyJson(emptyList<Any?>()))
        assertEquals("null", toSortedPrettyJson(null))
    }

    @Test
    fun `strings with quotes are escaped`() {
        val out = toSortedPrettyJson(mapOf("q" to "say \"hi\""))
        assertEquals("{\n  \"q\": \"say \\\"hi\\\"\"\n}", out)
    }
}
