import DittoSwift
import Foundation

/// Owns sync-related state for the studio: peer status grid, transport
/// connection counts, the local peer's identity, and the sync on/off toggle.
///
/// Lives as a sub-ViewModel of `MainStudioView.ViewModel`; the parent stores it
/// behind `@ObservationIgnored` so SwiftUI tracks property reads on the child
/// directly (`viewModel.syncVM.syncStatusItems`) rather than through the parent.
///
/// Phase 10b extraction — see `plans/2026-05-07-pre-v1-shipping-fixes.md`.
@Observable
@MainActor
final class SyncStatusViewModel {
    // MARK: - Injected Dependencies

    @ObservationIgnored
    private let dittoManager: any DittoManagerProtocol
    @ObservationIgnored
    private let systemRepository: any SystemRepositoryProtocol
    /// Injected rather than read from `.shared` so this stays unit-testable; production
    /// always gets the process-wide instance the `DittoManager` funnels publish to.
    @ObservationIgnored
    private let syncRuntime: SyncRuntimeState

    // MARK: - State

    /// Peers currently visible via presence graph + sync status. Populated by
    /// the SystemRepository sync-status callback installed in `installCallbacks`.
    var syncStatusItems: [SyncStatusInfo] = []

    /// Drives the toolbar sync indicator and `toggleSync` semantics.
    ///
    /// **Derived, not stored.** This used to be a `Bool` defaulting to `true` "because
    /// hydration starts sync", written only by `toggleSync` and `reset()`. That made it a
    /// guess, and it disagreed with reality whenever sync stopped by any other route — a
    /// failed restart after a transport change, a failed system-settings reset, or a
    /// silent no-op start. The indicator showed green over stopped sync, and the first
    /// recovery tap took the *stop* branch, so it took two taps to restart.
    ///
    /// It now reflects `SyncRuntimeState`, which only the two `DittoManager` funnels write
    /// and only after the SDK call they wrap has actually returned.
    var isSyncEnabled: Bool {
        syncRuntime.isRunning
    }

    /// Live transport connection counts from the presence observer.
    var connectionsByTransport: ConnectionsByTransport = .empty

    // MARK: - Local Peer Identity

    var localPeerDeviceName: String?
    var localPeerSDKLanguage: String?
    var localPeerSDKPlatform: String?
    var localPeerSDKVersion: String?

    // MARK: - Init

    init(
        dittoManager: any DittoManagerProtocol = DittoManager.shared,
        systemRepository: any SystemRepositoryProtocol = SystemRepository.shared,
        syncRuntime: SyncRuntimeState = .shared
    ) {
        self.dittoManager = dittoManager
        self.systemRepository = systemRepository
        self.syncRuntime = syncRuntime
    }

    // MARK: - Lifecycle hooks (called from parent's performLoad)

    /// Registers the SystemRepository callbacks that drive `syncStatusItems`
    /// and `connectionsByTransport`. Caller (parent VM's `performLoad`) is
    /// responsible for ordering this before `registerPresenceObserver` so
    /// callbacks are wired before the first SDK emission.
    func installCallbacks() async {
        await systemRepository.setOnSyncStatusUpdate { [weak self] statusItems, completion in
            Task { @MainActor [weak self] in
                self?.mergeStatusItems(statusItems)

                // CRITICAL: signal completion AFTER the UI update dispatches.
                // The 50ms delay lets the SwiftUI LazyVGrid render before the next
                // batch is accepted. Kept inline (no nested Task) so it stays tied
                // to this MainActor hop.
                try? await Task.sleep(for: .milliseconds(50))
                completion()
            }
        }
        await systemRepository.setOnConnectionsUpdate { [weak self] connections in
            Task { @MainActor [weak self] in
                // Same reasoning as `mergeStatusItems`. This observer has no
                // backpressure at all — unlike the sync-status one above, there
                // is no completion handshake — so an unconditional write was the
                // hottest invalidation source in the detail tree.
                guard let self, connectionsByTransport != connections else { return }
                connectionsByTransport = connections
            }
        }
    }

    /// Starts presence observation; surfaced as a separate hook so the parent
    /// can sequence it after `installCallbacks` and the parallel repository
    /// loads complete.
    func registerPresenceObserver() async throws {
        try await systemRepository.registerConnectionsPresenceObserver()
    }

    /// Fetches the local peer info via a direct (non-Query-Service) SDK query
    /// so it doesn't pollute Query Metrics. Failures are logged and swallowed
    /// because the studio still works without local peer identity.
    func loadLocalPeerInfo() async {
        do {
            let query = "SELECT ditto_sdk_language, ditto_sdk_platform, ditto_sdk_version FROM __small_peer_info"
            if let ditto = await dittoManager.dittoSelectedApp {
                let results = try await ditto.store.execute(query: query)
                if let firstItem = results.items.first {
                    let json = firstItem.value.compactMapValues { $0 }
                    firstItem.dematerialize()
                    localPeerDeviceName = "Edge Studio"
                    localPeerSDKLanguage = json["ditto_sdk_language"] as? String
                    localPeerSDKPlatform = json["ditto_sdk_platform"] as? String
                    localPeerSDKVersion = json["ditto_sdk_version"] as? String
                }
            }
        } catch {
            Log.error("Failed to fetch local peer info: \(error.localizedDescription)")
        }
    }

    /// Clears the peer/transport caches so the next database open starts from a
    /// known-empty baseline. Called from the parent VM's `closeSelectedApp`.
    ///
    /// It deliberately does **not** touch sync state: the caller
    /// (`MainStudioViewModel.closeSelectedApp`) goes on to close the database, and
    /// `DittoManager.closeDittoSelectedDatabase` publishes `isRunning = false` through the
    /// stop funnel. Writing it here as well would be a second, competing source of truth —
    /// the thing this refactor removes.
    func reset() {
        syncStatusItems = []
        connectionsByTransport = .empty

        localPeerDeviceName = nil
        localPeerSDKLanguage = nil
        localPeerSDKPlatform = nil
        localPeerSDKVersion = nil
    }

    // MARK: - Sync Toggle

    /// Toggles sync on/off via the DittoManager. When disabling, also clears
    /// the live transport / peer caches so stale UI doesn't linger.
    ///
    /// Neither branch assigns `isSyncEnabled` any more — it is derived from
    /// `SyncRuntimeState`, which the manager's funnels update once the SDK call has
    /// actually succeeded. Assigning it here is what previously let a failed or no-op
    /// start still light the indicator green.
    func toggleSync() async throws {
        if isSyncEnabled {
            await dittoManager.selectedDatabaseStopSync()
            connectionsByTransport = .empty
            syncStatusItems = []
        } else {
            try await dittoManager.selectedDatabaseStartSync()
        }
    }

    // MARK: - Merge Helpers

    /// Merges an incoming snapshot of peers into `syncStatusItems` while
    /// preserving each card's current grid position.
    ///
    /// - Existing peers have their data updated in-place (no reorder).
    /// - Peers absent from `newItems` are removed.
    /// - Peers new to `newItems` are appended to the end.
    private func mergeStatusItems(_ newItems: [SyncStatusInfo]) {
        let newById = Dictionary(uniqueKeysWithValues: newItems.map { ($0.id, $0) })

        // Keep existing peers in order, updating their data; drop peers that left.
        var merged = syncStatusItems.compactMap { existing in
            newById[existing.id]
        }

        // Append peers that weren't in the previous list.
        let existingIds = Set(syncStatusItems.map(\.id))
        let brandNewPeers = newItems.filter { !existingIds.contains($0.id) }
        merged.append(contentsOf: brandNewPeers)

        // `@Observable` does not equality-check its setters — every assignment
        // calls `withMutation` and invalidates every reader. The presence
        // observer fires continuously, so an unconditional write here re-ran
        // `MainStudioView.body` (the whole NavigationSplitView, including its
        // ViewThatFits measurement) many times a second even when nothing had
        // changed. Gating on inequality makes an idle mesh genuinely free.
        guard merged != syncStatusItems else { return }
        syncStatusItems = merged
    }
}
