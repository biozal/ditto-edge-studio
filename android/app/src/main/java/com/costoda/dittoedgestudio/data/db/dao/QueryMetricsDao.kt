package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Transaction
import com.costoda.dittoedgestudio.data.db.entity.QueryMetricsEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface QueryMetricsDao {

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: QueryMetricsEntity): Long

    /**
     * Insert + evict-oldest as one transaction so the retention cap is atomic —
     * a failure between the two statements can never leave the table over [keep].
     * The cap is per database ([QueryMetricsEntity.databaseId]).
     */
    @Transaction
    suspend fun insertAndTrim(entity: QueryMetricsEntity, keep: Int): Long {
        val id = insert(entity)
        trimToLatest(entity.databaseId, keep)
        return id
    }

    /**
     * Fetch by the metrics row's own primary key. Detail lookups MUST use this —
     * `history_id` is non-unique (history dedups re-runs of the same query), so a
     * history-keyed lookup can return an arbitrary older capture.
     */
    @Query("SELECT * FROM query_metrics WHERE id = :id")
    suspend fun getById(id: Long): QueryMetricsEntity?

    @Query(
        "SELECT * FROM query_metrics WHERE database_id = :databaseId " +
            "ORDER BY captured_at DESC, id DESC"
    )
    suspend fun getAllByDatabase(databaseId: String): List<QueryMetricsEntity>

    /** Live stream of [databaseId]'s captures — the list pane collects this so new
     *  captures appear without a manual refresh. */
    @Query(
        "SELECT * FROM query_metrics WHERE database_id = :databaseId " +
            "ORDER BY captured_at DESC, id DESC"
    )
    fun observeByDatabase(databaseId: String): Flow<List<QueryMetricsEntity>>

    @Query("DELETE FROM query_metrics WHERE database_id = :databaseId")
    suspend fun deleteAllByDatabase(databaseId: String)

    /**
     * Keeps only the [keep] most recent rows of [databaseId], evicting the oldest —
     * mirrors the 200-record cap of SwiftUI's `QueryMetricsRepository`. Other
     * databases' rows are untouched.
     */
    @Query(
        "DELETE FROM query_metrics WHERE database_id = :databaseId AND id NOT IN (" +
            "SELECT id FROM query_metrics WHERE database_id = :databaseId " +
            "ORDER BY captured_at DESC, id DESC LIMIT :keep" +
            ")"
    )
    suspend fun trimToLatest(databaseId: String, keep: Int)
}
