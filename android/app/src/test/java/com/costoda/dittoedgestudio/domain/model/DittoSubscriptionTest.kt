package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

class DittoSubscriptionTest {

    @Test
    fun `default values are empty strings and zero id`() {
        val sub = DittoSubscription()
        assertEquals(0L, sub.id)
        assertEquals("", sub.databaseId)
        assertEquals("", sub.name)
        assertEquals("", sub.query)
    }

    @Test
    fun `equality is structural`() {
        val a = DittoSubscription(id = 1L, databaseId = "db1", name = "Sub", query = "SELECT *")
        val b = DittoSubscription(id = 1L, databaseId = "db1", name = "Sub", query = "SELECT *")
        assertEquals(a, b)
    }

    @Test
    fun `copy updates specified field only`() {
        val original = DittoSubscription(id = 1L, databaseId = "db1", name = "Sub", query = "SELECT *")
        val updated = original.copy(query = "SELECT _id")
        assertEquals("SELECT _id", updated.query)
        assertEquals("Sub", updated.name)
    }
}
