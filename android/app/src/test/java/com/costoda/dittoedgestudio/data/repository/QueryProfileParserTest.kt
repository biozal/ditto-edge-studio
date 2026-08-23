package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.repository.QueryProfileParser.envelopeKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QueryProfileParserTest {

    private val canonicalEnvelope: Map<String, Any?> = mapOf(
        "_id" to "e526fe68-04e9-4881-bf76-d0a582827e9b",
        "app_id" to "f5e954d9-0092-47a0-9a79-2829e767ba7b",
        "featureFlags" to "0x3a",
        "queryType" to "select",
        "requestType" to "SDK",
        "resultCount" to 1,
        "state" to "completed",
        "text" to "PROFILE SELECT * FROM tasks LIMIT 1",
        "times" to mapOf(
            "elapsed" to 1_294_166,
            "parse" to 49_834,
            "plan" to 32_167,
            "start" to "2026-05-26T20:59:21.310-05:00",
        ),
        "plan" to mapOf(
            "#operator" to "sequence",
            "children" to listOf(
                mapOf(
                    "#operator" to "scan",
                    "#stats" to mapOf(
                        "documentsOut" to 1,
                        "phaseTimes" to mapOf("exec" to 209, "recv" to 990_459, "send" to 61_500),
                    ),
                    "collection" to "tasks",
                    "datasource" to "default",
                ),
                mapOf(
                    "#operator" to "limit",
                    "#stats" to mapOf(
                        "documentsIn" to 2,
                        "documentsOut" to 1,
                        "phaseTimes" to mapOf("exec" to 2_083, "send" to 6_584),
                    ),
                    "limit" to 1,
                ),
            ),
        ),
    )

    private val wrappedItem: Map<String, Any?> = mapOf(envelopeKey to canonicalEnvelope)

    @Test
    fun `parseItem returns null for normal user document`() {
        val item = mapOf("_id" to "doc-1", "name" to "x")
        assertNull(QueryProfileParser.parseItem(item))
    }

    @Test
    fun `parseItem accepts wrapped envelope`() {
        val profile = QueryProfileParser.parseItem(wrappedItem)
        assertNotNull(profile)
        assertEquals("e526fe68-04e9-4881-bf76-d0a582827e9b", profile!!.id)
        assertEquals("select", profile.queryType)
        assertEquals("SDK", profile.requestType)
        assertEquals(1, profile.resultCount)
        assertEquals("completed", profile.state)
        assertEquals("PROFILE SELECT * FROM tasks LIMIT 1", profile.text)
        assertEquals(1_294_166L, profile.times.elapsedNs)
        assertEquals(49_834L, profile.times.parseNs)
        assertEquals(32_167L, profile.times.planNs)
        assertEquals("2026-05-26T20:59:21.310-05:00", profile.times.startISO)
    }

    @Test
    fun `parseItem accepts bare envelope without ~request_profile wrapper`() {
        val profile = QueryProfileParser.parseItem(canonicalEnvelope)
        assertNotNull(profile)
        assertEquals("e526fe68-04e9-4881-bf76-d0a582827e9b", profile!!.id)
    }

    @Test
    fun `operator tree preserves order and stats`() {
        val profile = QueryProfileParser.parseItem(wrappedItem)!!
        assertEquals("sequence", profile.plan.name)
        assertEquals(2, profile.plan.children.size)
        val scan = profile.plan.children[0]
        assertEquals("scan", scan.name)
        assertEquals(1, scan.stats?.documentsOut)
        assertEquals(209L, scan.stats?.execNs)
        assertEquals(990_459L, scan.stats?.recvNs)
        assertEquals(61_500L, scan.stats?.sendNs)
        // operator-specific attributes preserved in insertion order
        assertEquals(listOf("collection" to "tasks", "datasource" to "default"), scan.attributes)
        val limit = profile.plan.children[1]
        assertEquals("limit", limit.name)
        assertEquals(2, limit.stats?.documentsIn)
    }

    @Test
    fun `partitionItems splits user docs from profile`() {
        val items: List<Map<String, Any?>> = listOf(
            mapOf("_id" to "doc-1", "name" to "x"),
            mapOf("_id" to "doc-2", "name" to "y"),
            wrappedItem,
        )
        val (docs, profile) = QueryProfileParser.partition(items)
        assertEquals(2, docs.size)
        assertNotNull(profile)
        assertTrue(docs.none { it.containsKey(envelopeKey) })
    }

    @Test
    fun `partitionItems with no profile returns all docs + null`() {
        val items: List<Map<String, Any?>> = listOf(mapOf("_id" to "a"), mapOf("_id" to "b"))
        val (docs, profile) = QueryProfileParser.partition(items)
        assertEquals(2, docs.size)
        assertNull(profile)
    }

    @Test
    fun `parseItem returns null when plan missing`() {
        val malformed = mapOf(envelopeKey to canonicalEnvelope.minus("plan"))
        assertNull(QueryProfileParser.parseItem(malformed))
    }

    @Test
    fun `subtreeExecNs sums match canonical fixture`() {
        val profile = QueryProfileParser.parseItem(wrappedItem)!!
        // sequence(0) + scan(209) + limit(2083) = 2292 ns
        assertEquals(2_292L, profile.plan.subtreeExecNs)
    }
}
