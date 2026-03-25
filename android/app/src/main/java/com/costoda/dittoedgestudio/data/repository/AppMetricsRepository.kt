package com.costoda.dittoedgestudio.data.repository

import android.content.Context
import com.costoda.dittoedgestudio.domain.model.AppMetrics
import com.ditto.kotlin.Ditto

interface AppMetricsRepository {
    suspend fun snapshot(context: Context, ditto: Ditto? = null): AppMetrics
    fun recordQueryLatency(latencyMs: Double)
    fun incrementQueryCount()
}
