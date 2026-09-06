package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemMetricsAccumulatorTest {

    private fun counterRow(key: String, delta: Any, labels: Map<String, String> = emptyMap()) =
        mapOf<String, Any?>(
            "key" to key,
            "labels" to labels,
            "description" to "desc",
            "unit" to "",
            "delta" to delta,
        )

    private fun histogramRow(key: String, dcount: Any, dsum: Any = 0.0) =
        mapOf<String, Any?>(
            "key" to key,
            "labels" to emptyMap<String, String>(),
            "description" to "",
            "unit" to "secs",
            "dcount" to dcount,
            "dsum" to dsum,
        )

    @Test
    fun `deltas accumulate into since-connect totals`() {
        val samples = mutableMapOf<String, SystemMetricSample>()
        SystemMetricsAccumulator.accumulate(listOf(counterRow("a.b.c", 2)), samples = samples)
        SystemMetricsAccumulator.accumulate(listOf(counterRow("a.b.c", 3)), samples = samples)

        val sample = samples.values.single()
        assertEquals(5.0, sample.sinceConnect, 0.0)
        assertEquals(3.0, sample.periodDelta, 0.0) // last read only
    }

    @Test
    fun `label maps key separate series`() {
        val samples = mutableMapOf<String, SystemMetricSample>()
        SystemMetricsAccumulator.accumulate(
            listOf(
                counterRow("m", 1, mapOf("db" to "main")),
                counterRow("m", 4, mapOf("db" to "auth")),
            ),
            samples = samples,
        )
        assertEquals(2, samples.size)
    }

    @Test
    fun `label order does not affect the series signature`() {
        assertEquals(
            SystemMetricsAccumulator.seriesSignature("k", mapOf("b" to "2", "a" to "1")),
            SystemMetricsAccumulator.seriesSignature("k", mapOf("a" to "1", "b" to "2")),
        )
    }

    @Test
    fun `histograms accumulate dcount and dsum`() {
        val samples = mutableMapOf<String, SystemMetricSample>()
        SystemMetricsAccumulator.accumulate(listOf(histogramRow("h", 2, 0.5)), samples = samples)
        SystemMetricsAccumulator.accumulate(listOf(histogramRow("h", 1, 0.25)), samples = samples)
        val sample = samples.values.single()
        assertEquals(SystemMetricKind.HISTOGRAM, sample.kind)
        assertEquals(3.0, sample.sinceConnect, 0.0)
        assertEquals(0.75, sample.sumSinceConnect!!, 0.0)
    }

    @Test
    fun `garbage and placeholder rows are ignored`() {
        val samples = mutableMapOf<String, SystemMetricSample>()
        SystemMetricsAccumulator.accumulate(
            listOf(
                mapOf("status" to "disabled", "description" to "x"), // placeholder
                mapOf("key" to ""), // empty key
                mapOf("key" to "ok", "delta" to 1.5),
            ),
            samples = samples,
        )
        assertEquals(listOf("ok"), samples.values.map { it.key })
    }

    @Test
    fun `exporter-disabled detection requires all rows keyless plus disabled status`() {
        assertTrue(SystemMetricsAccumulator.isExporterDisabled(listOf(mapOf("status" to "disabled"))))
        assertTrue(
            SystemMetricsAccumulator.isExporterDisabled(
                listOf(mapOf("status" to "disabled"), mapOf("status" to "disabled")),
            ),
        )
        assertTrue(!SystemMetricsAccumulator.isExporterDisabled(emptyList()))
        assertTrue(!SystemMetricsAccumulator.isExporterDisabled(listOf(counterRow("k", 1))))
        assertTrue(
            !SystemMetricsAccumulator.isExporterDisabled(
                listOf(mapOf("status" to "disabled"), mapOf("key" to "k", "delta" to 1)),
            ),
        )
    }

    @Test
    fun `non-finite deltas read as zero`() {
        val samples = mutableMapOf<String, SystemMetricSample>()
        SystemMetricsAccumulator.accumulate(listOf(counterRow("k", Double.NaN)), samples = samples)
        assertEquals(0.0, samples.values.single().sinceConnect, 0.0)
    }
}

class SystemMetricsPinOrderingTest {

    private fun ref(key: String) = SystemMetricSeriesRef(key, emptyMap())

    private val pins = listOf(ref("a"), ref("b"), ref("c"), ref("d"))

    private fun keys(pins: List<SystemMetricSeriesRef>) = pins.map { it.key }

    // ── move(from, to): the live swap-as-you-drag path ───────────────────────

    @Test
    fun `move swaps with the next row`() {
        assertEquals(listOf("a", "c", "b", "d"), keys(SystemMetricsPinOrdering.move(pins, 1, 2)))
    }

    @Test
    fun `move swaps with the previous row`() {
        assertEquals(listOf("a", "c", "b", "d"), keys(SystemMetricsPinOrdering.move(pins, 2, 1)))
    }

    @Test
    fun `move across several slots keeps the rest in order`() {
        assertEquals(listOf("b", "c", "d", "a"), keys(SystemMetricsPinOrdering.move(pins, 0, 3)))
    }

    @Test
    fun `move out of range or onto itself changes nothing`() {
        listOf(0 to -1, 3 to 4, 1 to 1, -1 to 0, 9 to 0).forEach { (from, to) ->
            assertEquals("move($from, $to)", keys(pins), keys(SystemMetricsPinOrdering.move(pins, from, to)))
        }
    }

    @Test
    fun `move preserves the set - no duplicates, nothing dropped`() {
        val moved = SystemMetricsPinOrdering.move(pins, 0, 3)
        assertEquals(pins.size, moved.size)
        assertEquals(pins.map { it.id }.toSet(), moved.map { it.id }.toSet())
    }

    // ── moved(dragged, target, before): parity with SwiftUI / the extension ───

    @Test
    fun `dragging down past a row's midpoint lands after it`() {
        val moved = SystemMetricsPinOrdering.moved(
            pins, draggedId = ref("a").id, targetId = ref("c").id, insertBefore = false,
        )
        // Lands where the pointer was, not one slot short of it.
        assertEquals(listOf("b", "c", "a", "d"), keys(moved))
    }

    @Test
    fun `dragging down onto a row's upper half lands before it`() {
        val moved = SystemMetricsPinOrdering.moved(
            pins, draggedId = ref("a").id, targetId = ref("c").id, insertBefore = true,
        )
        assertEquals(listOf("b", "a", "c", "d"), keys(moved))
    }

    @Test
    fun `dragging up onto a row's upper half lands before it`() {
        val moved = SystemMetricsPinOrdering.moved(
            pins, draggedId = ref("d").id, targetId = ref("b").id, insertBefore = true,
        )
        assertEquals(listOf("a", "d", "b", "c"), keys(moved))
    }

    @Test
    fun `dropping a row on itself changes nothing`() {
        val moved = SystemMetricsPinOrdering.moved(
            pins, draggedId = ref("b").id, targetId = ref("b").id, insertBefore = true,
        )
        assertEquals(keys(pins), keys(moved))
    }

    @Test
    fun `a target unpinned mid-drag leaves the order untouched`() {
        val moved = SystemMetricsPinOrdering.moved(
            pins, draggedId = ref("a").id, targetId = ref("gone").id, insertBefore = true,
        )
        assertEquals(keys(pins), keys(moved))
    }

    @Test
    fun `an unknown dragged series leaves the order untouched`() {
        val moved = SystemMetricsPinOrdering.moved(
            pins, draggedId = ref("gone").id, targetId = ref("b").id, insertBefore = true,
        )
        assertEquals(keys(pins), keys(moved))
    }
}
