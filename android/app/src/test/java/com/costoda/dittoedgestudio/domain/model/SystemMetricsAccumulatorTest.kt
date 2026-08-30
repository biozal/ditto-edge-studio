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
