package com.costoda.dittoedgestudio.data.repository

import android.content.Context
import android.os.Debug
import android.os.SystemClock
import com.costoda.dittoedgestudio.domain.model.AppMetrics
import com.costoda.dittoedgestudio.domain.model.CollectionStorageInfo
import com.ditto.kotlin.Ditto
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

    override suspend fun snapshot(context: Context, ditto: Ditto?): AppMetrics = withContext(Dispatchers.IO) {
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

        // Storage metrics from app files directory
        val dittoDir = File(context.filesDir, "ditto")
        var storeBytes = 0L
        var replicationBytes = 0L
        var attachmentsBytes = 0L
        var authBytes = 0L
        var walShmBytes = 0L
        var logsBytes = 0L
        var otherBytes = 0L

        if (dittoDir.exists()) {
            dittoDir.walkTopDown().forEach { file ->
                if (file.isFile) {
                    val size = file.length()
                    val rel = file.path.removePrefix(dittoDir.path)
                    when {
                        rel.contains("ditto_store") -> storeBytes += size
                        rel.contains("ditto_replication") -> replicationBytes += size
                        rel.contains("ditto_attachments") -> attachmentsBytes += size
                        rel.contains("ditto_auth") -> authBytes += size
                        rel.endsWith(".wal") || rel.endsWith(".shm") -> walShmBytes += size
                        rel.contains("ditto_logs") -> logsBytes += size
                        else -> otherBytes += size
                    }
                }
            }
        }

        // Collection breakdown
        val collectionBreakdown = if (ditto != null) computeCollectionBreakdown(ditto) else emptyList()

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
            storeBytes = storeBytes,
            replicationBytes = replicationBytes,
            attachmentsBytes = attachmentsBytes,
            authBytes = authBytes,
            walShmBytes = walShmBytes,
            logsBytes = logsBytes,
            otherBytes = otherBytes,
            collectionBreakdown = collectionBreakdown,
        )
    }

    private suspend fun computeCollectionBreakdown(ditto: Ditto): List<CollectionStorageInfo> {
        return try {
            val colResult = ditto.store.execute("SELECT * FROM system:collections")
            val names = colResult.items.mapNotNull { item ->
                (item.value["name"] as? String).also { item.dematerialize() }
            }
            colResult.close()

            val breakdown = names.mapNotNull { name ->
                try {
                    val escaped = name.replace("`", "``")
                    val docResult = ditto.store.execute("SELECT * FROM `$escaped`")
                    var jsonBytes = 0L
                    var docCount = 0
                    docResult.items.forEach { item ->
                        jsonBytes += item.jsonString().toByteArray(Charsets.UTF_8).size.toLong()
                        docCount++
                        item.dematerialize()
                    }
                    docResult.close()
                    CollectionStorageInfo(
                        collectionName = name,
                        documentCount = docCount,
                        estimatedBytes = jsonBytes,
                    )
                } catch (e: Exception) {
                    null
                }
            }
            breakdown.sortedByDescending { it.estimatedBytes }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun readProcStat(key: String): Long {
        return try {
            RandomAccessFile("/proc/self/status", "r").use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    if (line!!.startsWith(key)) {
                        return line!!.replace(Regex("[^0-9]"), "").toLongOrNull() ?: 0L
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
