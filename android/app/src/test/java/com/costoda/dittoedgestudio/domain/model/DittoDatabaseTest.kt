package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DittoDatabaseTest {

    @Test
    fun `empty factory creates default values`() {
        val db = DittoDatabase.empty()
        assertEquals(0L, db.id)
        assertEquals("", db.name)
        assertEquals("", db.databaseId)
        assertEquals(AuthMode.SERVER, db.mode)
        assertFalse(db.allowUntrustedCerts)
        assertTrue(db.isBluetoothLeEnabled)
        assertTrue(db.isLanEnabled)
        assertFalse(db.isAwdlEnabled)
        assertTrue(db.isCloudSyncEnabled)
        assertEquals("info", db.logLevel)
    }

    @Test
    fun `copy preserves all fields`() {
        val original = DittoDatabase(
            id = 1L,
            name = "TestDB",
            databaseId = "abc-123",
            mode = AuthMode.SMALL_PEERS_ONLY
        )
        val copy = original.copy(name = "Renamed")
        assertEquals(1L, copy.id)
        assertEquals("Renamed", copy.name)
        assertEquals("abc-123", copy.databaseId)
        assertEquals(AuthMode.SMALL_PEERS_ONLY, copy.mode)
    }

    @Test
    fun `equality is structural`() {
        val a = DittoDatabase(id = 1L, name = "DB", databaseId = "x")
        val b = DittoDatabase(id = 1L, name = "DB", databaseId = "x")
        assertEquals(a, b)
    }
}
