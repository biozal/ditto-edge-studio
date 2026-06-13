package com.costoda.dittoedgestudio.ui.navigation

import androidx.navigation3.runtime.NavKey
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem
import kotlinx.serialization.Serializable

/**
 * Navigation 3 keys for the top-level app graph.
 *
 * Each key represents a destination consumed by [AppNavGraph]'s `NavDisplay`.
 * Keys are `@Serializable` so the back stack can be restored across configuration
 * changes via `rememberNavBackStack`.
 *
 * `id` and `databaseId` are `Long` to match the Room auto-increment primary key
 * type used by `DittoDatabase` and consumed by `DatabaseEditorScreen`.
 */
@Serializable
data object DatabaseListKey : NavKey

@Serializable
data class DatabaseEditorKey(val id: Long = -1L) : NavKey

@Serializable
data object QrScannerKey : NavKey

// ---------------------------------------------------------------------------
// Studio rail section keys
// ---------------------------------------------------------------------------

/** Marker for the 7 studio rail sections. Rail selection replaces the top entry
 *  (no per-section history): back from any section exits the studio. */
sealed interface StudioSectionKey : NavKey {
    val databaseId: Long
}

@Serializable data class SubscriptionsKey(override val databaseId: Long) : StudioSectionKey   // canonical name: Presence
@Serializable data class QueryKey(override val databaseId: Long) : StudioSectionKey           // Query Workbench
@Serializable data class ObserversKey(override val databaseId: Long) : StudioSectionKey       // Observation
@Serializable data class LoggingKey(override val databaseId: Long) : StudioSectionKey         // Log Analyzer
@Serializable data class AppMetricsKey(override val databaseId: Long) : StudioSectionKey      // App Metrics
@Serializable data class QueryMetricsKey(override val databaseId: Long) : StudioSectionKey    // Query Metrics
@Serializable data class DiskUsageKey(override val databaseId: Long) : StudioSectionKey       // Database Metrics

// ---------------------------------------------------------------------------
// Studio child keys (compact-width drill-ins)
// ---------------------------------------------------------------------------

/**
 * Marker for the compact-width drill-in keys that belong to the studio but are NOT rail
 * section keys. Every instance carries a [databaseId] so [StudioScopeManager] can keep the
 * Koin scope alive, and [AppNavGraph.StudioSectionContainer] can strip them all in one
 * `removeIf` call on rail switches.
 */
sealed interface StudioChildKey : NavKey {
    val databaseId: Long
}

/** Compact-width drill-in: observer events for one observable (pushed entry so system back pops it).
 *  [observerId] matches [com.costoda.dittoedgestudio.domain.model.DittoObservable.id] (Long). */
@Serializable data class ObserverEventsKey(override val databaseId: Long, val observerId: Long) : StudioChildKey

/**
 * Compact-width drill-in: the EXPLAIN / stats detail for a single executed query.
 *
 * At ≥600dp this content is rendered as the [ListDetailSceneStrategy.detailPane] and the
 * ListDetailSceneStrategy places it side-by-side with [QueryMetricsKey]; no back-stack push
 * occurs. At compact widths it is pushed on top of [QueryMetricsKey] so the user reaches the
 * detail via a normal drill-in.
 *
 * [historyId] matches [com.costoda.dittoedgestudio.domain.model.QueryMetrics.historyId] (Long).
 */
@Serializable data class QueryMetricDetailKey(override val databaseId: Long, val historyId: Long) : StudioChildKey

// ---------------------------------------------------------------------------
// Mapping helpers between StudioNavItem enum and StudioSectionKey
// ---------------------------------------------------------------------------

/** Convert a [StudioNavItem] to its corresponding [StudioSectionKey] for [databaseId].
 *  The exhaustive `when` guarantees a compile error if a new rail item is added without
 *  a matching key. */
fun StudioNavItem.toSectionKey(databaseId: Long): StudioSectionKey = when (this) {
    StudioNavItem.SUBSCRIPTIONS -> SubscriptionsKey(databaseId)
    StudioNavItem.QUERY         -> QueryKey(databaseId)
    StudioNavItem.OBSERVERS     -> ObserversKey(databaseId)
    StudioNavItem.LOGGING       -> LoggingKey(databaseId)
    StudioNavItem.APP_METRICS   -> AppMetricsKey(databaseId)
    StudioNavItem.QUERY_METRICS -> QueryMetricsKey(databaseId)
    StudioNavItem.DISK_USAGE    -> DiskUsageKey(databaseId)
}

/** Reverse mapping: recover the [StudioNavItem] from any [StudioSectionKey].
 *  Also exhaustive — adding a new key without updating this property is a compile error. */
val StudioSectionKey.navItem: StudioNavItem get() = when (this) {
    is SubscriptionsKey -> StudioNavItem.SUBSCRIPTIONS
    is QueryKey         -> StudioNavItem.QUERY
    is ObserversKey     -> StudioNavItem.OBSERVERS
    is LoggingKey       -> StudioNavItem.LOGGING
    is AppMetricsKey    -> StudioNavItem.APP_METRICS
    is QueryMetricsKey  -> StudioNavItem.QUERY_METRICS
    is DiskUsageKey     -> StudioNavItem.DISK_USAGE
}

/**
 * Reverse mapping: recover the parent rail section's [StudioNavItem] from any [StudioChildKey].
 *
 * Used by [AppNavGraph] to derive the active studio context (which rail section's chrome to
 * render) when the back-stack top is a compact-width drill-in detail key rather than a
 * section key. Exhaustive `when` — adding a new child key without updating this property is
 * a compile error.
 */
val StudioChildKey.parentNavItem: StudioNavItem get() = when (this) {
    is ObserverEventsKey      -> StudioNavItem.OBSERVERS
    is QueryMetricDetailKey   -> StudioNavItem.QUERY_METRICS
}
