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
        // Convert SDK enum to custom enum
        let typeString = "\(dittoType)"

        if typeString.contains("bluetooth") {
            return .bluetooth
        } else if typeString.contains("accessPoint") {
            return .accessPoint
        } else if typeString.contains("p2pWiFi") || typeString.contains("p2pwifi") {
            return .p2pWiFi
        } else if typeString.contains("webSocket") || typeString.contains("websocket") {
            return .webSocket
        } else {
            return .unknown(typeString)
        }
    }

    private func extractPeerEnrichment(from peer: DittoPeer) -> PeerEnrichmentData {
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
        // The SDK returns one DittoConnection per directional endpoint (A→B and B→A are
        // separate objects with the same type but different IDs). Deduplicate by keeping
        // the first-seen entry per connection type so the peer card shows accurate counts.
        let connections: [ConnectionInfo]? = {
            let peerConnections = peer.connections

            guard !peerConnections.isEmpty else { return nil }

            var seenTypes: Set<String> = []
            let deduplicated = peerConnections.filter { seenTypes.insert("\($0.type)").inserted }

            return deduplicated.map { connection in
                ConnectionInfo(
                    id: connection.id,
                    type: self.convertConnectionType(connection.type),
                    peerKeyString1: connection.peerKeyString1,
                    peerKeyString2: connection.peerKeyString2,
                    approximateDistanceInMeters: connection.approximateDistanceInMeters
                )
            }
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

    private func buildPeerLookupMap(ditto: Ditto) async -> [String: PeerEnrichmentData] {
        // Access presence graph on background queue
        await Task.detached(priority: .utility) { [weak self] in
            guard let self else { return [:] }

            var peerMap: [String: PeerEnrichmentData] = [:]

            // Access remotePeers from presence graph
            let remotePeers = ditto.presence.graph.remotePeers

            for peer in remotePeers {
                let enrichment = await extractPeerEnrichment(from: peer)
                peerMap[peer.peerKeyString] = enrichment
            }

            return peerMap
        }.value
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

                // Step 1: Extract connected peers from presence graph (source of truth)
                let connectedPeers = presenceGraph.remotePeers

                // Step 2: Query DQL for sync metrics (all peers with full documents object)
                let query = """
                SELECT *
                FROM system:data_sync_info
                """

                // Query DQL for sync metrics; on failure degrade to presence-only data
                // so cards still render without commit info (rather than showing empty state).
                var jsonResults: [String] = []
                do {
                    jsonResults = try await QueryService.shared.executeSelectedAppQuery(query: query)
                } catch {
                    Log.error("Failed to query system:data_sync_info: \(error.localizedDescription)")
                    // Fall through with empty jsonResults — presence graph is still the source
                    // of truth for which peers are connected, so cards will still render.
                }

                // Step 3: Build sync metrics lookup map from DQL results
                var syncMetricsLookup: [String: [String: Any]] = [:]
                for jsonString in jsonResults {
                    guard let data = jsonString.data(using: .utf8),
                          let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let peerId = dict["_id"] as? String else
                    {
                        continue
                    }
                    syncMetricsLookup[peerId] = dict
                }

                // Step 4: Build status items for ALL connected peers (presence is source of truth)
                var newDittoServerCount = 0
                var statusItems: [SyncStatusInfo] = []
                var processedPeerIds = Set<String>()

                // First: Add all peers from presence graph
                for peer in connectedPeers {
                    let peerId = peer.peerKeyString

                    // Extract peer enrichment data from presence
                    let enrichment = await extractPeerEnrichment(from: peer)

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

                // Iterate through all remote peers in the presence graph.
                // Deduplicate by type before counting — the SDK returns one DittoConnection
                // per directional endpoint (A→B and B→A), which would otherwise double counts.
                for peer in presenceGraph.remotePeers {
                    var seenTypes: Set<String> = []
                    for connection in peer.connections {
                        guard seenTypes.insert("\(connection.type)").inserted else { continue }

                        let connectionType = await convertConnectionType(connection.type)

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
