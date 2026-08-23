package com.costoda.dittoedgestudio.ui.mainstudio

import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Unit tests for [studioNavItemForDigit] — the pure mapping function that backs the
 * Ctrl+1..7 keyboard shortcuts.
 *
 * Note: [studioShortcutFor] depends on [androidx.compose.ui.input.key.KeyEvent], which
 * wraps android.view.KeyEvent and therefore requires an Android runtime. That part of the
 * shortcut pipeline cannot be meaningfully unit-tested on the JVM; manual verification on
 * a desktop-windowing device is required. The mapping logic itself is fully covered here.
 */
class StudioKeyboardShortcutsTest {

    // ---------------------------------------------------------------------------
    // studioNavItemForDigit — valid range (1-7)
    // ---------------------------------------------------------------------------

    @Test
    fun `digit 1 maps to SUBSCRIPTIONS`() {
        assertEquals(StudioNavItem.SUBSCRIPTIONS, studioNavItemForDigit(1))
    }

    @Test
    fun `digit 2 maps to QUERY`() {
        assertEquals(StudioNavItem.QUERY, studioNavItemForDigit(2))
    }

    @Test
    fun `digit 3 maps to OBSERVERS`() {
        assertEquals(StudioNavItem.OBSERVERS, studioNavItemForDigit(3))
    }

    @Test
    fun `digit 4 maps to LOGGING`() {
        assertEquals(StudioNavItem.LOGGING, studioNavItemForDigit(4))
    }

    @Test
    fun `digit 5 maps to APP_METRICS`() {
        assertEquals(StudioNavItem.APP_METRICS, studioNavItemForDigit(5))
    }

    @Test
    fun `digit 6 maps to QUERY_METRICS`() {
        assertEquals(StudioNavItem.QUERY_METRICS, studioNavItemForDigit(6))
    }

    @Test
    fun `digit 7 maps to DISK_USAGE`() {
        assertEquals(StudioNavItem.DISK_USAGE, studioNavItemForDigit(7))
    }

    // ---------------------------------------------------------------------------
    // studioNavItemForDigit — out-of-range inputs
    // ---------------------------------------------------------------------------

    @Test
    fun `digit 0 returns null`() {
        assertNull(studioNavItemForDigit(0))
    }

    @Test
    fun `digit 8 returns null (beyond 7 entries)`() {
        assertNull(studioNavItemForDigit(8))
    }

    @Test
    fun `negative digit returns null`() {
        assertNull(studioNavItemForDigit(-1))
    }

    // ---------------------------------------------------------------------------
    // Exhaustive coverage: every StudioNavItem has exactly one digit mapped to it
    // ---------------------------------------------------------------------------

    @Test
    fun `each StudioNavItem entry is reachable from exactly one digit 1-7`() {
        val entries = StudioNavItem.entries
        assertEquals(
            "Expected 7 StudioNavItem entries; mapping table must be updated if this changes",
            7,
            entries.size,
        )
        entries.forEachIndexed { index, item ->
            val oneBasedDigit = index + 1
            assertEquals(
                "Digit $oneBasedDigit should map to $item",
                item,
                studioNavItemForDigit(oneBasedDigit),
            )
        }
    }

    @Test
    fun `digits 1-7 cover every index in StudioNavItem entries`() {
        val mapped = (1..7).mapNotNull { studioNavItemForDigit(it) }
        assertEquals(StudioNavItem.entries.toList(), mapped)
    }

    // ---------------------------------------------------------------------------
    // Filtered item lists (metrics hidden when "Collect Metrics" is disabled)
    // ---------------------------------------------------------------------------

    @Test
    fun `digit positions follow the visible items list when metrics are hidden`() {
        val visible = StudioNavItem.visibleEntries(metricsEnabled = false)
        // With APP_METRICS and QUERY_METRICS hidden, DISK_USAGE shifts from digit 7 to 5.
        assertEquals(StudioNavItem.DISK_USAGE, studioNavItemForDigit(5, visible))
        assertNull(studioNavItemForDigit(6, visible))
        assertNull(studioNavItemForDigit(7, visible))
    }

}
