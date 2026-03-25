package com.costoda.dittoedgestudio.domain.model

data class CollectionStorageInfo(
    val collectionName: String,
    val documentCount: Int,
    val estimatedBytes: Long,
) {
    val estimatedBytesFormatted: String get() = formatBytes(estimatedBytes)
    val documentCountFormatted: String get() = "$documentCount docs"
}

data class AppMetrics(
    val capturedAt: Long,
    // Process
    val residentMemoryBytes: Long,
    val virtualMemoryBytes: Long,
    val cpuTimeMs: Long,
    val openFileDescriptors: Int,
    val processUptimeMs: Long,
    // Queries
    val totalQueryCount: Int,
    val avgQueryLatencyMs: Double,
    val lastQueryLatencyMs: Double?,
    // Storage
    val storeBytes: Long,
    val replicationBytes: Long,
    val attachmentsBytes: Long,
    val authBytes: Long,
    val walShmBytes: Long,
    val logsBytes: Long,
    val otherBytes: Long,
    val collectionBreakdown: List<CollectionStorageInfo> = emptyList(),
) {
    val residentMemoryFormatted: String get() = formatBytes(residentMemoryBytes)
    val virtualMemoryFormatted: String get() = formatBytes(virtualMemoryBytes)
    val cpuTimeFormatted: String get() =
        if (cpuTimeMs < 1000) "${cpuTimeMs} ms" else "${"%.2f".format(cpuTimeMs / 1000.0)} s"
    val uptimeFormatted: String get() {
        val secs = processUptimeMs / 1000
        val mins = secs / 60
        val hours = mins / 60
        return when {
            hours >= 1 -> "${hours}h ${mins % 60}m"
            mins >= 1 -> "${mins}m ${secs % 60}s"
            else -> "${secs}s"
        }
    }
    val avgLatencyFormatted: String get() = if (totalQueryCount > 0) formatMs(avgQueryLatencyMs) else "—"
    val lastLatencyFormatted: String get() = lastQueryLatencyMs?.let { formatMs(it) } ?: "—"
    val storeBytesFormatted: String get() = formatBytes(storeBytes)
    val replicationBytesFormatted: String get() = formatBytes(replicationBytes)
    val attachmentsBytesFormatted: String get() = formatBytes(attachmentsBytes)
    val authBytesFormatted: String get() = formatBytes(authBytes)
    val walShmBytesFormatted: String get() = formatBytes(walShmBytes)
    val logsBytesFormatted: String get() = formatBytes(logsBytes)
    val otherBytesFormatted: String get() = formatBytes(otherBytes)
    val totalStorageBytes: Long get() = storeBytes + replicationBytes + attachmentsBytes + authBytes + walShmBytes + logsBytes + otherBytes
    val totalStorageBytesFormatted: String get() = formatBytes(totalStorageBytes)
}

private fun formatBytes(bytes: Long): String = when {
    bytes == 0L -> "0 B"
    bytes < 1024 -> "$bytes B"
    bytes < 1024 * 1024 -> "${"%.1f".format(bytes / 1024.0)} KB"
    else -> "${"%.1f".format(bytes / (1024.0 * 1024))} MB"
}

private fun formatMs(ms: Double): String = when {
    ms < 1 -> "< 1 ms"
    ms < 1000 -> "${"%.1f".format(ms)} ms"
    else -> "${"%.2f".format(ms / 1000)} s"
}
