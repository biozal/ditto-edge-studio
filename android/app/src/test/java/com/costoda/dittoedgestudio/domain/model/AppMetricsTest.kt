package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

class AppMetricsTest {

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    private fun makeMetrics(
        residentMemoryBytes: Long = 0L,
        virtualMemoryBytes: Long = 0L,
        cpuTimeMs: Long = 0L,
        processUptimeMs: Long = 0L,
        totalQueryCount: Int = 0,
        avgQueryLatencyMs: Double = 0.0,
        lastQueryLatencyMs: Double? = null,
        storeBytes: Long = 0L,
        replicationBytes: Long = 0L,
        attachmentsBytes: Long = 0L,
        authBytes: Long = 0L,
        walShmBytes: Long = 0L,
        logsBytes: Long = 0L,
        otherBytes: Long = 0L,
        collectionBreakdown: List<CollectionStorageInfo> = emptyList(),
    ) = AppMetrics(
        capturedAt = 0L,
        residentMemoryBytes = residentMemoryBytes,
        virtualMemoryBytes = virtualMemoryBytes,
        cpuTimeMs = cpuTimeMs,
        openFileDescriptors = 0,
        processUptimeMs = processUptimeMs,
        totalQueryCount = totalQueryCount,
        avgQueryLatencyMs = avgQueryLatencyMs,
        lastQueryLatencyMs = lastQueryLatencyMs,
        storeBytes = storeBytes,
        replicationBytes = replicationBytes,
        attachmentsBytes = attachmentsBytes,
        authBytes = authBytes,
        walShmBytes = walShmBytes,
        logsBytes = logsBytes,
        otherBytes = otherBytes,
        collectionBreakdown = collectionBreakdown,
    )

    // -------------------------------------------------------------------------
    // formatBytes (tested via residentMemoryFormatted)
    // -------------------------------------------------------------------------

    @Test
    fun `formatBytes 0 bytes returns 0 B`() {
        val m = makeMetrics(residentMemoryBytes = 0L)
        assertEquals("0 B", m.residentMemoryFormatted)
    }

    @Test
    fun `formatBytes 512 bytes returns 512 B`() {
        val m = makeMetrics(residentMemoryBytes = 512L)
        assertEquals("512 B", m.residentMemoryFormatted)
    }

    @Test
    fun `formatBytes 1024 bytes returns 1_0 KB`() {
        val m = makeMetrics(residentMemoryBytes = 1024L)
        assertEquals("1.0 KB", m.residentMemoryFormatted)
    }

    @Test
    fun `formatBytes 1536 bytes returns 1_5 KB`() {
        val m = makeMetrics(residentMemoryBytes = 1536L)
        assertEquals("1.5 KB", m.residentMemoryFormatted)
    }

    @Test
    fun `formatBytes 1048576 bytes returns 1_0 MB`() {
        val m = makeMetrics(residentMemoryBytes = 1_048_576L)
        assertEquals("1.0 MB", m.residentMemoryFormatted)
    }

    @Test
    fun `formatBytes 1572864 bytes returns 1_5 MB`() {
        val m = makeMetrics(residentMemoryBytes = 1_572_864L)
        assertEquals("1.5 MB", m.residentMemoryFormatted)
    }

    // -------------------------------------------------------------------------
    // cpuTimeFormatted
    // -------------------------------------------------------------------------

    @Test
    fun `cpuTimeFormatted 500ms returns 500 ms`() {
        val m = makeMetrics(cpuTimeMs = 500L)
        assertEquals("500 ms", m.cpuTimeFormatted)
    }

    @Test
    fun `cpuTimeFormatted 1000ms returns 1_00 s`() {
        val m = makeMetrics(cpuTimeMs = 1000L)
        assertEquals("1.00 s", m.cpuTimeFormatted)
    }

    @Test
    fun `cpuTimeFormatted 1500ms returns 1_50 s`() {
        val m = makeMetrics(cpuTimeMs = 1500L)
        assertEquals("1.50 s", m.cpuTimeFormatted)
    }

    // -------------------------------------------------------------------------
    // uptimeFormatted
    // -------------------------------------------------------------------------

    @Test
    fun `uptimeFormatted 30000ms returns 30s`() {
        val m = makeMetrics(processUptimeMs = 30_000L)
        assertEquals("30s", m.uptimeFormatted)
    }

    @Test
    fun `uptimeFormatted 90000ms returns 1m 30s`() {
        val m = makeMetrics(processUptimeMs = 90_000L)
        assertEquals("1m 30s", m.uptimeFormatted)
    }

    @Test
    fun `uptimeFormatted 3600000ms returns 1h 0m`() {
        val m = makeMetrics(processUptimeMs = 3_600_000L)
        assertEquals("1h 0m", m.uptimeFormatted)
    }

    @Test
    fun `uptimeFormatted 5400000ms returns 1h 30m`() {
        val m = makeMetrics(processUptimeMs = 5_400_000L)
        assertEquals("1h 30m", m.uptimeFormatted)
    }

    // -------------------------------------------------------------------------
    // avgLatencyFormatted
    // -------------------------------------------------------------------------

    @Test
    fun `avgLatencyFormatted when totalQueryCount is 0 returns dash`() {
        val m = makeMetrics(totalQueryCount = 0, avgQueryLatencyMs = 99.0)
        assertEquals("—", m.avgLatencyFormatted)
    }

    @Test
    fun `avgLatencyFormatted 0_5ms returns less than 1 ms`() {
        val m = makeMetrics(totalQueryCount = 1, avgQueryLatencyMs = 0.5)
        assertEquals("< 1 ms", m.avgLatencyFormatted)
    }

    @Test
    fun `avgLatencyFormatted 50_5ms returns 50_5 ms`() {
        val m = makeMetrics(totalQueryCount = 1, avgQueryLatencyMs = 50.5)
        assertEquals("50.5 ms", m.avgLatencyFormatted)
    }

    @Test
    fun `avgLatencyFormatted 1500ms returns 1_50 s`() {
        val m = makeMetrics(totalQueryCount = 1, avgQueryLatencyMs = 1500.0)
        assertEquals("1.50 s", m.avgLatencyFormatted)
    }

    // -------------------------------------------------------------------------
    // lastLatencyFormatted
    // -------------------------------------------------------------------------

    @Test
    fun `lastLatencyFormatted when lastQueryLatencyMs is null returns dash`() {
        val m = makeMetrics(lastQueryLatencyMs = null)
        assertEquals("—", m.lastLatencyFormatted)
    }

    @Test
    fun `lastLatencyFormatted 0_5ms returns less than 1 ms`() {
        val m = makeMetrics(lastQueryLatencyMs = 0.5)
        assertEquals("< 1 ms", m.lastLatencyFormatted)
    }

    @Test
    fun `lastLatencyFormatted 50_5ms returns 50_5 ms`() {
        val m = makeMetrics(lastQueryLatencyMs = 50.5)
        assertEquals("50.5 ms", m.lastLatencyFormatted)
    }

    @Test
    fun `lastLatencyFormatted 1500ms returns 1_50 s`() {
        val m = makeMetrics(lastQueryLatencyMs = 1500.0)
        assertEquals("1.50 s", m.lastLatencyFormatted)
    }

    // -------------------------------------------------------------------------
    // totalStorageBytes computed property
    // -------------------------------------------------------------------------

    @Test
    fun `totalStorageBytes sums all storage fields`() {
        val m = makeMetrics(
            storeBytes = 100L,
            replicationBytes = 200L,
            attachmentsBytes = 300L,
            authBytes = 400L,
            walShmBytes = 500L,
            logsBytes = 600L,
            otherBytes = 700L,
        )
        assertEquals(2800L, m.totalStorageBytes)
    }

    @Test
    fun `totalStorageBytes is zero when all fields are zero`() {
        val m = makeMetrics()
        assertEquals(0L, m.totalStorageBytes)
    }

    // -------------------------------------------------------------------------
    // CollectionStorageInfo
    // -------------------------------------------------------------------------

    @Test
    fun `CollectionStorageInfo estimatedBytesFormatted 0 bytes returns 0 B`() {
        val info = CollectionStorageInfo("col", documentCount = 1, estimatedBytes = 0L)
        assertEquals("0 B", info.estimatedBytesFormatted)
    }

    @Test
    fun `CollectionStorageInfo estimatedBytesFormatted 2048 bytes returns 2_0 KB`() {
        val info = CollectionStorageInfo("col", documentCount = 1, estimatedBytes = 2048L)
        assertEquals("2.0 KB", info.estimatedBytesFormatted)
    }

    @Test
    fun `CollectionStorageInfo documentCountFormatted 5 returns 5 docs`() {
        val info = CollectionStorageInfo("col", documentCount = 5, estimatedBytes = 0L)
        assertEquals("5 docs", info.documentCountFormatted)
    }

    @Test
    fun `CollectionStorageInfo documentCountFormatted 1 returns 1 docs`() {
        val info = CollectionStorageInfo("col", documentCount = 1, estimatedBytes = 0L)
        assertEquals("1 docs", info.documentCountFormatted)
    }
}
