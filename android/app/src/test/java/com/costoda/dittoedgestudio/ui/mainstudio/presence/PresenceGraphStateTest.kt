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
import org.junit.Assert.assertTrue
import org.junit.Test

class PresenceGraphStateTest {

    private fun makeLocal(isCloud: Boolean = false): LocalPeerInfo = LocalPeerInfo(
        peerId = "local",
        deviceName = "Test Device",
        sdkLanguage = "Kotlin",
        sdkPlatform = "Android",
        sdkVersion = "5.0.0",
        isCloudConnected = isCloud,
    )

    private fun makePeer(
        id: String,
        deviceName: String = "Pixel",
        connections: List<PeerConnectionInfo> = listOf(
            PeerConnectionInfo(id = "$id-conn-0", type = ConnectionType.LAN),
        ),
    ): SyncStatusInfo = SyncStatusInfo(
        peerId = id,
        deviceName = deviceName,
        dittoSdkVersion = "5.0.0",
        connections = connections,
    )

    @Test
    fun `Initializing state is not an Active state`() {
        val state: PeersUiState = PeersUiState.Initializing
        // toGraphModel is defined only on Active — callers pattern-match in PresenceGraphView.
        // This test guards against accidental refactors that would inherit toGraphModel into
        // the sealed base.
        assertTrue("Initializing should be its own subtype", state is PeersUiState.Initializing)
        assertFalse(state is PeersUiState.Active)
    }

    @Test
    fun `Active state with no remote peers contains only local`() {
        val state = PeersUiState.Active(localPeer = makeLocal(), remotePeers = emptyList())
        val model = state.toGraphModel(showDirectConnectedOnly = true)

        assertEquals(1, model.nodes.size)
        assertEquals("local", model.nodes[0].peerId)
        assertTrue(model.nodes[0].isLocal)
        assertEquals("Me", model.nodes[0].displayName)
        assertTrue(model.edges.isEmpty())
        assertEquals("local", model.localPeerId)
    }

    @Test
    fun `Active state with one remote peer produces one node and one edge`() {
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(makePeer("p1", deviceName = "Pixel 10a")),
        )
        val model = state.toGraphModel(showDirectConnectedOnly = true)

        assertEquals(2, model.nodes.size)
        assertEquals(1, model.edges.size)
        val edge = model.edges[0]
        assertEquals("local", edge.fromPeerId)
        assertEquals("p1", edge.toPeerId)
        assertEquals(ConnectionType.LAN, edge.type)
        assertFalse(edge.isCloud)
    }

    @Test
    fun `cloud flag synthesizes cloud node and cloud edge`() {
        val state = PeersUiState.Active(
            localPeer = makeLocal(isCloud = true),
            remotePeers = emptyList(),
        )
        val model = state.toGraphModel(showDirectConnectedOnly = true)

        assertEquals(2, model.nodes.size)
        val cloudNode = model.nodes.firstOrNull { it.isCloud }
        assertTrue("expected synthetic cloud node", cloudNode != null)
        assertEquals(CLOUD_NODE_KEY, cloudNode!!.peerId)
        assertEquals(CLOUD_NODE_DISPLAY_NAME, cloudNode.displayName)
        assertEquals(PeerDeviceKind.Cloud, cloudNode.deviceKind)

        assertEquals(1, model.edges.size)
        val cloudEdge = model.edges[0]
        assertTrue(cloudEdge.isCloud)
        assertEquals("cloud_local", cloudEdge.edgeId)
    }

    @Test
    fun `cloud flag false omits cloud node`() {
        val state = PeersUiState.Active(
            localPeer = makeLocal(isCloud = false),
            remotePeers = listOf(makePeer("p1")),
        )
        val model = state.toGraphModel(showDirectConnectedOnly = true)
        assertTrue(model.nodes.none { it.isCloud })
        assertTrue(model.edges.none { it.isCloud })
    }

    @Test
    fun `multi transport peer produces one edge per transport`() {
        val peer = makePeer(
            id = "p1",
            connections = listOf(
                PeerConnectionInfo(id = "c1", type = ConnectionType.Bluetooth),
                PeerConnectionInfo(id = "c2", type = ConnectionType.LAN),
            ),
        )
        val state = PeersUiState.Active(localPeer = makeLocal(), remotePeers = listOf(peer))
        val model = state.toGraphModel(showDirectConnectedOnly = true)

        assertEquals(2, model.edges.size)
        val types = model.edges.map { it.type }.toSet()
        assertEquals(setOf(ConnectionType.Bluetooth, ConnectionType.LAN), types)
    }

    @Test
    fun `duplicate connection of same type is deduplicated`() {
        // Mirrors iOS `seenPairTypes` dedup. SyncStatusInfo already distincts by type at
        // the repository layer, but `toGraphModel` defends against duplicates anyway via
        // its `seenPairTypes` set.
        val peer = makePeer(
            id = "p1",
            connections = listOf(
                PeerConnectionInfo(id = "c1", type = ConnectionType.LAN),
                PeerConnectionInfo(id = "c2", type = ConnectionType.LAN),
            ),
        )
        val state = PeersUiState.Active(localPeer = makeLocal(), remotePeers = listOf(peer))
        val model = state.toGraphModel(showDirectConnectedOnly = true)
        assertEquals(1, model.edges.size)
    }

    @Test
    fun `multicast connection produces a multicast edge in direct mode`() {
        val peer = makePeer(
            id = "p1",
            connections = listOf(
                PeerConnectionInfo(id = "c1", type = ConnectionType.Multicast),
            ),
        )
        val state = PeersUiState.Active(localPeer = makeLocal(), remotePeers = listOf(peer))
        val model = state.toGraphModel(showDirectConnectedOnly = true)

        assertEquals(1, model.edges.size)
        assertEquals(ConnectionType.Multicast, model.edges[0].type)
    }

    @Test
    fun `OFF mode preserves multicast mesh edges`() {
        // Mirrors the VS Code extension's peer-info test "preserves multicast edges":
        // a multicast edge reported in the mesh must survive into the graph model.
        val mesh = MeshTopology(
            localPeerKey = "local",
            peers = listOf(
                MeshPeer(peerKey = "p1", deviceName = "A"),
                MeshPeer(peerKey = "p2", deviceName = "B"),
            ),
            edges = listOf(
                MeshEdge(peer1 = "local", peer2 = "p1", type = ConnectionType.Multicast),
                MeshEdge(peer1 = "p1", peer2 = "p2", type = ConnectionType.Multicast),
            ),
        )
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = emptyList(),
            meshTopology = mesh,
        )
        val model = state.toGraphModel(showDirectConnectedOnly = false)

        assertEquals(2, model.edges.size)
        assertTrue(model.edges.all { it.type == ConnectionType.Multicast })
    }

    @Test
    fun `OFF mode surfaces non-direct peers from meshTopology`() {
        // A direct peer (p1) AND a peer not directly connected to local (p2). With the
        // toggle ON, only p1 should appear. With it OFF, both p1 and p2 should appear.
        val direct = makePeer("p1", "Pixel 10a")
        val mesh = MeshTopology(
            localPeerKey = "local",
            peers = listOf(
                MeshPeer(peerKey = "p1", deviceName = "Pixel 10a"),
                MeshPeer(peerKey = "p2", deviceName = "Galaxy Tab"),
            ),
            edges = listOf(
                MeshEdge(peer1 = "local", peer2 = "p1", type = ConnectionType.LAN),
                MeshEdge(peer1 = "p1", peer2 = "p2", type = ConnectionType.Bluetooth),
            ),
        )
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(direct),
            meshTopology = mesh,
        )

        val onModel = state.toGraphModel(showDirectConnectedOnly = true)
        assertEquals(2, onModel.nodes.size) // local + p1
        assertEquals(1, onModel.edges.size) // local↔p1 only

        val offModel = state.toGraphModel(showDirectConnectedOnly = false)
        assertEquals(3, offModel.nodes.size) // local + p1 + p2
        assertEquals(2, offModel.edges.size) // local↔p1 AND p1↔p2
        val remoteRemoteEdge = offModel.edges.firstOrNull {
            it.fromPeerId != "local" && it.toPeerId != "local"
        }
        assertTrue("expected a remote↔remote edge in OFF mode", remoteRemoteEdge != null)
        assertTrue("remote↔remote edge arcs outward", remoteRemoteEdge!!.arcOutward)
    }

    @Test
    fun `OFF mode dedupes same pair-type edges from A→B and B→A SDK duplicates`() {
        val mesh = MeshTopology(
            localPeerKey = "local",
            peers = listOf(
                MeshPeer(peerKey = "p1", deviceName = "A"),
                MeshPeer(peerKey = "p2", deviceName = "B"),
            ),
            edges = listOf(
                MeshEdge(peer1 = "p1", peer2 = "p2", type = ConnectionType.LAN),
                MeshEdge(peer1 = "p2", peer2 = "p1", type = ConnectionType.LAN),
            ),
        )
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = emptyList(),
            meshTopology = mesh,
        )
        val model = state.toGraphModel(showDirectConnectedOnly = false)
        assertEquals(1, model.edges.size)
    }

    @Test
    fun `direct mode drops a peer whose connections were all stripped`() {
        // The repository keeps a peer whose RAW connections touch local, but the
        // enabled-transport filter can strip every surviving connection. Such a
        // peer must not render as an edgeless floating node — the Direct node set
        // derives from the gated edges' endpoints (extension parity).
        val stripped = makePeer("p1", deviceName = "Pixel 10a", connections = emptyList())
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(stripped),
        )
        val model = state.toGraphModel(showDirectConnectedOnly = true)

        assertEquals(listOf("local"), model.nodes.map { it.peerId })
        assertTrue(model.edges.isEmpty())
    }

    @Test
    fun `expanded fallback to the direct star is not an expanded projection`() {
        // No mesh published yet (MeshTopology.Empty): the OFF projection falls
        // back to the direct-only star and must report itself as compact so the
        // view lays it out at 1× instead of the expanded radius scale.
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(makePeer("p1")),
            meshTopology = MeshTopology.Empty,
        )
        val model = state.toGraphModel(showDirectConnectedOnly = false)

        assertFalse(model.isExpandedProjection)
        assertEquals(2, model.nodes.size) // still the direct star, not an empty mesh
    }

    @Test
    fun `published mesh is an expanded projection`() {
        val mesh = MeshTopology(
            localPeerKey = "local",
            peers = listOf(MeshPeer(peerKey = "p1", deviceName = "A")),
            edges = listOf(MeshEdge(peer1 = "local", peer2 = "p1", type = ConnectionType.LAN)),
        )
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(makePeer("p1")),
            meshTopology = mesh,
        )

        assertTrue(state.toGraphModel(showDirectConnectedOnly = false).isExpandedProjection)
        assertFalse(state.toGraphModel(showDirectConnectedOnly = true).isExpandedProjection)
    }

    @Test
    fun `device kind detection from name`() {
        assertEquals(PeerDeviceKind.Phone, detectDeviceKind("Pixel 10a"))
        assertEquals(PeerDeviceKind.Phone, detectDeviceKind("iPhone 15 Pro"))
        assertEquals(PeerDeviceKind.Phone, detectDeviceKind("Galaxy S24"))
        assertEquals(PeerDeviceKind.Laptop, detectDeviceKind("MacBook Pro 14"))
        assertEquals(PeerDeviceKind.Cloud, detectDeviceKind("Ditto Cloud"))
        assertEquals(PeerDeviceKind.Server, detectDeviceKind("Unknown Box"))
        assertEquals(PeerDeviceKind.Server, detectDeviceKind(null))
    }

    @Test
    fun `ditto server is not misclassified as cloud`() {
        // Regression: an earlier substring("ditto") match incorrectly bucketed
        // on-prem "Ditto Server" peers as the synthetic Cloud node. Tighten
        // ensures they route to PeerDeviceKind.Server instead.
        assertEquals(PeerDeviceKind.Server, detectDeviceKind("Ditto Server"))
        assertEquals(PeerDeviceKind.Server, detectDeviceKind("ditto-server-prod-01"))
    }

    // ── Detail payload for the focus-mode card ──────────────────────────────

    @Test
    fun `direct-mode nodes carry sync progress and are marked directly connected`() {
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(
                makePeer("A").copy(
                    syncedUpToLocalCommitId = 42L,
                    lastUpdateReceivedTime = 1_700_000_000_000.0,
                    peerMetadata = "{role=kiosk, store=7}",
                    peerMetadataKeyCount = 2,
                ),
            ),
        )

        val detail = state.toGraphModel(showDirectConnectedOnly = true)
            .nodes.first { it.peerId == "A" }.detail

        assertTrue("a peer in the direct list is by definition direct", detail!!.isDirectlyConnected)
        assertEquals(42L, detail.syncedUpToLocalCommitId)
        assertEquals(1_700_000_000_000.0, detail.lastUpdateReceivedTime!!, 0.001)
        assertEquals("metadata is summarised by key count, never inlined", 2, detail.peerMetadataKeyCount)
    }

    @Test
    fun `mesh-mode marks an indirect peer as having no sync session`() {
        // B is in the mesh but not in remotePeers — i.e. no session with this device, so
        // system:data_sync_info has no row for it and the card must say so rather than
        // rendering a blank commit id.
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(makePeer("A").copy(syncedUpToLocalCommitId = 7L)),
            meshTopology = MeshTopology(
                localPeerKey = "local",
                peers = listOf(
                    MeshPeer(peerKey = "A", deviceName = "Pixel"),
                    MeshPeer(peerKey = "B", deviceName = "iPhone"),
                ),
                edges = listOf(
                    MeshEdge("local", "A", ConnectionType.LAN),
                    MeshEdge("A", "B", ConnectionType.Bluetooth),
                ),
            ),
        )

        val nodes = state.toGraphModel(showDirectConnectedOnly = false).nodes
        val a = nodes.first { it.peerId == "A" }.detail!!
        val b = nodes.first { it.peerId == "B" }.detail!!

        assertTrue(a.isDirectlyConnected)
        assertEquals(7L, a.syncedUpToLocalCommitId)

        assertFalse("B has no session with us", b.isDirectlyConnected)
        assertEquals("no session means no commit to report", null, b.syncedUpToLocalCommitId)
        assertEquals(null, b.lastUpdateReceivedTime)
    }

    @Test
    fun `mesh-mode carries the SDK facts that are known for indirect peers`() {
        // Everything on DittoPeer is reported for peers we cannot reach — that is the
        // whole reason the card is worth showing for them.
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = emptyList(),
            meshTopology = MeshTopology(
                localPeerKey = "local",
                peers = listOf(
                    MeshPeer(
                        peerKey = "B",
                        deviceName = "iPhone 17 Pro",
                        os = com.costoda.dittoedgestudio.domain.model.PeerOS.iOS,
                        dittoSdkVersion = "5.1.0",
                        isConnectedToDittoServer = true,
                        isCompatible = true,
                        peerMetadata = """{"a":1}""",
                        peerMetadataKeyCount = 1,
                    ),
                ),
                edges = listOf(MeshEdge("local", "B", ConnectionType.LAN)),
            ),
        )

        val detail = state.toGraphModel(showDirectConnectedOnly = false)
            .nodes.first { it.peerId == "B" }.detail!!

        assertEquals(com.costoda.dittoedgestudio.domain.model.PeerOS.iOS, detail.os)
        assertEquals("5.1.0", detail.dittoSdkVersion)
        assertEquals(true, detail.isConnectedToDittoServer)
        assertEquals(true, detail.isCompatible)
        assertEquals(1, detail.peerMetadataKeyCount)
        assertFalse("not in remotePeers → indirect", detail.isDirectlyConnected)
    }

    @Test
    fun `the synthetic cloud node has no peer record behind it`() {
        val state = PeersUiState.Active(
            localPeer = makeLocal(isCloud = true),
            remotePeers = listOf(makePeer("A")),
        )

        val cloud = state.toGraphModel(showDirectConnectedOnly = true)
            .nodes.first { it.peerId == CLOUD_NODE_KEY }

        assertTrue("cloud is synthetic — no DittoPeer exists for it", cloud.detail == null)
        assertTrue(cloud.isCloud)
    }

    @Test
    fun `metadata key counts are carried through, never parsed from the string`() {
        // The count must come from the SDK's typed object. Deriving it from the raw
        // string is what the deleted jsonKeyCount() did, and it silently always returned
        // 0: ObjectValue.toString() emits Kotlin map syntax ("{role=my kiosk}"), which
        // org.json rejects.
        val state = PeersUiState.Active(
            localPeer = makeLocal(),
            remotePeers = listOf(
                makePeer("A").copy(
                    peerMetadata = "{role=kiosk, store=7}", // what the SDK really produces
                    peerMetadataKeyCount = 2,
                ),
            ),
        )

        val detail = state.toGraphModel(showDirectConnectedOnly = true)
            .nodes.first { it.peerId == "A" }.detail!!

        assertEquals(2, detail.peerMetadataKeyCount)
        assertEquals("{role=kiosk, store=7}", detail.peerMetadata)
    }

    @Test
    fun `the local peer has a real record, not a synthetic-node placeholder`() {
        // Tapping "Me" opens a card like any other peer. Leaving detail null made that
        // card claim the device we know most about had no peer record at all.
        val state = PeersUiState.Active(
            localPeer = makeLocal(isCloud = true),
            remotePeers = listOf(makePeer("A")),
        )

        for (directOnly in listOf(true, false)) {
            val me = state.toGraphModel(showDirectConnectedOnly = directOnly)
                .nodes.first { it.isLocal }
            val detail = me.detail
            assertTrue("local peer must carry a detail record (directOnly=$directOnly)", detail != null)
            assertEquals("local", detail!!.peerKey)
            assertEquals("Test Device", detail.deviceName)
            assertEquals("5.0.0", detail.dittoSdkVersion)
            assertEquals(true, detail.isConnectedToDittoServer)
            // We hold no sync session with ourselves; the card renders "This device".
            assertEquals(null, detail.syncedUpToLocalCommitId)
        }
    }
}
