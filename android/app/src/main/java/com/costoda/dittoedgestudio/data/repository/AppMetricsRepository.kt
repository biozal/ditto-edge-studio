package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.AppMetrics

interface AppMetricsRepository {
    suspend fun snapshot(): AppMetrics
    fun recordQueryLatency(latencyMs: Double)
    fun incrementQueryCount()
}
