package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QueryAdviceExtractorTest {

    private val sampleRow = mapOf<String, Any?>(
        "advice" to mapOf(
            "statement" to "SELECT * FROM atest WHERE e=1\n",
            "suggestedIndexes" to listOf(
                mapOf(
                    "collection" to "atest",
                    "reason" to "equality predicates on `e`",
                    "statement" to "CREATE INDEX IF NOT EXISTS adv_atest_e ON default:`atest` (`e` ASC)",
                ),
            ),
        ),
    )

    @Test
    fun `extracts statement and one suggestion`() {
        val advice = QueryAdviceExtractor.extract(listOf(sampleRow))!!
        assertTrue(advice.statement.startsWith("SELECT * FROM atest"))
        assertEquals(1, advice.suggestions.size)
        val s = advice.suggestions[0]
        assertEquals("atest", s.collection)
        assertEquals("equality predicates on `e`", s.reason)
        assertEquals("CREATE INDEX IF NOT EXISTS adv_atest_e ON default:`atest` (`e` ASC)", s.statement)
    }

    @Test
    fun `outcome carried when nothing to advise`() {
        val advice = QueryAdviceExtractor.extract(
            listOf(mapOf("advice" to mapOf("statement" to "SELECT * FROM atest", "outcome" to "no keys to advise on"))),
        )!!
        assertTrue(advice.suggestions.isEmpty())
        assertEquals("no keys to advise on", advice.outcome)
    }

    @Test
    fun `nil for non-ADVISE rows`() {
        assertNull(QueryAdviceExtractor.extract(emptyList()))
        assertNull(QueryAdviceExtractor.extract(listOf(mapOf("_id" to "a"))))
    }

    @Test
    fun `merges across rows and drops incomplete suggestions`() {
        val partial = mapOf<String, Any?>(
            "advice" to mapOf(
                "suggestedIndexes" to listOf(
                    mapOf("collection" to "onlycollection", "reason" to "no statement — dropped"),
                    mapOf(
                        "collection" to "good",
                        "reason" to "",
                        "statement" to "CREATE INDEX IF NOT EXISTS adv_good_x ON default:`good` (`x` ASC)",
                    ),
                ),
            ),
        )
        val second = mapOf<String, Any?>("advice" to mapOf("statement" to "SELECT * FROM good WHERE x=1"))
        val advice = QueryAdviceExtractor.extract(listOf(partial, second))!!
        assertEquals("SELECT * FROM good WHERE x=1", advice.statement)
        assertEquals(1, advice.suggestions.size)
        assertEquals("good", advice.suggestions[0].collection)
    }

    @Test
    fun `statement guards`() {
        assertTrue(DqlStatements.isSelectStatement("SELECT * FROM t"))
        assertTrue(DqlStatements.isSelectStatement("  select * from t"))
        assertFalse(DqlStatements.isSelectStatement("SELECTOR * FROM t"))
        assertFalse(DqlStatements.isSelectStatement(""))
        assertTrue(DqlStatements.isAdviseStatement("ADVISE SELECT * FROM t"))
        assertTrue(DqlStatements.isAdviseStatement(" advise\nSELECT * FROM t"))
        assertFalse(DqlStatements.isAdviseStatement("ADVISORY SELECT * FROM t"))
        assertFalse(DqlStatements.isAdviseStatement(""))
    }
}
