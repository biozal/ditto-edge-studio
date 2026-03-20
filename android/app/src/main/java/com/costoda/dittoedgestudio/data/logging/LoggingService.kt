package com.costoda.dittoedgestudio.data.logging

import android.content.Context
import android.util.Log
import timber.log.Timber
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class LoggingService(private val context: Context) {

    private val logsDir: File
        get() = File(context.filesDir, "app_logs").also { it.mkdirs() }

    private val timestampFormat = SimpleDateFormat("yyyy/MM/dd HH:mm:ss:SSS", Locale.US)
    private val fileDateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)

    fun createTree(): Timber.Tree = FileLoggingTree()

    fun getAllLogFiles(): List<File> =
        logsDir.listFiles { f -> f.name.startsWith("app-") && f.name.endsWith(".log") }
            ?.sortedBy { it.name }
            ?: emptyList()

    fun getLogsDirectory(): File = logsDir

    fun clearAllLogs() {
        logsDir.listFiles()?.forEach { it.delete() }
    }

    fun rotateOldLogs() {
        val sevenDaysAgo = System.currentTimeMillis() - (7L * 24 * 60 * 60 * 1000)
        logsDir.listFiles()?.forEach { f ->
            if (f.lastModified() < sevenDaysAgo) f.delete()
        }
    }

    inner class FileLoggingTree : Timber.Tree() {
        override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
            val level = priorityToLabel(priority)
            val tagStr = if (tag != null) " [$tag]" else ""
            synchronized(this) {
                val now = Date()
                val line = "${timestampFormat.format(now)} $level$tagStr $message\n"
                val file = File(logsDir, "app-${fileDateFormat.format(now)}.log")
                runCatching {
                    FileWriter(file, true).use { it.write(line) }
                }.onFailure { e ->
                    Log.e("LoggingService", "Failed to write log: ${e.message}")
                }
            }
            // Also log to Logcat so we don't lose logs during development
            Log.println(priority, tag ?: "App", message)
        }

        private fun priorityToLabel(priority: Int): String = when (priority) {
            Log.ERROR -> "ERROR"
            Log.WARN -> "WARN"
            Log.DEBUG -> "DEBUG"
            Log.VERBOSE -> "VERBOSE"
            else -> "INFO"
        }
    }
}
