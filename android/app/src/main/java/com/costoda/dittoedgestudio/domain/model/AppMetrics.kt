package com.costoda.dittoedgestudio.domain.model

/**
 * Process- and query-level metrics displayed on the App Metrics rail item.
 *
 * Storage and per-collection payload metrics moved to [DatabaseMetrics] / the
 * Database Metrics rail item; this model is intentionally narrow now.
 */
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
) {
    val residentMemoryFormatted: String get() = formatBytes(residentMemoryBytes)
    val virtualMemoryFormatted: String get() = formatBytes(virtualMemoryBytes)
    val cpuTimeFormatted: String get() =
        if (cpuTimeMs < 1000) "$cpuTimeMs ms" else "${"%.2f".format(cpuTimeMs / 1000.0)} s"
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
