package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.key
import com.costoda.dittoedgestudio.viewmodel.StudioNavItem

/**
 * Maps a keyboard digit key code (1-indexed) to a [StudioNavItem], or returns null if the
 * index is out of range. This pure function is the testable core of the Ctrl+1..8 shortcut.
 *
 * @param oneBasedIndex 1-based digit pressed (1 = first visible item, N = last visible item).
 * @param items The rail items currently visible. When "Collect Metrics" is disabled the
 *   metrics items are hidden, so callers pass [StudioNavItem.visibleEntries] to keep digit
 *   positions aligned with what the user sees.
 * @return The [StudioNavItem] at that position, or null if [oneBasedIndex] is out of range.
 */
fun studioNavItemForDigit(
    oneBasedIndex: Int,
    items: List<StudioNavItem> = StudioNavItem.entries,
): StudioNavItem? {
    val zeroBasedIndex = oneBasedIndex - 1
    return if (zeroBasedIndex in items.indices) items[zeroBasedIndex] else null
}

/**
 * Maps a [KeyEvent] to a [StudioNavItem] for the Ctrl+1..8 rail-section shortcuts.
 *
 * Returns the matching [StudioNavItem] when the event is Ctrl+[1-8], or null for any
 * other event.
 *
 * Mapping:
 *   Ctrl+1 → SUBSCRIPTIONS  (index 0)
 *   Ctrl+2 → QUERY          (index 1)
 *   Ctrl+3 → OBSERVERS      (index 2)
 *   Ctrl+4 → LOGGING        (index 3)
 *   Ctrl+5 → APP_METRICS    (index 4)
 *   Ctrl+6 → QUERY_METRICS  (index 5)
 *   Ctrl+7 → DISK_USAGE     (index 6)
 *   Ctrl+8 → SYSTEM_METRICS (index 7)
 *
 * UI-event plumbing (attaching onPreviewKeyEvent to the scaffold's root container) cannot
 * be meaningfully unit-tested on the JVM without a full Compose runtime. The pure key→digit
 * mapping is extracted into [studioNavItemForDigit] which is testable without Android.
 */
fun studioShortcutFor(
    event: KeyEvent,
    items: List<StudioNavItem> = StudioNavItem.entries,
): StudioNavItem? {
    if (!event.isCtrlPressed) return null
    val digit = when (event.key) {
        Key.One -> 1
        Key.Two -> 2
        Key.Three -> 3
        Key.Four -> 4
        Key.Five -> 5
        Key.Six -> 6
        Key.Seven -> 7
        Key.Eight -> 8
        else -> return null
    }
    return studioNavItemForDigit(digit, items)
}
