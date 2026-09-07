package com.costoda.dittoedgestudio.ui.mainstudio.presence

import com.costoda.dittoedgestudio.data.session.PeersUiState

/**
 * One peer row in the Presence Viewer's search results card.
 *
 * [isLocal] rows are listed — so a full-opacity **Me** makes sense while the rest of
 * the graph dims — but are never clickable: the graph deliberately rejects focusing
 * the local peer (in Direct mode every edge touches it, so focusing it would exempt
 * the whole graph from dimming).
 */
data class PeerSearchMatch(
    val key: String,
    val name: String,
    val isLocal: Boolean,
) {
    /** An unnamed peer still needs a row the user can tap. */
    val displayName: String get() = name.ifBlank { "(unnamed)" }
}

/**
 * Pure matching rules behind the Presence Viewer's peer search — the VS Code
 * extension's `graphSearchCandidates` / `graphSearchMatches`
 * (`webview-ui/peers/peers-element.ts`).
 *
 * Deliberately Compose-free so the rules are unit-testable on the JVM without a
 * device, a Ditto instance, or a composition.
 */
object PresencePeerSearch {
    /** Peer keys are long; the results card shows a truncated column beside the name. */
    const val KEY_DISPLAY_LIMIT: Int = 24

    /**
     * Every peer the search may find, in card order: remote peers (as the presence
     * graph reports them), then the cloud node, then the local device last.
     *
     * The source is the **full mesh** ([PeersUiState.Active.meshTopology]), never the
     * mode-filtered projection — a multi-hop peer must be findable while "Direct" is
     * on, because picking it is exactly how the user jumps the graph over to it.
     *
     * Before the first presence emission there is no mesh topology at all, so the
     * directly connected peers stand in — the same fallback [toGraphModel] makes.
     */
    fun candidates(state: PeersUiState): List<PeerSearchMatch> {
        if (state !is PeersUiState.Active) return emptyList()
        val local = state.localPeer ?: return emptyList()
        val result = mutableListOf<PeerSearchMatch>()
        val seen = mutableSetOf<String>()

        fun add(key: String, name: String, isLocal: Boolean) {
            if (key.isBlank() || !seen.add(key)) return
            result.add(PeerSearchMatch(key = key, name = name, isLocal = isLocal))
        }

        val mesh = state.meshTopology
        // Direct-peer names win over the raw graph's, so a peer that appears in both
        // keeps the same label the pill shows (buildFullMeshModel parity).
        val directNameById = state.remotePeers.associate { it.peerId to it.deviceName }
        if (mesh.localPeerKey.isNotBlank()) {
            for (peer in mesh.peers) {
                if (peer.peerKey == local.peerId) continue
                val name = directNameById[peer.peerKey]?.takeIf { !it.isNullOrBlank() }
                    ?: peer.deviceName?.takeIf { it.isNotBlank() }
                    ?: peer.peerKey.take(8)
                add(peer.peerKey, name, isLocal = false)
            }
        } else {
            // Pre-first-emission fallback: only the direct peers are known. The cloud
            // is a synthetic node added below, never a real peer row.
            for (peer in state.remotePeers) {
                if (peer.isDittoServer) continue
                add(peer.peerId, peer.deviceName.orEmpty(), isLocal = false)
            }
        }
        // The cloud node exists in the graph only when the local peer has a cloud link
        // — the SDK does not expose remote peers' cloud status.
        if (local.isCloudConnected) {
            add(CLOUD_NODE_KEY, CLOUD_NODE_DISPLAY_NAME, isLocal = false)
        }
        add(local.peerId, local.deviceName, isLocal = true)
        return result
    }

    /**
     * Case-insensitive substring match over device name and peer key — the same two
     * fields the Log Analyzer and System Metrics searches filter on. The query is
     * trimmed first; whitespace alone matches nothing.
     */
    fun matches(candidates: List<PeerSearchMatch>, query: String): List<PeerSearchMatch> {
        val needle = query.trim().lowercase()
        if (needle.isEmpty()) return emptyList()
        return candidates.filter {
            it.name.lowercase().contains(needle) || it.key.lowercase().contains(needle)
        }
    }

    /** Whether the box holds a real query. Whitespace alone is not a search. */
    fun isActive(query: String): Boolean = query.isNotBlank()

    /**
     * The match set to hand the renderer.
     *
     * `null` when the box is empty (no search dimming at all); an **empty set** when
     * the query has no hits, which deliberately dims the whole graph — "nothing here"
     * is useful feedback. Conflating those two states is the defect this exists to
     * prevent, so the decision lives in one place.
     */
    fun matchIds(candidates: List<PeerSearchMatch>, query: String): Set<String>? {
        if (!isActive(query)) return null
        return matches(candidates, query).mapTo(mutableSetOf()) { it.key }
    }

    /** Compact peer-key column for the results card. */
    fun truncatedKey(key: String): String =
        if (key.length > KEY_DISPLAY_LIMIT) "${key.take(KEY_DISPLAY_LIMIT)}…" else key

    /**
     * Whether the tab row should give the whole row to the search field.
     *
     * Below the inline threshold the field is normally collapsed behind a magnifier,
     * but an ACTIVE QUERY must always keep a visible field and clear button. The
     * query lives on the retained view model while [searchExpanded] is view-local
     * and can only be set by that magnifier — which never renders at inline widths.
     * So typing inline leaves [searchExpanded] false, and a width change crossing
     * the threshold downward (folding a foldable, rotating a tablet, resizing a
     * pane) would otherwise strand the user: graph dimmed, results card up, no field
     * and no way to clear it.
     */
    fun showsExpandedNarrowSearch(
        onSearchTab: Boolean,
        inlineSearch: Boolean,
        searchExpanded: Boolean,
        searchIsActive: Boolean,
    ): Boolean = onSearchTab && !inlineSearch && (searchExpanded || searchIsActive)
}
