package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DittoQueryHistoryTest {

    @Test
    fun `defaults are correct`() {
        val before = System.currentTimeMillis()
        val item = DittoQueryHistory()
        val after = System.currentTimeMillis()
        assertEquals(0L, item.id)
        assertEquals("", item.databaseId)
        assertEquals("", item.query)
        assertTrue(item.createdDate in before..after)
    }

    @Test
    fun `equality is structural`() {
        val a = DittoQueryHistory(id = 1L, databaseId = "db", query = "SELECT *", createdDate = 1000L)
        val b = DittoQueryHistory(id = 1L, databaseId = "db", query = "SELECT *", createdDate = 1000L)
        assertEquals(a, b)
    }

    @Test
    fun `copy updates specified field`() {
        val original = DittoQueryHistory(id = 1L, databaseId = "db", query = "SELECT *", createdDate = 1000L)
        val updated = original.copy(query = "SELECT _id")
        assertEquals("SELECT _id", updated.query)
        assertEquals(1000L, updated.createdDate)
    }
}
