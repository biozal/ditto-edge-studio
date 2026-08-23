package com.costoda.dittoedgestudio.domain.model

/**
 * Storage category breakdown buckets for the Database Metrics screen.
 *
 * Order here is the order tiles render in the UI (matches `screens/database-metrics-vsc.png`).
 * Each label / description string is pulled verbatim from the VSC reference so the three
 * platforms speak with one voice.
 */
enum class StorageCategoryKey(val label: String, val description: String) {
    STORE(
        label = "Store",
        description = "Primary document store (the SQLite files). Grows with document count and field richness.",
    ),
    REPLICATION(
        label = "Replication",
        description = "Sync state — what this peer has told other peers it has, and what it expects from them.",
    ),
    ATTACHMENTS(
        label = "Attachments",
        description = "Binary blobs linked from documents. Lives outside the document store.",
    ),
    AUTH(
        label = "Auth",
        description = "Auth tokens and session material. Usually tiny.",
    ),
    WAL_SHM(
        label = "WAL / SHM",
        description = "SQLite write-ahead log + shared-memory files. Spikes mid-transaction; reclaimed on checkpoint.",
    ),
    LOGS(
        label = "Logs",
        description = "SDK and extension log files. Safe to delete if you need disk space.",
    ),
    OTHER(
        label = "Other",
        description = "Lock files, metrics scratch, anything Ditto writes outside the named buckets.",
    ),
}

data class StorageCategory(
    val key: StorageCategoryKey,
    val bytes: Long,
) {
    val label: String get() = key.label
    val description: String get() = key.description
    val bytesFormatted: String get() = formatBytes(bytes)
}

data class CollectionPayloadInfo(
    val name: String,
    val documentCount: Int,
    val cborPayloadBytes: Long,
) {
    /**
     * Collection sizes use a KB-only ramp until they would exceed 1024 KB, then switch to MB.
     * This avoids the visual jolt of seeing "12.7 KB" for one collection and "16312.7 KB" for
     * the next — we'd rather display "15.93 MB" once the value crosses into MB territory.
     */
    val cborPayloadBytesFormatted: String get() = formatBytesKbOrMb(cborPayloadBytes)
    val documentCountFormatted: String get() = formatCount(documentCount)
}

data class DatabaseMetrics(
    val capturedAt: Long,
    /** Storage categories in [StorageCategoryKey] declaration order — UI renders in this order. */
    val storage: List<StorageCategory>,
    /** Collections sorted descending by [CollectionPayloadInfo.cborPayloadBytes]. */
    val collections: List<CollectionPayloadInfo>,
) {
    val totalStorageBytes: Long = storage.sumOf { it.bytes }
    val totalStorageBytesFormatted: String get() = formatBytes(totalStorageBytes)

    val collectionPayloadBytes: Long = collections.sumOf { it.cborPayloadBytes }
    val collectionPayloadBytesFormatted: String get() = formatBytesKbOrMb(collectionPayloadBytes)

    fun bytesFor(category: StorageCategoryKey): Long =
        storage.firstOrNull { it.key == category }?.bytes ?: 0L

    /** Returns 0 when [totalStorageBytes] is zero (no divide-by-zero). */
    fun percentOfTotal(category: StorageCategoryKey): Double =
        if (totalStorageBytes == 0L) 0.0 else bytesFor(category) * 100.0 / totalStorageBytes

    /** Returns 0 when [collectionPayloadBytes] is zero (no divide-by-zero). */
    fun percentOfPayload(c: CollectionPayloadInfo): Double =
        if (collectionPayloadBytes == 0L) 0.0 else c.cborPayloadBytes * 100.0 / collectionPayloadBytes
}

private fun formatBytes(bytes: Long): String = when {
    bytes == 0L -> "0 B"
    bytes < 1024 -> "$bytes B"
    bytes < 1024L * 1024 -> "%.1f KB".format(bytes / 1024.0)
    bytes < 1024L * 1024 * 1024 -> "%.2f MB".format(bytes / (1024.0 * 1024.0))
    else -> "%.2f GB".format(bytes / (1024.0 * 1024.0 * 1024.0))
}

/**
 * KB-or-MB formatter for collection payload sizes. Always reports KB until the value
 * crosses 1024 KB, at which point it switches to MB. Never reports raw bytes or GB.
 */
private fun formatBytesKbOrMb(bytes: Long): String {
    val kb = bytes / 1024.0
    return if (kb < 1024.0) {
        "%.1f KB".format(kb)
    } else {
        "%.2f MB".format(kb / 1024.0)
    }
}

private fun formatCount(count: Int): String =
    if (count == 1) "1 doc" else "$count docs"
