package com.costoda.dittoedgestudio.ui.mainstudio.presence

import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

/**
 * BFS ring-layout algorithm for the presence graph. Pure Kotlin, no Compose imports —
 * unit-testable on the JVM. Ported from iOS `NetworkLayoutEngine.swift` and the VS Code
 * extension's `src/presence/NetworkLayoutEngine.ts`.
 *
 * **Expanded-mode ring packing has deliberately diverged** from both — see
 * [packBfsRings] and [calculateOptimalAngles]. The shared algorithm gave each BFS
 * layer its own visual ring and started every ring at 90°, which stranded lone
 * multi-hop peers on long spokes and drew a seam of stacked nodes straight up. The
 * reference implementations have the same defect; it is masked there because their
 * test meshes are a single wide layer. Port these two changes back when convenient.
 *
 * Coordinate system: positions are returned in y-UP math coordinates with the local
 * peer at `(0, 0)`. The Compose-side view layer is responsible for flipping y when
 * rendering (Compose canvases use y-down). Keeping the math here in y-up matches the
 * iOS source so behavior translates verbatim.
 */

/**
 * Pure 2D point used by the layout. The view layer converts to `androidx.compose.ui
 * .geometry.Offset` at the draw boundary so this file stays Compose-free.
 */
data class Point2D(val x: Float, val y: Float)

/** Edge input for the layout engine — only endpoint identities matter. */
internal data class LayoutEdgeInput(val fromPeerId: String, val toPeerId: String)

/** Output of [calculateRadialLayout]. */
data class LayoutResult(
    val positions: Map<String, Point2D>,
    val ringAssignments: Map<Int, List<String>>,
    val ringRadii: Map<Int, Float>,
)

// iOS-parity constants — sourced from NetworkLayoutEngine.swift.
internal const val BASE_RADIUS_DP: Float = 123.75f
internal const val RADIUS_INCREMENT_DP: Float = 101.25f
private const val PEER_DIAMETER_DP: Float = 60f
private const val PEER_RING_PADDING_DP: Float = 20f

/**
 * Ring spread multiplier for full-mesh (Direct OFF) mode — the VS Code
 * extension's `EXPANDED_RADIUS_SCALE`, iOS `PresenceNetworkScene.expandedRadiusScale`.
 */
internal const val EXPANDED_RADIUS_SCALE: Float = 1.75f

/**
 * Conservative center-to-center footprint used only when expanded (full-mesh)
 * mode packs a BFS layer across multiple visual rings. Pills have variable
 * widths, so this intentionally errs on the side of fewer peers per ring.
 */
private const val EXPANDED_NODE_FOOTPRINT_DP: Float = 200f

/**
 * Hard ceiling on visual rings. Ring capacity grows with radius, so ~11 rings already
 * seat over 500 peers — far past the 120-node mesh this view is built for. Purely a
 * runaway guard on the packing loop.
 */
private const val MAX_VISUAL_RINGS: Int = 32

/**
 * Compute a BFS-based ring layout for the given peers.
 *
 * The cloud node (when present in [peerIds]) is laid out like any other ring-1 peer.
 * The plan originally specified pinning it to top-center at `(0, +1.5 × r1)`, but
 * that override caused vertical collisions when another ring-1 peer landed near 90°
 * (notably iPhone, whose edge would then visually pass through the cloud line).
 *
 * [radiusScale] (default 1) multiplies the base ring radius and the per-ring
 * increment. Expanded mode (> 1) also packs each BFS layer into as many concentric
 * visual rings as needed: direct peers stay closest to the local peer, and later
 * BFS layers do not start until the previous layer is complete. The crowding-based
 * minimum-circumference floor is intentionally NOT scaled (pill sizes don't
 * change), so very small meshes don't drift apart for no reason.
 *
 * [peerFootprints] carries renderer-measured pill widths (in the same dp space as
 * the layout) so long pills aren't packed too tightly; peers without a
 * measurement fall back to [EXPANDED_NODE_FOOTPRINT_DP] / [PEER_DIAMETER_DP].
 *
 * In lockstep with iOS `NetworkLayoutEngine.swift` and the VS Code extension's
 * `src/presence/NetworkLayoutEngine.ts` apart from the expanded-mode packing and
 * ring-angle stagger documented at the top of this file.
 *
 * @param localPeerId  the local device's peer key. Always placed at origin (ring 0).
 * @param peerIds      all peer keys to lay out (must include [localPeerId]).
 * @param edges        connection edges (undirected — direction is normalized internally).
 */
internal fun calculateRadialLayout(
    localPeerId: String,
    peerIds: Iterable<String>,
    edges: Iterable<LayoutEdgeInput>,
    radiusScale: Float = 1f,
    peerFootprints: Map<String, Float>? = null,
): LayoutResult {
    val allPeers: Set<String> = peerIds.toSet() + localPeerId
    val adjacency = buildAdjacency(edges)
    val (bfsRings, parentMap) = performBfs(localPeerId, adjacency, allPeers)
    val expanded = radiusScale > 1f

    val orderedBfsRings = if (expanded) {
        // Preserve the useful ring-1 chord locality before a crowded direct layer
        // is split across multiple visual rings.
        val logicalRing1 = bfsRings[1]
        if (logicalRing1 != null && logicalRing1.size > 1) {
            bfsRings + (1 to sortRing1Peers(logicalRing1, adjacency))
        } else {
            bfsRings
        }
    } else {
        bfsRings
    }
    val ringAssignments = if (expanded) {
        packBfsRings(orderedBfsRings, radiusScale, peerFootprints)
    } else {
        orderedBfsRings
    }

    val ringRadii = calculateRingRadii(ringAssignments, radiusScale, peerFootprints)
    val positions = calculatePositions(
        ringAssignments = ringAssignments,
        ringRadii = ringRadii,
        localPeerId = localPeerId,
        parentMap = parentMap,
        adjacency = adjacency,
        expanded = expanded,
    )
    return LayoutResult(positions, ringAssignments, ringRadii)
}

// ── Expanded-mode ring packing ─────────────────────────────────────────────────

/**
 * Convert logical BFS layers into balanced visual rings for expanded (full-mesh) mode.
 *
 * **Deliberate divergence from the VS Code extension and iOS.** Those implementations
 * give every BFS layer its own fresh visual ring ("the next BFS layer never starts
 * until the current layer is complete"). That reads well only when the mesh is a
 * single wide layer. On a real multicast mesh, where a handful of peers are two or
 * three hops out, it produces a ring holding exactly one peer at a huge radius — the
 * lone node dangling on a long spoke, which is what the presence viewer was actually
 * doing on device. A trailing remainder had the same effect: 60 peers packed as
 * 6 / 12 / 17 / 23 / **2**, with two nodes stranded on the outermost orbit.
 *
 * Instead: flatten the layers in hop order (so low-hop peers still land innermost),
 * take the fewest rings that can hold everyone, and spread the peers across those
 * rings **in proportion to each ring's capacity**. Equal capacity share means equal
 * spacing between neighbours on every orbit, which is what makes the rings read as
 * balanced — outer rings legitimately hold more peers, exactly as the reference
 * renderer looks when its mesh happens to be one wide layer.
 *
 * A peer two hops out can now share a ring with direct peers. That is the intended
 * trade: ring index stops being a strict hop count, and becomes "roughly how far out
 * you are", in exchange for orbits that stay balanced up to 120 nodes.
 */
private fun packBfsRings(
    bfsRings: Map<Int, List<String>>,
    radiusScale: Float,
    peerFootprints: Map<String, Float>?,
): Map<Int, List<String>> {
    val packed = HashMap<Int, List<String>>()
    packed[0] = bfsRings[0] ?: emptyList()

    // Hop order is preserved across the flatten, so ring 1 still fills with the
    // nearest peers and the outermost ring still holds the furthest.
    val ordered = bfsRings.keys.filter { it > 0 }.sorted().flatMap { bfsRings[it].orEmpty() }
    if (ordered.isEmpty()) return packed

    val capacities = expandedRingCapacities(ordered, radiusScale, peerFootprints)
    val counts = distributeAcrossRings(ordered.size, capacities)

    var offset = 0
    for ((index, count) in counts.withIndex()) {
        if (count <= 0) continue
        packed[index + 1] = ordered.subList(offset, offset + count)
        offset += count
    }
    return packed
}

/**
 * Capacity of each visual ring, growing outward until the rings can hold [peers].
 *
 * Capacity is measured against the widest pill in the whole mesh rather than the
 * widest still-unplaced one: the balanced packer decides all rings up front, so a
 * per-ring measurement would depend on an assignment that hasn't happened yet.
 */
private fun expandedRingCapacities(
    peers: List<String>,
    radiusScale: Float,
    peerFootprints: Map<String, Float>?,
): List<Int> {
    val capacities = mutableListOf<Int>()
    var seated = 0
    var ring = 1
    while (seated < peers.size && ring <= MAX_VISUAL_RINGS) {
        val capacity = peersPerExpandedRing(ring, radiusScale, peers, peerFootprints)
        capacities += capacity
        seated += capacity
        ring += 1
    }
    // Degenerate guard: peersPerExpandedRing always returns >= 1, so the loop only
    // exits early at the ring cap. Park any overflow on the outermost ring rather
    // than dropping peers off the graph.
    if (seated < peers.size && capacities.isNotEmpty()) {
        capacities[capacities.lastIndex] += peers.size - seated
    }
    return capacities
}

/**
 * Split [total] peers across rings in proportion to [capacities], never exceeding a
 * ring's capacity. Largest-remainder apportionment, so the counts sum to exactly
 * [total] and the rounding loss lands on the rings that were closest to another slot.
 */
private fun distributeAcrossRings(total: Int, capacities: List<Int>): IntArray {
    val counts = IntArray(capacities.size)
    val capacitySum = capacities.sum()
    if (capacitySum <= 0 || total <= 0) return counts

    val exact = capacities.map { total.toDouble() * it / capacitySum }
    for (i in counts.indices) counts[i] = floor(exact[i]).toInt()

    // Hand out what rounding dropped, largest fractional part first. Ties break on
    // ring index so the same mesh always lays out the same way.
    val byRemainder = exact.indices.sortedWith(
        compareByDescending<Int> { exact[it] - floor(exact[it]) }.thenBy { it },
    )
    var remaining = total - counts.sum()
    var progressed = true
    while (remaining > 0 && progressed) {
        progressed = false
        for (index in byRemainder) {
            if (remaining == 0) break
            if (counts[index] < capacities[index]) {
                counts[index] += 1
                remaining -= 1
                progressed = true
            }
        }
    }
    return counts
}

/**
 * How many peers fit on one visual ring at the given radius scale.
 *
 * Arc length is a useful first approximation, but equal-angle points are
 * separated by a chord — so the capacity is reduced until the shortest chord in
 * the ring can contain the widest pill plus its gap.
 */
private fun peersPerExpandedRing(
    ring: Int,
    radiusScale: Float,
    peers: List<String>,
    peerFootprints: Map<String, Float>?,
): Int {
    val radius = ((BASE_RADIUS_DP + (ring - 1) * RADIUS_INCREMENT_DP) * radiusScale).toDouble()
    val widestPill = peers.fold(0f) { widest, peer ->
        max(widest, peerFootprints?.get(peer) ?: 0f)
    }
    val footprint = (max(EXPANDED_NODE_FOOTPRINT_DP, widestPill + PEER_RING_PADDING_DP)).toDouble()
    var capacity = max(1, floor(2.0 * PI * radius / footprint).toInt())
    while (capacity > 1 && 2.0 * radius * sin(PI / capacity) < footprint) {
        capacity -= 1
    }
    return capacity
}

// ── Internals ───────────────────────────────────────────────────────────────────

private fun buildAdjacency(edges: Iterable<LayoutEdgeInput>): Map<String, Set<String>> {
    val adj = HashMap<String, MutableSet<String>>()
    for (e in edges) {
        adj.getOrPut(e.fromPeerId) { mutableSetOf() }.add(e.toPeerId)
        adj.getOrPut(e.toPeerId) { mutableSetOf() }.add(e.fromPeerId)
    }
    return adj
}

private fun performBfs(
    localPeerId: String,
    adjacency: Map<String, Set<String>>,
    allPeers: Set<String>,
): Pair<Map<Int, List<String>>, Map<String, String>> {
    val ringAssignments = HashMap<Int, MutableList<String>>()
    val parentMap = HashMap<String, String>()
    val visited = HashSet<String>()
    val queue = ArrayDeque<Pair<String, Int>>()

    ringAssignments[0] = mutableListOf(localPeerId)
    visited += localPeerId
    queue.addLast(localPeerId to 0)

    while (queue.isNotEmpty()) {
        val (peer, ring) = queue.removeFirst()
        // Sorted for determinism: HashSet iteration order is not contractual, and
        // without this a peer's ring/angle could vary between runs (and differ
        // between the direct and expanded passes of one toggle). Mirrors the
        // iOS engine's sorted-neighbor BFS.
        val neighbors = adjacency[peer] ?: continue
        for (n in neighbors.sorted()) {
            if (n in visited) continue
            visited += n
            val nextRing = ring + 1
            parentMap[n] = peer
            ringAssignments.getOrPut(nextRing) { mutableListOf() }.add(n)
            queue.addLast(n to nextRing)
        }
    }

    val disconnected = allPeers - visited
    if (disconnected.isNotEmpty()) {
        val maxRing = ringAssignments.keys.maxOrNull() ?: 0
        // Sorted — Set iteration order must not leak into ring order.
        ringAssignments[maxRing + 1] = disconnected.sorted().toMutableList()
    }
    return ringAssignments.mapValues { (_, v) -> v.toList() } to parentMap
}

/**
 * Ring radii, expanded when a ring is crowded.
 *
 * The crowding floor is intentionally NOT scaled by [radiusScale]: pill sizes are
 * fixed, so the floor represents physical crowding, not visual breathing room.
 *
 * Two floors per ring, and the binding one wins:
 *  - Circumference: the ring's total arc must fit every pill plus its gap.
 *  - Chord (VS Code extension `expandDirectRingForLabels` parity): equal-angle
 *    neighbours are separated by the chord 2R·sin(π/n), which is shorter than
 *    their arc share — at small ring counts the arc floor under-expands and wide
 *    pills overlap, so the widest pill plus gap must fit inside the chord.
 */
private fun calculateRingRadii(
    ringAssignments: Map<Int, List<String>>,
    radiusScale: Float,
    peerFootprints: Map<String, Float>?,
): Map<Int, Float> {
    val radii = HashMap<Int, Float>()
    radii[0] = 0f
    for (ring in ringAssignments.keys.sorted()) {
        if (ring == 0) continue
        val peers = ringAssignments[ring] ?: continue
        val base = (BASE_RADIUS_DP + (ring - 1) * RADIUS_INCREMENT_DP) * radiusScale
        var minCircumference = 0.0
        var widestPill = 0f
        for (peer in peers) {
            val footprint = max(PEER_DIAMETER_DP, peerFootprints?.get(peer) ?: 0f)
            minCircumference += footprint + PEER_RING_PADDING_DP
            widestPill = max(widestPill, footprint)
        }
        val arcMinRadius = (minCircumference / (2.0 * PI)).toFloat()
        // Chord floor: R ≥ (widestPill + gap) / (2·sin(π/n)). A single node has
        // no neighbour, so no chord constraint (sin(π/1) ≈ 0 would blow up).
        val chordMinRadius = if (peers.size > 1) {
            ((widestPill + PEER_RING_PADDING_DP) / (2.0 * sin(PI / peers.size))).toFloat()
        } else {
            0f
        }
        radii[ring] = max(base, max(arcMinRadius, chordMinRadius))
    }
    return radii
}

private fun calculatePositions(
    ringAssignments: Map<Int, List<String>>,
    ringRadii: Map<Int, Float>,
    localPeerId: String,
    parentMap: Map<String, String>,
    adjacency: Map<String, Set<String>>,
    expanded: Boolean,
): Map<String, Point2D> {
    val positions = HashMap<String, Point2D>()
    positions[localPeerId] = Point2D(0f, 0f)

    for (ring in ringAssignments.keys.sorted()) {
        if (ring == 0) continue
        val peers = ringAssignments[ring] ?: continue
        val radius = ringRadii[ring] ?: continue
        if (peers.isEmpty()) continue

        if (expanded) {
            // Every visual ring is an independent orbit. Parent anchoring would
            // bunch siblings together again, so expanded rings always use equal
            // angular spacing. Ring 1 keeps its chord-locality ordering (re-sorted
            // per packed subset so connected pairs stay adjacent within a ring).
            val ordered = if (ring == 1) sortRing1Peers(peers, adjacency) else peers
            val angles = calculateOptimalAngles(ordered.size, ring)
            for ((i, peer) in ordered.withIndex()) {
                val a = angles[i]
                positions[peer] = Point2D(
                    (radius * cos(a)).toFloat(),
                    (radius * sin(a)).toFloat(),
                )
            }
        } else if (ring == 1) {
            val ordered = sortRing1Peers(peers, adjacency)
            val angles = calculateOptimalAngles(ordered.size, ring)
            for ((i, peer) in ordered.withIndex()) {
                val a = angles[i]
                positions[peer] = Point2D(
                    (radius * cos(a)).toFloat(),
                    (radius * sin(a)).toFloat(),
                )
            }
        } else {
            val peersByParent = HashMap<String, MutableList<String>>()
            for (p in peers) {
                val parent = parentMap[p] ?: localPeerId
                peersByParent.getOrPut(parent) { mutableListOf() }.add(p)
            }
            val parentAngles: List<Pair<String, Double>> = peersByParent.keys
                .mapNotNull { key ->
                    val pos = positions[key] ?: return@mapNotNull null
                    key to atan2(pos.y.toDouble(), pos.x.toDouble())
                }
                .sortedBy { it.second }

            for ((parentKey, children) in peersByParent) {
                val parentPos = positions[parentKey] ?: Point2D(0f, 0f)
                val parentAngle = atan2(parentPos.y.toDouble(), parentPos.x.toDouble())

                val halfGap: Double = if (parentAngles.size <= 1) {
                    PI / 3.0
                } else {
                    val sortedAngles = parentAngles.map { it.second }
                    val idx = sortedAngles.indexOf(parentAngle).coerceAtLeast(0)
                    val prev = sortedAngles[(idx + sortedAngles.size - 1) % sortedAngles.size]
                    val next = sortedAngles[(idx + 1) % sortedAngles.size]
                    var gapLeft = parentAngle - prev
                    var gapRight = next - parentAngle
                    if (gapLeft < 0) gapLeft += 2.0 * PI
                    if (gapRight < 0) gapRight += 2.0 * PI
                    min(min(gapLeft, gapRight) * 0.8, PI / 3.0)
                }

                val childCount = children.size
                val siblingSpread: Double = if (childCount > 1) {
                    max(halfGap * 2.0 / (childCount - 1), PI / 12.0)
                } else {
                    0.0
                }

                val totalSpan = siblingSpread * (childCount - 1)
                val startAngle = parentAngle - totalSpan / 2.0

                for ((i, child) in children.withIndex()) {
                    val angle = startAngle + siblingSpread * i
                    positions[child] = Point2D(
                        (radius * cos(angle)).toFloat(),
                        (radius * sin(angle)).toFloat(),
                    )
                }
            }
        }
    }
    return positions
}

/**
 * Greedy double-ended path through ring-1 peers, weighted by their inter-peer
 * connection count. Direct port of `NetworkLayoutEngine.sortRing1Peers`.
 *
 * The resulting linear order is mapped onto the circle so connected pairs land at
 * adjacent angular positions — keeping their chord short and away from unrelated
 * nodes that would otherwise sit between them.
 */
private fun sortRing1Peers(
    peers: List<String>,
    adjacency: Map<String, Set<String>>,
): List<String> {
    if (peers.size <= 2) return peers
    val peerSet = peers.toSet()
    val ring1Degree: Map<String, Int> = peers.associateWith { peer ->
        (adjacency[peer] ?: emptySet()).count { it in peerSet }
    }
    if (ring1Degree.values.all { it == 0 }) return peers

    val remaining = peers.toMutableSet()
    val path = ArrayDeque<String>()
    val start = peers.sorted().maxByOrNull { ring1Degree[it] ?: 0 } ?: peers[0]
    path.addLast(start)
    remaining.remove(start)

    while (remaining.isNotEmpty()) {
        val tail = path.lastOrNull() ?: break
        val tailNeighbour = (adjacency[tail] ?: emptySet())
            .filter { it in remaining }
            .sortedWith(compareByDescending<String> { ring1Degree[it] ?: 0 }.thenBy { it })
            .firstOrNull()

        if (tailNeighbour != null) {
            path.addLast(tailNeighbour)
            remaining.remove(tailNeighbour)
            continue
        }
        val head = path.firstOrNull() ?: break
        val headNeighbour = (adjacency[head] ?: emptySet())
            .filter { it in remaining }
            .sortedWith(compareByDescending<String> { ring1Degree[it] ?: 0 }.thenBy { it })
            .firstOrNull()

        if (headNeighbour != null) {
            path.addFirst(headNeighbour)
            remaining.remove(headNeighbour)
            continue
        }

        val fallback = remaining.sorted().maxByOrNull { ring1Degree[it] ?: 0 } ?: break
        path.addLast(fallback)
        remaining.remove(fallback)
    }
    return path.toList()
}

/**
 * Distribute [peerCount] peers evenly around a full circle.
 *
 * Ring 1 starts at the top (90°). Each ring further out is rotated by half of its own
 * angular step, so consecutive orbits don't line their first peer up on the same
 * radial spoke. Without the stagger every ring began at exactly 90°, drawing a seam
 * of stacked nodes straight up from the local peer — and a ring holding a single peer
 * always put it at the top, when either side of it was free.
 */
private fun calculateOptimalAngles(peerCount: Int, ringIndex: Int): DoubleArray {
    if (peerCount <= 0) return DoubleArray(0)
    val step = 2.0 * PI / peerCount
    val start = PI / 2.0 + step * 0.5 * (ringIndex - 1)
    return DoubleArray(peerCount) { i -> start + step * i }
}
