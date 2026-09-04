package com.costoda.dittoedgestudio.ui.mainstudio.presence

import com.costoda.dittoedgestudio.domain.model.ConnectionType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [PresenceFocusPlanner] — the pure decisions behind focus mode
 * (Expanded/full-mesh view): which peers form the focused neighbourhood, and the
 * zoom the focus view lands on. Mirrors the VS Code extension's `scene.ts`
 * (`neighboursOf`, `clampZoom(min(max(zoom, FOCUS_ZOOM), fitZoom))`) and the iOS
 * `PresenceFocusPlannerTests` (which uses inverted camera-scale semantics —
 * Compose `Transform.scale` IS the magnification, so the formula applies directly).
 */
class PresenceFocusPlannerTest {

    private fun edge(from: String, to: String) = PeerEdge(
        edgeId = "${listOf(from, to).sorted().joinToString("_")}_P2PWiFi",
        pairKey = listOf(from, to).sorted().joinToString("_"),
        fromPeerId = from,
        toPeerId = to,
        type = ConnectionType.P2PWiFi,
        isCloud = false,
        arcOutward = false,
    )

    @Test
    fun `neighbourKeys collects both edge directions, excluding self`() {
        val edges = listOf(
            edge("A", "local"),
            edge("A", "B"),
            edge("B", "C"),
            edge("A", "A"),
        )
        assertEquals(listOf("B", "local"), PresenceFocusPlanner.neighbourKeys("A", edges))
    }

    @Test
    fun `neighbourKeys of an isolated peer is empty`() {
        assertTrue(PresenceFocusPlanner.neighbourKeys("ghost", listOf(edge("A", "B"))).isEmpty())
    }

    @Test
    fun `focus scale magnifies to 1,25x for a small neighbourhood`() {
        // content 556px in a 1000×800 viewport → fitZoom = min(1.799, 1.439) ≈ 1.439
        val fit = PresenceFocusPlanner.fitZoom(556f, 556f, 1000f, 800f)
        val scale = PresenceFocusPlanner.focusScale(fitZoom = fit, currentZoom = 1f)
        // min(max(1.0, 1.25), 1.439) = 1.25 — the close-up applies.
        assertEquals(PresenceFocusPlanner.FOCUS_ZOOM, scale, 0.0001f)
    }

    @Test
    fun `focus scale never exceeds the fit for a large neighbourhood`() {
        // content 1056px → fitZoom = min(0.947, 0.758) ≈ 0.758
        val fit = PresenceFocusPlanner.fitZoom(1056f, 1056f, 1000f, 800f)
        val scale = PresenceFocusPlanner.focusScale(fitZoom = fit, currentZoom = 1f)
        // min(max(1.0, 1.25), 0.758) = 0.758 — fit wins over the 1.25× target.
        assertEquals(fit, scale, 0.0001f)
    }

    @Test
    fun `focus scale pulls a zoomed-in user out to the fit`() {
        val scale = PresenceFocusPlanner.focusScale(fitZoom = 1f, currentZoom = 2f)
        assertEquals(1f, scale, 0.0001f)
    }

    @Test
    fun `focus scale never leaves the view's scale range`() {
        assertEquals(
            Transform.MIN_SCALE,
            PresenceFocusPlanner.focusScale(fitZoom = 0.1f, currentZoom = 0.1f),
        )
        assertEquals(
            Transform.MAX_SCALE,
            PresenceFocusPlanner.focusScale(fitZoom = 9.9f, currentZoom = Transform.MAX_SCALE),
        )
    }

    @Test
    fun `fitZoom falls back to 1 for degenerate inputs`() {
        assertEquals(1f, PresenceFocusPlanner.fitZoom(0f, 100f, 100f, 100f))
        assertEquals(1f, PresenceFocusPlanner.fitZoom(100f, 100f, 0f, 100f))
    }
}
