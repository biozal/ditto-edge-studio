package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.rememberScrollState
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.costoda.dittoedgestudio.data.logging.LogAnalytics
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.ui.components.DittoConnectedButtonGroup
import com.ditto.kotlin.DittoLogLevel
import java.util.UUID

/**
 * The five analyzer filter tabs, matching the SwiftUI `LogFilterTab` and the VS
 * Code extension's `FilterKey` exactly. See `docs/LOG_ANALYZER_SPEC.md` §3.
 */
enum class LogFilterTab(val label: String) {
    ALL("All"),
    CRITICAL("Critical"),
    ERROR("Errors"),
    WARNING("Warnings"),
    PROBLEM("Problems"),
    ;

    /**
     * Badge count for this tab.
     *
     * Critical and Problems deliberately read the **distinct-entry** counters
     * (`criticalEntries` / `problemEntries`), never the occurrence counters. A
     * line matched by three patterns adds three to `counts.problems` but can
     * only ever appear once in the list, so a badge sourced from `problems`
     * would promise rows the list cannot render.
     *
     * `counts` is nullable because the first analytics pass is asynchronous —
     * before it lands every badge is honestly zero rather than a stale guess.
     */
    fun badgeCount(counts: LogAnalytics.Counts?): Int {
        if (counts == null) return 0
        return when (this) {
            ALL -> counts.totalLines
            CRITICAL -> counts.criticalEntries
            ERROR -> counts.errors
            WARNING -> counts.warnings
            PROBLEM -> counts.problemEntries
        }
    }

    /**
     * Whether [entry] passes this tab.
     *
     * - [CRITICAL] — the entry was matched by a severity-5 pattern.
     * - [PROBLEM] — the entry was matched by any pattern.
     * - [ERROR] / [WARNING] — level equality.
     */
    fun accepts(entry: LogEntry, problemIds: Set<UUID>, criticalIds: Set<UUID>): Boolean = when (this) {
        ALL -> true
        CRITICAL -> entry.id in criticalIds
        ERROR -> entry.level == DittoLogLevel.Error
        PROBLEM -> entry.id in problemIds
        WARNING -> entry.level == DittoLogLevel.Warning
    }

    /**
     * True when this tab owns the level dimension, so the per-level chips must
     * be both hidden **and** not applied while it is active.
     *
     * Leaving the chips live would let a stale chip selection silently subtract
     * rows from the tab the user just picked, which reads as a broken filter
     * rather than as two filters disagreeing (spec §3).
     */
    val suppressesLevelChips: Boolean
        get() = this != ALL

    /**
     * Honest explanation of why the level chips are gone.
     *
     * SwiftUI shows "Level filtered by the X tab" for every non-All tab, which
     * is factually wrong for Critical and Problems: those select on *pattern
     * severity*, not on level, and will happily list a DEBUG line. The copy
     * here distinguishes the two cases.
     */
    val levelChipNotice: String?
        get() = when (this) {
            ALL -> null
            ERROR -> "Level is fixed to Error by this tab."
            WARNING -> "Level is fixed to Warning by this tab."
            CRITICAL -> "Showing severity-5 pattern matches at any level — level chips do not apply."
            PROBLEM -> "Showing pattern-matched lines at any level — level chips do not apply."
        }
}

/**
 * Tab strip with count badges above the log list.
 *
 * Reuses [DittoConnectedButtonGroup] — the same connected-button-group idiom as
 * the log source switcher directly above it — so the screen has one visual
 * language for "pick exactly one of these". The group sizes every segment to
 * the widest label, which five labelled-and-badged segments will overflow on a
 * phone, so it is wrapped in a horizontal scroll (the same treatment the
 * SwiftUI strip uses).
 */
@Composable
fun LogFilterTabs(
    selected: LogFilterTab,
    counts: LogAnalytics.Counts?,
    onSelect: (LogFilterTab) -> Unit,
    modifier: Modifier = Modifier,
) {
    val tabs = LogFilterTab.entries
    Row(
        modifier = modifier
            .testTag("LogFilterTabs")
            .horizontalScroll(rememberScrollState()),
    ) {
        DittoConnectedButtonGroup(
            options = tabs.map { "${it.label}  ${formatBadgeCount(it.badgeCount(counts))}" },
            selectedIndex = tabs.indexOf(selected),
            onSelect = { onSelect(tabs[it]) },
        )
    }
}

/**
 * Renders a badge count.
 *
 * The full number, never abbreviated. An earlier version shortened `5000` to
 * `"5.0k"` to keep the strip narrow, which SwiftUI does not do — and the
 * abbreviation destroys exactly the information the badge exists to give: the
 * analysis window caps at 5 000 entries, so `5.0k` and a genuine 4 950 are
 * indistinguishable, and the user cannot tell a full window from a nearly-full
 * one. The strip is already horizontally scrollable, so width is not the
 * constraint that was being traded against.
 */
internal fun formatBadgeCount(value: Int): String = value.toString()
