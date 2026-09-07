package com.costoda.dittoedgestudio.ui.mainstudio

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.ditto.kotlin.DittoLogLevel
import java.util.UUID

/**
 * The **analysis population**: the entries that the badges, the histograms, the
 * pattern scan and the log list all describe.
 *
 * ## The trade-off this type resolves
 *
 * Two properties were previously in conflict, and each platform had picked a
 * different one:
 *
 * - **SwiftUI** filters the whole capture buffer but computes analytics over the
 *   newest 5 000 entries. Search reaches everything; the badges describe a
 *   different set of rows than the list can show, so above 5 000 entries they
 *   silently under-report.
 * - **Android** (before this type) did both over the newest 5 000. Badges and
 *   list agreed, but the search box and the date filter were blind to anything
 *   older: on a 12 000-entry capture, a string that occurs only in the oldest
 *   7 000 lines returned "No log entries".
 *
 * Neither is acceptable, and the resolution is to reorder the two steps rather
 * than to choose between them. **Filter first over the whole buffer, then take
 * the newest [maxWindow] of what matched.** Search and the date filter reach the
 * entire buffer; the scan stays bounded at
 * `LogPatternEngine.MAX_SCAN_ENTRIES`; and every badge is measured over exactly
 * the population the list filters, so the two can never disagree.
 *
 * The visible consequence — deliberate, and the reason [matchedCount] is carried
 * here for the footer to report — is that the histograms and the time range now
 * describe the *matching* entries rather than the raw tail of the buffer. When a
 * search is active that is what the user is asking about; when it is not, the
 * population is the raw tail exactly as before.
 *
 * @property entries the analysis window: the newest [maxWindow] matching entries.
 * @property matchedCount how many entries in the whole buffer matched, before windowing.
 * @property bufferCount the size of the whole buffer.
 */
internal data class LogPopulation(
    val entries: List<LogEntry>,
    val matchedCount: Int,
    val bufferCount: Int,
) {
    /** True when matches were dropped to fit the window — the footer says so. */
    val isWindowed: Boolean get() = matchedCount > entries.size

    companion object {
        val EMPTY = LogPopulation(emptyList(), 0, 0)
    }
}

/**
 * Filters that define the population — as opposed to the ones that select
 * *within* it.
 *
 * The split is not arbitrary. A badge answers "how many Errors are there?", so
 * the level chips and the filter tab must be applied **after** the counting, or
 * the Errors badge would only ever be able to say "all of them". Search, date
 * range and component instead answer "which log am I looking at?", so they
 * belong to the population and the badges must reflect them.
 */
internal data class LogPopulationFilter(
    val searchQuery: String = "",
    val component: LogComponent = LogComponent.ALL,
    /** Component applies to the SDK source only; the other sources have no components. */
    val componentApplies: Boolean = false,
    val dateFilterEnabled: Boolean = false,
    val dateRangeStartMillis: Long? = null,
    val dateRangeEndMillis: Long? = null,
) {
    /**
     * True when this filter can remove anything. When false the population is
     * the plain tail of the buffer and a second pattern scan can be skipped.
     */
    val isActive: Boolean
        get() = searchQuery.isNotBlank() ||
            (componentApplies && component != LogComponent.ALL) ||
            (dateFilterEnabled && (dateRangeStartMillis != null || dateRangeEndMillis != null))
}

/**
 * Applies [filter] across the whole [full] buffer, then keeps the newest
 * [maxWindow] matches.
 *
 * @param searchTagsById user-tag labels per entry id, used so that searching for
 *   a pattern's `user_tag` finds the lines it labelled (SwiftUI matches tags too
 *   — `LoggingDetailView.computeFilteredEntries`). This map must come from a scan
 *   of the **unfiltered** window: deriving it from the population's own scan
 *   would make the search predicate depend on its own output, and switching from
 *   one tag query to another would then find nothing.
 */
internal fun logAnalysisPopulation(
    full: List<LogEntry>,
    filter: LogPopulationFilter,
    searchTagsById: Map<UUID, List<String>> = emptyMap(),
    maxWindow: Int,
): LogPopulation {
    if (full.isEmpty()) return LogPopulation(emptyList(), 0, 0)

    // Fast path: nothing to filter, so skip the predicate entirely. This is the
    // steady state (no search, no date range, component = All) and must stay as
    // cheap as the plain `takeLast` it replaces.
    if (!filter.isActive) {
        val window = if (full.size > maxWindow) full.takeLast(maxWindow) else full
        return LogPopulation(window, full.size, full.size)
    }

    val query = filter.searchQuery.trim()
    val matched = full.filter { entry ->
        matchesComponent(entry, filter) &&
            matchesDateRange(entry, filter) &&
            matchesSearch(entry, query, searchTagsById[entry.id])
    }
    val window = if (matched.size > maxWindow) matched.takeLast(maxWindow) else matched
    return LogPopulation(window, matched.size, full.size)
}

private fun matchesComponent(entry: LogEntry, filter: LogPopulationFilter): Boolean =
    !filter.componentApplies ||
        filter.component == LogComponent.ALL ||
        entry.component == filter.component

private fun matchesDateRange(entry: LogEntry, filter: LogPopulationFilter): Boolean {
    if (!filter.dateFilterEnabled) return true
    val time = entry.timestamp.time
    val afterStart = filter.dateRangeStartMillis?.let { time >= it } ?: true
    val beforeEnd = filter.dateRangeEndMillis?.let { time <= it } ?: true
    return afterStart && beforeEnd
}

private fun matchesSearch(entry: LogEntry, query: String, tags: List<String>?): Boolean {
    if (query.isEmpty()) return true
    return entry.message.contains(query, ignoreCase = true) ||
        tags?.any { it.contains(query, ignoreCase = true) } == true
}

/**
 * Selects the rows to render from an already-computed population.
 *
 * The level chips apply on **every** log source, not just Ditto SDK — SwiftUI
 * renders and applies them for all four, and an Android user previously had no
 * level control at all on App Logs / Transports / Connections. They stay
 * suppressed while a non-All tab is active, because that tab already owns the
 * level dimension and letting both run lets a stale chip selection silently
 * subtract rows from the tab the user just picked (spec §3).
 *
 * The final [maxDisplayed] cap is a rendering bound, not a filter: it is why the
 * footer reports both "shown" and "in population" counts.
 */
internal fun logDisplayEntries(
    population: List<LogEntry>,
    filterTab: LogFilterTab,
    problemIds: Set<UUID>,
    criticalIds: Set<UUID>,
    selectedLevels: Set<DittoLogLevel>,
    maxDisplayed: Int,
): List<LogEntry> {
    val chipsApply = !filterTab.suppressesLevelChips
    val filtered = population.filter { entry ->
        filterTab.accepts(entry, problemIds, criticalIds) &&
            (!chipsApply || entry.level in selectedLevels)
    }
    return if (filtered.size > maxDisplayed) filtered.takeLast(maxDisplayed) else filtered
}
