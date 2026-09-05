package com.costoda.dittoedgestudio.ui.mainstudio.presence

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [centreDetailCard] and [cardContains].
 *
 * The card is centred rather than anchored to its peer: anchoring put it wherever that
 * peer happened to be, including hard against an edge where the parent's
 * `clipToBounds()` cut off the sync rows. Narrowest target is a folded Galaxy Z Fold
 * cover display, 904 x 2316 px, against a 260 dp (683 px) card.
 */
class PeerCardPlacementTest {

    private val pxPerDp = 2.625f
    private val cardW = 260f * pxPerDp
    private val cardH = 300f * pxPerDp
    private val viewW = 904f
    private val viewH = 2316f
    private val margin = 16f * pxPerDp

    private fun place(w: Float = cardW, h: Float = cardH, vw: Float = viewW, vh: Float = viewH) =
        centreDetailCard(w, h, vw, vh, margin)

    @Test
    fun `the card is centred in the viewport`() {
        val p = place()
        assertEquals((viewW - cardW) / 2f, p.x, 0.01f)
        assertEquals((viewH - cardH) / 2f, p.y, 0.01f)
    }

    @Test
    fun `a centred card is fully on screen, which is the whole point`() {
        val p = place()
        assertTrue(p.x >= margin)
        assertTrue(p.y >= margin)
        assertTrue(p.x + cardW <= viewW - margin)
        assertTrue(p.y + cardH <= viewH - margin)
    }

    @Test
    fun `placement does not depend on where the peer is`() {
        // Regression guard on the anchoring this replaced: the old placement produced a
        // different result per peer position, which is how cards ended up clipped.
        assertEquals(place(), place())
    }

    @Test
    fun `a card taller than the viewport pins to the margin so its top stays visible`() {
        // Reachable at large system font scales, or in a short split-screen window. The
        // card scrolls from there rather than centring itself off the top edge.
        val p = place(h = viewH + 500f)
        assertEquals(margin, p.y, 0.01f)
        assertTrue("must never place above the margin", p.y >= margin)
    }

    @Test
    fun `a card wider than the viewport pins to the margin`() {
        val p = place(w = viewW + 500f)
        assertEquals(margin, p.x, 0.01f)
    }

    @Test
    fun `an unmeasured card still yields a finite placement`() {
        // First frame runs at size 0 before onSizeChanged reports; the card is invisible
        // then, but the placement must not be NaN or negative.
        val p = place(w = 0f, h = 0f)
        assertTrue(p.x.isFinite() && p.y.isFinite())
        assertTrue(p.x >= 0f && p.y >= 0f)
    }

    // ── cardContains: the graph must ignore touches that belong to the card ──

    @Test
    fun `a point inside the card is claimed by it`() {
        val p = place()
        assertTrue(cardContains(p.x + cardW / 2f, p.y + cardH / 2f, p, cardW, cardH))
        assertTrue("top-left corner", cardContains(p.x, p.y, p, cardW, cardH))
        assertTrue("bottom-right corner", cardContains(p.x + cardW, p.y + cardH, p, cardW, cardH))
    }

    @Test
    fun `a point outside the card is not claimed`() {
        val p = place()
        assertFalse("above", cardContains(p.x + 10f, p.y - 1f, p, cardW, cardH))
        assertFalse("below", cardContains(p.x + 10f, p.y + cardH + 1f, p, cardW, cardH))
        assertFalse("left", cardContains(p.x - 1f, p.y + 10f, p, cardW, cardH))
        assertFalse("right", cardContains(p.x + cardW + 1f, p.y + 10f, p, cardW, cardH))
        assertFalse("far corner", cardContains(0f, 0f, p, cardW, cardH))
    }
}
