package com.costoda.dittoedgestudio.ui.navigation

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Unit tests for [activeStudioDatabaseIds] — the pure logic underpinning the
 * [StudioScopeManager] composable. Exercises every transition the back stack can go through:
 * studio entry, rail-section switch, observer drill-in, and studio exit.
 */
class StudioScopeManagerTest {

    @Test
    fun `empty back stack yields no active databaseIds`() {
        assertEquals(emptySet<Long>(), activeStudioDatabaseIds(emptyList()))
    }

    @Test
    fun `database list only yields no active databaseIds`() {
        assertEquals(emptySet<Long>(), activeStudioDatabaseIds(listOf(DatabaseListKey)))
    }

    @Test
    fun `entering studio via SubscriptionsKey marks its databaseId active`() {
        // User taps a database card -> we push SubscriptionsKey(id) as the new studio entry.
        val stack = listOf(DatabaseListKey, SubscriptionsKey(databaseId = 7L))
        assertEquals(setOf(7L), activeStudioDatabaseIds(stack))
    }

    @Test
    fun `rail switch preserves the same databaseId (no scope churn)`() {
        // Replace-top behaviour: Subscriptions -> Observers, same databaseId.
        // Both before and after states must show the same active set.
        val before = listOf(DatabaseListKey, SubscriptionsKey(databaseId = 7L))
        val after = listOf(DatabaseListKey, ObserversKey(databaseId = 7L))
        assertEquals(activeStudioDatabaseIds(before), activeStudioDatabaseIds(after))
        assertEquals(setOf(7L), activeStudioDatabaseIds(after))
    }

    @Test
    fun `ObserverEventsKey on top of ObserversKey keeps the same databaseId active`() {
        // Compact-width drill-in: ObserversKey -> ObserverEventsKey.
        val stack = listOf(
            DatabaseListKey,
            ObserversKey(databaseId = 7L),
            ObserverEventsKey(databaseId = 7L, observerId = 99L),
        )
        assertEquals(setOf(7L), activeStudioDatabaseIds(stack))
    }

    @Test
    fun `exiting the studio removes the databaseId from active set`() {
        // Back from any studio key -> only DatabaseListKey remains.
        val stack = listOf(DatabaseListKey)
        assertEquals(emptySet<Long>(), activeStudioDatabaseIds(stack))
    }

    @Test
    fun `two concurrent studios yield both databaseIds`() {
        // Hypothetical multi-window / future case. The logic should not assume one studio.
        val stack = listOf(
            DatabaseListKey,
            SubscriptionsKey(databaseId = 7L),
            ObserversKey(databaseId = 8L),
        )
        assertEquals(setOf(7L, 8L), activeStudioDatabaseIds(stack))
    }

    @Test
    fun `result preserves first-seen ordering`() {
        // Determinism: stable iteration order is useful for any caller using forEach.
        val stack = listOf(
            DatabaseListKey,
            ObserversKey(databaseId = 9L),
            SubscriptionsKey(databaseId = 4L),
            ObserverEventsKey(databaseId = 9L, observerId = 1L),
        )
        val ids = activeStudioDatabaseIds(stack).toList()
        assertEquals(listOf(9L, 4L), ids)
    }

    @Test
    fun `every StudioChildKey subtype contributes its databaseId to the active set`() {
        // Regression guard: if a new StudioChildKey subtype is added, this test catches it
        // before a strip-site or scope-manager site is missed. List all subtypes explicitly
        // (no reflection) so the test fails to compile if a constructor signature changes.
        val databaseId = 42L
        val subtypes: List<StudioChildKey> = listOf(
            ObserverEventsKey(databaseId = databaseId, observerId = 1L),
            QueryMetricDetailKey(databaseId = databaseId, metricsId = 1L),
        )
        subtypes.forEach { childKey ->
            assertEquals(
                "StudioChildKey subtype ${childKey::class.simpleName} not recognized by activeStudioDatabaseIds",
                setOf(databaseId),
                activeStudioDatabaseIds(listOf(childKey)),
            )
        }
    }

    @Test
    fun `unknown nav keys are ignored`() {
        // QrScannerKey / DatabaseEditorKey must never contribute to scope ownership.
        val stack = listOf(
            DatabaseListKey,
            DatabaseEditorKey(id = 1L),
            QrScannerKey,
            ObserversKey(databaseId = 2L),
        )
        assertEquals(setOf(2L), activeStudioDatabaseIds(stack))
    }

    @Test
    fun `QueryMetricDetailKey on top of QueryMetricsKey keeps the same databaseId active`() {
        // Compact-width drill-in: QueryMetricsKey -> QueryMetricDetailKey.
        val stack = listOf(
            DatabaseListKey,
            QueryMetricsKey(databaseId = 7L),
            QueryMetricDetailKey(databaseId = 7L, metricsId = 42L),
        )
        assertEquals(setOf(7L), activeStudioDatabaseIds(stack))
    }

}
