package com.costoda.dittoedgestudio.viewmodel

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Unit tests for [StudioNavItem.isMetricsDestination] and [StudioNavItem.visibleEntries] —
 * the rail-item gating behind the "Collect Metrics" setting (mirrors SwiftUI's
 * `SidebarDestination.isMetricsDestination` / `MainStudioView.availableDestinations`).
 */
class StudioNavItemTest {

    @Test
    fun `APP_METRICS and QUERY_METRICS are metrics destinations`() {
        assertTrue(StudioNavItem.APP_METRICS.isMetricsDestination)
        assertTrue(StudioNavItem.QUERY_METRICS.isMetricsDestination)
    }

    @Test
    fun `all other items are not metrics destinations`() {
        val nonMetrics = StudioNavItem.entries.filter { !it.isMetricsDestination }
        assertEquals(
            listOf(
                StudioNavItem.SUBSCRIPTIONS,
                StudioNavItem.QUERY,
                StudioNavItem.OBSERVERS,
                StudioNavItem.LOGGING,
                StudioNavItem.DISK_USAGE,
            ),
            nonMetrics,
        )
    }

    @Test
    fun `visibleEntries returns all items when metrics enabled`() {
        assertEquals(StudioNavItem.entries, StudioNavItem.visibleEntries(metricsEnabled = true))
    }

    @Test
    fun `visibleEntries drops metrics items when metrics disabled`() {
        val visible = StudioNavItem.visibleEntries(metricsEnabled = false)
        assertFalse(StudioNavItem.APP_METRICS in visible)
        assertFalse(StudioNavItem.QUERY_METRICS in visible)
        assertFalse(StudioNavItem.SYSTEM_METRICS in visible)
        assertEquals(StudioNavItem.entries.size - 3, visible.size)
        // Order of the surviving items is preserved.
        assertEquals(
            StudioNavItem.entries.filter { !it.isMetricsDestination },
            visible,
        )
    }
}
