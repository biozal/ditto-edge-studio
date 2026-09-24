import DittoSwift
import Foundation

/// Protocol abstraction for peer data to allow both real DittoPeer and mock test data
protocol PeerProtocol {
    var peerKeyString: String { get }
    var deviceName: String { get }
    var connectionProtocols: [any ConnectionProtocol] { get }
    var isConnectedToDittoCloud: Bool { get }

    // MARK: Detail-card fields

    //
    // The presence graph reports all of these for peers the local device cannot reach,
    // which is most of a focus orbit — the orbit is the *focused* peer's neighbourhood,
    // not ours. They are deliberately NOT sourced from `SyncStatusInfo`, which only
    // exists for directly connected peers.
    //
    // Nullable because the SDK learns them gradually: a peer can appear in the graph
    // before its OS or SDK version is known.

    /// Operating system reported by the peer, if known yet.
    var peerOS: PeerOS? { get }
    /// Ditto SDK version the peer runs, if known yet.
    var sdkVersionString: String? { get }
    /// Whether the peer's protocol is compatible with ours, if known yet.
    var isCompatiblePeer: Bool? { get }
    /// Peer metadata as JSON, plus its top-level key count. Nil when the peer has set none.
    var peerMetadataJSON: (json: String, keyCount: Int)? { get }
    /// Identity-service metadata (set by the auth webhook) as JSON, plus its key count.
    var identityMetadataJSON: (json: String, keyCount: Int)? { get }
}

/// Defaults so conformers that predate the detail card (notably `MockPeer`) keep
/// compiling, and so a test fixture never has to invent SDK values it doesn't model.
extension PeerProtocol {
    var peerOS: PeerOS? {
        nil
    }

    var sdkVersionString: String? {
        nil
    }

    var isCompatiblePeer: Bool? {
        nil
    }

    var peerMetadataJSON: (json: String, keyCount: Int)? {
        nil
    }

    var identityMetadataJSON: (json: String, keyCount: Int)? {
        nil
    }
}

/// Protocol abstraction for connection data
/// Note: approximateDistanceInMeters was removed in Ditto SDK v5.
protocol ConnectionProtocol {
    var type: DittoConnectionType { get }
    var id: String { get }
    var peerKeyString1: String { get }
    var peerKeyString2: String { get }
}

// MARK: - DittoPeer Conformance

/// Extend DittoPeer to conform to PeerProtocol.
/// In v5, DittoPeer uses `peerKey` (was `peerKeyString`) and
/// `isConnectedToDittoServer` (was `isConnectedToDittoCloud`).
/// We bridge those renames here so all callsites use the stable protocol names.
extension DittoPeer: PeerProtocol {
    /// Bridge v5 `peerKey` to the stable protocol name `peerKeyString`.
    var peerKeyString: String {
        peerKey
    }

    /// Bridge v5 `isConnectedToDittoServer` to the legacy protocol name `isConnectedToDittoCloud`.
    var isConnectedToDittoCloud: Bool {
        isConnectedToDittoServer
    }

    var connectionProtocols: [any ConnectionProtocol] {
        connections.map { $0 as ConnectionProtocol }
    }

    // MARK: Detail-card bridges

    var peerOS: PeerOS? {
        PeerOS(dittoPeerOS: os)
    }

    var sdkVersionString: String? {
        dittoSDKVersion?.isEmpty == false ? dittoSDKVersion : nil
    }

    var isCompatiblePeer: Bool? {
        isCompatible
    }

    /// Unlike the Kotlin SDK — where `peerMetadata` is a typed `ObjectValue` whose
    /// `toString()` is Kotlin map syntax rather than JSON, and whose `isNull` is a type
    /// discriminator rather than an emptiness test — the Swift SDK hands back a plain
    /// dictionary. Emptiness and JSON encoding are both honest here, so this mirrors
    /// `SystemRepository`'s existing conversion rather than inventing a second one.
    var peerMetadataJSON: (json: String, keyCount: Int)? {
        Self.encodeMetadata(peerMetadata)
    }

    var identityMetadataJSON: (json: String, keyCount: Int)? {
        Self.encodeMetadata(identityServiceMetadata)
    }

    private static func encodeMetadata(_ metadata: [String: Any?]) -> (json: String, keyCount: Int)? {
        let filtered = metadata.compactMapValues { $0 }
        guard !filtered.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: filtered, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else
        {
            return nil
        }
        return (json, filtered.count)
    }
}

/// Extend DittoConnection to conform to ConnectionProtocol.
/// In v5, DittoConnection uses `peer1`/`peer2` (were `peerKeyString1`/`peerKeyString2`).
/// We bridge those renames here so all callsites use the stable protocol names.
extension DittoConnection: ConnectionProtocol {
    /// Bridge v5 `peer1` to the stable protocol name `peerKeyString1`.
    var peerKeyString1: String {
        peer1
    }

    /// Bridge v5 `peer2` to the stable protocol name `peerKeyString2`.
    var peerKeyString2: String {
        peer2
    }
}

// MARK: - Edge Aggregation

/// A deduplicated, direct-filtered peer-to-peer edge aggregated from the presence
/// graph. Both the change-detection pass and the draw pass in
/// `PresenceNetworkScene` build from this single source so the two can never
/// drift apart (a drift causes either phantom edges or a rebuild every update).
struct PresenceEdge: Equatable {
    /// Stable identity: `"<sortedPairKey>_<type>"` (matches historical line ids).
    let connectionId: String
    /// Normalized endpoint pair: the two peer keys sorted and joined with `_`.
    let pairKey: String
    let from: String
    let to: String
    let type: DittoConnectionType
}

/// Pure edge-aggregation logic for the presence graph scene.
enum PresenceEdgeAggregator {
    /// Aggregates peer-to-peer edges from the local peer AND all remote peers.
    ///
    /// The local peer's own connection list must be included: Ditto usually
    /// reports an undirected edge from both endpoints, but the local peer is the
    /// authoritative source for edges attached to this process — a transport
    /// (notably multicast) is lost from the graph when only the local side
    /// advertises the edge. Mirrors the VS Code extension's
    /// `buildPresenceGraphView` (`src/ditto/peer-info.ts`).
    ///
    /// Rules:
    /// - Edges are deduplicated globally by `(sortedPair, type)` because the SDK
    ///   reports A→B and B→A as separate connection objects with different ids.
    /// - Distinct transport types between the same pair are kept (parallel edges).
    /// - When `showDirectConnectedOnly` is true, edges that don't involve the
    ///   local peer are dropped (see `docs/PRESENCE_GRAPH.md`).
    /// - Connections with an empty endpoint key are dropped (they can never be
    ///   drawn; expecting them would force a rebuild on every update).
    static func aggregate(
        localPeer: any PeerProtocol,
        remotePeers: [any PeerProtocol],
        showDirectConnectedOnly: Bool
    ) -> [PresenceEdge] {
        let localPeerKey = localPeer.peerKeyString
        var seen: Set<String> = []
        var edges: [PresenceEdge] = []

        for peer in [localPeer] + remotePeers {
            for connection in peer.connectionProtocols {
                let pk1 = connection.peerKeyString1
                let pk2 = connection.peerKeyString2
                guard !pk1.isEmpty, !pk2.isEmpty else { continue }

                // When filtering to direct connections only, skip edges that don't
                // involve the local device (e.g., PeerA ↔ PeerB connections).
                if showDirectConnectedOnly, pk1 != localPeerKey, pk2 != localPeerKey {
                    continue
                }

                let pairKey = [pk1, pk2].sorted().joined(separator: "_")
                let connectionId = "\(pairKey)_\(connection.type)"
                guard seen.insert(connectionId).inserted else { continue }

                edges.append(PresenceEdge(
                    connectionId: connectionId,
                    pairKey: pairKey,
                    from: pk1,
                    to: pk2,
                    type: connection.type
                ))
            }
        }

        return edges
    }

    /// Keys of the remote peers visible in Direct mode: every non-local
    /// endpoint of an aggregated, direct-filtered edge.
    ///
    /// Deriving visibility from the aggregated edges (which include the local
    /// peer's own advertised connections) — rather than from each remote
    /// peer's connection list — surfaces a peer whose edge ONLY the local side
    /// advertises (the multicast asymmetry `aggregate` exists for). Mirrors
    /// the VS Code extension's `buildGraphInput`, which derives Direct-mode
    /// visible peers from the aggregated connections' endpoints so multicast
    /// edges stay consistent between the two views.
    static func directVisiblePeerKeys(
        localPeer: any PeerProtocol,
        remotePeers: [any PeerProtocol]
    ) -> Set<String> {
        let localPeerKey = localPeer.peerKeyString
        var keys: Set<String> = []
        for edge in aggregate(localPeer: localPeer, remotePeers: remotePeers, showDirectConnectedOnly: true) {
            if edge.from != localPeerKey {
                keys.insert(edge.from)
            }
            if edge.to != localPeerKey {
                keys.insert(edge.to)
            }
        }
        return keys
    }

    /// Keys of every peer participating in at least one aggregated
    /// (unfiltered) edge, local peer included.
    ///
    /// Expanded (full-mesh) mode filters the remote list against this set so
    /// orphan peers — discovered over mDNS/BLE but with no established sync
    /// session, most common in the sync stop→start window — don't render as
    /// floating pills. A peer that only appears as the OTHER endpoint of a
    /// neighbour's advertised edge is kept. Mirrors the VS Code extension's
    /// `buildPresenceGraphView` pass 2 (`peersInAnyEdge`).
    static func meshVisiblePeerKeys(
        localPeer: any PeerProtocol,
        remotePeers: [any PeerProtocol]
    ) -> Set<String> {
        var keys: Set<String> = []
        for edge in aggregate(localPeer: localPeer, remotePeers: remotePeers, showDirectConnectedOnly: false) {
            keys.insert(edge.from)
            keys.insert(edge.to)
        }
        return keys
    }
}

// MARK: - Focus-Mode Planning

/// Pure focus-mode decisions for the presence scene, extracted for unit tests
/// (no SpriteKit required). Mirrors the VS Code extension's `scene.ts` focus view.
enum PresenceFocusPlanner {
    /// Keys directly connected to `key` among the given edges — the focused peer's
    /// neighbourhood. Sorted for determinism; `key` itself is not included.
    /// (Extension: `neighboursOf`, minus its per-epoch cache.)
    static func neighbourKeys(of key: String, edges: [PresenceEdge]) -> [String] {
        var neighbours: Set<String> = []
        for edge in edges {
            if edge.from == key, edge.to != key {
                neighbours.insert(edge.to)
            }
            if edge.to == key, edge.from != key {
                neighbours.insert(edge.from)
            }
        }
        return neighbours.sorted()
    }

    /// Camera scale that exactly fits a layout in the viewport.
    ///
    /// `viewSize` is the visible extent in SCENE units at camera scale 1.0 —
    /// not raw view points. The scene is a fixed 1000×800 with
    /// `scaleMode = .aspectFill`, so callers must convert the view bounds
    /// first (see `PresenceNetworkScene.visibleSceneSize(for:)`) or the fit
    /// under-zooms whenever the aspectFill scale factor exceeds 1.
    ///
    /// SKCamera semantics: a LARGER scale shows MORE of the scene (zoomed out), so
    /// the fit is the largest ratio of content extent to available extent.
    /// `padding` is the per-edge breathing room (the extension's
    /// `FOCUS_VIEW_PADDING_X/Y` equivalents).
    static func fitScale(
        layoutRadius: CGFloat,
        maxPillWidth: CGFloat,
        viewSize: CGSize,
        padding: CGFloat
    ) -> CGFloat {
        guard layoutRadius > 0, viewSize.width > 0, viewSize.height > 0 else { return 1 }
        let contentWidth = layoutRadius * 2 + maxPillWidth + padding * 2
        let contentHeight = layoutRadius * 2 + maxPillWidth + padding * 2
        return max(contentWidth / viewSize.width, contentHeight / viewSize.height)
    }

    /// The camera scale for a focused neighbourhood.
    ///
    /// Mirrors the extension's `clampZoom(min(max(zoom, FOCUS_ZOOM=1.25), fitZoom))`
    /// in SK camera terms (scale = 1/magnification, so 1.25× magnification is scale
    /// 0.8): zoom in to at least 1.25×, never exceed the fit for the complete
    /// neighbourhood, and never leave the app's [0.5, 4.0] camera range.
    static func focusCameraScale(fitScale: CGFloat, currentScale: CGFloat) -> CGFloat {
        min(4.0, max(0.5, max(fitScale, min(currentScale, 0.8))))
    }

    /// Focus-view context dimming (the rest of the mesh stays as backdrop).
    static let contextPeerAlpha: CGFloat = 0.08
    static let contextLineAlpha: CGFloat = 0.04
}

// MARK: - PeerOS Bridge

extension PeerOS {
    /// Map the SDK's `DittoPeerOS` onto the app's `PeerOS`.
    ///
    /// Extracted from `SystemRepository.extractPeerEnrichment` so the presence viewer's
    /// detail card and the peer list cannot drift apart on OS naming. The string match
    /// is kept verbatim from that original: `DittoPeerOS` has no exhaustive public case
    /// list to switch over, so its description is what there is to work with.
    init?(dittoPeerOS: DittoPeerOS?) {
        guard let dittoPeerOS else { return nil }
        let name = "\(dittoPeerOS)"
        if name.contains("iOS") || name.contains("ios") {
            self = .iOS(version: nil)
        } else if name.contains("Android") || name.contains("android") {
            self = .android(version: nil)
        } else if name.contains("macOS") || name.contains("macos") {
            self = .macOS(version: nil)
        } else if name.contains("Linux") || name.contains("linux") {
            self = .linux(version: nil)
        } else if name.contains("Windows") || name.contains("windows") {
            self = .windows(version: nil)
        } else {
            self = .unknown(name: name)
        }
    }
}

// MARK: - Mock Implementations for Testing

/// Mock peer for testing (conforms to PeerProtocol)
struct MockPeer: PeerProtocol {
    let peerKeyString: String
    let deviceName: String
    let connectionProtocols: [any ConnectionProtocol]
    let isConnectedToDittoCloud: Bool

    init(
        peerKey: String,
        deviceName: String,
        connections: [MockConnection],
        isConnectedToDittoCloud: Bool = false
    ) {
        peerKeyString = peerKey
        self.deviceName = deviceName
        connectionProtocols = connections.map { $0 as ConnectionProtocol }
        self.isConnectedToDittoCloud = isConnectedToDittoCloud
    }
}

/// Mock connection for testing (conforms to ConnectionProtocol)
/// Note: approximateDistanceInMeters was removed from DittoConnection in Ditto SDK v5.
struct MockConnection: ConnectionProtocol {
    let type: DittoConnectionType
    let id: String
    let peerKeyString1: String
    let peerKeyString2: String

    init(
        type: DittoConnectionType,
        id: String,
        peerKeyString1: String = "",
        peerKeyString2: String = ""
    ) {
        self.type = type
        self.id = id
        self.peerKeyString1 = peerKeyString1
        self.peerKeyString2 = peerKeyString2
    }
}
