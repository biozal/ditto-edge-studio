package com.costoda.dittoedgestudio.ui.mainstudio.presence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

/**
 * Unit tests for the design-space → canvas-space scaling in [drawPresenceEdge].
 *
 * Everything positional in the presence graph (peer positions, pill rects, pill
 * labels) is multiplied by the camera zoom. The edge renderer's own constants —
 * parallel-edge separation, stroke width, arc ceilings, cloud-circle geometry —
 * used to be applied at 1x regardless, which held together at 100% zoom and fell
 * apart once the auto-fit started framing meshes at 34% on a narrow screen: a
 * connection line terminated well outside the pill it connects to.
 */
class PresenceEdgeGeometryTest {

    /** Galaxy Z Fold cover screen: 420 dpi → 2.625 px/dp. */
    private val pxPerDp = 2.625f

    /** Design constants from PresenceGraphView / measurePeerPill. */
    private val designOffsetPx = 10f * pxPerDp
    private val pillHeightPx = 22.5f * pxPerDp
    private val baseStrokePx = 2f * pxPerDp
    private val minStrokePx = MIN_EDGE_STROKE_DP * pxPerDp

    private val zooms = listOf(Transform.MIN_SCALE, 0.34f, 0.5f, 1f, 1.5f, Transform.MAX_SCALE)

    @Test
    fun `a parallel edge endpoint stays inside its pill at every zoom`() {
        for (zoom in zooms) {
            val offset = parallelEdgeOffsetPx(designOffsetPx, zoom)
            val pillHalfHeight = pillHeightPx * zoom * 0.5f
            assertTrue(
                "at ${zoom}x the endpoint sits $offset px off centre, outside the " +
                    "$pillHalfHeight px pill half-height",
                abs(offset) < pillHalfHeight,
            )
        }
    }

    @Test
    fun `an unscaled offset is what walked the endpoint out of the pill`() {
        // Regression witness: the pre-fix behaviour, at the zoom the screenshot showed.
        val zoom = 0.34f
        val pillHalfHeight = pillHeightPx * zoom * 0.5f
        assertTrue(
            "the unscaled offset must be the thing that overshoots",
            designOffsetPx > pillHalfHeight,
        )
        assertTrue(
            "scaling it brings the endpoint back inside",
            parallelEdgeOffsetPx(designOffsetPx, zoom) < pillHalfHeight,
        )
    }

    @Test
    fun `parallel offset keeps its sign so paired edges stay on opposite sides`() {
        assertEquals(-designOffsetPx * 0.5f, parallelEdgeOffsetPx(-designOffsetPx, 0.5f), 0.0001f)
        assertEquals(designOffsetPx * 0.5f, parallelEdgeOffsetPx(designOffsetPx, 0.5f), 0.0001f)
    }

    @Test
    fun `a single edge has no separation at any zoom`() {
        for (zoom in zooms) {
            assertEquals(0f, parallelEdgeOffsetPx(0f, zoom), 0.0001f)
        }
    }

    @Test
    fun `edge stroke keeps a constant ratio to the pill while it can`() {
        // At 1x a 2 dp line is 8.9% of a 22.5 dp pill; scaling holds that ratio until
        // the minimum-visibility floor takes over.
        val ratioAt1x = edgeStrokeWidthPx(baseStrokePx, 1f, minStrokePx) / pillHeightPx
        val ratioAtHalf = edgeStrokeWidthPx(baseStrokePx, 0.5f, minStrokePx) / (pillHeightPx * 0.5f)
        assertEquals(ratioAt1x, ratioAtHalf, 0.0001f)
    }

    @Test
    fun `edge stroke never thins below the visibility floor`() {
        for (zoom in zooms) {
            assertTrue(
                "a connection must stay visible at ${zoom}x",
                edgeStrokeWidthPx(baseStrokePx, zoom, minStrokePx) >= minStrokePx,
            )
        }
        // 2 dp x 0.25 = 0.5 dp would be a near-invisible hairline — the floor wins.
        assertEquals(minStrokePx, edgeStrokeWidthPx(baseStrokePx, Transform.MIN_SCALE, minStrokePx), 0.0001f)
    }

    @Test
    fun `edge stroke thickens when the camera zooms in`() {
        assertEquals(baseStrokePx * 2f, edgeStrokeWidthPx(baseStrokePx, 2f, minStrokePx), 0.0001f)
    }
}
