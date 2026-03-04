package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test

class DittoObservableTest {

    @Test
    fun `defaults are correct`() {
        val obs = DittoObservable()
        assertEquals(0L, obs.id)
        assertEquals("", obs.databaseId)
        assertEquals("", obs.name)
        assertEquals("", obs.query)
        assertFalse(obs.isActive)
        assertNull(obs.lastUpdated)
    }

    @Test
    fun `equality is structural`() {
        val a = DittoObservable(id = 2L, databaseId = "db", name = "Obs", query = "SELECT *", isActive = true, lastUpdated = 100L)
        val b = DittoObservable(id = 2L, databaseId = "db", name = "Obs", query = "SELECT *", isActive = true, lastUpdated = 100L)
        assertEquals(a, b)
    }
}
