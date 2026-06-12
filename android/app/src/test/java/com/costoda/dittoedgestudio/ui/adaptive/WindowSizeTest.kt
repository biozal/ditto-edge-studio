package com.costoda.dittoedgestudio.ui.adaptive

import androidx.compose.ui.unit.dp
import androidx.window.core.layout.WindowSizeClass
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Tests for the Edge Studio pane-policy breakpoint extensions on [WindowSizeClass].
 *
 * Breakpoint constants (window-core 1.5.1):
 *   WIDTH_DP_MEDIUM_LOWER_BOUND   = 600
 *   WIDTH_DP_EXPANDED_LOWER_BOUND = 840
 *   WIDTH_DP_LARGE_LOWER_BOUND    = 1200
 *
 * [WindowSizeClass] is constructable on the JVM without an Android runtime via
 * `WindowSizeClass(minWidthDp: Int, minHeightDp: Int)`.
 */
class WindowSizeTest {

    // ---------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------

    private fun wsc(widthDp: Int) = WindowSizeClass(widthDp, 0)

    // ---------------------------------------------------------------------------
    // showsRail — boundary at 600 dp
    // ---------------------------------------------------------------------------

    @Test
    fun `showsRail is false below medium boundary (599dp)`() {
        assertFalse(wsc(599).showsRail)
    }

    @Test
    fun `showsRail is true at medium boundary (600dp)`() {
        assertTrue(wsc(600).showsRail)
    }

    @Test
    fun `showsRail is true above medium boundary (601dp)`() {
        assertTrue(wsc(601).showsRail)
    }

    // ---------------------------------------------------------------------------
    // studioMultiPane — boundary at 840 dp (studio rail + listPane + detailPane layout)
    // Below 840dp the studio uses drawer mode (Rail + Data Panel folded into the modal drawer,
    // Content Pane as the default view).
    // ---------------------------------------------------------------------------

    @Test
    fun `studioMultiPane is false below expanded boundary (839dp)`() {
        assertFalse(wsc(839).studioMultiPane)
    }

    @Test
    fun `studioMultiPane is true at expanded boundary (840dp)`() {
        assertTrue(wsc(840).studioMultiPane)
    }

    @Test
    fun `studioMultiPane is true above expanded boundary (841dp)`() {
        assertTrue(wsc(841).studioMultiPane)
    }

    @Test
    fun `studioMultiPane is false for compact window (400dp)`() {
        assertFalse(wsc(400).studioMultiPane)
    }

    @Test
    fun `studioMultiPane is false for medium window (720dp) - drawer mode despite showing rail elsewhere`() {
        val wsc = wsc(720)
        // Even though showsRail is true for non-studio screens, the studio is in drawer mode
        // below 840dp.
        assertTrue(wsc.showsRail)
        assertFalse(wsc.studioMultiPane)
    }

    // ---------------------------------------------------------------------------
    // dataPanelDefaultVisible — boundary at 840 dp
    // ---------------------------------------------------------------------------

    @Test
    fun `dataPanelDefaultVisible is false below expanded boundary (839dp)`() {
        assertFalse(wsc(839).dataPanelDefaultVisible)
    }

    @Test
    fun `dataPanelDefaultVisible is true at expanded boundary (840dp)`() {
        assertTrue(wsc(840).dataPanelDefaultVisible)
    }

    @Test
    fun `dataPanelDefaultVisible is true above expanded boundary (841dp)`() {
        assertTrue(wsc(841).dataPanelDefaultVisible)
    }

    // ---------------------------------------------------------------------------
    // inspectorDefaultVisible — boundary at 1200 dp
    // ---------------------------------------------------------------------------

    @Test
    fun `inspectorDefaultVisible is false below large boundary (1199dp)`() {
        assertFalse(wsc(1199).inspectorDefaultVisible)
    }

    @Test
    fun `inspectorDefaultVisible is true at large boundary (1200dp)`() {
        assertTrue(wsc(1200).inspectorDefaultVisible)
    }

    @Test
    fun `inspectorDefaultVisible is true above large boundary (1201dp)`() {
        assertTrue(wsc(1201).inspectorDefaultVisible)
    }

    // ---------------------------------------------------------------------------
    // Cross-property consistency checks
    // ---------------------------------------------------------------------------

    @Test
    fun `compact window (400dp) shows no rail, no data panel, no inspector`() {
        val wsc = wsc(400)
        assertFalse(wsc.showsRail)
        assertFalse(wsc.dataPanelDefaultVisible)
        assertFalse(wsc.inspectorDefaultVisible)
    }

    @Test
    fun `medium window (720dp) shows rail but not data panel or inspector`() {
        val wsc = wsc(720)
        assertTrue(wsc.showsRail)
        assertFalse(wsc.dataPanelDefaultVisible)
        assertFalse(wsc.inspectorDefaultVisible)
    }

    @Test
    fun `expanded window (900dp) shows rail and data panel but not inspector`() {
        val wsc = wsc(900)
        assertTrue(wsc.showsRail)
        assertTrue(wsc.dataPanelDefaultVisible)
        assertFalse(wsc.inspectorDefaultVisible)
    }

    @Test
    fun `large window (1440dp) shows rail, data panel, and inspector`() {
        val wsc = wsc(1440)
        assertTrue(wsc.showsRail)
        assertTrue(wsc.dataPanelDefaultVisible)
        assertTrue(wsc.inspectorDefaultVisible)
    }

    // ---------------------------------------------------------------------------
    // inspectorWidth — 300dp below Large, 360dp at Large, 400dp at XL (1600dp)
    // ---------------------------------------------------------------------------

    @Test
    fun `inspectorWidth is 300dp below large boundary (1199dp)`() {
        assertEquals(300.dp, wsc(1199).inspectorWidth)
    }

    @Test
    fun `inspectorWidth is 360dp at large boundary (1200dp)`() {
        assertEquals(360.dp, wsc(1200).inspectorWidth)
    }

    @Test
    fun `inspectorWidth is 360dp in large range (1400dp)`() {
        assertEquals(360.dp, wsc(1400).inspectorWidth)
    }

    @Test
    fun `inspectorWidth is 360dp just below XL boundary (1599dp)`() {
        assertEquals(360.dp, wsc(1599).inspectorWidth)
    }

    @Test
    fun `inspectorWidth is 400dp at XL boundary (1600dp)`() {
        assertEquals(400.dp, wsc(1600).inspectorWidth)
    }

    @Test
    fun `inspectorWidth is 400dp above XL boundary (1920dp)`() {
        assertEquals(400.dp, wsc(1920).inspectorWidth)
    }

    @Test
    fun `inspectorWidth is 300dp for compact window (400dp)`() {
        assertEquals(300.dp, wsc(400).inspectorWidth)
    }
}
