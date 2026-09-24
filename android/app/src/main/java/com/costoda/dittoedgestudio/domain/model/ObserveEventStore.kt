package com.costoda.dittoedgestudio.domain.model

/**
 * Bounded, ordered store of [DittoObserveEvent]s captured by active store observers.
 *
 * Parity port of the SwiftUI `ObservableEventStore`: events are in-memory only,
 * hard-capped at [DEFAULT_CAPACITY] with FIFO eviction of the oldest events, and
 * indexed by id for O(1) lookup. Not thread-safe by itself — all access is
 * confined to the owning session's coroutine context (see `StudioSession`).
 */
class ObserveEventStore(private val capacity: Int = DEFAULT_CAPACITY) {

    private val eventList = ArrayList<DittoObserveEvent>()
    private val eventsById = LinkedHashMap<String, DittoObserveEvent>()

    /** Events in capture order (oldest first). Returns a snapshot copy. */
    val events: List<DittoObserveEvent> get() = eventList.toList()

    val size: Int get() = eventList.size

    fun event(id: String): DittoObserveEvent? = eventsById[id]

    fun append(event: DittoObserveEvent) {
        eventList.add(event)
        eventsById[event.id] = event
        applyCapacity()
    }

    fun appendAll(newEvents: List<DittoObserveEvent>) {
        if (newEvents.isEmpty()) return
        eventList.addAll(newEvents)
        newEvents.forEach { eventsById[it.id] = it }
        applyCapacity()
    }

    /** Purges every event belonging to [observerId]. Unknown ids are a no-op. */
    fun removeEventsForObserver(observerId: String) {
        val removed = eventList.filter { it.observeId == observerId }
        if (removed.isEmpty()) return
        eventList.removeAll(removed.toSet())
        removed.forEach { eventsById.remove(it.id) }
    }

    fun clear() {
        eventList.clear()
        eventsById.clear()
    }

    private fun applyCapacity() {
        while (eventList.size > capacity) {
            val evicted = eventList.removeAt(0)
            eventsById.remove(evicted.id)
        }
    }

    companion object {
        /** Hard cap matching the SwiftUI `ObservableEventStore.capacity`. */
        const val DEFAULT_CAPACITY = 500
    }
}
