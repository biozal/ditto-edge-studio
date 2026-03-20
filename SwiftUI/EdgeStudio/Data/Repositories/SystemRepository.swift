import DittoSwift
import Foundation

actor SystemRepository {
    static let shared = SystemRepository()

    private let dittoManager = DittoManager.shared
    private var syncStatusObserver: DittoObserver?
    private var connectionsPresenceObserver: DittoObserver?
    private var appState: AppState?
    private var dittoServerCount = 0

    // Backpressure handling
    private var isProcessingUpdate = false
    private var hasPendingUpdate = false
    private var pendingStatusItems: [SyncStatusInfo]?

    // Store the callback inside the actor
    private var onSyncStatusUpdate: (([SyncStatusInfo], @escaping () -> Void) -> Void)?
    private var onConnectionsUpdate: ((ConnectionsByTransport) -> Void)?

    private init() {}

    deinit {
        syncStatusObserver = nil
        connectionsPresenceObserver = nil
    }

    private func convertConnectionType(_ dittoType: DittoConnectionType) -> ConnectionType {
        switch dittoType {
        case .bluetooth: return .bluetooth
        case .accessPoint: return .accessPoint
        case .p2pWiFi: return .p2pWiFi
        case .webSocket: return .webSocket
        @unknown default: return .unknown("\(dittoType)")
        }
    }

    /// Returns true if the given connection type is enabled in the current transport config.
    ///
    /// Used as a workaround for an SDK bug in Ditto v5.0.0-preview.5 where the presence graph
    /// continues to report connections via transports that have been disabled (e.g. `accessPoint`
    /// connections appearing after `lan=false` is applied). Filtering here ensures the UI reflects
    /// the actual configured transports rather than stale SDK presence data.
    private nonisolated func isConnectionTypeEnabled(_ type: ConnectionType, config: DittoConfigForDatabase) -> Bool {
        switch type {
        case .bluetooth: return config.isBluetoothLeEnabled
        case .accessPoint: return config.isLanEnabled
        case .p2pWiFi: return config.isAwdlEnabled
        case .webSocket: return config.isCloudSyncEnabled
        case .unknown: return true
        }
    }

    private func extractPeerEnrichment(
        from peer: DittoPeer,
        localPeerKeyString: String? = nil,
        filteredBy config: DittoConfigForDatabase? = nil
    ) -> PeerEnrichmentData {
        // Convert DittoPeerOS to custom PeerOS
        let osInfo: PeerOS? = {
            guard let dittoOS = peer.osV2 else { return nil }

            // Map DittoPeerOS to custom PeerOS enum
            let osString = "\(dittoOS)"

            if osString.contains("iOS") || osString.contains("ios") {
                return .iOS(version: nil)
            } else if osString.contains("Android") || osString.contains("android") {
                return .android(version: nil)
            } else if osString.contains("macOS") || osString.contains("macos") {
                return .macOS(version: nil)
            } else if osString.contains("Linux") || osString.contains("linux") {
                return .linux(version: nil)
            } else if osString.contains("Windows") || osString.contains("windows") {
                return .windows(version: nil)
            } else {
                return .unknown(name: osString)
            }
        }()

        // Convert DittoAddress to custom PeerAddressInfo
        // Note: peer.address is deprecated but still usable for display purposes
        let addressInfo: PeerAddressInfo? = {
            let addressString = "\(peer.peerKeyString)"

            // Infer connection type from peerKeyString format
            var connType = "Network"
            if addressString.contains("bluetooth") || addressString.contains("ble") {
                connType = "Bluetooth"
            } else if addressString.contains("wifi") || addressString.contains("wireless") {
                connType = "WiFi"
            } else if addressString.contains("websocket") || addressString.contains("ws") {
                connType = "WebSocket"
            } else if addressString.contains("lan") || addressString.contains("ethernet") {
                connType = "LAN"
            }

            return PeerAddressInfo(connectionType: connType, description: addressString)
        }()

        // Convert identityServiceMetadata to JSON string
        let identityMetadata: String? = {
            let metadata = peer.identityServiceMetadata
            // Filter out nil values for JSON serialization
            let filteredMetadata = metadata.compactMapValues { $0 }

            guard !filteredMetadata.isEmpty,
                  let jsonData = try? JSONSerialization.data(withJSONObject: filteredMetadata, options: .prettyPrinted),
                  let jsonString = String(data: jsonData, encoding: .utf8) else
            {
                return nil
            }
            return jsonString
        }()

        // Convert peerMetadata to JSON string
        let peerMetadata: String? = {
            let metadata = peer.peerMetadata
            let filteredMetadata = metadata.compactMapValues { $0 }

            guard !filteredMetadata.isEmpty,
                  let jsonData = try? JSONSerialization.data(withJSONObject: filteredMetadata, options: .prettyPrinted),
                  let jsonString = String(data: jsonData, encoding: .utf8) else
            {
                return nil
            }
            return jsonString
        }()

        // Convert connections array to custom ConnectionInfo.
        // First filter to only direct connections (local peer must be an endpoint), then
        // deduplicate by type. The SDK returns one DittoConnection per directional endpoint
        // (A→B and B→A are separate objects with the same type but different IDs).
        let connections: [ConnectionInfo]? = {
            let rawConnections = peer.connections
            // Only include connections where the local peer is an endpoint (direct connections).
            // presenceGraph.remotePeers includes multihop peers; filtering here ensures only
            // directly connected transports appear on the peer card.
            let peerConnections: [DittoConnection] = if let localKey = localPeerKeyString {
                rawConnections.filter {
                    $0.peerKeyString1 == localKey || $0.peerKeyString2 == localKey
                }
            } else {
                rawConnections
            }

            guard !peerConnections.isEmpty else { return nil }

            var seenTypes: Set<String> = []
            let deduplicated = peerConnections.filter { seenTypes.insert("\($0.type)").inserted }

            let mapped = deduplicated.map { connection in
                ConnectionInfo(
                    id: connection.id,
                    type: self.convertConnectionType(connection.type),
                    peerKeyString1: connection.peerKeyString1,
                    peerKeyString2: connection.peerKeyString2,
                    approximateDistanceInMeters: connection.approximateDistanceInMeters
                )
            }
            guard let config else { return mapped.isEmpty ? nil : mapped }
            let filtered = mapped.filter { self.isConnectionTypeEnabled($0.type, config: config) }
            return filtered.isEmpty ? nil : filtered
        }()

        return PeerEnrichmentData(
            deviceName: peer.deviceName,
            osInfo: osInfo,
            dittoSDKVersion: peer.dittoSDKVersion,
            addressInfo: addressInfo,
            identityMetadata: identityMetadata,
            peerMetadata: peerMetadata,
            connections: connections
        )
    }

    /// Registers a presence-based observer for sync status with manual backpressure handling.
    ///
    /// **Architecture Change (2026-02)**: Flipped from DQL-first to presence-first for real-time updates.
    ///
    /// **New Flow**:
    /// 1. Presence observer fires on connection changes (real-time)
    /// 2. Extract connected peer IDs from presence graph
    /// 3. Query DQL for sync metrics (synced_up_to_local_commit_id, last_update_received_time)
    /// 4. Merge DQL metrics with presence peer data
    /// 5. Return ONLY connected peers to UI
    ///
    /// **Backpressure Strategy**: If an update arrives while processing, it's queued as
    /// pending. Only the latest pending update is kept (intermediate updates are dropped).
    /// When the UI signals completion, the pending update is processed if available.
    ///
    /// **Benefits**:
    /// - Real-time peer connection updates (no DQL lag)
    /// - Accurate connection status (presence graph is source of truth)
    /// - Improved performance (no continuous DQL observer)
    ///
    /// - Throws: InvalidStateError if no selected app available
    func registerSyncStatusObserver() async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No selected app available")
        }

        // Register presence observer for real-time peer connection changes
        syncStatusObserver = ditto.presence.observe { [weak self] presenceGraph in
            Task { [weak self] in
                guard let self else { return }

                // Step 1: Extract directly connected peers from presence graph (source of truth).
                // presenceGraph.remotePeers returns the full mesh topology (all peers, including
                // multihop). Filter to only peers where the local device is an endpoint of at
                // least one connection to avoid showing peers we never directly communicated with.
                let localPeerKeyString = presenceGraph.localPeer.peerKeyString
                let connectedPeers = presenceGraph.remotePeers.filter { peer in
                    peer.connections.contains {
                        $0.peerKeyString1 == localPeerKeyString || $0.peerKeyString2 == localPeerKeyString
                    }
                }

                // Fetch transport config for filtering stale SDK connections (SDK bug workaround)
                let appConfig = await dittoManager.dittoSelectedAppConfig

                // Step 2: Query DQL for sync metrics directly (bypassing QueryService so these
                // internal system queries are invisible to Query Metrics).
                // On failure degrade to presence-only data so cards still render.
                var syncMetricsLookup: [String: [String: Any]] = [:]
                do {
                    let results = try await ditto.store.execute(query: "SELECT * FROM system:data_sync_info")
                    for item in results.items {
                        let dict = item.value.compactMapValues { $0 }
                        if let peerId = dict["_id"] as? String {
                            syncMetricsLookup[peerId] = dict
                        }
                        item.dematerialize()
                    }
                } catch {
                    Log.error("Failed to query system:data_sync_info: \(error.localizedDescription)")
                    // Fall through with empty syncMetricsLookup — presence graph is still the
                    // source of truth for which peers are connected, so cards will still render.
                }

                // Step 4: Build status items for ALL connected peers (presence is source of truth)
                var newDittoServerCount = 0
                var statusItems: [SyncStatusInfo] = []
                var processedPeerIds = Set<String>()

                // Deduplicate remotePeers by peerKeyString, preferring entries that carry
                // SDK version information (the SDK can surface both sides of a bidirectional
                // connection as separate DittoPeer objects, where only one side has dittoSDKVersion set).
                var bestPeerMap: [String: DittoPeer] = [:]
                for peer in connectedPeers {
                    let peerId = peer.peerKeyString
                    if let existing = bestPeerMap[peerId] {
                        // Prefer the entry that has SDK version over one that doesn't.
                        // If both have it (or neither does), keep the first-seen.
                        if existing.dittoSDKVersion == nil, peer.dittoSDKVersion != nil {
                            bestPeerMap[peerId] = peer
                        }
                    } else {
                        bestPeerMap[peerId] = peer
                    }
                }
                let dedupedPeers = bestPeerMap.values

                // First: Add deduplicated peers from presence graph (one entry per peerKeyString,
                // preferring the entry with SDK version populated)
                for peer in dedupedPeers {
                    let peerId = peer.peerKeyString

                    // Extract peer enrichment data from presence, filtering to direct connections
                    // and disabled transports (SDK bug workaround)
                    let enrichment = await extractPeerEnrichment(from: peer, localPeerKeyString: localPeerKeyString, filteredBy: appConfig)

                    // Look up sync metrics for this peer (may not exist)
                    var dict: [String: Any]
                    if let syncMetrics = syncMetricsLookup[peerId] {
                        // Peer has sync metrics - use them
                        dict = syncMetrics

                        // Check if this is a Ditto Server (Big Peer)
                        let isDittoServer = dict["is_ditto_server"] as? Bool ?? false
                        if isDittoServer {
                            newDittoServerCount += 1
                        }
                    } else {
                        // Peer connected but no sync metrics yet - create minimal dict
                        dict = [
                            "_id": peerId,
                            "is_ditto_server": false
                        ]
                    }

                    // Set syncSessionStatus to "Connected" in the documents object
                    if var documents = dict["documents"] as? [String: Any] {
                        documents["sync_session_status"] = "Connected"
                        dict["documents"] = documents
                    } else {
                        // No documents object - create one with just the status
                        dict["documents"] = ["sync_session_status": "Connected"]
                    }

                    let statusInfo = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
                    statusItems.append(statusInfo)
                    processedPeerIds.insert(peerId)
                }

                // Second: Add any Ditto Cloud Server peers from DQL that weren't in presence graph
                // (Cloud Servers may appear in system:data_sync_info but not in presence graph)
                for (peerId, syncMetrics) in syncMetricsLookup {
                    // Skip if already processed from presence graph
                    if processedPeerIds.contains(peerId) {
                        continue
                    }

                    // Only include Ditto Cloud Servers
                    let isDittoServer = syncMetrics["is_ditto_server"] as? Bool ?? false
                    guard isDittoServer else {
                        continue
                    }

                    newDittoServerCount += 1

                    // Create dict with sync metrics
                    var dict = syncMetrics

                    // Check sync_session_status from documents object
                    let syncSessionStatus = (dict["documents"] as? [String: Any])?["sync_session_status"] as? String
                    let isNotConnected = syncSessionStatus == "Not Connected"
                    guard !isNotConnected else {
                        continue
                    }

                    // Set syncSessionStatus to "Connected" in the documents object
                    if var documents = dict["documents"] as? [String: Any] {
                        documents["sync_session_status"] = "Connected"
                        dict["documents"] = documents
                    } else {
                        dict["documents"] = ["sync_session_status": "Connected"]
                    }

                    // Cloud Server won't have presence enrichment data
                    let statusInfo = SyncStatusInfo(from: dict, peerEnrichment: nil)
                    statusItems.append(statusInfo)
                }

                // Step 5: Update Ditto Server count and trigger connections update
                let currentDittoServerCount = await dittoServerCount
                if newDittoServerCount != currentDittoServerCount {
                    await updateDittoServerCount(newDittoServerCount)
                    await triggerConnectionsUpdate()
                }

                // Step 6: Backpressure handling (unchanged)
                await processSyncStatusUpdate(statusItems)
            }
        }
    }

    /// Processes sync status updates with backpressure handling
    private func processSyncStatusUpdate(_ statusItems: [SyncStatusInfo]) async {
        if isProcessingUpdate {
            // Already processing - queue this update as pending (drops any previous pending)
            hasPendingUpdate = true
            pendingStatusItems = statusItems
            return
        }

        // Guard against nil callback BEFORE locking the pipeline. If we set
        // isProcessingUpdate = true and then the optional call is a no-op, the flag
        // stays true forever and all subsequent updates are silently dropped.
        guard let callback = onSyncStatusUpdate else {
            hasPendingUpdate = true
            pendingStatusItems = statusItems
            return
        }

        // Mark as processing and send to UI
        isProcessingUpdate = true

        callback(statusItems) { [weak self] in
            Task {
                guard let self else { return }

                // Update complete - check for pending updates
                await self.handleUpdateComplete()
            }
        }
    }

    /// Handles completion of a UI update and processes any pending updates
    private func handleUpdateComplete() async {
        if hasPendingUpdate, let pending = pendingStatusItems {
            // Clear pending state
            hasPendingUpdate = false
            pendingStatusItems = nil

            // CRITICAL: Reset isProcessingUpdate BEFORE calling processSyncStatusUpdate.
            // processSyncStatusUpdate checks isProcessingUpdate first; if it's still true,
            // the pending items would be re-queued as pending instead of dispatched,
            // causing a permanent deadlock where completion() is never called again.
            isProcessingUpdate = false

            // Process the pending update (recursive call)
            await processSyncStatusUpdate(pending)
        } else {
            // No pending updates - mark as not processing
            isProcessingUpdate = false
        }
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    /// Function to set the callback from outside the actor.
    /// Drains any pending update that queued up before the callback was registered
    /// (e.g. when the presence observer fires before the new session's callback is set).
    func setOnSyncStatusUpdate(_ callback: @escaping ([SyncStatusInfo], @escaping () -> Void) -> Void) {
        onSyncStatusUpdate = callback

        // If a pending update arrived while the callback was nil, process it now.
        if hasPendingUpdate, let pending = pendingStatusItems {
            hasPendingUpdate = false
            pendingStatusItems = nil
            Task {
                await processSyncStatusUpdate(pending)
            }
        }
    }

    private func updateDittoServerCount(_ count: Int) {
        dittoServerCount = count
    }

    private func triggerConnectionsUpdate() async {
        // This will be called by presence observer with current counts
        // For now, we'll rely on presence observer to include dittoServerCount
    }

    func registerConnectionsPresenceObserver() async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No selected app available")
        }

        // Register presence observer for real-time connection updates
        connectionsPresenceObserver = ditto.presence.observe { [weak self] presenceGraph in
            Task { [weak self] in
                guard let self else { return }

                // Initialize counters for each transport type
                var totalAccessPoint = 0
                var totalBluetooth = 0
                var totalP2PWiFi = 0
                var totalWebSocket = 0

                // Fetch transport config for filtering stale SDK connections (SDK bug workaround)
                let appConfig = await dittoManager.dittoSelectedAppConfig

                // Only count connections where the local peer is a direct endpoint.
                // presenceGraph.remotePeers includes multihop peers; their connections are not
                // direct and should not contribute to the transport counts in the status bar.
                // Also deduplicate by type — the SDK returns one DittoConnection per directional
                // endpoint (A→B and B→A), which would otherwise double-count.
                let localPeerKeyString = presenceGraph.localPeer.peerKeyString
                for peer in presenceGraph.remotePeers {
                    var seenTypes: Set<String> = []
                    for connection in peer.connections {
                        guard connection.peerKeyString1 == localPeerKeyString ||
                            connection.peerKeyString2 == localPeerKeyString else { continue }
                        guard seenTypes.insert("\(connection.type)").inserted else { continue }

                        let connectionType = await convertConnectionType(connection.type)

                        // Skip connections for disabled transports (SDK bug workaround: presence
                        // graph retains stale connections after transport config changes)
                        if let config = appConfig, !isConnectionTypeEnabled(connectionType, config: config) {
                            continue
                        }

                        switch connectionType {
                        case .bluetooth:
                            totalBluetooth += 1
                        case .accessPoint:
                            totalAccessPoint += 1
                        case .p2pWiFi:
                            totalP2PWiFi += 1
                        case .webSocket:
                            totalWebSocket += 1
                        case .unknown:
                            break
                        }
                    }
                }

                // Create aggregated result including Ditto Server count
                let aggregated = await ConnectionsByTransport(
                    accessPoint: totalAccessPoint,
                    bluetooth: totalBluetooth,
                    dittoServer: dittoServerCount,
                    p2pWiFi: totalP2PWiFi,
                    webSocket: totalWebSocket
                )

                // Call the callback to update the ViewModel's published property
                await onConnectionsUpdate?(aggregated)
            }
        }
    }

    func setOnConnectionsUpdate(_ callback: @escaping (ConnectionsByTransport) -> Void) {
        onConnectionsUpdate = callback
    }

    /// One-time peer snapshot for MCP tools.
    ///
    /// Reads the presence graph and queries `system:data_sync_info` for commit IDs without
    /// registering a persistent observer. The two reads run sequentially on a utility queue
    /// so neither blocks the main thread.
    ///
    /// - Returns: An array of serializable peer dictionaries, or an empty array if no peers
    ///   are connected or no database is active. Commit IDs are omitted gracefully if the
    ///   `system:data_sync_info` query fails (e.g. sync is stopped).
    func fetchPeersOnce() async -> [[String: Any]] {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            return []
        }

        // Read presence peers on a utility queue (synchronous property access)
        let remotePeers = await Task.detached(priority: .utility) {
            ditto.presence.graph.remotePeers
        }.value

        guard !remotePeers.isEmpty else { return [] }

        // Query sync metrics for commit IDs — degrades gracefully if unavailable
        var syncMetricsLookup: [String: [String: Any]] = [:]
        do {
            let results = try await ditto.store.execute(query: "SELECT * FROM system:data_sync_info")
            for item in results.items {
                let dict = item.value.compactMapValues { $0 }
                if let peerId = dict["_id"] as? String {
                    syncMetricsLookup[peerId] = dict
                }
                item.dematerialize()
            }
        } catch {
            Log.warning("fetchPeersOnce: system:data_sync_info unavailable, commit IDs will be omitted")
        }

        // Fetch transport config for filtering stale SDK connections (SDK bug workaround)
        let appConfig = await dittoManager.dittoSelectedAppConfig

        // Enrich each peer using the same private enrichment logic as the observer
        var peerDicts: [[String: Any]] = []
        for peer in remotePeers {
            let enrichment = extractPeerEnrichment(from: peer, filteredBy: appConfig)
            let peerId = peer.peerKeyString
            let syncMetrics = syncMetricsLookup[peerId]

            // Map PeerOS enum to a display string
            let osType: String = {
                switch enrichment.osInfo {
                case .iOS: return "iOS"
                case .android: return "Android"
                case .macOS: return "macOS"
                case .linux: return "Linux"
                case .windows: return "Windows"
                case let .unknown(name): return name ?? "Unknown"
                case nil: return "Unknown"
                }
            }()

            // Map each ConnectionInfo to a serializable dict
            let connectionsList: [[String: Any]] = (enrichment.connections ?? []).map { conn in
                let typeName: String = switch conn.type {
                case .bluetooth: "Bluetooth LE"
                case .accessPoint: "Access Point"
                case .p2pWiFi: "P2P WiFi"
                case .webSocket: "WebSocket"
                case let .unknown(t): t
                }
                var entry: [String: Any] = ["type": typeName]
                if let dist = conn.approximateDistanceInMeters {
                    entry["distanceMeters"] = (dist * 10).rounded() / 10
                }
                return entry
            }

            let peerDict: [String: Any] = [
                "peerKey": peerId,
                "deviceName": enrichment.deviceName ?? "Unknown",
                "osType": osType,
                "sdkVersion": enrichment.dittoSDKVersion ?? "",
                "connectionStatus": "Connected",
                "addressInfo": enrichment.addressInfo?.description ?? "",
                "connections": connectionsList,
                "identityMetadata": enrichment.identityMetadata ?? "",
                "peerMetadata": enrichment.peerMetadata ?? "",
                "syncedUpToCommitId": syncMetrics?["synced_up_to_local_commit_id"] as? String ?? ""
            ]
            peerDicts.append(peerDict)
        }

        return peerDicts
    }

    /// Stops only the sync-status observer (called when leaving the Peers List tab).
    ///
    /// Preserves the connections-presence observer (which drives the status bar) and all
    /// callbacks. Only the backpressure pipeline state is reset so the next registration
    /// starts clean.
    func stopSyncStatusObserver() async {
        syncStatusObserver = nil
        isProcessingUpdate = false
        hasPendingUpdate = false
        pendingStatusItems = nil
    }

    /// Full session cleanup — stops ALL observers and resets ALL per-session state.
    ///
    /// Call this only when closing a database session entirely (not for tab switches).
    ///
    /// Previously this fired a `Task.detached` and returned immediately, which caused two bugs:
    /// 1. The detached task raced with the new session's registration and could nil out
    ///    newly registered observers after the fact.
    /// 2. `isProcessingUpdate` was never reset, so a session that closed mid-update left
    ///    the backpressure pipeline permanently locked — all new updates queued as pending
    ///    but were never drained.
    ///
    /// Callbacks (`onSyncStatusUpdate`, `onConnectionsUpdate`) are intentionally NOT cleared:
    /// the new session's `setOn*` calls replace them, and `setOnSyncStatusUpdate` drains
    /// any pending update that arrived before the new callback was registered.
    func stopObserver() async {
        syncStatusObserver = nil
        connectionsPresenceObserver = nil
        dittoServerCount = 0
        isProcessingUpdate = false
        hasPendingUpdate = false
        pendingStatusItems = nil
    }
}
