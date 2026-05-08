import Foundation

/// Bounded, indexed storage for `DittoObserveEvent` instances surfaced by an
/// active observer session.
///
/// Stores events as a flat ordered list (FIFO eviction) for paginated display
/// and maintains a parallel dictionary index for O(1) lookup by event id —
/// avoiding the linear scan that an unbounded array would incur on every view
/// re-render.
///
/// The capacity guards against unbounded memory growth during long-running
/// high-frequency observer sessions, which previously could leak hundreds of
/// thousands of events into the view model.
public struct ObservableEventStore {
    /// Hard cap on retained events. Oldest events are evicted FIFO when
    /// the cap is exceeded.
    public static let capacity = 500

    public private(set) var events: [DittoObserveEvent] = []
    public private(set) var eventsById: [String: DittoObserveEvent] = [:]

    public init() {}

    public var count: Int {
        events.count
    }

    public var isEmpty: Bool {
        events.isEmpty
    }

    /// O(1) lookup by event id.
    public func event(id: String) -> DittoObserveEvent? {
        eventsById[id]
    }

    /// Appends a single event and applies the FIFO eviction policy.
    public mutating func append(_ event: DittoObserveEvent) {
        events.append(event)
        eventsById[event.id] = event
        applyCapacity()
    }

    /// Appends a batch of events and applies the FIFO eviction policy once.
    public mutating func append(contentsOf newEvents: [DittoObserveEvent]) {
        guard !newEvents.isEmpty else { return }
        events.append(contentsOf: newEvents)
        for event in newEvents {
            eventsById[event.id] = event
        }
        applyCapacity()
    }

    /// Removes every event whose `observeId` matches the supplied value
    /// (used when an observer is deleted/stopped).
    public mutating func remove(observerId: String) {
        events.removeAll { event in
            if event.observeId == observerId {
                eventsById.removeValue(forKey: event.id)
                return true
            }
            return false
        }
    }

    /// Drops all stored events.
    public mutating func removeAll() {
        events.removeAll()
        eventsById.removeAll()
    }

    private mutating func applyCapacity() {
        guard events.count > Self.capacity else { return }
        let overflow = events.count - Self.capacity
        let evicted = events.prefix(overflow)
        for event in evicted {
            eventsById.removeValue(forKey: event.id)
        }
        events.removeFirst(overflow)
    }
}
