import Foundation

/// One peer row in the Presence Viewer's search results card.
///
/// `isLocal` rows are listed — so a full-opacity **Me** makes sense while the rest
/// of the graph dims — but are never clickable: the scene deliberately rejects
/// focusing the local peer (in Direct mode every line touches it, so focusing it
/// would exempt the whole graph from dimming).
struct PresencePeerSearchMatch: Identifiable, Equatable, Sendable {
    let key: String
    let name: String
    let isLocal: Bool

    var id: String {
        key
    }

    /// Name for display — an unnamed peer still needs a row the user can click.
    var displayName: String {
        name.isEmpty ? "(unnamed)" : name
    }
}

/// Pure matching rules behind the Presence Viewer's peer search — the VS Code
/// extension's `graphSearchCandidates` / `graphSearchMatches`
/// (`webview-ui/peers/peers-element.ts`).
///
/// Foundation-pure and side-effect free so the rules are unit-testable without a
/// SpriteKit scene, a Ditto instance, or a view.
enum PresencePeerSearch {
    /// The synthetic cloud node, which is a searchable, focusable peer like any
    /// other. Must match `PresenceNetworkScene`'s own `cloudNodeKey`.
    static let cloudPeerKey = "ditto-cloud-node"
    static let cloudDisplayName = "Ditto Cloud"

    /// Peer keys are long; the results card shows a truncated column beside the
    /// device name rather than wrapping or eliding the name itself.
    static let keyDisplayLimit = 24

    /// Every peer the search may find, in card order: remote peers (as the
    /// presence graph reports them), then the cloud node, then the local device
    /// last.
    ///
    /// The source is the **full mesh**, never the mode-filtered graph — a
    /// multi-hop peer must be findable while "Direct" is on, because picking it
    /// is exactly how the user jumps the graph over to it.
    static func candidates(
        localPeer: (any PeerProtocol)?,
        remotePeers: [any PeerProtocol]
    ) -> [PresencePeerSearchMatch] {
        var seen: Set<String> = []
        var result: [PresencePeerSearchMatch] = []

        func add(key: String, name: String, isLocal: Bool) {
            guard !key.isEmpty, !seen.contains(key) else { return }
            seen.insert(key)
            result.append(PresencePeerSearchMatch(key: key, name: name, isLocal: isLocal))
        }

        for peer in remotePeers {
            add(key: peer.peerKeyString, name: peer.deviceName, isLocal: false)
        }
        // The cloud node only exists in the graph when the local peer has a cloud
        // link — the SDK does not expose remote peers' cloud status.
        if localPeer?.isConnectedToDittoCloud == true {
            add(key: cloudPeerKey, name: cloudDisplayName, isLocal: false)
        }
        if let localPeer {
            add(key: localPeer.peerKeyString, name: localPeer.deviceName, isLocal: true)
        }
        return result
    }

    /// Case-insensitive substring match over device name and peer key — the same
    /// two fields the Log Analyzer and System Metrics searches filter on.
    ///
    /// An all-whitespace query matches nothing *and* is not an active search;
    /// callers decide that with `isActive(query:)`.
    static func matches(
        in candidates: [PresencePeerSearchMatch],
        query: String
    ) -> [PresencePeerSearchMatch] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return [] }
        return candidates.filter {
            $0.name.lowercased().contains(needle) || $0.key.lowercased().contains(needle)
        }
    }

    /// Whether the box holds a real query. Whitespace alone is not a search.
    static func isActive(query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Compact peer-key column for the results card.
    static func truncatedKey(_ key: String) -> String {
        key.count > keyDisplayLimit ? "\(key.prefix(keyDisplayLimit))…" : key
    }
}
