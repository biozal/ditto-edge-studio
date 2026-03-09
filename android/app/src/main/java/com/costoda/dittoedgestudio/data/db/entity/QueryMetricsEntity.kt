package com.costoda.dittoedgestudio.data.db.entity

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "query_metrics",
    foreignKeys = [
        ForeignKey(
            entity = HistoryEntity::class,
            parentColumns = ["_id"],
            childColumns = ["history_id"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [Index(value = ["history_id"])]
)
data class QueryMetricsEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    @ColumnInfo(name = "history_id") val historyId: Long,
    @ColumnInfo(name = "execution_time_ms") val executionTimeMs: Long,
    @ColumnInfo(name = "docs_examined") val docsExamined: Int,
    @ColumnInfo(name = "docs_returned") val docsReturned: Int,
    @ColumnInfo(name = "indexes_used") val indexesUsed: String,   // JSON array string
    @ColumnInfo(name = "bytes_read") val bytesRead: Long,
    @ColumnInfo(name = "explain_plan") val explainPlan: String?,
    @ColumnInfo(name = "captured_at") val capturedAt: Long,       // epoch ms
)
