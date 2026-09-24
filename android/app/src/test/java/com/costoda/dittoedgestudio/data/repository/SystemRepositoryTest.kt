package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.ConnectionType
import com.costoda.dittoedgestudio.domain.model.ConnectionsByTransport
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
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

    // Both the collection scope AND the metrics dispatcher are Unconfined.
    //
    // `updatePresence` awaits the `system:data_sync_info` enrichment before it publishes
    // meshTopology/peers, and that await hops to the metrics dispatcher. Leaving that one on
    // Dispatchers.IO meant the hop was a real suspension point: `startObserving` returned
    // while the coroutine was still parked, so a synchronous read of `meshTopology.value`
    // raced the assignment and saw MeshTopology.Empty. Pinning both to Unconfined makes the
    // whole pipeline run to completion inside `startObserving`, which is what these tests
    // assume. Production still gets Dispatchers.IO by default.
    private fun makeRepo(database: DittoDatabase? = null) = SystemRepositoryImpl(
        CoroutineScope(SupervisorJob() + Dispatchers.Unconfined),
        databaseProvider = { database },
        metricsDispatcher = Dispatchers.Unconfined,
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

    @Test
    fun `presence counts a two-sided connection once per remote peer and transport`() {
        val lan = mockConnection("lan", "local", "p1", DittoConnectionType.AccessPoint)
        val reverseLan = mockConnection("lan-reverse", "p1", "local", DittoConnectionType.AccessPoint)
        val bluetooth = mockConnection("ble", "local", "p1", DittoConnectionType.Bluetooth)
        val indirect = mockConnection("indirect", "p1", "p2", DittoConnectionType.AccessPoint)

        val repo = publishGraph(
            localConnections = listOf(lan, bluetooth),
            remotePeers = listOf(mockPeer("p1", listOf(reverseLan, bluetooth, indirect))),
        )

        assertEquals(1, repo.connectionsByTransport.value.lan)
        assertEquals(1, repo.connectionsByTransport.value.bluetooth)
        assertEquals(
            setOf(ConnectionType.LAN, ConnectionType.Bluetooth),
            repo.peers.value.single().connections.map { it.type }.toSet(),
        )
        assertEquals(2, repo.peers.value.single().connections.size)
        repo.stopObserving()
    }

    @Test
    fun `presence counts every local-only remote endpoint on the same transport`() {
        val first = mockConnection("m1", "local", "p1", DittoConnectionType.Multicast)
        val second = mockConnection("m2", "p2", "local", DittoConnectionType.Multicast)

        val repo = publishGraph(
            localConnections = listOf(first, second),
            remotePeers = listOf(mockPeer("p1", emptyList()), mockPeer("p2", emptyList())),
        )

        assertEquals(2, repo.connectionsByTransport.value.multicast)
        assertEquals(2, repo.peers.value.size)
        assertTrue(repo.peers.value.all { peer ->
            peer.connections.map { it.type } == listOf(ConnectionType.Multicast)
        })
        assertEquals(2, repo.meshTopology.value.edges.size)
        repo.stopObserving()
    }

    @Test
    fun `peer card transports exclude other local endpoints and transitive edges`() {
        val direct = mockConnection("m1", "local", "p1", DittoConnectionType.Multicast)
        val otherLocal = mockConnection("lan", "local", "p2", DittoConnectionType.AccessPoint)
        val transitive = mockConnection("ble", "p1", "p2", DittoConnectionType.Bluetooth)

        val repo = publishGraph(
            localConnections = listOf(direct, otherLocal),
            remotePeers = listOf(mockPeer("p1", listOf(transitive)), mockPeer("p2", listOf(transitive))),
        )

        val cards = repo.peers.value.associateBy { it.peerId }
        assertEquals(listOf(ConnectionType.Multicast), cards.getValue("p1").connections.map { it.type })
        assertEquals(listOf(ConnectionType.LAN), cards.getValue("p2").connections.map { it.type })
        assertEquals(1, repo.connectionsByTransport.value.multicast)
        assertEquals(1, repo.connectionsByTransport.value.lan)
        assertEquals(0, repo.connectionsByTransport.value.bluetooth)
        assertEquals(3, repo.meshTopology.value.edges.size)
        repo.stopObserving()
    }

    @Test
    fun `peer card still filters user-disabled transports advertised only locally`() {
        val lan = mockConnection("lan", "local", "p1", DittoConnectionType.AccessPoint)
        val bluetooth = mockConnection("ble", "p1", "local", DittoConnectionType.Bluetooth)

        val repo = publishGraph(
            localConnections = listOf(lan, bluetooth),
            remotePeers = listOf(mockPeer("p1", emptyList())),
            database = DittoDatabase(databaseId = "test", isLanEnabled = false, isBluetoothLeEnabled = true),
        )

        assertEquals(listOf(ConnectionType.Bluetooth), repo.peers.value.single().connections.map { it.type })
        assertEquals(0, repo.connectionsByTransport.value.lan)
        assertEquals(1, repo.connectionsByTransport.value.bluetooth)
        repo.stopObserving()
    }

    private fun publishGraph(
        localConnections: List<DittoConnection>,
        remotePeers: List<DittoPeer>,
        database: DittoDatabase? = null,
    ): SystemRepositoryImpl {
        val local = mockPeer("local", localConnections)
        val graph = mockk<DittoPresenceGraph> {
            every { localPeer } returns local
            every { this@mockk.remotePeers } returns remotePeers
        }
        val presence = mockk<DittoPresence> { every { observe() } returns flowOf(graph) }
        val ditto = mockk<Ditto>(relaxed = true) {
            every { this@mockk.presence } returns presence
        }
        return makeRepo(database).also { it.startObserving(ditto) }
    }

    private fun mockConnection(
        id: String,
        first: String,
        second: String,
        type: DittoConnectionType,
    ): DittoConnection = mockk {
        every { this@mockk.id } returns id
        every { peer1 } returns first
        every { peer2 } returns second
        every { connectionType } returns type
    }

    private fun mockPeer(peerKey: String, connections: List<DittoConnection>): DittoPeer = mockk {
        every { this@mockk.peerKey } returns peerKey
        every { this@mockk.connections } returns connections
        every { deviceName } returns "Test Device"
        every { dittoSdkVersion } returns "5.1.0"
        every { os } returns null
        every { isConnectedToDittoServer } returns false
        every { isCompatible } returns null
        // Real empty objects, not mocks stubbing `isNull = true` — the SDK cannot
        // produce that state (an ObjectValue is never JSON null), and stubbing it hid
        // the fact that the emptiness guard never fired, so every peer without metadata
        // was reported as having some.
        every { peerMetadata } returns DittoJsonSerializable.ObjectValue()
        every { identityServiceMetadata } returns DittoJsonSerializable.ObjectValue()
    }
}
