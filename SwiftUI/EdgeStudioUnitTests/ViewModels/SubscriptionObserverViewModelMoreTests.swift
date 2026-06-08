import DittoSwift
import Foundation
import Testing
@testable import Ditto_Edge_Studio

/// Additional `SubscriptionObserverViewModel` coverage beyond
/// `SubscriptionObserverViewModelTests`: inspector-tab selection, the remaining
/// editor-staging paths, observer form-save routing, selected-event lookup,
/// delete routing, the load helpers' graceful-failure contract, and QR bulk
/// import.
///
/// Store-observer registration (`registerStoreObserver` / `removeStoreObserver`)
/// and the private 100ms event-coalescing flush are NOT exercised here: they
/// require a live `Ditto` instance (the mock `DittoManager.dittoSelectedApp`
/// returns `nil`, so `registerStoreObserver` throws `InvalidStateError` before
/// any observable behaviour can be asserted). Those belong to integration tests.
@Suite("SubscriptionObserverViewModel — staging, save & delete", .serialized)
struct SubscriptionObserverViewModelMoreTests {

    // MARK: - Helper

    @MainActor
    private func makeViewModel(_ mocks: MockSet) -> SubscriptionObserverViewModel {
        SubscriptionObserverViewModel(
            dittoManager: mocks.dittoManager,
            subscriptionsRepository: mocks.subscriptionsRepository,
            observableRepository: mocks.observableRepository
        )
    }

    // MARK: - Inspector tab selection

    @Test(.tags(.fast))
    @MainActor
    func `selectInspectorTab switches to a known tab and ignores unknown names`() {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)

        // ACT — switch to "Help" (present in the default menu).
        viewModel.selectInspectorTab(named: "Help")

        // ASSERT
        #expect(viewModel.selectedObserveInspectorMenuItem.name == "Help")

        // ACT — an unknown name is a no-op.
        viewModel.selectInspectorTab(named: "NopeNotThere")

        // ASSERT — selection unchanged.
        #expect(viewModel.selectedObserveInspectorMenuItem.name == "Help")
    }

    // MARK: - Editor staging

    @Test(.tags(.fast))
    @MainActor
    func `stageSubscriptionEditor and stageObservableEditor hold the supplied instances`() {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)

        var sub = DittoSubscription.new()
        sub.name = "Existing sub"
        var obs = DittoObservable.new()
        obs.name = "Existing obs"

        // ACT
        viewModel.stageSubscriptionEditor(sub)
        viewModel.stageObservableEditor(obs)

        // ASSERT
        #expect(viewModel.editorSubscription?.name == "Existing sub")
        #expect(viewModel.editorObservable?.name == "Existing obs")
    }

    @Test(.tags(.fast))
    @MainActor
    func `stageNewObservable seeds an empty editorObservable`() {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)

        // ACT
        viewModel.stageNewObservable()

        // ASSERT
        #expect(viewModel.editorObservable != nil)
        #expect(viewModel.editorObservable?.name == "")
        #expect(viewModel.editorObservable?.query == "")
    }

    @Test(.tags(.fast))
    @MainActor
    func `formCancel clears both staged editors`() {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)
        viewModel.stageNewSubscription()
        viewModel.stageNewObservable()

        // ACT
        viewModel.formCancel()

        // ASSERT
        #expect(viewModel.editorSubscription == nil)
        #expect(viewModel.editorObservable == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `formSaveSubscription with no staged editor is a no-op`() async {
        // ARRANGE — nothing staged.
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = makeViewModel(mocks)

        // ACT
        viewModel.formSaveSubscription(name: "x", query: "y", appState: appState)

        // ASSERT — give any (non-)dispatched task a moment, then confirm
        // nothing reached the repository.
        try? await Task.sleep(for: .milliseconds(50))
        let saved = await mocks.subscriptionsRepository.savedSubscriptions
        #expect(saved.isEmpty)
        // Editor stays nil; save guard early-returned.
        #expect(viewModel.editorSubscription == nil)
    }

    // MARK: - Observer form save

    @Test(.tags(.fast))
    @MainActor
    func `formSaveObserver forwards the saved observable to the repository`() async {
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = makeViewModel(mocks)
        viewModel.stageNewObservable()

        // ACT
        viewModel.formSaveObserver(
            name: "Cars observer",
            query: "SELECT * FROM cars",
            appState: appState
        )

        // ASSERT — editor cleared synchronously, save lands async. Poll up to 1s.
        #expect(viewModel.editorObservable == nil)
        for _ in 0 ..< 100 {
            let saved = await mocks.observableRepository.savedObservables
            if !saved.isEmpty {
                #expect(saved.first?.name == "Cars observer")
                #expect(saved.first?.query == "SELECT * FROM cars")
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("formSaveObserver did not reach the repository within 1s")
    }

    // MARK: - Selected event lookup

    @Test(.tags(.fast))
    @MainActor
    func `selectedEventObject returns nil when nothing selected`() {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)

        #expect(viewModel.selectedEventId == nil)
        #expect(viewModel.selectedEventObject == nil)
    }

    @Test(.tags(.fast))
    @MainActor
    func `selectedEventObject resolves a selected id from the event store`() {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)

        // ARRANGE — push an event into the store and select it.
        var event = DittoObserveEvent.new(observeId: "obs-1")
        event.eventTime = "2026-06-07T00:00:00Z"
        viewModel.eventStore.append(event)
        viewModel.selectedEventId = event.id

        // ASSERT
        #expect(viewModel.selectedEventObject?.id == event.id)
        #expect(viewModel.selectedEventObject?.observeId == "obs-1")

        // A stale id resolves to nil.
        viewModel.selectedEventId = "does-not-exist"
        #expect(viewModel.selectedEventObject == nil)
    }

    // MARK: - Delete routing

    @Test(.tags(.fast))
    @MainActor
    func `deleteSubscription routes through the repository`() async throws {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)
        let sub = DittoSubscription.new()

        // ACT / ASSERT — should not throw with the inert mock.
        try await viewModel.deleteSubscription(sub)
    }

    @Test(.tags(.fast))
    @MainActor
    func `deleteObservable clears selection and removes events for that observer`() async throws {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)

        var obs = DittoObservable.new()
        obs.name = "ToDelete"
        viewModel.observerables = [obs]
        viewModel.selectedObservable = obs

        // Seed an event belonging to this observer and select it.
        let event = DittoObserveEvent.new(observeId: obs.id)
        viewModel.eventStore.append(event)
        viewModel.selectedEventId = event.id

        // ACT
        try await viewModel.deleteObservable(obs)

        // ASSERT — selection cleared and the observer's events were purged.
        #expect(viewModel.selectedObservable == nil)
        #expect(viewModel.selectedEventId == nil)
        #expect(viewModel.eventStore.event(id: event.id) == nil)
    }

    // MARK: - Load helpers (graceful failure contract)

    @Test(.tags(.fast))
    @MainActor
    func `loadSubscriptions and loadObservers return empty arrays from the inert mocks`() async {
        let mocks = MockSet()
        let viewModel = makeViewModel(mocks)

        // ACT
        let subs = await viewModel.loadSubscriptions(for: "db-1")
        let obs = await viewModel.loadObservers(for: "db-1")

        // ASSERT
        #expect(subs.isEmpty)
        #expect(obs.isEmpty)
    }

    // MARK: - QR bulk import

    @Test(.tags(.fast))
    @MainActor
    func `importSubscriptionsFromQR saves every item and reports progress`() async {
        let mocks = MockSet()
        let appState = AppState()
        let viewModel = makeViewModel(mocks)

        let items = [
            SubscriptionQRItem(name: "A", query: "SELECT * FROM a", args: nil),
            SubscriptionQRItem(name: "B", query: "SELECT * FROM b", args: nil)
        ]

        var progressCalls: [(Int, Int)] = []

        // ACT
        await viewModel.importSubscriptionsFromQR(items, appState: appState) { done, total in
            progressCalls.append((done, total))
        }

        // ASSERT — both items reached the repository...
        let saved = await mocks.subscriptionsRepository.savedSubscriptions
        #expect(saved.count == 2)
        #expect(saved.map(\.name).sorted() == ["A", "B"])

        // ...and progress fired once per item with the running count.
        #expect(progressCalls.count == 2)
        #expect(progressCalls.first?.0 == 1)
        #expect(progressCalls.first?.1 == 2)
        #expect(progressCalls.last?.0 == 2)

        // The VM refreshed its cached snapshot from the repository.
        #expect(viewModel.subscriptions.count == 2)
        #expect(appState.error == nil)
    }
}

// MARK: - ObservableEventStore model coverage

/// Pure-model tests for `ObservableEventStore` — the indexed, capacity-bounded
/// backing store the observer VM mutates directly.
@Suite("ObservableEventStore — indexing & eviction", .serialized)
struct ObservableEventStoreModelTests {
    @Test(.tags(.model, .fast))
    func `append indexes events for O(1) lookup`() {
        // ARRANGE
        var store = ObservableEventStore()
        let event = DittoObserveEvent.new(observeId: "o1")

        // ACT
        store.append(event)

        // ASSERT
        #expect(store.count == 1)
        #expect(store.isEmpty == false)
        #expect(store.event(id: event.id)?.observeId == "o1")
    }

    @Test(.tags(.model, .fast))
    func `remove by observerId drops only matching events`() {
        // ARRANGE
        var store = ObservableEventStore()
        let keep = DittoObserveEvent.new(observeId: "keep")
        let drop = DittoObserveEvent.new(observeId: "drop")
        store.append(contentsOf: [keep, drop])

        // ACT
        store.remove(observerId: "drop")

        // ASSERT
        #expect(store.count == 1)
        #expect(store.event(id: keep.id) != nil)
        #expect(store.event(id: drop.id) == nil)
    }

    @Test(.tags(.model, .fast))
    func `appending past capacity evicts the oldest events FIFO`() {
        // ARRANGE — fill beyond the hard cap.
        var store = ObservableEventStore()
        let overflow = ObservableEventStore.capacity + 5
        var firstFew: [DittoObserveEvent] = []
        for index in 0 ..< overflow {
            let event = DittoObserveEvent.new(observeId: "o\(index)")
            if index < 5 { firstFew.append(event) }
            store.append(event)
        }

        // ASSERT — count is clamped and the earliest events were evicted.
        #expect(store.count == ObservableEventStore.capacity)
        for evicted in firstFew {
            #expect(store.event(id: evicted.id) == nil)
        }
    }

    @Test(.tags(.model, .fast))
    func `removeAll clears events and the index`() {
        // ARRANGE
        var store = ObservableEventStore()
        store.append(DittoObserveEvent.new(observeId: "o1"))

        // ACT
        store.removeAll()

        // ASSERT
        #expect(store.isEmpty)
        #expect(store.count == 0)
    }
}
