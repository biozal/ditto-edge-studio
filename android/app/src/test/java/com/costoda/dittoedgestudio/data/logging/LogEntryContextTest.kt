package com.costoda.dittoedgestudio.data.logging

import com.costoda.dittoedgestudio.domain.model.LogComponent
import com.costoda.dittoedgestudio.domain.model.LogEntry
import com.costoda.dittoedgestudio.domain.model.LogEntrySource
import com.ditto.kotlin.DittoLogLevel
import java.util.Date
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors `SwiftUI/EdgeStudioUnitTests/Logging/LogEntryContextTests.swift`. */
class LogEntryContextTest {

    /**
     * A buffer of [count] entries whose messages are their index, so the
     * assertions can talk about position without depending on ids.
     */
    private fun buffer(count: Int, level: DittoLogLevel = DittoLogLevel.Info): List<LogEntry> =
        (0 until count).map { index ->
            LogEntry(
                timestamp = Date(index * 1000L),
                level = level,
                message = "line-$index",
                component = LogComponent.SYNC,
                source = LogEntrySource.DittoSDK,
                rawLine = "line-$index",
            )
        }

    // ── Happy path ──────────────────────────────────────────────────────────

    @Test
    fun `slices the default five entries either side`() {
        // Arrange
        val entries = buffer(20)

        // Act
        val context = LogEntryContext.around(entries[10].id, entries)

        // Assert
        assertEquals(listOf("line-5", "line-6", "line-7", "line-8", "line-9"), context.before.map { it.message })
        assertEquals(
            listOf("line-11", "line-12", "line-13", "line-14", "line-15"),
            context.after.map { it.message },
        )
    }

    @Test
    fun `the focused entry is never included in either side`() {
        // Arrange
        val entries = buffer(20)
        val focused = entries[10]

        // Act
        val context = LogEntryContext.around(focused.id, entries)

        // Assert — the row renders the focused entry itself between the two
        // groups, so including it here would print it twice.
        assertFalse(context.before.any { it.id == focused.id })
        assertFalse(context.after.any { it.id == focused.id })
    }

    @Test
    fun `honours a custom radius`() {
        // Arrange
        val entries = buffer(20)

        // Act
        val context = LogEntryContext.around(entries[10].id, entries, radius = 2)

        // Assert
        assertEquals(listOf("line-8", "line-9"), context.before.map { it.message })
        assertEquals(listOf("line-11", "line-12"), context.after.map { it.message })
    }

    // ── Boundaries ──────────────────────────────────────────────────────────

    @Test
    fun `clamps at the start of the buffer`() {
        // Arrange
        val entries = buffer(20)

        // Act
        val context = LogEntryContext.around(entries[2].id, entries)

        // Assert
        assertEquals(listOf("line-0", "line-1"), context.before.map { it.message })
        assertEquals(5, context.after.size)
    }

    @Test
    fun `clamps at the end of the buffer`() {
        // Arrange — expanding the newest row is the common case, and it must not
        // trap on the upper bound.
        val entries = buffer(20)

        // Act
        val context = LogEntryContext.around(entries[19].id, entries)

        // Assert
        assertEquals(
            listOf("line-14", "line-15", "line-16", "line-17", "line-18"),
            context.before.map { it.message },
        )
        assertTrue(context.after.isEmpty())
    }

    @Test
    fun `the first entry has no before context`() {
        // Arrange
        val entries = buffer(20)

        // Act
        val context = LogEntryContext.around(entries[0].id, entries)

        // Assert
        assertTrue(context.before.isEmpty())
        assertEquals(5, context.after.size)
    }

    @Test
    fun `a single-entry buffer yields empty context`() {
        // Arrange
        val entries = buffer(1)

        // Act
        val context = LogEntryContext.around(entries[0].id, entries)

        // Assert
        assertTrue(context.isEmpty)
    }

    @Test
    fun `a buffer smaller than the radius returns everything else`() {
        // Arrange
        val entries = buffer(3)

        // Act
        val context = LogEntryContext.around(entries[1].id, entries)

        // Assert
        assertEquals(listOf("line-0"), context.before.map { it.message })
        assertEquals(listOf("line-2"), context.after.map { it.message })
    }

    // ── Missing entry ───────────────────────────────────────────────────────

    @Test
    fun `an id absent from the buffer yields empty context not a crash`() {
        // Arrange — the buffers are capped, so an expanded entry can be trimmed
        // away underneath the user; switching source replaces the buffer too.
        val entries = buffer(20)

        // Act
        val context = LogEntryContext.around(UUID.randomUUID(), entries)

        // Assert
        assertTrue(context.isEmpty)
    }

    @Test
    fun `an empty buffer yields empty context`() {
        assertTrue(LogEntryContext.around(UUID.randomUUID(), emptyList()).isEmpty)
    }

    @Test
    fun `a non-positive radius yields empty context`() {
        // Arrange
        val entries = buffer(20)

        // Act & Assert
        assertTrue(LogEntryContext.around(entries[10].id, entries, radius = 0).isEmpty)
        assertTrue(LogEntryContext.around(entries[10].id, entries, radius = -3).isEmpty)
    }

    // ── The point of the feature ────────────────────────────────────────────

    @Test
    fun `context comes from the unfiltered buffer so it can cross a filter`() {
        // Arrange — one error surrounded by info lines. This is what expanding
        // an error in the Errors tab must show: the info lines that explain it.
        // Slicing the filtered list would return the other errors instead, which
        // is exactly the information the user already had.
        val entries = buffer(11).toMutableList()
        val errorEntry = LogEntry(
            timestamp = Date(5_000),
            level = DittoLogLevel.Error,
            message = "boom",
            component = LogComponent.SYNC,
            source = LogEntrySource.DittoSDK,
            rawLine = "boom",
        )
        entries[5] = errorEntry

        // Act
        val context = LogEntryContext.around(errorEntry.id, entries)

        // Assert
        assertTrue(context.before.all { it.level == DittoLogLevel.Info })
        assertTrue(context.after.all { it.level == DittoLogLevel.Info })
        assertEquals(5, context.before.size)
        assertEquals(5, context.after.size)
    }

    @Test
    fun `ordering is preserved on both sides`() {
        // Arrange
        val entries = buffer(20)

        // Act
        val context = LogEntryContext.around(entries[10].id, entries)

        // Assert — the drawer prints before + focused + after as one run, so
        // both sides have to stay in buffer order.
        assertEquals(context.before.map { it.timestamp }.sorted(), context.before.map { it.timestamp })
        assertEquals(context.after.map { it.timestamp }.sorted(), context.after.map { it.timestamp })
        assertTrue(context.before.last().timestamp.before(entries[10].timestamp))
        assertTrue(context.after.first().timestamp.after(entries[10].timestamp))
    }
}
