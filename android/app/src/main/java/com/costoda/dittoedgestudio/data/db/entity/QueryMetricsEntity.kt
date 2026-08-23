package com.costoda.dittoedgestudio.data.db.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

/**
 * Per-query metrics capture.
 *
 * Deliberately has NO foreign key (schema v6): the previous `history_id` FK with
 * `onDelete = CASCADE` meant history housekeeping (`clearHistory`, `removeHistoryItem`,
 * the 1000-row trim) silently wiped every metrics capture for the affected query.
 * SwiftUI's metrics store is independent of history — `history_id` is kept as a plain
 * reference column only.
 */
@Entity(
    tableName = "query_metrics",
    indices = [Index(value = ["database_id"])]
)
data class QueryMetricsEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @ColumnInfo(name = "history_id") val historyId: Long,
    @ColumnInfo(name = "database_id", defaultValue = "")
    val databaseId: String = "",                                // Ditto databaseId string
    @ColumnInfo(name = "execution_time_ms") val executionTimeMs: Long,
    @ColumnInfo(name = "docs_examined") val docsExamined: Int,
    @ColumnInfo(name = "docs_returned") val docsReturned: Int,
    @ColumnInfo(name = "indexes_used") val indexesUsed: String,   // JSON array string
    @ColumnInfo(name = "bytes_read") val bytesRead: Long,
    @ColumnInfo(name = "explain_plan") val explainPlan: String?,
    @ColumnInfo(name = "captured_at") val capturedAt: Long,       // epoch ms
    @ColumnInfo(name = "query_text", defaultValue = "")
    val queryText: String = "",                                   // DQL as typed by the user
)
