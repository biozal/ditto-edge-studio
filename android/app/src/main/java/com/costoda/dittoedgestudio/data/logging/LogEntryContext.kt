package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogEntry
import java.util.UUID

/**
 * The log entries immediately surrounding one focused entry.
 *
 * ## Why this is sliced from the *unfiltered* buffer
 *
 * The whole point of context is to show what the SDK was doing around a line,
 * which is almost always something the current filter hides. Slicing the
 * filtered display list instead would mean that expanding an error in the Errors
 * tab shows five other errors — the neighbours you already had, and none of the
 * ones that explain them. So [around] must always be handed the active source
 * buffer, never the filtered rows.
 *
 * Expansion state belongs to the list's owner, not the row: a row cannot reach
 * the unfiltered buffer, and per-row state does not survive a re-parse (which
 * mints new entry ids). One row open at a time.
 */
data class LogEntryContext(
    /** Entries immediately before the focused one, oldest first. */
    val before: List<LogEntry>,
    /** Entries immediately after the focused one, oldest first. */
    val after: List<LogEntry>,
) {
    val isEmpty: Boolean get() = before.isEmpty() && after.isEmpty()

    companion object {
        val EMPTY = LogEntryContext(emptyList(), emptyList())

        /**
         * Default number of entries shown on each side, matching the VS Code
         * analyzer's `contextBefore` / `contextAfter`.
         */
        const val DEFAULT_RADIUS = 5

        /**
         * Slices up to [radius] entries either side of the entry with [id].
         *
         * Returns [EMPTY] when the id is not in [entries] — which happens
         * legitimately: the buffer is capped, so an entry the user expanded can
         * be trimmed away underneath them, and a source switch replaces the
         * buffer entirely. A linear scan is fine here because this only runs for
         * a single expanded row, never per visible row.
         */
        fun around(id: UUID, entries: List<LogEntry>, radius: Int = DEFAULT_RADIUS): LogEntryContext {
            if (radius <= 0) return EMPTY
            val index = entries.indexOfFirst { it.id == id }
            if (index < 0) return EMPTY
            val lower = maxOf(0, index - radius)
            val upper = minOf(entries.size, index + radius + 1)
            return LogEntryContext(
                before = entries.subList(lower, index).toList(),
                after = entries.subList(index + 1, upper).toList(),
            )
        }
    }
}
