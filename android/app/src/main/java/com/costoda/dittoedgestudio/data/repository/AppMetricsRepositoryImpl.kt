package com.costoda.dittoedgestudio.data.repository

import android.os.Debug
import android.os.SystemClock
import com.costoda.dittoedgestudio.domain.model.AppMetrics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.RandomAccessFile
import java.util.LinkedList
import java.util.concurrent.atomic.AtomicInteger

class AppMetricsRepositoryImpl : AppMetricsRepository {

    private val queryCount = AtomicInteger(0)
    private val latencySamples = LinkedList<Double>()
    private val maxSamples = 120

    override fun incrementQueryCount() {
        queryCount.incrementAndGet()
    }

    override fun recordQueryLatency(latencyMs: Double) {
        synchronized(latencySamples) {
            latencySamples.add(latencyMs)
            while (latencySamples.size > maxSamples) latencySamples.poll()
        }
    }

    override suspend fun snapshot(): AppMetrics = withContext(Dispatchers.IO) {
        // Process metrics
        val memInfo = Debug.MemoryInfo()
        Debug.getMemoryInfo(memInfo)
        val residentMemory = memInfo.totalPrivateDirty.toLong() * 1024L
        val virtualMemory = readProcStat("VmSize") * 1024L
        val cpuTimeMs = readCpuTimeMs()
        val openFds = countOpenFds()
        val uptimeMs = SystemClock.elapsedRealtime()

        // Query metrics
        val total = queryCount.get()
        val samples = synchronized(latencySamples) { latencySamples.toList() }
        val avgLatency = if (samples.isNotEmpty()) samples.average() else 0.0
        val lastLatency = samples.lastOrNull()

        AppMetrics(
            capturedAt = System.currentTimeMillis(),
            residentMemoryBytes = residentMemory,
            virtualMemoryBytes = virtualMemory,
            cpuTimeMs = cpuTimeMs,
            openFileDescriptors = openFds,
            processUptimeMs = uptimeMs,
            totalQueryCount = total,
            avgQueryLatencyMs = avgLatency,
            lastQueryLatencyMs = lastLatency,
        )
    }

    private fun readProcStat(key: String): Long {
        return try {
            RandomAccessFile("/proc/self/status", "r").use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    if (line!!.startsWith(key)) {
                        return line.replace(Regex("[^0-9]"), "").toLongOrNull() ?: 0L
                    }
                }
                0L
            }
        } catch (e: Exception) {
            0L
        }
    }

    private fun readCpuTimeMs(): Long {
        return try {
            val stat = File("/proc/self/stat").readText().split(" ")
            val utime = stat[13].toLongOrNull() ?: 0L
            val stime = stat[14].toLongOrNull() ?: 0L
            val clkTck = 100L
            (utime + stime) * 1000L / clkTck
        } catch (e: Exception) {
            0L
        }
    }

    private fun countOpenFds(): Int {
        return try {
            File("/proc/self/fd").listFiles()?.size ?: 0
        } catch (e: Exception) {
            0
        }
    }
}
