package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Port of the SwiftUI `ObservableEventStoreTests` / `ObservableEventStoreModelTests`
 * behaviors: id indexing, per-observer removal, FIFO capacity eviction, clear.
 */
class ObserveEventStoreTest {

    private fun event(observeId: String = "obs1") = DittoObserveEvent(observeId = observeId)

    @Test
    fun `append adds events in order and indexes by id`() {
        val store = ObserveEventStore()
        val a = event()
        val b = event()
        store.append(a)
        store.append(b)
        assertEquals(listOf(a, b), store.events)
        assertSame(a, store.event(a.id))
        assertSame(b, store.event(b.id))
    }

    @Test
    fun `appendAll appends in bulk and indexes every event`() {
        val store = ObserveEventStore()
        val batch = (1..5).map { event() }
        store.appendAll(batch)
        assertEquals(batch, store.events)
        batch.forEach { assertSame(it, store.event(it.id)) }
    }

    @Test
    fun `appendAll with empty list is a no-op`() {
        val store = ObserveEventStore()
        store.appendAll(emptyList())
        assertTrue(store.events.isEmpty())
    }

    @Test
    fun `exactly at capacity retains all events`() {
        val store = ObserveEventStore()
        val batch = (1..ObserveEventStore.DEFAULT_CAPACITY).map { event() }
        store.appendAll(batch)
        assertEquals(ObserveEventStore.DEFAULT_CAPACITY, store.size)
        assertEquals(batch, store.events)
    }

    @Test
    fun `overflow evicts oldest events FIFO and keeps id index consistent`() {
        val store = ObserveEventStore()
        val overflow = 5
        val batch = (1..ObserveEventStore.DEFAULT_CAPACITY + overflow).map { event() }
        store.appendAll(batch)

        // Oldest `overflow` events evicted; newest 500 retained in order.
        val expected = batch.drop(overflow)
        assertEquals(expected, store.events)
        batch.take(overflow).forEach { assertNull(store.event(it.id)) }
        expected.forEach { assertSame(it, store.event(it.id)) }
    }

    @Test
    fun `single-append overflow evicts oldest one at a time`() {
        val store = ObserveEventStore(capacity = 3)
        val first = event()
        store.append(first)
        val rest = (1..3).map { event() }
        rest.forEach { store.append(it) }
        assertEquals(rest, store.events)
        assertNull(store.event(first.id))
    }

    @Test
    fun `removeEventsForObserver purges only that observer's events`() {
        val store = ObserveEventStore()
        val obs1 = (1..3).map { event("obs1") }
        val obs2 = (1..2).map { event("obs2") }
        store.appendAll(obs1 + obs2)

        store.removeEventsForObserver("obs1")

        assertEquals(obs2, store.events)
        obs1.forEach { assertNull(store.event(it.id)) }
        obs2.forEach { assertSame(it, store.event(it.id)) }
    }

    @Test
    fun `removeEventsForObserver with unknown id is a no-op`() {
        val store = ObserveEventStore()
        val a = event()
        store.append(a)
        store.removeEventsForObserver("nope")
        assertEquals(listOf(a), store.events)
        assertSame(a, store.event(a.id))
    }

    @Test
    fun `clear empties events and index`() {
        val store = ObserveEventStore()
        val a = event()
        store.appendAll(listOf(a, event()))
        store.clear()
        assertTrue(store.events.isEmpty())
        assertEquals(0, store.size)
        assertNull(store.event(a.id))
    }

    @Test
    fun `event lookup with unknown id returns null`() {
        val store = ObserveEventStore()
        store.append(event())
        assertNull(store.event("unknown-id"))
    }
}
