package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [QueryMetrics.indexesUsedFromExplain] — the index-usage heuristic
 * mirroring SwiftUI's `QueryExplainRecord.usedIndex` (any "index" mention in the
 * EXPLAIN output means the planner likely used an index).
 */
class QueryMetricsTest {

    @Test
    fun `plan mentioning an index yields a non-empty marker list`() {
        val plan = "{ \"plan\": { \"index\": \"idx_tasks_done\" } }"
        assertTrue(QueryMetrics.indexesUsedFromExplain(plan).isNotEmpty())
    }

    @Test
    fun `match is case-insensitive`() {
        assertTrue(QueryMetrics.indexesUsedFromExplain("{ \"INDEX_SCAN\": {} }").isNotEmpty())
    }

    @Test
    fun `full-scan plan without index mention yields empty list`() {
        val plan = "{ \"plan\": { \"operator\": \"scan\" } }"
        assertTrue(QueryMetrics.indexesUsedFromExplain(plan).isEmpty())
    }

    @Test
    fun `null blank and failure-string plans yield empty list`() {
        assertTrue(QueryMetrics.indexesUsedFromExplain(null).isEmpty())
        assertTrue(QueryMetrics.indexesUsedFromExplain("").isEmpty())
        assertTrue(QueryMetrics.indexesUsedFromExplain("No explain output").isEmpty())
        assertTrue(QueryMetrics.indexesUsedFromExplain("EXPLAIN failed: boom").isEmpty())
    }

    @Test
    fun `marker list content is a single presence marker`() {
        assertEquals(listOf("index"), QueryMetrics.indexesUsedFromExplain("uses index"))
    }
}
