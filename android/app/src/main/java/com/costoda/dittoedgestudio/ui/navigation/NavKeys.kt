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
 * type used by `DittoDatabase` and consumed by `DatabaseEditorScreen` /
 * `MainStudioScreen`.
 */
@Serializable
data object DatabaseListKey : NavKey

@Serializable
data class DatabaseEditorKey(val id: Long = -1L) : NavKey

@Serializable
data object QrScannerKey : NavKey

@Serializable
data class StudioKey(val databaseId: Long) : NavKey

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

/** Compact-width drill-in: observer events for one observable (pushed entry so system back pops it).
 *  [observerId] matches [com.costoda.dittoedgestudio.domain.model.DittoObservable.id] (Long). */
@Serializable data class ObserverEventsKey(val databaseId: Long, val observerId: Long) : NavKey

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
@Serializable data class QueryMetricDetailKey(val databaseId: Long, val historyId: Long) : NavKey

/**
 * Compact-width drill-in: the Presence content pane (Connected Peers tabs).
 *
 * At ≥600dp this content is rendered as the [ListDetailSceneStrategy.listPane] detail
 * placeholder and never pushed onto the back stack. At compact widths it is pushed on
 * top of [SubscriptionsKey] so the user reaches "Peers List / Presence Viewer" via a
 * normal back-stack drill-in from the subscriptions list.
 */
@Serializable data class PresenceContentKey(val databaseId: Long) : NavKey

/**
 * Compact-width drill-in: the Query Workbench content pane (DQL editor + results).
 *
 * At ≥600dp this content is rendered as the [ListDetailSceneStrategy.listPane] detail
 * placeholder and never pushed onto the back stack — the editor is always visible
 * side-by-side with the collections list.
 *
 * At compact widths the user lands on [QueryKey] (collections list) by default, but a
 * one-frame LaunchedEffect pushes this key automatically so the *effective* compact
 * landing is the editor — matching legacy phone UX where the editor was the primary
 * surface and collections lived in the rail drawer. Tapping system back from the editor
 * returns to the collections list (one-tap-away from anything in the editor).
 */
@Serializable data class QueryContentKey(val databaseId: Long) : NavKey

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
