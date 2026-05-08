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

    // MARK: - State

    /// Peers currently visible via presence graph + sync status. Populated by
    /// the SystemRepository sync-status callback installed in `installCallbacks`.
    var syncStatusItems: [SyncStatusInfo] = []

    /// Drives the toolbar sync indicator and `toggleSync` semantics. Defaults
    /// to `true` because hydration starts sync; flipped by `toggleSync` and by
    /// `reset()` on close.
    var isSyncEnabled = true

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
        systemRepository: any SystemRepositoryProtocol = SystemRepository.shared
    ) {
        self.dittoManager = dittoManager
        self.systemRepository = systemRepository
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

                // CRITICAL: signal completion AFTER UI update dispatches.
                // 50ms delay allows SwiftUI LazyVGrid rendering to complete.
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    completion()
                }
            }
        }
        await systemRepository.setOnConnectionsUpdate { [weak self] connections in
            Task { @MainActor [weak self] in
                self?.connectionsByTransport = connections
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

    /// Clears all sync state. Called from the parent VM's `closeSelectedApp`
    /// so the next database open starts from a known-empty baseline.
    func reset() {
        syncStatusItems = []
        connectionsByTransport = .empty
        isSyncEnabled = false

        localPeerDeviceName = nil
        localPeerSDKLanguage = nil
        localPeerSDKPlatform = nil
        localPeerSDKVersion = nil
    }

    // MARK: - Sync Toggle

    /// Toggles sync on/off via the DittoManager. When disabling, also clears
    /// the live transport / peer caches so stale UI doesn't linger.
    func toggleSync() async throws {
        if isSyncEnabled {
            await dittoManager.selectedDatabaseStopSync()
            connectionsByTransport = .empty
            syncStatusItems = []
            isSyncEnabled = false
        } else {
            try await dittoManager.selectedDatabaseStartSync()
            isSyncEnabled = true
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

        syncStatusItems = merged
    }
}
