import DittoSwift
import Foundation

/// Owns subscriptions, observers, observed-event state, and the editor staging
/// shared by the FAB and empty-state CTAs. Sub-VM of `MainStudioView.ViewModel`.
///
/// Phase 10b extraction. Observer-event coalescing (100ms flush window) is
/// preserved from the prior god-VM. The View struct's
/// `presentNewSubscriptionEditor()` / `presentNewObserverEditor()` now delegate
/// to `stageNewSubscription()` / `stageNewObservable()` here so empty-state
/// CTAs and the FAB share a single VM-owned creation path.
@Observable
@MainActor
final class SubscriptionObserverViewModel {
    // MARK: - Injected Dependencies

    @ObservationIgnored
    private let dittoManager: any DittoManagerProtocol
    @ObservationIgnored
    private let subscriptionsRepository: any SubscriptionsRepositoryProtocol
    @ObservationIgnored
    private let observableRepository: any ObservableRepositoryProtocol

    // MARK: - State

    var subscriptions: [DittoSubscription] = []
    var observerables: [DittoObservable] = []

    var selectedObservable: DittoObservable?
    var selectedEventId: String?

    /// Editor staging — populated by `stageSubscriptionEditor` /
    /// `stageObservableEditor` (or the new-instance variants) before the View
    /// presents the editor sheet. Cleared by `formCancel` and the form save
    /// callbacks.
    var editorSubscription: DittoSubscription?
    var editorObservable: DittoObservable?

    /// Drives the observer detail's "items" vs "events" toggle.
    var eventMode = "items"

    /// Stores observer-emitted events keyed by observerId for O(1) lookup.
    /// `var` is required because `ObservableEventStore` is a struct with
    /// mutating methods (`append`, `removeAll`, `remove(observerId:)`).
    var eventStore = ObservableEventStore()

    // MARK: - Inspector Menu (Observe context)

    var selectedObserveInspectorMenuItem: MenuItem
    var observeInspectorMenuItems: [MenuItem] = []

    // MARK: - Event Coalescing

    /// Coalesces high-frequency observer callbacks into a single batched
    /// SwiftUI update every ~100ms to prevent invalidation storms.
    private var pendingObservedEvents: [DittoObserveEvent] = []
    private var observedEventFlushTask: Task<Void, Never>?
    private static let observedEventFlushInterval: Duration = .milliseconds(100)

    // MARK: - Init

    init(
        dittoManager: any DittoManagerProtocol = DittoManager.shared,
        subscriptionsRepository: any SubscriptionsRepositoryProtocol = SubscriptionsRepository.shared,
        observableRepository: any ObservableRepositoryProtocol = ObservableRepository.shared
    ) {
        self.dittoManager = dittoManager
        self.subscriptionsRepository = subscriptionsRepository
        self.observableRepository = observableRepository

        let jsonObserveItem = MenuItem(id: 9, name: "JSON", systemIcon: "text.document.fill")
        observeInspectorMenuItems = [
            jsonObserveItem,
            MenuItem(id: 10, name: "Help", systemIcon: "questionmark")
        ]
        selectedObserveInspectorMenuItem = jsonObserveItem
    }

    // MARK: - Lifecycle hooks

    /// Wires repository update callbacks into this VM. Caller is responsible
    /// for ordering (callbacks installed before any user-triggered save fires).
    func installCallbacks() async {
        await observableRepository.setOnObservablesUpdate { [weak self] observables in
            Task { @MainActor [weak self] in
                self?.observerables = observables
            }
        }
        await subscriptionsRepository.setOnSubscriptionsUpdate { [weak self] newSubscriptions in
            self?.subscriptions = newSubscriptions
        }
    }

    /// Loads subscriptions for the supplied database id. Returns the snapshot
    /// so the caller can sequence assignment with sibling parallel loads.
    func loadSubscriptions(for databaseId: String) async -> [DittoSubscription] {
        do {
            return try await subscriptionsRepository.loadSubscriptions(for: databaseId)
        } catch {
            Log.error("Failed to load subscriptions: \(error.localizedDescription)")
            return []
        }
    }

    /// Loads observers for the supplied database id. Same contract as `loadSubscriptions`.
    func loadObservers(for databaseId: String) async -> [DittoObservable] {
        do {
            return try await observableRepository.loadObservers(for: databaseId)
        } catch {
            Log.error("Failed to load observers: \(error.localizedDescription)")
            return []
        }
    }

    /// Clears all subscription/observer state. Called from the parent VM's
    /// `closeSelectedApp` so the next session starts blank.
    func reset() {
        editorObservable = nil
        editorSubscription = nil
        selectedEventId = nil
        selectedObservable = nil

        subscriptions = []
        observerables = []
        cancelObservedEventFlush()
        eventStore.removeAll()
    }

    // MARK: - Inspector Menu Helpers

    /// Selects an inspector tab by name in the Observe context. No-op if the
    /// named tab isn't in the menu.
    func selectInspectorTab(named name: String) {
        if let tab = observeInspectorMenuItems.first(where: { $0.name == name }) {
            selectedObserveInspectorMenuItem = tab
        }
    }

    // MARK: - Selected Event

    /// Looks up the currently selected observer event by id from the store.
    /// Returns `nil` when nothing is selected or the id is stale.
    var selectedEventObject: DittoObserveEvent? {
        guard let selectedId = selectedEventId else { return nil }
        return eventStore.event(id: selectedId)
    }

    // MARK: - Editor Staging

    /// Stages an existing subscription for editing. The View flips
    /// `activeSheet = .editSubscription` after this returns.
    func stageSubscriptionEditor(_ subscription: DittoSubscription) {
        editorSubscription = subscription
    }

    /// Stages an existing observable for editing.
    func stageObservableEditor(_ observable: DittoObservable) {
        editorObservable = observable
    }

    /// Stages a brand-new subscription. Called by both the FAB ("Add Subscription"
    /// menu) and the empty-state CTA so both go through the same VM-owned path.
    func stageNewSubscription() {
        editorSubscription = DittoSubscription.new()
    }

    /// Stages a brand-new observable. Same single-path rationale as
    /// `stageNewSubscription`.
    func stageNewObservable() {
        editorObservable = DittoObservable.new()
    }

    // MARK: - Form Save / Cancel

    func formCancel() {
        editorSubscription = nil
        editorObservable = nil
    }

    func formSaveSubscription(name: String, query: String, appState: AppState) {
        guard var subscription = editorSubscription else { return }
        subscription.name = name
        subscription.query = query
        // Clear the editor synchronously so a fast re-open can't observe stale
        // data while the async save is still in flight.
        editorSubscription = nil
        Task { [subscriptionsRepository] in
            do {
                try await subscriptionsRepository.saveDittoSubscription(subscription)
            } catch {
                appState.setError(error)
            }
        }
    }

    func formSaveObserver(name: String, query: String, appState: AppState) {
        guard var observer = editorObservable else { return }
        observer.name = name
        observer.query = query
        // Clear the editor synchronously (see formSaveSubscription).
        editorObservable = nil
        Task { [observableRepository] in
            do {
                try await observableRepository.saveDittoObservable(observer)
            } catch {
                appState.setError(error)
            }
        }
    }

    // MARK: - Bulk Import

    /// Imports a batch of subscriptions from a QR-code payload. After the loop
    /// finishes, the cached snapshot is read on the MainActor to avoid a race
    /// between the cross-actor `onSubscriptionsUpdate` callback and the
    /// dismiss re-render.
    func importSubscriptionsFromQR(
        _ items: [SubscriptionQRItem],
        appState: AppState,
        onProgress: @escaping @MainActor (Int, Int) -> Void
    ) async {
        let total = items.count
        for (index, item) in items.enumerated() {
            var sub = DittoSubscription(id: UUID().uuidString)
            sub.name = item.name
            sub.query = item.query
            do {
                try await subscriptionsRepository.saveDittoSubscription(sub)
            } catch {
                appState.setError(error)
            }
            onProgress(index + 1, total)
        }
        subscriptions = await subscriptionsRepository.getCachedSubscriptions()
    }

    // MARK: - Delete

    func deleteObservable(_ observable: DittoObservable) async throws {
        if let storeObserver = observable.storeObserver {
            storeObserver.cancel()
        }

        try await observableRepository.removeDittoObservable(observable)

        // remove events for the observable
        eventStore.remove(observerId: observable.id)
        pendingObservedEvents.removeAll { $0.observeId == observable.id }

        if selectedObservable?.id == observable.id {
            selectedObservable = nil
        }
        if selectedEventObject?.observeId == observable.id {
            selectedEventId = nil
        }
    }

    func deleteSubscription(_ subscription: DittoSubscription) async throws {
        try await subscriptionsRepository.removeDittoSubscription(subscription)
    }

    // MARK: - Store Observer Registration

    /// Registers a Ditto store observer for the given observable. Events are
    /// enqueued onto `pendingObservedEvents` and flushed every 100ms onto
    /// `eventStore` so SwiftUI sees coalesced updates rather than per-event
    /// invalidations.
    func registerStoreObserver(_ observable: DittoObservable) async throws {
        guard let index = observerables.firstIndex(where: { $0.id == observable.id }) else {
            throw InvalidStoreState(message: "Could not find observable")
        }
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "Could not get ditto reference from manager")
        }
        if observerables[index].storeObserver != nil {
            throw InvalidStoreState(message: "Observer already registered")
        }

        // if you activate an observable it's instantly selected
        selectedObservable = observable

        // used for calculating the diffs
        let dittoDiffer = DittoDiffer()

        // Deserialize arguments from JSON string. The observer callback runs
        // on an SDK-determined thread (non-MainActor). Build the event from
        // the results synchronously, then hop to the MainActor to mutate
        // @Observable view-model state.
        let observableId = observable.id
        let observer = try ditto.store.registerObserver(
            query: observable.query
        ) { [weak self] results in
            // required to show the end user when the event fired
            var event = DittoObserveEvent.new(observeId: observableId)

            let diff = dittoDiffer.diff(results.items)

            event.eventTime = Date.now.ISO8601Format()

            // set diff information
            event.insertIndexes = Array(diff.insertions)
            event.deletedIndexes = Array(diff.deletions)
            event.updatedIndexes = Array(diff.updates)
            event.movedIndexes = Array(diff.moves)

            event.data = results.items.compactMap {
                let data = $0.jsonData()
                return String(data: data, encoding: .utf8)
            }

            let capturedEvent = event
            Task { @MainActor [weak self] in
                self?.enqueueObservedEvent(capturedEvent)
            }
        }
        observerables[index].storeObserver = observer
    }

    func removeStoreObserver(_ observable: DittoObservable) async throws {
        guard let index = observerables.firstIndex(where: { $0.id == observable.id }) else {
            throw InvalidStoreState(message: "Could not find observable")
        }
        observerables[index].storeObserver?.cancel()
        observerables[index].storeObserver = nil
        selectedEventId = nil
        cancelObservedEventFlush()
        eventStore.removeAll()
    }

    // MARK: - Event Coalescing (private)

    /// Enqueues a freshly emitted observer event onto the pending buffer
    /// and (re)schedules a flush. Coalescing across a 100ms window keeps
    /// SwiftUI from re-rendering on every individual SDK callback during
    /// high-frequency sync.
    private func enqueueObservedEvent(_ event: DittoObserveEvent) {
        pendingObservedEvents.append(event)
        guard observedEventFlushTask == nil else { return }
        observedEventFlushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.observedEventFlushInterval)
            guard let self else { return }
            flushPendingObservedEvents()
        }
    }

    private func flushPendingObservedEvents() {
        observedEventFlushTask = nil
        guard !pendingObservedEvents.isEmpty else { return }
        let batch = pendingObservedEvents
        pendingObservedEvents.removeAll(keepingCapacity: true)
        eventStore.append(contentsOf: batch)
    }

    private func cancelObservedEventFlush() {
        observedEventFlushTask?.cancel()
        observedEventFlushTask = nil
        pendingObservedEvents.removeAll(keepingCapacity: false)
    }
}
