package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoConnection
import com.ditto.kotlin.DittoConnectionType
import com.ditto.kotlin.DittoPeer
import com.ditto.kotlin.DittoPresence
import com.ditto.kotlin.DittoPresenceGraph
import com.ditto.kotlin.serialization.DittoJsonSerializable
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.flowOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemRepositoryTest {

    private fun makeRepo() = SystemRepositoryImpl(
        CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
    )

    @Test
    fun `initial state has empty peers and null localPeer`() {
        val repo = makeRepo()

        assertTrue(repo.peers.value.isEmpty())
        assertNull(repo.localPeer.value)
        assertEquals(ConnectionsByTransport.Empty, repo.connectionsByTransport.value)
    }

    @Test
    fun `stopObserving resets all flows to empty`() {
        val repo = makeRepo()

        // stopObserving when nothing is observing should safely no-op
        repo.stopObserving()

        assertTrue(repo.peers.value.isEmpty())
        assertNull(repo.localPeer.value)
        assertEquals(ConnectionsByTransport.Empty, repo.connectionsByTransport.value)
    }

    @Test
    fun `mesh aggregation includes edges only the local peer advertises`() {
        // Ditto usually reports an undirected edge from both endpoints, but the
        // local peer is authoritative for edges attached to this process: an edge
        // (notably multicast) that ONLY localPeer.connections carries must still
        // land in the mesh topology — and keep the remote peer drawable.
        val localToRemote = mockk<DittoConnection> {
            every { id } returns "c0"
            every { peer1 } returns "local"
            every { peer2 } returns "p1"
            every { connectionType } returns DittoConnectionType.Multicast
        }
        val localPeer = mockPeer("local", connections = listOf(localToRemote))
        // The remote side advertises nothing.
        val remotePeer = mockPeer("p1", connections = emptyList())
        val graph = mockk<DittoPresenceGraph> {
            every { this@mockk.localPeer } returns localPeer
            every { remotePeers } returns listOf(remotePeer)
        }
        val presence = mockk<DittoPresence> {
            every { observe() } returns flowOf(graph)
        }
        val ditto = mockk<Ditto>(relaxed = true) {
            every { this@mockk.presence } returns presence
        }

        val repo = makeRepo()
        repo.startObserving(ditto)

        val mesh = repo.meshTopology.value
        assertEquals("local", mesh.localPeerKey)
        assertEquals(1, mesh.edges.size)
        val edge = mesh.edges.single()
        assertEquals(setOf("local", "p1"), setOf(edge.peer1, edge.peer2))
        assertEquals(ConnectionType.Multicast, edge.type)
        // p1 participates in the aggregated edge, so the orphan filter keeps it.
        assertEquals(listOf("p1"), mesh.peers.map { it.peerKey })
    }

    private fun mockPeer(peerKey: String, connections: List<DittoConnection>): DittoPeer = mockk {
        every { this@mockk.peerKey } returns peerKey
        every { this@mockk.connections } returns connections
        every { deviceName } returns "Test Device"
        every { dittoSdkVersion } returns "5.1.0"
        every { os } returns null
        every { isConnectedToDittoServer } returns false
        every { peerMetadata } returns mockk<DittoJsonSerializable.ObjectValue> {
            every { isNull } returns true
        }
        every { identityServiceMetadata } returns mockk<DittoJsonSerializable.ObjectValue> {
            every { isNull } returns true
        }
    }
}
