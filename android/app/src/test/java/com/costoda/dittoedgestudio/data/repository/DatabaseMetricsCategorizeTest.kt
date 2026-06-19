package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.StorageCategoryKey
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Port of `SwiftUI/EdgeStudioUnitTests/Repositories/StorageRepositoryTests.swift` —
 * CategorizationTests suite. Verifies the pure [categorize] function buckets
 * (path, sizeInBytes) pairs into the seven storage categories the same way the
 * SwiftUI implementation does.
 */
class DatabaseMetricsCategorizeTest {

    private fun bytes(category: StorageCategoryKey, files: List<Pair<String, Long>>): Long =
        categorize(files).first { it.key == category }.bytes

    @Test
    fun `ditto_store files go to STORE`() {
        val files = listOf("/data/ditto_store/db.sql" to 5_000_000L)
        assertEquals(5_000_000L, bytes(StorageCategoryKey.STORE, files))
        assertEquals(0L, bytes(StorageCategoryKey.WAL_SHM, files))
    }

    @Test
    fun `ditto_replication files go to REPLICATION`() {
        val files = listOf("/data/ditto_replication/peerA/peerB/db.sql" to 1_000_000L)
        assertEquals(1_000_000L, bytes(StorageCategoryKey.REPLICATION, files))
        assertEquals(0L, bytes(StorageCategoryKey.STORE, files))
    }

    @Test
    fun `ditto_attachments files go to ATTACHMENTS`() {
        val files = listOf("/data/ditto_attachments/db.sql" to 2_000_000L)
        assertEquals(2_000_000L, bytes(StorageCategoryKey.ATTACHMENTS, files))
    }

    @Test
    fun `ditto_auth and ditto_auth_tmp go to AUTH`() {
        val files = listOf(
            "/data/ditto_auth/site.cbor" to 1_024L,
            "/data/ditto_auth_tmp/scratch" to 512L,
        )
        assertEquals(1_536L, bytes(StorageCategoryKey.AUTH, files))
    }

    @Test
    fun `ditto_logs directory and log_gz go to LOGS`() {
        val files = listOf(
            "/data/ditto_logs/ditto-2026.log" to 400_000L,
            "/data/ditto_logs/ditto-2025.log.gz" to 200_000L,
        )
        assertEquals(600_000L, bytes(StorageCategoryKey.LOGS, files))
    }

    @Test
    fun `log suffix files go to LOGS`() {
        val files = listOf("/var/app.log" to 500L)
        assertEquals(500L, bytes(StorageCategoryKey.LOGS, files))
    }

    @Test
    fun `wal and shm suffixes go to WAL_SHM regardless of directory`() {
        val files = listOf(
            "/data/ditto_store/db.sql-wal" to 10_000_000L,
            "/data/ditto_replication/peer/db.sql-shm" to 4_096L,
        )
        assertEquals(10_004_096L, bytes(StorageCategoryKey.WAL_SHM, files))
        assertEquals(0L, bytes(StorageCategoryKey.STORE, files))
        assertEquals(0L, bytes(StorageCategoryKey.REPLICATION, files))
    }

    @Test
    fun `unrecognised files go to OTHER`() {
        val files = listOf(
            "/data/ditto_system_info/db.sql" to 50_000L,
            "/data/__ditto_lock_file" to 0L,
            "/data/ditto_metrics/some.dat" to 1_000L,
        )
        assertEquals(51_000L, bytes(StorageCategoryKey.OTHER, files))
        assertEquals(0L, bytes(StorageCategoryKey.STORE, files))
    }

    @Test
    fun `empty input returns all-zero categories`() {
        val result = categorize(emptyList())
        assertEquals(7, result.size)
        result.forEach { assertEquals(0L, it.bytes) }
    }

    @Test
    fun `WAL_SHM takes priority over log suffix`() {
        // A file ending in -wal goes to WAL_SHM even when inside ditto_logs/.
        val files = listOf("/data/ditto_logs/app-wal" to 100L)
        assertEquals(100L, bytes(StorageCategoryKey.WAL_SHM, files))
        assertEquals(0L, bytes(StorageCategoryKey.LOGS, files))
    }

    @Test
    fun `category order matches StorageCategoryKey declaration order`() {
        val result = categorize(emptyList())
        assertEquals(
            StorageCategoryKey.entries.toList(),
            result.map { it.key },
        )
    }
}
