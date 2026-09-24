package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Covers [SystemMetricsPinOrdering.dropIndex], which resolves where a pinned-row
 * drag would land.
 *
 * Two defects motivated these. A drag from the far end of the list stalled part
 * way and could not be resumed without lifting and starting over — the live
 * re-order moved the dragged row's composable out from under its own gesture. And
 * ordinary hand tremor made the insertion point flick back and forth.
 *
 * Mirrors `SystemMetricsPinDragTests` on SwiftUI — the rule has to stay identical
 * on both platforms.
 */
class SystemMetricsPinDragTest {

    private val sevenRows = List(7) { 40 }

    /** Replays a drag one event at a time, exactly as the screen does. */
    private fun replay(translations: List<Float>, heights: List<Int>, startIndex: Int): Pair<Int, Int> {
        var slot = startIndex
        var changes = 0
        for (translation in translations) {
            val next = SystemMetricsPinOrdering.dropIndex(startIndex, translation, heights, slot)
            if (next != slot) changes++
            slot = next
        }
        return slot to changes
    }

    /** A steady drag with hand tremor superimposed on every event. Deterministic. */
    private fun drag(to: Float, frames: Int, tremor: Float): List<Float> {
        var seed = 987_654.0
        return (0 until frames).map { frame ->
            seed = (seed * 1_103_515_245 + 12345) % 2_147_483_648
            to * frame / frames + (((seed / 2_147_483_648) - 0.5) * 2 * tremor).toFloat()
        }
    }

    @Test
    fun `a drag from the bottom reaches the top in one gesture`() {
        val (slot, _) = replay(drag(-250f, 300, 1f), sevenRows, startIndex = 6)
        assertEquals(0, slot)
    }

    @Test
    fun `a drag from the top reaches the bottom in one gesture`() {
        val (slot, _) = replay(drag(250f, 300, 1f), sevenRows, startIndex = 0)
        assertEquals(6, slot)
    }

    @Test
    fun `a single large jump still lands on the right slot`() {
        // Several pointer events can be coalesced; the slot must not advance by
        // only one per event.
        assertEquals(0, SystemMetricsPinOrdering.dropIndex(6, -250f, sevenRows, 6))
    }

    @Test
    fun `the slot never leaves the list`() {
        assertEquals(0, SystemMetricsPinOrdering.dropIndex(6, -10_000f, sevenRows, 6))
        assertEquals(6, SystemMetricsPinOrdering.dropIndex(0, 10_000f, sevenRows, 0))
    }

    @Test
    fun `the slot changes when the dragged centre passes the next row's`() {
        assertEquals(0, SystemMetricsPinOrdering.dropIndex(0, 39f, sevenRows, 0))
        assertEquals(1, SystemMetricsPinOrdering.dropIndex(0, 41f, sevenRows, 0))
    }

    @Test
    fun `mixed row heights use their own centres`() {
        // An expanded detail panel makes row 1 taller: its centre sits
        // 30/2 + 90/2 = 60px below row 0's.
        val heights = listOf(30, 90, 30)
        assertEquals(0, SystemMetricsPinOrdering.dropIndex(0, 59f, heights, 0))
        assertEquals(1, SystemMetricsPinOrdering.dropIndex(0, 61f, heights, 0))
    }

    @Test
    fun `an unmeasured row leaves the slot alone`() {
        // Heights arrive from onGloballyPositioned, so they are zero for a frame
        // or two. Resolving against a zero-height layout would teleport the row.
        assertEquals(0, SystemMetricsPinOrdering.dropIndex(0, 500f, listOf(40, 0, 40), 0))
    }

    @Test
    fun `tremor never flicks the insertion point back and forth`() {
        for (tremor in listOf(1f, 2f, 4f, 8f)) {
            val held = (0 until 200).map { 120f + if (it % 2 == 0) tremor else -tremor }
            val (slot, changes) = replay(drag(120f, 300, tremor) + held, sevenRows, startIndex = 0)
            assertEquals("slot at tremor $tremor", 3, slot)
            org.junit.Assert.assertTrue("changes at tremor $tremor: $changes", changes <= 3)
        }
    }

    @Test
    fun `a drag that goes nowhere changes nothing`() {
        val (slot, changes) = replay(drag(0f, 300, 8f), sevenRows, startIndex = 3)
        assertEquals(3, slot)
        assertEquals(0, changes)
    }

    @Test
    fun `rows the drag has passed slide up to open the gap`() {
        val offsets = (0 until 5).map {
            SystemMetricsPinOrdering.gapOffset(it, startIndex = 1, dropIndex = 3, draggedHeight = 40f)
        }
        assertEquals(listOf(0f, 0f, -40f, -40f, 0f), offsets)
    }

    @Test
    fun `rows the drag has passed slide down when moving up the list`() {
        val offsets = (0 until 5).map {
            SystemMetricsPinOrdering.gapOffset(it, startIndex = 3, dropIndex = 1, draggedHeight = 40f)
        }
        assertEquals(listOf(0f, 40f, 40f, 0f, 0f), offsets)
    }

    @Test
    fun `nothing shifts while the drop slot is where the row started`() {
        val offsets = (0 until 5).map {
            SystemMetricsPinOrdering.gapOffset(it, startIndex = 2, dropIndex = 2, draggedHeight = 40f)
        }
        assertEquals(List(5) { 0f }, offsets)
    }
}
