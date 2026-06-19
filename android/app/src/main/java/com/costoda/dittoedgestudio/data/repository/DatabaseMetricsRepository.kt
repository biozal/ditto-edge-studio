package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DatabaseMetrics
import com.ditto.kotlin.Ditto

interface DatabaseMetricsRepository {
    /**
     * Compute a full Database Metrics snapshot. This is expensive — it walks the SDK's
     * `diskUsage` tree and reads every document of every collection to sum CBOR bytes.
     * Callers should treat it as manually triggered (no auto-refresh).
     */
    suspend fun snapshot(ditto: Ditto): DatabaseMetrics
}
