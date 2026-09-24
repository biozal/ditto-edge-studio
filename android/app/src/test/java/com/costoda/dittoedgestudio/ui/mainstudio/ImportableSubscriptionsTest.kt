package com.costoda.dittoedgestudio.ui.mainstudio

import org.junit.Assert.assertEquals
import org.junit.Test

class ImportableSubscriptionsTest {
    private fun peer(id: String, vararg queries: String): Map<String, Any?> = mapOf(
        "_id" to id,
        "device_name" to "Edge Studio",
        "local_subscriptions" to mapOf("queries" to queries.map { mapOf("query" to it) }),
    )

    @Test
    fun `same query from same-name peers produces one selectable import row`() {
        val rows = importableSubscriptions(
            listOf(
                peer("peer-one", "SELECT * FROM cars"),
                peer("peer-two", " SELECT * FROM cars "),
            ),
            emptyList(),
        )
        assertEquals(listOf("SELECT * FROM cars"), rows.map { it.query })
    }

    @Test
    fun `different queries remain independently selectable even with shared names`() {
        val rows = importableSubscriptions(
            listOf(peer("one", "SELECT * FROM cars", "SELECT * FROM trucks", "SELECT * FROM cars")),
            emptyList(),
        )
        assertEquals(listOf("SELECT * FROM cars", "SELECT * FROM trucks"), rows.map { it.query })
        assertEquals(rows.size, rows.map { it.query }.distinct().size)
    }
}
