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

    // ── meshFitZoom: keeping every device name inside the viewport ───────────
    // Fold cover screen: 904x2316 px at 2.625 px/dp = 344x882 dp of viewport.

    @Test
    fun `meshFitZoom zooms out when one ring plus its pills overruns a narrow screen`() {
        // Compact ring 1 = BASE_RADIUS_DP (123.75) and a 345 px pill — roughly what
        // a real device name ("Aaron's Galaxy Z Fold5") measures at 9sp bold on a
        // 2.625 px/dp screen — plus the 40 dp margin:
        // content = (123.75 * 2 * 2.625) + 345 + 105 = 1099.7 px against 904 px wide.
        val zoom = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = BASE_RADIUS_DP,
            maxPillWidthPx = 345f,
            pxPerDp = 2.625f,
            viewWidthPx = 904f,
            viewHeightPx = 2316f,
            marginPx = 40f * 2.625f,
        )
        assertEquals(904f / 1099.6875f, zoom, 0.001f)
        assertTrue("width is the binding dimension on a tall narrow screen", zoom < 1f)
    }

    @Test
    fun `meshFitZoom leaves a short-named compact mesh alone on the same screen`() {
        // Same ring, but 100 px pills: content = 854.7 px, which already fits 904 px.
        // Regression guard on the auto-fit only ever firing when it has to.
        val zoom = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = BASE_RADIUS_DP,
            maxPillWidthPx = 100f,
            pxPerDp = 2.625f,
            viewWidthPx = 904f,
            viewHeightPx = 2316f,
            marginPx = 40f * 2.625f,
        )
        assertTrue("nothing to fit — the caller must not zoom out", zoom > 1f)
    }

    @Test
    fun `meshFitZoom zooms out hard for an expanded ring on a narrow screen`() {
        // Expanded ring 1 = 123.75 * 1.75 = 216.5625 dp → content 1362 px vs 904 px.
        val zoom = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = BASE_RADIUS_DP * EXPANDED_RADIUS_SCALE,
            maxPillWidthPx = 100f,
            pxPerDp = 2.625f,
            viewWidthPx = 904f,
            viewHeightPx = 2316f,
            marginPx = 40f * 2.625f,
        )
        assertTrue("an expanded ring must zoom out well past half", zoom < 0.7f)
        assertTrue("but never below the view's minimum", zoom >= Transform.MIN_SCALE)
    }

    @Test
    fun `meshFitZoom leaves a mesh that already fits a tablet at 1x`() {
        // Same compact ring on a 2560x1600 px tablet viewport — no zoom-out needed.
        val zoom = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = BASE_RADIUS_DP,
            maxPillWidthPx = 100f,
            pxPerDp = 2f,
            viewWidthPx = 2560f,
            viewHeightPx = 1600f,
            marginPx = 40f * 2f,
        )
        assertTrue("a mesh that fits is never zoomed out", zoom > 1f)
    }

    @Test
    fun `meshFitZoom accounts for the widest pill, not just the ring`() {
        val short = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = BASE_RADIUS_DP,
            maxPillWidthPx = 60f,
            pxPerDp = 2.625f,
            viewWidthPx = 904f,
            viewHeightPx = 2316f,
            marginPx = 40f * 2.625f,
        )
        val long = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = BASE_RADIUS_DP,
            maxPillWidthPx = 400f,
            pxPerDp = 2.625f,
            viewWidthPx = 904f,
            viewHeightPx = 2316f,
            marginPx = 40f * 2.625f,
        )
        assertTrue("a long device name must pull the camera further out", long < short)
    }

    @Test
    fun `meshFitZoom falls back to 1 for degenerate inputs`() {
        assertEquals(1f, PresenceFocusPlanner.meshFitZoom(0f, 100f, 2f, 904f, 2316f, 80f))
        assertEquals(1f, PresenceFocusPlanner.meshFitZoom(123f, 100f, 0f, 904f, 2316f, 80f))
    }

    @Test
    fun `meshFitZoom is clamped to the view's scale range`() {
        val tiny = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = 100_000f,
            maxPillWidthPx = 100f,
            pxPerDp = 2.625f,
            viewWidthPx = 904f,
            viewHeightPx = 2316f,
            marginPx = 105f,
        )
        assertEquals(Transform.MIN_SCALE, tiny)
        val huge = PresenceFocusPlanner.meshFitZoom(
            maxRingRadiusDp = 1f,
            maxPillWidthPx = 1f,
            pxPerDp = 1f,
            viewWidthPx = 4000f,
            viewHeightPx = 4000f,
            marginPx = 1f,
        )
        assertEquals(Transform.MAX_SCALE, huge)
    }
}
