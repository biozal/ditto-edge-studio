package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.MeshEdge
import com.costoda.dittoedgestudio.domain.model.MeshPeer
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Expanded-mode orphan filter behind [filterOrphanMeshPeers] (VS Code extension
 * `buildPresenceGraphView` pass 2): remote peers participating in no aggregated
 * edge are dropped so they don't render as floating pills in the window right
 * after `sync.stop()` → `sync.start()`, when transports stay alive across the
 * toggle but sync sessions don't.
 */
class OrphanMeshPeerFilterTest {

    @Test
    fun `peers appearing in at least one edge are kept`() {
        val peers = listOf(MeshPeer(peerKey = "a", deviceName = "A"), MeshPeer(peerKey = "b", deviceName = "B"))
        val edges = listOf(
            MeshEdge(peer1 = "local", peer2 = "a", type = ConnectionType.LAN),
            MeshEdge(peer1 = "a", peer2 = "b", type = ConnectionType.Bluetooth),
        )

        val result = filterOrphanMeshPeers(peers, edges)

        assertEquals(listOf("a", "b"), result.map { it.peerKey })
    }

    @Test
    fun `peer participating in no edge is dropped`() {
        val peers = listOf(MeshPeer(peerKey = "a", deviceName = "A"), MeshPeer(peerKey = "orphan", deviceName = "Orphan"))
        val edges = listOf(MeshEdge(peer1 = "local", peer2 = "a", type = ConnectionType.LAN))

        val result = filterOrphanMeshPeers(peers, edges)

        assertEquals(listOf("a"), result.map { it.peerKey })
    }

    @Test
    fun `peer appearing only as peer2 of another peer's connection is kept`() {
        // X might only be reachable via its appearance as peer2 in Y's
        // connection list — it must still be drawn while Y advertises the edge.
        val peers = listOf(MeshPeer(peerKey = "x", deviceName = null))
        val edges = listOf(MeshEdge(peer1 = "y", peer2 = "x", type = ConnectionType.Multicast))

        val result = filterOrphanMeshPeers(peers, edges)

        assertEquals(listOf("x"), result.map { it.peerKey })
    }

    @Test
    fun `no edges drops every remote peer`() {
        val peers = listOf(MeshPeer(peerKey = "a", deviceName = "A"))

        val result = filterOrphanMeshPeers(peers, emptyList())

        assertEquals(emptyList<String>(), result.map { it.peerKey })
    }
}
