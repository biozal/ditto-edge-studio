package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Test

class DatabaseMetricsTest {

    private fun storage(
        store: Long = 0,
        replication: Long = 0,
        attachments: Long = 0,
        auth: Long = 0,
        walShm: Long = 0,
        logs: Long = 0,
        other: Long = 0,
    ) = listOf(
        StorageCategory(StorageCategoryKey.STORE, store),
        StorageCategory(StorageCategoryKey.REPLICATION, replication),
        StorageCategory(StorageCategoryKey.ATTACHMENTS, attachments),
        StorageCategory(StorageCategoryKey.AUTH, auth),
        StorageCategory(StorageCategoryKey.WAL_SHM, walShm),
        StorageCategory(StorageCategoryKey.LOGS, logs),
        StorageCategory(StorageCategoryKey.OTHER, other),
    )

    @Test
    fun `totalStorageBytes sums all categories`() {
        val m = DatabaseMetrics(
            capturedAt = 0L,
            storage = storage(store = 100, replication = 50, walShm = 25),
            collections = emptyList(),
        )
        assertEquals(175L, m.totalStorageBytes)
    }

    @Test
    fun `percentOfTotal returns zero when total is zero`() {
        val m = DatabaseMetrics(0L, storage(), emptyList())
        assertEquals(0.0, m.percentOfTotal(StorageCategoryKey.STORE), 0.0001)
    }

    @Test
    fun `percentOfTotal returns each category share`() {
        val m = DatabaseMetrics(
            capturedAt = 0L,
            storage = storage(store = 100, replication = 100, walShm = 200),
            collections = emptyList(),
        )
        assertEquals(25.0, m.percentOfTotal(StorageCategoryKey.STORE), 0.0001)
        assertEquals(25.0, m.percentOfTotal(StorageCategoryKey.REPLICATION), 0.0001)
        assertEquals(50.0, m.percentOfTotal(StorageCategoryKey.WAL_SHM), 0.0001)
        assertEquals(0.0, m.percentOfTotal(StorageCategoryKey.AUTH), 0.0001)
    }

    @Test
    fun `bytesFor returns 0 for absent category`() {
        val m = DatabaseMetrics(
            capturedAt = 0L,
            storage = listOf(StorageCategory(StorageCategoryKey.STORE, 42)),
            collections = emptyList(),
        )
        assertEquals(0L, m.bytesFor(StorageCategoryKey.LOGS))
        assertEquals(42L, m.bytesFor(StorageCategoryKey.STORE))
    }

    @Test
    fun `collectionPayloadBytes sums collection cbor bytes`() {
        val m = DatabaseMetrics(
            capturedAt = 0L,
            storage = storage(),
            collections = listOf(
                CollectionPayloadInfo("a", 1, 200L),
                CollectionPayloadInfo("b", 1, 300L),
                CollectionPayloadInfo("c", 1, 100L),
            ),
        )
        assertEquals(600L, m.collectionPayloadBytes)
    }

    @Test
    fun `percentOfPayload returns zero when payload total is zero`() {
        val empty = CollectionPayloadInfo("x", 0, 0L)
        val m = DatabaseMetrics(0L, storage(), listOf(empty))
        assertEquals(0.0, m.percentOfPayload(empty), 0.0001)
    }

    @Test
    fun `percentOfPayload returns each collection share`() {
        val a = CollectionPayloadInfo("a", 33, 200L)
        val b = CollectionPayloadInfo("b", 163, 600L)
        val m = DatabaseMetrics(0L, storage(), listOf(b, a))
        assertEquals(25.0, m.percentOfPayload(a), 0.0001)
        assertEquals(75.0, m.percentOfPayload(b), 0.0001)
    }

    @Test
    fun `documentCountFormatted uses singular vs plural`() {
        assertEquals("1 doc", CollectionPayloadInfo("a", 1, 0L).documentCountFormatted)
        assertEquals("0 docs", CollectionPayloadInfo("a", 0, 0L).documentCountFormatted)
        assertEquals("163 docs", CollectionPayloadInfo("a", 163, 0L).documentCountFormatted)
    }

    @Test
    fun `cborPayloadBytesFormatted uses KB below 1024 KB`() {
        // 22 bytes → 0.02 KB → displays as "0.0 KB" (1-decimal KB rounding).
        assertEquals("0.0 KB", CollectionPayloadInfo("a", 0, 22L).cborPayloadBytesFormatted)
        // 7900 bytes → 7.71 KB → "7.7 KB"
        assertEquals("7.7 KB", CollectionPayloadInfo("a", 0, 7900L).cborPayloadBytesFormatted)
        // Just under the cutover: 1023 KB = 1047552 bytes
        assertEquals("1023.0 KB", CollectionPayloadInfo("a", 0, 1023L * 1024).cborPayloadBytesFormatted)
    }

    @Test
    fun `cborPayloadBytesFormatted switches to MB at or above 1024 KB`() {
        // 1024 KB exactly → 1.00 MB
        assertEquals("1.00 MB", CollectionPayloadInfo("a", 0, 1024L * 1024).cborPayloadBytesFormatted)
        // 16_700_000 bytes → 16308.59 KB → 15.93 MB (2-decimal MB)
        assertEquals("15.93 MB", CollectionPayloadInfo("a", 0, 16_700_000L).cborPayloadBytesFormatted)
    }

    @Test
    fun `collectionPayloadBytesFormatted matches per-collection formatter`() {
        // Total across collections also uses the KB-or-MB cutover so the section subtitle
        // never reports raw bytes or GB.
        val m = DatabaseMetrics(
            capturedAt = 0L,
            storage = storage(),
            collections = listOf(
                CollectionPayloadInfo("a", 1, 1024L * 600),     // 600 KB
                CollectionPayloadInfo("b", 1, 1024L * 600),     // 600 KB
            ),
        )
        // Total 1200 KB → crosses cutover → MB
        assertEquals("1.17 MB", m.collectionPayloadBytesFormatted)
    }
}
