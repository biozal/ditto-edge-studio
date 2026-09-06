package com.costoda.dittoedgestudio.ui.mainstudio.presence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.sin

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

    // ── Expanded mode (radiusScale > 1) ───────────────────────────────────────
    // Ported from the VS Code extension's NetworkLayoutEngine.test.ts (the shared
    // behavioral contract across all three engines).

    @Test
    fun `radiusScale spreads rings outward proportionally`() {
        // 4-peer star; the crowding floor doesn't kick in, so scale is the only factor.
        val peers = listOf("local", "A", "B", "C", "D")
        val edges = listOf("A", "B", "C", "D").map { LayoutEdgeInput("local", it) }

        val compact = calculateRadialLayout("local", peers, edges)
        val expanded = calculateRadialLayout("local", peers, edges, radiusScale = EXPANDED_RADIUS_SCALE)

        val r1 = compact.ringRadii[1]!!
        val r2 = expanded.ringRadii[1]!!
        assertEquals(r1 * EXPANDED_RADIUS_SCALE, r2, 0.001f)
        // Same angles, bigger radius: positions scale by the same factor.
        for (key in listOf("A", "B", "C", "D")) {
            val p1 = compact.positions[key]!!
            val p2 = expanded.positions[key]!!
            assertEquals("$key.x scales", p1.x * EXPANDED_RADIUS_SCALE, p2.x, 0.01f)
            assertEquals("$key.y scales", p1.y * EXPANDED_RADIUS_SCALE, p2.y, 0.01f)
        }
    }

    @Test
    fun `expanded mode packs a crowded BFS layer into concentric rings`() {
        val direct = (0 until 12).map { "direct-$it" }
        val peers = listOf("local") + direct + "indirect"
        val edges = direct.map { LayoutEdgeInput("local", it) } +
            LayoutEdgeInput("direct-0", "indirect")

        val result = calculateRadialLayout(
            "local", peers, edges, radiusScale = EXPANDED_RADIUS_SCALE,
        )

        // Hop order still decides who sits innermost — ring 1 is all direct peers and
        // the multi-hop peer is on the outermost ring. What it must NOT do is claim a
        // ring of its own: before the balanced packer, "indirect" was alone on ring 3
        // at a radius half again as large as ring 2, dangling on a long spoke.
        val ring1 = result.ringAssignments[1] ?: emptyList()
        val ring2 = result.ringAssignments[2] ?: emptyList()
        assertTrue(ring1.isNotEmpty() && ring1.all { it in direct })
        assertTrue("the multi-hop peer must share a ring, not get its own", ring2.size > 1)
        assertTrue("the multi-hop peer belongs on the outermost ring", "indirect" in ring2)
        assertEquals(null, result.ringAssignments[3])

        // Visual rings must expand outward.
        val radii = result.ringRadii.filterKeys { it > 0 }.toSortedMap().values.toList()
        for (i in 1 until radii.size) {
            assertTrue("visual rings must expand outward", radii[i] > radii[i - 1])
        }
        assertEquals(peers.size, result.positions.size)
    }

    @Test
    fun `expanded mode evenly spaces peers within every visual ring`() {
        val peers = listOf("local") + (0 until 30).map { "P$it" }
        val edges = peers.drop(1).map { LayoutEdgeInput("local", it) }

        val result = calculateRadialLayout(
            "local", peers, edges, radiusScale = EXPANDED_RADIUS_SCALE,
        )

        for ((ring, ringPeers) in result.ringAssignments) {
            if (ring == 0 || ringPeers.size < 2) continue
            val angles = ringPeers.map { peer ->
                val p = result.positions[peer]!!
                var a = atan2(p.y.toDouble(), p.x.toDouble())
                if (a < 0) a += 2 * PI
                a
            }.sorted()
            val expectedGap = 2 * PI / ringPeers.size
            for (i in 1 until angles.size) {
                assertEquals("ring $ring is not evenly spaced", expectedGap, angles[i] - angles[i - 1], 1e-4)
            }
        }
    }

    @Test
    fun `expanded mode uses supplied pill footprints when packing rings`() {
        val direct = (0 until 12).map { "P$it" }
        val peers = listOf("local") + direct
        val edges = direct.map { LayoutEdgeInput("local", it) }
        // Very wide (340dp) pills must reduce visual-ring capacity.
        val footprints = direct.associateWith { 340f }

        val result = calculateRadialLayout(
            "local", peers, edges,
            radiusScale = EXPANDED_RADIUS_SCALE, peerFootprints = footprints,
        )

        val ring1 = result.ringAssignments[1] ?: emptyList()
        assertTrue("wide pills should reduce ring-1 capacity", ring1.size < direct.size)
        // The chord between neighbors is never shorter than the pill width.
        for ((ring, ringPeers) in result.ringAssignments) {
            if (ring == 0 || ringPeers.size < 2) continue
            val positions = ringPeers.map { result.positions[it]!! }
            for (i in positions.indices) {
                val next = positions[(i + 1) % positions.size]
                val distance = hypot(positions[i].x - next.x, positions[i].y - next.y)
                assertTrue("ring $ring chord too short: $distance", distance >= 340f - 0.5f)
            }
        }
    }

    @Test
    fun `expanded mode continues outward beyond 100 peers`() {
        val peers = listOf("local") + (0 until 101).map { "P$it" }
        val edges = peers.drop(1).map { LayoutEdgeInput("local", it) }

        val result = calculateRadialLayout(
            "local", peers, edges, radiusScale = EXPANDED_RADIUS_SCALE,
        )

        val visualRings = result.ringAssignments.keys.filter { it > 0 }
        assertTrue("expected at least 5 visual rings, got ${visualRings.size}", visualRings.size >= 5)
        assertEquals(peers.size, result.positions.size)
        val unique = result.positions.values.map { "${it.x},${it.y}" }.toSet()
        assertEquals("large meshes must not reuse a position", peers.size, unique.size)
    }

    @Test
    fun `small ring with wide pills respects the chord floor`() {
        // 4 peers × 340dp pills, compact mode: the circumference floor
        // (4×360/2π ≈ 229dp) would space adjacent centers by the chord
        // 2R·sin(π/4) ≈ 324dp — ~10% pill overlap. The chord-aware floor
        // (360 / (2·sin(π/4)) ≈ 255dp) is the binding constraint instead.
        val remotes = listOf("A", "B", "C", "D")
        val edges = remotes.map { LayoutEdgeInput("local", it) }
        val footprints = remotes.associateWith { 340f }

        val result = calculateRadialLayout(
            "local", listOf("local") + remotes, edges, peerFootprints = footprints,
        )

        val positions = remotes.map { result.positions[it]!! }
        for (i in positions.indices) {
            val next = positions[(i + 1) % positions.size]
            val distance = hypot(positions[i].x - next.x, positions[i].y - next.y)
            assertTrue(
                "adjacent centers must clear the 340dp pill + 20dp gap, got $distance",
                distance >= 360f - 0.5f,
            )
        }
    }

    @Test
    fun `chord floor does not push typical small rings past the base radius`() {
        // 4 default-size (60dp) pills: arc floor ≈ 51dp, chord floor ≈ 57dp —
        // both below the 123.75dp base, so the base wins and nothing drifts apart.
        val remotes = listOf("A", "B", "C", "D")
        val edges = remotes.map { LayoutEdgeInput("local", it) }

        val result = calculateRadialLayout("local", listOf("local") + remotes, edges)

        assertEquals(BASE_RADIUS_DP, result.ringRadii[1]!!, 0.001f)
    }

    @Test
    fun `radiusScale does not shrink rings below the crowding floor`() {
        // 20 ring-1 peers; scaling DOWN with a tiny scale must not overlap pills.
        val peers = listOf("local") + (0 until 20).map { "P$it" }
        val edges = peers.drop(1).map { LayoutEdgeInput("local", it) }

        val tight = calculateRadialLayout("local", peers, edges, radiusScale = 0.1f)

        // Floor is ~254 (20 × 80dp / 2π); the tiny scale must not shrink it.
        assertTrue("crowding floor should hold ring at ~254, got ${tight.ringRadii[1]}",
            (tight.ringRadii[1] ?: 0f) > 200f)
    }

    // ── Balanced ring packing (expanded / full-mesh mode) ────────────────────

    private fun ringSizes(result: LayoutResult): List<Int> =
        result.ringAssignments.keys.filter { it > 0 }.sorted().map { result.ringAssignments[it]!!.size }

    private fun fullMesh(n: Int): LayoutResult {
        val peers = listOf("local") + (0 until n).map { "P%03d".format(it) }
        val edges = buildList {
            for (i in peers.indices) for (j in i + 1 until peers.size) {
                add(LayoutEdgeInput(peers[i], peers[j]))
            }
        }
        return calculateRadialLayout("local", peers, edges, radiusScale = EXPANDED_RADIUS_SCALE)
    }

    @Test
    fun `no ring is left stranded with a lone peer`() {
        // The on-device symptom: a couple of multi-hop stragglers each took a whole
        // ring to themselves, hundreds of dp out, on a spoke pointing straight up.
        val core = (0 until 14).map { "core%02d".format(it) }
        val peers = listOf("local") + core + listOf("hop2", "hop3")
        val edges = buildList {
            val meshed = listOf("local") + core
            for (i in meshed.indices) for (j in i + 1 until meshed.size) {
                add(LayoutEdgeInput(meshed[i], meshed[j]))
            }
            add(LayoutEdgeInput(core.first(), "hop2"))
            add(LayoutEdgeInput("hop2", "hop3"))
        }

        val result = calculateRadialLayout("local", peers, edges, radiusScale = EXPANDED_RADIUS_SCALE)

        val sizes = ringSizes(result)
        assertTrue("every ring must carry more than one peer, got $sizes", sizes.all { it > 1 })
        assertEquals(peers.size, result.positions.size)
    }

    @Test
    fun `rings grow outward in population, never shrinking to a remainder`() {
        // 60 peers used to pack as 6/12/17/23/2 — the outermost orbit held two nodes.
        for (n in listOf(12, 25, 40, 60, 90, 120)) {
            val sizes = ringSizes(fullMesh(n))
            assertEquals("all $n peers must be placed", n, sizes.sum())
            for (i in 1 until sizes.size) {
                assertTrue(
                    "ring ${i + 1} must not hold fewer peers than ring $i (n=$n, $sizes)",
                    sizes[i] >= sizes[i - 1],
                )
            }
        }
    }

    @Test
    fun `a peer never sits closer together than its neighbours on an inner ring`() {
        // Capacity-proportional sharing means neighbour spacing stays roughly constant
        // across orbits, which is what makes the rings read as balanced.
        val result = fullMesh(60)
        val gaps = result.ringAssignments.keys.filter { it > 0 }.sorted().map { ring ->
            val n = result.ringAssignments[ring]!!.size
            val radius = result.ringRadii[ring]!!
            2.0 * radius * sin(PI / n)
        }
        val smallest = gaps.min()
        val largest = gaps.max()
        assertTrue(
            "neighbour spacing should stay within 2x across rings, got $gaps",
            largest <= smallest * 2.0,
        )
    }

    @Test
    fun `consecutive rings do not stack their first peer on the same spoke`() {
        val result = fullMesh(120)
        val startAngles = result.ringAssignments.keys.filter { it > 0 }.sorted().map { ring ->
            val first = result.ringAssignments[ring]!!.first()
            val p = result.positions[first]!!
            var a = atan2(p.y.toDouble(), p.x.toDouble())
            if (a < 0) a += 2 * PI
            a
        }
        assertEquals(
            "every ring started at 90 degrees, drawing a seam straight up",
            startAngles.size,
            startAngles.map { Math.round(it * 1000) }.toSet().size,
        )
    }

    @Test
    fun `a single straggler ring cannot park a peer at the top`() {
        // Two peers one hop apart behind a single direct peer: the old packer put the
        // 3-hop peer alone on its own ring at exactly 90 degrees.
        val peers = listOf("local", "a", "b", "c")
        val edges = listOf(
            LayoutEdgeInput("local", "a"),
            LayoutEdgeInput("a", "b"),
            LayoutEdgeInput("b", "c"),
        )
        val result = calculateRadialLayout("local", peers, edges, radiusScale = EXPANDED_RADIUS_SCALE)

        assertEquals("three peers fit one orbit", listOf(3), ringSizes(result))
        assertEquals(peers.size, result.positions.size)
    }
}
