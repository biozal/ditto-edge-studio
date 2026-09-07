package com.costoda.dittoedgestudio.ui.mainstudio.presence

import com.costoda.dittoedgestudio.data.session.PeersUiState
import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.LocalPeerInfo
import com.costoda.dittoedgestudio.domain.model.MeshEdge
import com.costoda.dittoedgestudio.domain.model.MeshPeer
import com.costoda.dittoedgestudio.domain.model.MeshTopology
import com.costoda.dittoedgestudio.domain.model.PeerConnectionInfo
import com.costoda.dittoedgestudio.domain.model.SyncStatusInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The pure matching rules behind the Presence Viewer's peer search, and the
 * dimming precedence they feed — the VS Code extension's `graphSearchCandidates` /
 * `graphSearchMatches` / `focusForPeer`.
 */
class PresencePeerSearchTest {

    private fun makeLocal(isCloud: Boolean = false, name: String = "My Fold"): LocalPeerInfo =
        LocalPeerInfo(
            peerId = "local",
            deviceName = name,
            sdkLanguage = "Kotlin",
            sdkPlatform = "Android",
            sdkVersion = "5.1.0",
            isCloudConnected = isCloud,
        )

    private fun makeDirectPeer(
        id: String,
        deviceName: String = "Pixel",
        isDittoServer: Boolean = false,
    ): SyncStatusInfo = SyncStatusInfo(
        peerId = id,
        deviceName = deviceName,
        dittoSdkVersion = "5.1.0",
        connections = listOf(PeerConnectionInfo(id = "$id-conn-0", type = ConnectionType.LAN)),
        isDittoServer = isDittoServer,
    )

    private fun makeMeshPeer(key: String, deviceName: String?): MeshPeer =
        MeshPeer(peerKey = key, deviceName = deviceName)

    /**
     * local — A — B: B is reachable only through A, so it is absent from the
     * direct-only projection but present in the mesh topology.
     */
    private fun multiHopState(isCloud: Boolean = false): PeersUiState.Active = PeersUiState.Active(
        localPeer = makeLocal(isCloud = isCloud),
        remotePeers = listOf(makeDirectPeer("A", deviceName = "Alpha")),
        meshTopology = MeshTopology(
            localPeerKey = "local",
            peers = listOf(
                makeMeshPeer("local", "My Fold"),
                makeMeshPeer("A", "Alpha"),
                makeMeshPeer("B", "Bravo"),
            ),
            edges = listOf(
                MeshEdge(peer1 = "local", peer2 = "A", type = ConnectionType.LAN),
                MeshEdge(peer1 = "A", peer2 = "B", type = ConnectionType.LAN),
            ),
        ),
    )

    // ── Candidates ───────────────────────────────────────────────────────────

    @Test
    fun `candidates come from the full mesh, so a multi-hop peer is findable`() {
        // ARRANGE: B is two hops away — finding it is the whole point of the search
        val state = multiHopState()

        // ACT
        val candidates = PresencePeerSearch.candidates(state)

        // ASSERT
        assertEquals(listOf("A", "B", "local"), candidates.map { it.key })
    }

    @Test
    fun `card order is remote peers, then cloud, then the local device last`() {
        // ARRANGE
        val state = multiHopState(isCloud = true)

        // ACT
        val candidates = PresencePeerSearch.candidates(state)

        // ASSERT
        assertEquals(listOf("A", "B", CLOUD_NODE_KEY, "local"), candidates.map { it.key })
        assertTrue(candidates.last().isLocal)
        // The cloud node is a normal, focusable peer — only the local one is not.
        assertFalse(candidates[2].isLocal)
        assertEquals(CLOUD_NODE_DISPLAY_NAME, candidates[2].name)
    }

    @Test
    fun `no cloud candidate without a cloud link`() {
        // ARRANGE: the SDK only exposes the LOCAL peer's cloud status
        val state = multiHopState(isCloud = false)

        // ACT
        val candidates = PresencePeerSearch.candidates(state)

        // ASSERT
        assertFalse(candidates.any { it.key == CLOUD_NODE_KEY })
    }

    @Test
    fun `before the first presence emission the direct peers stand in`() {
        // ARRANGE: no mesh topology yet — the same fallback toGraphModel makes
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(
                makeDirectPeer("A", deviceName = "Alpha"),
                makeDirectPeer("cloud-row", isDittoServer = true),
            ),
        )

        // ACT
        val candidates = PresencePeerSearch.candidates(state)

        // ASSERT: the Ditto server row is not a real peer — the cloud node is synthetic
        assertEquals(listOf("A", "local"), candidates.map { it.key })
    }

    @Test
    fun `an Initializing state has no candidates`() {
        // ARRANGE / ACT / ASSERT
        assertTrue(PresencePeerSearch.candidates(PeersUiState.Initializing).isEmpty())
    }

    @Test
    fun `a mesh peer without a device name falls back to a key prefix`() {
        // ARRANGE
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = emptyList(),
            meshTopology = MeshTopology(
                localPeerKey = "local",
                peers = listOf(makeMeshPeer("abcdefghijkl", null)),
                edges = emptyList(),
            ),
        )

        // ACT
        val candidates = PresencePeerSearch.candidates(state)

        // ASSERT
        assertEquals("abcdefgh", candidates.first { it.key == "abcdefghijkl" }.name)
    }

    @Test
    fun `a direct peer's name wins over the raw graph's, so the pill label matches`() {
        // ARRANGE: the graph reports a stale name for A
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(makeDirectPeer("A", deviceName = "Alpha (renamed)")),
            meshTopology = MeshTopology(
                localPeerKey = "local",
                peers = listOf(makeMeshPeer("A", "Alpha")),
                edges = emptyList(),
            ),
        )

        // ACT
        val candidates = PresencePeerSearch.candidates(state)

        // ASSERT
        assertEquals("Alpha (renamed)", candidates.first { it.key == "A" }.name)
    }

    // ── Matching ─────────────────────────────────────────────────────────────

    @Test
    fun `matching is case-insensitive over both device name and peer key`() {
        // ARRANGE
        val candidates = PresencePeerSearch.candidates(multiHopState())

        // ACT / ASSERT
        assertEquals(listOf("B"), PresencePeerSearch.matches(candidates, "bravo").map { it.key })
        assertEquals(listOf("B"), PresencePeerSearch.matches(candidates, "BRAVO").map { it.key })
        // key match
        assertEquals(listOf("A"), PresencePeerSearch.matches(candidates, "a").map { it.key }.filter { it == "A" })
        // substring, not prefix
        assertEquals(listOf("B"), PresencePeerSearch.matches(candidates, "rav").map { it.key })
    }

    @Test
    fun `the query is trimmed before matching`() {
        // ARRANGE
        val candidates = PresencePeerSearch.candidates(multiHopState())

        // ACT / ASSERT
        assertEquals(listOf("A"), PresencePeerSearch.matches(candidates, "  alpha \n").map { it.key })
    }

    @Test
    fun `whitespace alone is not an active search and matches nothing`() {
        // ARRANGE
        val candidates = PresencePeerSearch.candidates(multiHopState())

        // ACT / ASSERT
        assertFalse(PresencePeerSearch.isActive("   "))
        assertFalse(PresencePeerSearch.isActive(""))
        assertTrue(PresencePeerSearch.isActive(" a "))
        assertTrue(PresencePeerSearch.matches(candidates, "   ").isEmpty())
    }

    @Test
    fun `the local device is matchable and flagged so the card refuses to focus it`() {
        // ARRANGE
        val candidates = PresencePeerSearch.candidates(multiHopState())

        // ACT
        val matches = PresencePeerSearch.matches(candidates, "fold")

        // ASSERT
        assertEquals(listOf("local"), matches.map { it.key })
        assertTrue(matches.single().isLocal)
    }

    // ── null vs empty: the state distinction the whole feature turns on ───────

    @Test
    fun `an empty box means no dimming at all`() {
        // ARRANGE
        val candidates = PresencePeerSearch.candidates(multiHopState())

        // ACT / ASSERT: null = not searching
        assertNull(PresencePeerSearch.matchIds(candidates, ""))
        assertNull(PresencePeerSearch.matchIds(candidates, "   "))
    }

    @Test
    fun `a zero-hit query is an EMPTY set, which dims the whole graph`() {
        // ARRANGE
        val candidates = PresencePeerSearch.candidates(multiHopState())

        // ACT
        val ids = PresencePeerSearch.matchIds(candidates, "nothing-like-this")

        // ASSERT: emphatically NOT null — "nothing here" is useful feedback, and
        // conflating it with "not searching" is the defect this guards.
        assertEquals(emptySet<String>(), ids)
    }

    @Test
    fun `an active query with hits yields exactly the matching keys`() {
        // ARRANGE
        val candidates = PresencePeerSearch.candidates(multiHopState())

        // ACT / ASSERT
        assertEquals(setOf("B"), PresencePeerSearch.matchIds(candidates, "bravo"))
    }

    // ── Display helpers ──────────────────────────────────────────────────────

    @Test
    fun `long peer keys are truncated for the key column`() {
        // ARRANGE
        val long = "a".repeat(40)

        // ACT / ASSERT
        assertEquals("short", PresencePeerSearch.truncatedKey("short"))
        assertEquals("a".repeat(24) + "…", PresencePeerSearch.truncatedKey(long))
    }

    @Test
    fun `an unnamed peer still renders a tappable label`() {
        // ARRANGE / ACT
        val match = PeerSearchMatch(key = "A", name = "", isLocal = false)

        // ASSERT
        assertEquals("(unnamed)", match.displayName)
    }
}

/**
 * The dimming precedence the search feeds into. Search is the WEAKEST source: an
 * explicit focus and a tap-to-isolate selection both win over it (extension
 * `scene.ts` `focusForPeer` / `focusForLine`).
 */
class PresenceSearchDimmingTest {

    @Test
    fun `with nothing active every peer is lit`() {
        // ARRANGE / ACT
        val lit = PresenceFocusPlanner.litPeerIds(
            focusedPeerId = null,
            focusNeighbourhood = emptySet(),
            selectedPeerId = null,
            selectionNeighbourhood = emptySet(),
            searchMatchIds = null,
        )

        // ASSERT: null means "no dimming source" — the caller lights everyone
        assertNull(lit)
        assertNull(
            PresenceFocusPlanner.litEdgeAnchors(
                focusedPeerId = null,
                selectedPeerId = null,
                searchMatchIds = null,
            ),
        )
    }

    @Test
    fun `an active search lights only its matches`() {
        // ARRANGE / ACT
        val lit = PresenceFocusPlanner.litPeerIds(
            focusedPeerId = null,
            focusNeighbourhood = emptySet(),
            selectedPeerId = null,
            selectionNeighbourhood = emptySet(),
            searchMatchIds = setOf("B"),
        )

        // ASSERT
        assertEquals(setOf("B"), lit)
        assertEquals(
            setOf("B"),
            PresenceFocusPlanner.litEdgeAnchors(null, null, setOf("B")),
        )
    }

    @Test
    fun `a zero-hit search lights nobody rather than everybody`() {
        // ARRANGE / ACT
        val lit = PresenceFocusPlanner.litPeerIds(
            focusedPeerId = null,
            focusNeighbourhood = emptySet(),
            selectedPeerId = null,
            selectionNeighbourhood = emptySet(),
            searchMatchIds = emptySet(),
        )

        // ASSERT: an empty set is a dimming source; null is not
        assertEquals(emptySet<String>(), lit)
    }

    @Test
    fun `focus outranks an active search`() {
        // ARRANGE / ACT
        val lit = PresenceFocusPlanner.litPeerIds(
            focusedPeerId = "A",
            focusNeighbourhood = setOf("A", "local", "B"),
            selectedPeerId = null,
            selectionNeighbourhood = emptySet(),
            searchMatchIds = setOf("B"),
        )

        // ASSERT: the whole orbit stays lit even though only B matched
        assertEquals(setOf("A", "local", "B"), lit)
        assertEquals(setOf("A"), PresenceFocusPlanner.litEdgeAnchors("A", null, setOf("B")))
    }

    @Test
    fun `a tap-to-isolate selection outranks an active search`() {
        // ARRANGE / ACT
        val lit = PresenceFocusPlanner.litPeerIds(
            focusedPeerId = null,
            focusNeighbourhood = emptySet(),
            selectedPeerId = "A",
            selectionNeighbourhood = setOf("A", "local"),
            searchMatchIds = setOf("B"),
        )

        // ASSERT
        assertEquals(setOf("A", "local"), lit)
        assertEquals(setOf("A"), PresenceFocusPlanner.litEdgeAnchors(null, "A", setOf("B")))
    }

    @Test
    fun `search dims to the selection level, not the far fainter focus backdrop`() {
        // ARRANGE / ACT / ASSERT: the extension defines the search treatment as
        // "the same treatment a click selection gives", so it reuses those alphas.
        assertEquals(
            PresenceFocusPlanner.SELECTION_PEER_ALPHA,
            PresenceFocusPlanner.dimmedPeerAlpha(focusedPeerId = null),
        )
        assertEquals(
            PresenceFocusPlanner.SELECTION_LINE_ALPHA,
            PresenceFocusPlanner.dimmedEdgeAlpha(focusedPeerId = null),
        )
        assertEquals(
            PresenceFocusPlanner.CONTEXT_PEER_ALPHA,
            PresenceFocusPlanner.dimmedPeerAlpha(focusedPeerId = "A"),
        )
        assertEquals(
            PresenceFocusPlanner.CONTEXT_LINE_ALPHA,
            PresenceFocusPlanner.dimmedEdgeAlpha(focusedPeerId = "A"),
        )
    }
}
