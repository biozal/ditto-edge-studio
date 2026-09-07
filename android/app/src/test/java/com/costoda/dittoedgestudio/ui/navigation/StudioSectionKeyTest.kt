package com.costoda.dittoedgestudio.ui.navigation

import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class StudioSectionKeyTest {

    // -----------------------------------------------------------------------
    // Round-trip: every StudioNavItem <-> StudioSectionKey
    // -----------------------------------------------------------------------

    @Test
    fun `toSectionKey round-trips back to the same navItem for every StudioNavItem entry`() {
        StudioNavItem.entries.forEach { item ->
            val key = item.toSectionKey(42L)
            assertEquals(
                "navItem round-trip failed for $item",
                item,
                key.navItem,
            )
        }
    }

    @Test
    fun `toSectionKey carries the supplied databaseId for every StudioNavItem entry`() {
        StudioNavItem.entries.forEach { item ->
            val key = item.toSectionKey(42L)
            assertEquals(
                "databaseId mismatch for $item",
                42L,
                key.databaseId,
            )
        }
    }

    @Test
    fun `all eight StudioNavItem entries are covered (entry count guard)`() {
        // If the enum grows, the exhaustive whens in NavKeys.kt will be compile errors,
        // but this test catches any accidental shrink of the mapping.
        assertEquals(8, StudioNavItem.entries.size)
    }

    // -----------------------------------------------------------------------
    // kotlinx-serialization round-trips
    // -----------------------------------------------------------------------

    @Test
    fun `SubscriptionsKey survives JSON encode-decode round-trip`() {
        val original = SubscriptionsKey(databaseId = 42L)
        val json = Json.encodeToString(SubscriptionsKey.serializer(), original)
        val decoded = Json.decodeFromString(SubscriptionsKey.serializer(), json)
        assertEquals(original, decoded)
    }

    @Test
    fun `QueryKey survives JSON encode-decode round-trip`() {
        val original = QueryKey(databaseId = 42L)
        val json = Json.encodeToString(QueryKey.serializer(), original)
        val decoded = Json.decodeFromString(QueryKey.serializer(), json)
        assertEquals(original, decoded)
    }

    @Test
    fun `ObserverEventsKey survives JSON encode-decode round-trip`() {
        val original = ObserverEventsKey(databaseId = 42L, observerId = 7L)
        val json = Json.encodeToString(ObserverEventsKey.serializer(), original)
        val decoded = Json.decodeFromString(ObserverEventsKey.serializer(), json)
        assertEquals(original, decoded)
        assertEquals(42L, decoded.databaseId)
        assertEquals(7L, decoded.observerId)
    }

    // -----------------------------------------------------------------------
    // StudioChildKey.parentNavItem — drives chrome hoisting in AppNavGraph
    // -----------------------------------------------------------------------

    @Test
    fun `ObserverEventsKey parentNavItem maps to OBSERVERS`() {
        val key: StudioChildKey = ObserverEventsKey(databaseId = 1L, observerId = 1L)
        assertEquals(StudioNavItem.OBSERVERS, key.parentNavItem)
    }

    @Test
    fun `QueryMetricDetailKey parentNavItem maps to QUERY_METRICS`() {
        val key: StudioChildKey = QueryMetricDetailKey(databaseId = 1L, metricsId = 9L)
        assertEquals(StudioNavItem.QUERY_METRICS, key.parentNavItem)
    }
}
