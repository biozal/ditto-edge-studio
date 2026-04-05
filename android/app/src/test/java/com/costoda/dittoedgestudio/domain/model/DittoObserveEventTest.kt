package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DittoObserveEventTest {

    @Test
    fun `default values are correct`() {
        val event = DittoObserveEvent(observeId = "obs1")
        assertTrue(event.id.isNotBlank())
        assertEquals("obs1", event.observeId)
        assertTrue(event.data.isEmpty())
        assertTrue(event.insertIndexes.isEmpty())
        assertTrue(event.updatedIndexes.isEmpty())
        assertTrue(event.deletedIndexes.isEmpty())
        assertTrue(event.movedIndexes.isEmpty())
        assertTrue(event.eventTime.isEmpty())
    }

    @Test
    fun `getInsertedData returns documents at insert indexes`() {
        val event = DittoObserveEvent(
            observeId = "obs1",
            data = listOf("""{"_id":"a"}""", """{"_id":"b"}""", """{"_id":"c"}"""),
            insertIndexes = listOf(0, 2),
            eventTime = "2026-04-03T12:00:00Z",
        )
        val inserted = event.getInsertedData()
        assertEquals(2, inserted.size)
        assertEquals("""{"_id":"a"}""", inserted[0])
        assertEquals("""{"_id":"c"}""", inserted[1])
    }

    @Test
    fun `getUpdatedData returns documents at updated indexes`() {
        val event = DittoObserveEvent(
            observeId = "obs1",
            data = listOf("""{"_id":"a"}""", """{"_id":"b"}"""),
            updatedIndexes = listOf(1),
            eventTime = "2026-04-03T12:00:00Z",
        )
        val updated = event.getUpdatedData()
        assertEquals(1, updated.size)
        assertEquals("""{"_id":"b"}""", updated[0])
    }

    @Test
    fun `getInsertedData handles out-of-bounds indexes gracefully`() {
        val event = DittoObserveEvent(
            observeId = "obs1",
            data = listOf("""{"_id":"a"}"""),
            insertIndexes = listOf(0, 5),
            eventTime = "2026-04-03T12:00:00Z",
        )
        val inserted = event.getInsertedData()
        assertEquals(1, inserted.size)
        assertEquals("""{"_id":"a"}""", inserted[0])
    }
}
