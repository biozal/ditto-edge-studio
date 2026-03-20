package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.costoda.dittoedgestudio.data.db.entity.QueryMetricsEntity

@Dao
interface QueryMetricsDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: QueryMetricsEntity): Long

    @Query("SELECT * FROM query_metrics WHERE history_id = :historyId LIMIT 1")
    suspend fun getByHistoryId(historyId: Long): QueryMetricsEntity?

    @Query("SELECT * FROM query_metrics ORDER BY captured_at DESC")
    suspend fun getAll(): List<QueryMetricsEntity>

    @Query("DELETE FROM query_metrics")
    suspend fun deleteAll()
}
