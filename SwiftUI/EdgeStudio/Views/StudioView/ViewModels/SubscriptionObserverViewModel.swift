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

    /// Database this VM was constructed for. Captured at init (i.e. at
    /// session start) so subscription saves that complete after the user
    /// switched databases carry the ORIGINAL database id — the repository
    /// refuses the write when it no longer matches the active session.
    @ObservationIgnored
    private let databaseId: String

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
        databaseId: String,
        dittoManager: any DittoManagerProtocol = DittoManager.shared,
        subscriptionsRepository: any SubscriptionsRepositoryProtocol = SubscriptionsRepository.shared,
        observableRepository: any ObservableRepositoryProtocol = ObservableRepository.shared
    ) {
        self.databaseId = databaseId
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

        // Cancel any live store observers BEFORE dropping their references.
        // Otherwise the underlying DittoStoreObserver keeps running and its
        // callback fires after teardown on a freed result, which traps.
        for observable in observerables {
            observable.storeObserver?.cancel()
        }

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
        Task { [subscriptionsRepository, databaseId] in
            do {
                try await subscriptionsRepository.saveDittoSubscription(subscription, databaseId: databaseId)
            } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                // Expected race on database switch — the repository correctly
                // refused the stale write. Log, don't alert the NEW session.
                Log.info("Subscription save skipped: \(error.message)")
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
        Task { [observableRepository, databaseId] in
            do {
                try await observableRepository.saveDittoObservable(observer, databaseId: databaseId)
            } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                // Expected race on database switch — log, don't alert.
                Log.info("Observer save skipped: \(error.message)")
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
                try await subscriptionsRepository.saveDittoSubscription(sub, databaseId: databaseId)
            } catch let error as InvalidStateError where error.isStaleSessionRefusal {
                // Expected race on database switch — log, don't alert.
                Log.info("Subscription import skipped: \(error.message)")
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

        // Capture whether the currently-selected event belongs to this observable
        // BEFORE purging events — `selectedEventObject` resolves `selectedEventId`
        // via an `eventStore` lookup, so checking it after the removal below would
        // always see `nil` and leave a stale `selectedEventId`.
        let selectedEventBelongsToObservable = selectedEventObject?.observeId == observable.id

        // remove events for the observable
        eventStore.remove(observerId: observable.id)
        pendingObservedEvents.removeAll { $0.observeId == observable.id }

        if selectedObservable?.id == observable.id {
            selectedObservable = nil
        }
        if selectedEventBelongsToObservable {
            selectedEventId = nil
        }
    }

    func deleteSubscription(_ subscription: DittoSubscription) async throws {
        try await subscriptionsRepository.removeDittoSubscription(subscription)
    }

    // MARK: - Store Observer Registration

    /// Serial background queue the Ditto SDK delivers store-observer callbacks
    /// on. `registerObserver` defaults `deliverOn:` to `.main` (verified in the
    /// SDK 5.1 swiftinterface); the per-emission JSON serialization and
    /// `DittoDiffer` diff are too heavy for the main thread, so delivery is
    /// redirected here and only the coalesced state update hops to MainActor.
    private static let storeObserverDeliveryQueue = DispatchQueue(
        label: "io.ditto.EdgeStudio.storeObserverDelivery",
        qos: .utility
    )

    /// Registers a Ditto store observer for the given observable. Events are
    /// enqueued onto `pendingObservedEvents` and flushed every 100ms onto
    /// `eventStore` so SwiftUI sees coalesced updates rather than per-event
    /// invalidations.
    func registerStoreObserver(_ observable: DittoObservable) async throws {
        guard observerables.contains(where: { $0.id == observable.id }) else {
            throw InvalidStoreState(message: "Could not find observable")
        }
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "Could not get ditto reference from manager")
        }
        // Re-lookup AFTER the await: `reset()` / `deleteObservable` can mutate
        // `observerables` while this call was suspended, so an index captured
        // before the await may be out of range or point at the wrong row.
        // `registerObserver` below is synchronous, so this index stays valid
        // through the assignment at the end of the function.
        guard let index = observerables.firstIndex(where: { $0.id == observable.id }) else {
            throw InvalidStoreState(message: "Observable was removed while registering")
        }
        if observerables[index].storeObserver != nil {
            throw InvalidStoreState(message: "Observer already registered")
        }

        // if you activate an observable it's instantly selected
        selectedObservable = observable

        // used for calculating the diffs
        let dittoDiffer = DittoDiffer()

        // The observer callback is delivered on `Self.storeObserverDeliveryQueue`
        // (a dedicated serial background queue) via `deliverOn:` — NOT on the
        // main thread, which is the SDK default. Build the event from the
        // results synchronously on that queue, then hop to the MainActor to
        // mutate @Observable view-model state.
        let observableId = observable.id
        let observer = try ditto.store.registerObserver(
            query: observable.query,
            deliverOn: Self.storeObserverDeliveryQueue
        ) { [weak self] results in
            // Defensive guard: only proceed if the view model is still alive.
            // The callback can fire on a later emission after the observer
            // should have stopped (teardown / orphaned observer); processing a
            // stale result then traps. Bail instead of crashing.
            guard self != nil else { return }

            // Read the result's items ONCE — they are cursors; re-accessing or
            // holding them across emissions is unsafe per the Ditto SDK.
            let items = results.items

            // required to show the end user when the event fired
            var event = DittoObserveEvent.new(observeId: observableId)

            // Extract each document's JSON FIRST, while the cursors are fresh
            // (the diff below may invalidate them). Use item.value +
            // JSONSerialization, which THROWS on a value it can't serialize and
            // is caught here — unlike item.jsonData(), which TRAPS
            // (EXC_BREAKPOINT) inside the SDK on such a document and takes down
            // the whole callback. A bad document is skipped instead of crashing.
            event.data = items.compactMap { item -> String? in
                let cleaned = item.value.compactMapValues { $0 }
                guard let data = try? JSONSerialization.data(
                    withJSONObject: cleaned,
                    options: [.fragmentsAllowed, .sortedKeys, .withoutEscapingSlashes]
                ) else {
                    return nil
                }
                return String(data: data, encoding: .utf8)
            }

            let diff = dittoDiffer.diff(items)

            event.eventTime = Date.now.ISO8601Format()

            // set diff information
            event.insertIndexes = Array(diff.insertions)
            event.deletedIndexes = Array(diff.deletions)
            event.updatedIndexes = Array(diff.updates)
            event.movedIndexes = Array(diff.moves)

            // Release the cursors now that diff + data extraction are done.
            for item in items {
                item.dematerialize()
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
