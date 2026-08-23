package com.costoda.dittoedgestudio.ui.navigation

import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [allowedHorizontalPartitions] — the policy deciding when the
 * ListDetailSceneStrategy may render list + detail side-by-side. Presence is the
 * special case: with "Split Presence view" off it stays single-pane at every width.
 */
class AllowedHorizontalPartitionsTest {

    @Test
    fun `compact width always allows only one partition`() {
        StudioNavItem.entries.forEach { section ->
            assertEquals(1, allowedHorizontalPartitions(false, section, presenceSplitView = true))
            assertEquals(1, allowedHorizontalPartitions(false, section, presenceSplitView = false))
        }
    }

    @Test
    fun `medium width allows two partitions for non-Presence sections`() {
        StudioNavItem.entries.filter { it != StudioNavItem.SUBSCRIPTIONS }.forEach { section ->
            assertEquals(2, allowedHorizontalPartitions(true, section, presenceSplitView = false))
            assertEquals(2, allowedHorizontalPartitions(true, section, presenceSplitView = true))
        }
    }

    @Test
    fun `presence allows two partitions only when split view is enabled`() {
        assertEquals(
            2,
            allowedHorizontalPartitions(true, StudioNavItem.SUBSCRIPTIONS, presenceSplitView = true),
        )
        assertEquals(
            1,
            allowedHorizontalPartitions(true, StudioNavItem.SUBSCRIPTIONS, presenceSplitView = false),
        )
    }

    @Test
    fun `no studio section on top (database list) allows two partitions at medium width`() {
        assertEquals(2, allowedHorizontalPartitions(true, null, presenceSplitView = false))
    }
}
