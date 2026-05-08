import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Tests the bounded, indexed event storage used by `MainStudioView.ViewModel`
/// to back the Observers tab.
///
/// Covers:
/// - FIFO eviction at the 500-event capacity
/// - Index integrity (eventsById stays in sync with the events array)
/// - Per-observer removal
/// - Bulk append + batch eviction
@Suite("ObservableEventStore Tests")
struct ObservableEventStoreTests {
    // MARK: - Helpers

    private func makeEvent(
        id: String = UUID().uuidString,
        observerId: String = "observer-A"
    ) -> DittoObserveEvent {
        DittoObserveEvent(id: id, observeId: observerId)
    }

    // MARK: - Capacity

    @Test(.tags(.model, .fast))
    func `Append below capacity retains every event`() {
        // ARRANGE
        var store = ObservableEventStore()

        // ACT
        for index in 0 ..< 100 {
            store.append(makeEvent(id: "evt-\(index)"))
        }

        // ASSERT
        #expect(store.count == 100)
        #expect(store.eventsById.count == 100)
        #expect(store.event(id: "evt-0")?.id == "evt-0")
        #expect(store.event(id: "evt-99")?.id == "evt-99")
    }

    @Test(.tags(.model, .fast))
    func `Append beyond capacity evicts oldest entries FIFO`() {
        // ARRANGE
        var store = ObservableEventStore()
        let overshoot = 50

        // ACT — push 550 events; capacity is 500
        for index in 0 ..< (ObservableEventStore.capacity + overshoot) {
            store.append(makeEvent(id: "evt-\(index)"))
        }

        // ASSERT
        #expect(store.count == ObservableEventStore.capacity)
        #expect(store.eventsById.count == ObservableEventStore.capacity)

        // The first 50 events should be evicted
        for index in 0 ..< overshoot {
            #expect(
                store.event(id: "evt-\(index)") == nil,
                "Expected evt-\(index) to have been evicted"
            )
        }
        // The latest event should still be present and at the tail
        #expect(store.event(id: "evt-549")?.id == "evt-549")
        #expect(store.events.last?.id == "evt-549")
        // The first retained event should be evt-50 (the oldest survivor)
        #expect(store.events.first?.id == "evt-50")
    }

    @Test(.tags(.model, .fast))
    func `Bulk append evicts in a single pass`() {
        // ARRANGE
        var store = ObservableEventStore()
        let batch = (0 ..< 700).map { makeEvent(id: "evt-\($0)") }

        // ACT
        store.append(contentsOf: batch)

        // ASSERT — exactly 500 retained, oldest 200 evicted
        #expect(store.count == ObservableEventStore.capacity)
        #expect(store.eventsById.count == ObservableEventStore.capacity)
        #expect(store.events.first?.id == "evt-200")
        #expect(store.events.last?.id == "evt-699")
        #expect(store.event(id: "evt-199") == nil)
        #expect(store.event(id: "evt-200")?.id == "evt-200")
    }

    // MARK: - Lookup

    @Test(.tags(.model, .fast))
    func `event(id:) returns nil for unknown id`() {
        // ARRANGE
        var store = ObservableEventStore()
        store.append(makeEvent(id: "known"))

        // ASSERT
        #expect(store.event(id: "unknown") == nil)
    }

    @Test(.tags(.model, .fast))
    func `event(id:) is consistent with the events array`() {
        // ARRANGE
        var store = ObservableEventStore()
        for index in 0 ..< 10 {
            store.append(makeEvent(id: "evt-\(index)"))
        }

        // ASSERT — each indexed event matches the dict-resolved event
        for event in store.events {
            #expect(store.event(id: event.id)?.id == event.id)
        }
    }

    // MARK: - Per-observer removal

    @Test(.tags(.model, .fast))
    func `remove(observerId:) deletes only that observer's events`() {
        // ARRANGE
        var store = ObservableEventStore()
        store.append(makeEvent(id: "a-1", observerId: "A"))
        store.append(makeEvent(id: "b-1", observerId: "B"))
        store.append(makeEvent(id: "a-2", observerId: "A"))
        store.append(makeEvent(id: "b-2", observerId: "B"))

        // ACT
        store.remove(observerId: "A")

        // ASSERT
        #expect(store.count == 2)
        #expect(store.eventsById.count == 2)
        #expect(store.event(id: "a-1") == nil)
        #expect(store.event(id: "a-2") == nil)
        #expect(store.event(id: "b-1")?.id == "b-1")
        #expect(store.event(id: "b-2")?.id == "b-2")
    }

    @Test(.tags(.model, .fast))
    func `remove(observerId:) on unknown id is a no-op`() {
        // ARRANGE
        var store = ObservableEventStore()
        store.append(makeEvent(id: "a-1", observerId: "A"))
        store.append(makeEvent(id: "a-2", observerId: "A"))

        // ACT
        store.remove(observerId: "Z")

        // ASSERT
        #expect(store.count == 2)
        #expect(store.eventsById.count == 2)
    }

    // MARK: - removeAll

    @Test(.tags(.model, .fast))
    func `removeAll clears array and index`() {
        // ARRANGE
        var store = ObservableEventStore()
        for index in 0 ..< 25 {
            store.append(makeEvent(id: "evt-\(index)"))
        }

        // ACT
        store.removeAll()

        // ASSERT
        #expect(store.isEmpty)
        #expect(store.isEmpty)
        #expect(store.eventsById.isEmpty)
    }

    // MARK: - Capacity boundary

    @Test(.tags(.model, .fast))
    func `Capacity is exactly 500`() {
        #expect(ObservableEventStore.capacity == 500)
    }
}
