package com.costoda.dittoedgestudio.ui.mainstudio.presence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot

/**
 * Unit tests for [calculateRadialLayout]. Pure JVM — no Compose imports, no Android.
 *
 * Coordinate convention: positions are y-UP math coordinates with local at (0, 0). All
 * assertions use that convention.
 */
class PresenceGraphLayoutTest {

    private fun distFromOrigin(p: Point2D): Float = hypot(p.x, p.y)

    @Test
    fun `single peer places local at center`() {
        val result = calculateRadialLayout(
            localPeerId = "local",
            peerIds = listOf("local"),
            edges = emptyList(),
        )
        assertEquals(1, result.positions.size)
        val pos = result.positions["local"]
        assertNotNull(pos)
        assertEquals(0f, pos!!.x, 0.001f)
        assertEquals(0f, pos.y, 0.001f)
    }

    @Test
    fun `five peers all land on ring 1 with unique angles`() {
        val peers = (1..5).map { "p$it" }
        val edges = peers.map { LayoutEdgeInput("local", it) }
        val result = calculateRadialLayout(
            localPeerId = "local",
            peerIds = listOf("local") + peers,
            edges = edges,
        )
        val ring1 = result.ringAssignments[1]
        assertNotNull(ring1)
        assertEquals(5, ring1!!.size)
        val expectedRadius = result.ringRadii[1]!!
        val angles = mutableSetOf<Double>()
        for (id in peers) {
            val pos = result.positions[id]!!
            assertEquals(
                "$id distance from origin",
                expectedRadius,
                distFromOrigin(pos),
                1f,
            )
            val angle = atan2(pos.y.toDouble(), pos.x.toDouble())
            assertTrue("duplicate angle: $angle", angles.add(angle))
        }
    }

    @Test
    fun `twenty one peers spread across two rings`() {
        // 20 remote peers all directly connected to local would still fit ring 1 only,
        // since rings expand to accommodate. To force a multi-ring layout we chain peers
        // (p10..p20 are reachable only via p1..p9 respectively — synthetic mesh).
        val ring1 = (1..10).map { "ring1-$it" }
        val ring2 = (1..10).map { "ring2-$it" }
        val edges = mutableListOf<LayoutEdgeInput>()
        ring1.forEach { edges += LayoutEdgeInput("local", it) }
        // Each ring-1 peer hosts exactly one ring-2 child
        ring1.zip(ring2).forEach { (parent, child) ->
            edges += LayoutEdgeInput(parent, child)
        }
        val result = calculateRadialLayout(
            localPeerId = "local",
            peerIds = listOf("local") + ring1 + ring2,
            edges = edges,
        )
        assertEquals(1, result.ringAssignments[0]!!.size)
        assertEquals(10, result.ringAssignments[1]!!.size)
        assertEquals(10, result.ringAssignments[2]!!.size)
        val r1 = result.ringRadii[1]!!
        val r2 = result.ringRadii[2]!!
        assertTrue("ring 2 must be larger than ring 1", r2 > r1)
    }

    @Test
    fun `multihop peer sits behind its parent`() {
        // Two ring-1 peers; only A has a child C. C should land near A's angle.
        val edges = listOf(
            LayoutEdgeInput("local", "A"),
            LayoutEdgeInput("local", "B"),
            LayoutEdgeInput("A", "C"),
        )
        val result = calculateRadialLayout(
            localPeerId = "local",
            peerIds = listOf("local", "A", "B", "C"),
            edges = edges,
        )
        val angleA = atan2(result.positions["A"]!!.y.toDouble(), result.positions["A"]!!.x.toDouble())
        val angleC = atan2(result.positions["C"]!!.y.toDouble(), result.positions["C"]!!.x.toDouble())
        val delta = kotlin.math.abs(angleC - angleA)
        // Plan tolerance: ±30°
        assertTrue("|angleC - angleA| = $delta > ${PI / 6.0}", delta < PI / 6.0)
    }

    @Test
    fun `cloud peer is placed by BFS as a ring 1 peer like any other`() {
        // The previous (0, +1.5 × r1) override caused vertical collisions with whichever
        // ring-1 peer landed at ~90° (iPhone in the field reports). Cloud now travels
        // through BFS like any other directly-connected peer.
        val edges = listOf(
            LayoutEdgeInput("local", "p1"),
            LayoutEdgeInput("local", CLOUD_NODE_KEY),
        )
        val result = calculateRadialLayout(
            localPeerId = "local",
            peerIds = listOf("local", "p1", CLOUD_NODE_KEY),
            edges = edges,
            cloudPeerId = CLOUD_NODE_KEY,
        )
        val cloudPos = result.positions[CLOUD_NODE_KEY]!!
        val ring1 = result.ringRadii[1]!!
        val dist = hypot(cloudPos.x, cloudPos.y)
        assertEquals("cloud sits on ring 1", ring1, dist, 1f)
        assertTrue("cloud is in ring 1 assignment", result.ringAssignments[1]!!.contains(CLOUD_NODE_KEY))
    }

    @Test
    fun `disconnected peer is assigned to the outermost ring`() {
        val edges = listOf(LayoutEdgeInput("local", "A"))
        val result = calculateRadialLayout(
            localPeerId = "local",
            peerIds = listOf("local", "A", "lonely"),
            edges = edges,
        )
        // ring 0 = local, ring 1 = A, lonely -> ring 2 (outermost since A is in ring 1).
        val outermost = result.ringAssignments.keys.max()
        assertTrue("lonely must be in outermost ring ($outermost)", result.ringAssignments[outermost]!!.contains("lonely"))
        // Sanity: not the same ring as A
        assertNotEquals(1, outermost)
    }

    @Test
    fun `bidirectional edges produce a single undirected adjacency`() {
        // The BFS should see (A,B) and (B,A) as the same edge — assigning each peer to
        // a single ring rather than creating an inflated graph.
        val edges = listOf(
            LayoutEdgeInput("local", "A"),
            LayoutEdgeInput("A", "local"),
        )
        val result = calculateRadialLayout(
            localPeerId = "local",
            peerIds = listOf("local", "A"),
            edges = edges,
        )
        assertEquals(1, result.ringAssignments[1]!!.size)
    }
}
