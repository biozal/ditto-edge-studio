package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.costoda.dittoedgestudio.data.db.entity.HistoryEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface HistoryDao {

    @Query("SELECT * FROM history WHERE databaseId = :databaseId ORDER BY createdDate DESC")
    fun observeByDatabase(databaseId: String): Flow<List<HistoryEntity>>

    @Query("SELECT * FROM history WHERE databaseId = :databaseId ORDER BY createdDate DESC")
    suspend fun getByDatabase(databaseId: String): List<HistoryEntity>

    @Query("SELECT * FROM history WHERE databaseId = :databaseId AND query = :query LIMIT 1")
    suspend fun findDuplicate(databaseId: String, query: String): HistoryEntity?

    @Query("SELECT COUNT(*) FROM history WHERE databaseId = :databaseId")
    suspend fun countByDatabase(databaseId: String): Int

    @Query("DELETE FROM history WHERE _id IN (SELECT _id FROM history WHERE databaseId = :databaseId ORDER BY createdDate ASC LIMIT :count)")
    suspend fun deleteOldest(databaseId: String, count: Int)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: HistoryEntity): Long

    @Query("DELETE FROM history WHERE _id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM history WHERE databaseId = :databaseId")
    suspend fun deleteByDatabaseId(databaseId: String)
}
