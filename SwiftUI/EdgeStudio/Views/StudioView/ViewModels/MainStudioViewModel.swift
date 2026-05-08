import DittoSwift
import Foundation

// MARK: - MainStudioView.ViewModel (Phase 10b composition root)

extension MainStudioView {
    /// Composition root ViewModel for the studio. Holds the four
    /// domain-specific sub-VMs (`syncVM`, `queryVM`, `attachmentVM`,
    /// `subObsVM`) that own their respective state and behavior, plus the
    /// orchestration state that genuinely spans them: the selected database
    /// config, the sidebar destination, the collections list, the loading
    /// gate, and the metrics inspector.
    ///
    /// `isLoading` is owned here (not a sub-VM) because the View's detail
    /// area uses it as a single source of truth to render the load progress
    /// indicator across all destinations. Sub-VMs are stored as `var`
    /// references — never reassigned, but `var` (not `let
    /// @ObservationIgnored`) so SwiftUI bindings can chain through them
    /// (e.g. `$viewModel.queryVM.selectedQuery` for `Picker` selections).
    ///
    /// Phase 10b — see `plans/2026-05-07-pre-v1-shipping-fixes.md` and
    /// `plans/handoffs/phase-10a-complete.md`.
    @Observable
    @MainActor
    final class ViewModel {
        // MARK: - Sub-ViewModels

        //
        // Stored as `var` (not `let @ObservationIgnored`) so the parent's
        // `@Observable` macro generates getter/setter — required for SwiftUI
        // bindings to chain through (e.g. `$viewModel.queryVM.selectedQuery`
        // in a Picker selection). The references are never reassigned, so
        // there's no observation churn from the parent perspective; the
        // sub-VMs' own `@Observable` macros drive the actual property-level
        // invalidations the View depends on.

        var syncVM: SyncStatusViewModel
        var queryVM: QueryViewModel
        var attachmentVM: AttachmentViewModel
        var subObsVM: SubscriptionObserverViewModel

        // MARK: - Direct Dependencies (parent-only orchestration)

        @ObservationIgnored
        private let dittoManager: any DittoManagerProtocol
        @ObservationIgnored
        private let systemRepository: any SystemRepositoryProtocol
        @ObservationIgnored
        private let collectionsRepository: any CollectionsRepositoryProtocol
        @ObservationIgnored
        private let historyRepository: any HistoryRepositoryProtocol
        @ObservationIgnored
        private let favoritesRepository: any FavoritesRepositoryProtocol
        @ObservationIgnored
        private let observableRepository: any ObservableRepositoryProtocol
        @ObservationIgnored
        private let subscriptionsRepository: any SubscriptionsRepositoryProtocol

        // MARK: - Parent State

        var selectedApp: DittoConfigForDatabase

        var collections: [DittoCollection] = []
        var isRefreshingCollections = false

        /// Drives the detail-area `if isLoading { ProgressView } else { ... }`
        /// gate (Phase 9). MUST stay on the parent — sub-VMs report into this
        /// during initial load and the View reads it as a single source of
        /// truth.
        var isLoading = false

        // MARK: - Sidebar Destination (persisted)

        @ObservationIgnored
        private static let sidebarDestinationKey = "selectedSidebarDestination"

        var selectedSidebarDestination: SidebarDestination = .subscriptions {
            didSet {
                UserDefaults.standard.set(
                    selectedSidebarDestination.rawValue,
                    forKey: Self.sidebarDestinationKey
                )
            }
        }

        // MARK: - Metrics Inspector (parent-owned cross-cutting state)

        var metricsInspectorMenuItems: [MenuItem] = []
        var selectedMetricsInspectorMenuItem: MenuItem

        // Metrics Inspector – Prometheus export form state (ephemeral UI)
        var metricsPrometheusURLText = ""
        var metricsPrometheusIntervalText = "60"
        var metricsPrometheusStatusMessage = ""
        var metricsPrometheusIsConfigured = false

        // MARK: - Load Task

        /// Tracks the structured-concurrency task that loads initial data so
        /// `closeSelectedApp` and `deinit` can cancel it if the user closes
        /// the database mid-load (e.g. tap-and-immediately-back).
        @ObservationIgnored
        private var loadTask: Task<Void, Never>?

        // MARK: - Init

        init(
            _ dittoAppConfig: DittoConfigForDatabase,
            dittoManager: any DittoManagerProtocol = DittoManager.shared,
            queryService: any QueryServiceProtocol = QueryService.shared,
            subscriptionsRepository: any SubscriptionsRepositoryProtocol = SubscriptionsRepository.shared,
            systemRepository: any SystemRepositoryProtocol = SystemRepository.shared,
            historyRepository: any HistoryRepositoryProtocol = HistoryRepository.shared,
            favoritesRepository: any FavoritesRepositoryProtocol = FavoritesRepository.shared,
            observableRepository: any ObservableRepositoryProtocol = ObservableRepository.shared,
            collectionsRepository: any CollectionsRepositoryProtocol = CollectionsRepository.shared
        ) {
            self.dittoManager = dittoManager
            self.systemRepository = systemRepository
            self.collectionsRepository = collectionsRepository
            self.historyRepository = historyRepository
            self.favoritesRepository = favoritesRepository
            self.observableRepository = observableRepository
            self.subscriptionsRepository = subscriptionsRepository

            selectedApp = dittoAppConfig

            // Restore the last-viewed sidebar destination from UserDefaults.
            // If the stored value is unrecognized (e.g. an obsolete enum case
            // after an upgrade) we fall back to `.subscriptions`. The View
            // gates metrics destinations on `metricsEnabled` so a stale
            // persisted metrics tab can't strand the user on a hidden
            // destination.
            let storedDestination = UserDefaults.standard
                .string(forKey: Self.sidebarDestinationKey)
                .flatMap(SidebarDestination.init(rawValue:))
            selectedSidebarDestination = storedDestination ?? .subscriptions

            // Construct sub-VMs with the matching protocol subset each needs.
            syncVM = SyncStatusViewModel(
                dittoManager: dittoManager,
                systemRepository: systemRepository
            )
            queryVM = QueryViewModel(
                dittoAppConfig: dittoAppConfig,
                queryService: queryService,
                historyRepository: historyRepository,
                favoritesRepository: favoritesRepository
            )
            attachmentVM = AttachmentViewModel(queryService: queryService)
            subObsVM = SubscriptionObserverViewModel(
                dittoManager: dittoManager,
                subscriptionsRepository: subscriptionsRepository,
                observableRepository: observableRepository
            )

            // Metrics Inspector toolbar
            let metricsDocsItem = MenuItem(id: 11, name: "Docs", systemIcon: "book.closed")
            metricsInspectorMenuItems = [
                metricsDocsItem,
                MenuItem(id: 12, name: "Export", systemIcon: "arrow.up.to.line")
            ]
            selectedMetricsInspectorMenuItem = metricsDocsItem
        }

        isolated deinit {
            // Cancel the load task if the ViewModel is being deallocated mid-load
            // (e.g. user closed the database before initial hydration completed).
            // `isolated deinit` keeps this on the MainActor so we can read
            // the actor-isolated `loadTask`.
            loadTask?.cancel()
            Log.debug("MainStudioView.ViewModel deinit")
        }

        // MARK: - Load

        /// Starts the initial data load. Idempotent — calling repeatedly cancels
        /// any in-flight load and starts a fresh one. Called from the view's
        /// `.task` modifier.
        func startLoad() {
            loadTask?.cancel()
            loadTask = Task { [weak self] in
                await self?.performLoad()
            }
        }

        /// Loads all repository state for the selected database in parallel and
        /// finishes post-load setup (presence observer registration, local peer
        /// info fetch). Honors cooperative cancellation at every awaited
        /// boundary so a fast close-during-load tears down cleanly without
        /// racing the cleanup path.
        private func performLoad() async {
            isLoading = true
            defer { isLoading = false }

            let databaseId = selectedApp.databaseId

            // 1. Register all repository update callbacks. Each sub-VM owns its
            //    own callback installations; the parent only installs the
            //    collections callback (parent-owned state) and orchestrates.
            await syncVM.installCallbacks()
            await subObsVM.installCallbacks()
            await queryVM.installCallbacks()
            await collectionsRepository.setOnCollectionsUpdate { [weak self] newCollections in
                self?.collections = newCollections
            }

            guard !Task.isCancelled else { return }

            // 2. Run the five independent repository loads concurrently. Each
            //    swallows its own error so one failure can't starve the
            //    others — matches the original sequential behavior, in parallel.
            async let loadedSubscriptions = subObsVM.loadSubscriptions(for: databaseId)
            async let loadedCollections: [DittoCollection] = {
                do {
                    return try await collectionsRepository.hydrateCollections()
                } catch {
                    Log.error("Failed to load collections: \(error.localizedDescription)")
                    return []
                }
            }()
            async let loadedHistory = queryVM.loadHistory(for: databaseId)
            async let loadedFavorites = queryVM.loadFavorites(for: databaseId)
            async let loadedObservers = subObsVM.loadObservers(for: databaseId)

            let (subs, cols, hist, favs, obsv) = await (
                loadedSubscriptions,
                loadedCollections,
                loadedHistory,
                loadedFavorites,
                loadedObservers
            )

            guard !Task.isCancelled else { return }

            // Assign results across the relevant VMs.
            subObsVM.subscriptions = subs
            collections = cols
            queryVM.history = hist
            queryVM.favorites = favs
            subObsVM.observerables = obsv

            // Cross-VM bridge: pre-fill the editor with a sensible first query.
            if collections.isEmpty {
                queryVM.selectedQuery = subObsVM.subscriptions.first?.query ?? ""
            } else {
                queryVM.selectedQuery = "SELECT * FROM \(collections.first?.name ?? "")"
            }

            // 3. Start observing connections via presence graph (drives bottom status bar)
            do {
                try await syncVM.registerPresenceObserver()
            } catch {
                // Not a programming error — can happen if the database was closed before
                // this async Task completed (e.g. user switched databases quickly).
                Log.error("Failed to register connections presence observer: \(error.localizedDescription)")
            }

            // Note: sync-status observer is registered by syncTabsDetailView().onAppear
            // (which fires before this point). No eager registration needed here —
            // it caused double-registration and backpressure pipeline deadlocks.

            guard !Task.isCancelled else { return }

            // 4. Local peer info fetch (bypasses QueryService so the startup
            //    query stays out of Query Metrics).
            await syncVM.loadLocalPeerInfo()
        }

        // MARK: - Close / Cleanup

        func closeSelectedApp() async {
            let closeStart = CFAbsoluteTimeGetCurrent()
            Log.info("[Close] Starting database close")

            // 0. Cancel any in-flight initial load so its callback registrations
            //    don't race with the cleanup pass below.
            loadTask?.cancel()
            loadTask = nil

            // 1. Invalidate observer sessions FIRST so in-flight callbacks bail early
            await systemRepository.invalidateSession()
            let invalidateElapsed = CFAbsoluteTimeGetCurrent() - closeStart
            Log.info("[Close] Session invalidated (\(String(format: "%.3f", invalidateElapsed))s)")

            // 2. Clean up UI state immediately on main actor across all sub-VMs.
            subObsVM.reset()
            collections = []
            queryVM.reset()
            syncVM.reset()
            // Note: AttachmentViewModel state is intentionally not reset here —
            // matches prior behavior where attachment progress / detected
            // attachments could survive a close. Documented for 10c review.

            let uiClearElapsed = CFAbsoluteTimeGetCurrent() - closeStart
            Log.info("[Close] UI state cleared (\(String(format: "%.3f", uiClearElapsed))s)")

            // 3. Perform heavy cleanup operations on background queue
            await performCleanupOperations()

            let totalElapsed = CFAbsoluteTimeGetCurrent() - closeStart
            Log.info("[Close] Total close time: \(String(format: "%.3f", totalElapsed))s")
        }

        private func performCleanupOperations() async {
            let cleanupStart = CFAbsoluteTimeGetCurrent()

            // Store-observer cancellation happens implicitly via the SDK when
            // `closeDittoSelectedDatabase` runs below. Explicit per-observer
            // cancellation for user-driven removal lives on
            // `SubscriptionObserverViewModel.removeStoreObserver(_:)`.

            // Capture injected repositories so the detached child tasks use the
            // (potentially mocked) instances rather than global singletons.
            let historyRepository = historyRepository
            let favoritesRepository = favoritesRepository
            let observableRepository = observableRepository
            let subscriptionsRepository = subscriptionsRepository
            let systemRepository = systemRepository
            let collectionsRepository = collectionsRepository
            let dittoManager = dittoManager

            await withTaskGroup(of: Void.self) { group in
                group.addTask(priority: .utility) {
                    // Clear repository caches
                    await historyRepository.clearCache()
                    await favoritesRepository.clearCache()
                    await observableRepository.clearCache()
                    await subscriptionsRepository.clearCache()

                    // Stop other repository observers
                    await systemRepository.stopObserver()
                    await collectionsRepository.stopObserver()

                    let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
                    Log.info("[Close:Repos] Caches cleared, observers stopped (\(String(format: "%.3f", elapsed))s)")
                }

                group.addTask(priority: .utility) {
                    // Close DittoManager selected app
                    await dittoManager.closeDittoSelectedDatabase()
                    let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
                    Log.info("[Close:DittoManager] closeDittoSelectedDatabase complete (\(String(format: "%.3f", elapsed))s)")
                }
            }

            let totalElapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
            Log.info("[Close] All cleanup operations complete (\(String(format: "%.3f", totalElapsed))s)")
        }

        // MARK: - Cross-VM Inspector Helpers

        /// Writes the JSON to the shared inspector slot, runs attachment
        /// detection, and selects the Query inspector's JSON tab. Single
        /// orchestration entry point so the View doesn't have to know which
        /// sub-VMs are involved.
        func showJsonInInspector(_ json: String) {
            queryVM.showJsonInInspector(json)
            attachmentVM.detectAttachments(in: json)
        }

        /// Same flow but selects the Observe inspector's JSON tab. Attachment
        /// detection is intentionally not triggered (matches prior behavior).
        func showJsonInObserveInspector(_ json: String) {
            queryVM.selectedJsonForInspector = json
            subObsVM.selectInspectorTab(named: "JSON")
        }

        // MARK: - Collections (parent-owned)

        @MainActor
        func refreshCollectionCounts() async {
            guard !isRefreshingCollections else { return } // Prevent concurrent refreshes

            isRefreshingCollections = true
            defer { isRefreshingCollections = false }

            do {
                collections = try await collectionsRepository.refreshCollections()
            } catch {
                Log.error("Failed to refresh collection counts: \(error.localizedDescription)")
            }
        }
    }
}
