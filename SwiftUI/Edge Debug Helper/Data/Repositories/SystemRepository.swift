import DittoSwift
import Foundation

actor SystemRepository {
    static let shared = SystemRepository()
    
    private let dittoManager = DittoManager.shared
    private var syncStatusObserver: DittoStoreObserver?
    private var appState: AppState?
    
    // Store the callback inside the actor
    private var onSyncStatusUpdate: (([SyncStatusInfo]) -> Void)?

    private init() { }
    
    deinit {
        syncStatusObserver?.cancel()
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
                  let jsonString = String(data: jsonData, encoding: .utf8) else {
                return nil
            }
            return jsonString
        }()

        // Convert connections array to custom ConnectionInfo
        let connections: [ConnectionInfo]? = {
            let peerConnections = peer.connections

            guard !peerConnections.isEmpty else { return nil }

            return peerConnections.map { connection in
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
            connections: connections
        )
    }

    private func buildPeerLookupMap(ditto: Ditto) async -> [String: PeerEnrichmentData] {
        // Access presence graph on background queue
        return await Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return [:] }

            var peerMap: [String: PeerEnrichmentData] = [:]

            // Access remotePeers from presence graph
            let remotePeers = ditto.presence.graph.remotePeers

            for peer in remotePeers {
                let enrichment = await self.extractPeerEnrichment(from: peer)
                peerMap[peer.peerKeyString] = enrichment
            }

            return peerMap
        }.value
    }

    func registerSyncStatusObserver() async throws {
        guard let ditto = await dittoManager.dittoSelectedApp else {
            throw InvalidStateError(message: "No selected app available")
        }
        
        // Register observer for sync status
        syncStatusObserver = try ditto.store.registerObserver(
            query: """
                SELECT *
                FROM system:data_sync_info
                ORDER BY documents.sync_session_status, documents.last_update_received_time desc
                """
        ) { [weak self] results in
            Task { [weak self] in
                guard let self else { return }

                // Build peer lookup map from presence graph
                let peerLookup = await self.buildPeerLookupMap(ditto: ditto)

                // Create enriched SyncStatusInfo instances
                let statusItems: [SyncStatusInfo] = results.items.compactMap { item in
                    let jsonData = item.jsonData()
                    guard let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                          let peerId = dict["_id"] as? String else {
                        item.dematerialize()
                        return nil
                    }

                    // Look up peer enrichment data by matching peerKeyString to id
                    let enrichment = peerLookup[peerId]

                    let syncItem = SyncStatusInfo(from: dict, peerEnrichment: enrichment)
                    item.dematerialize()
                    return syncItem
                }

                // Call the callback to update the ViewModel's published property
                await self.onSyncStatusUpdate?(statusItems)
            }
        }
    }
    
    func setAppState(_ appState: AppState) {
        self.appState = appState
    }
    
    // Function to set the callback from outside the actor
    func setOnSyncStatusUpdate(_ callback: @escaping ([SyncStatusInfo]) -> Void) {
        self.onSyncStatusUpdate = callback
    }
    
    func stopObserver() {
        // Use Task to ensure observer cleanup runs on appropriate background queue
        // This prevents priority inversion when called from main thread
        Task.detached(priority: .utility) { [weak self] in
            await self?.performObserverCleanup()
        }
    }
    
    private func performObserverCleanup() {
        syncStatusObserver?.cancel()
        syncStatusObserver = nil
    }
}

