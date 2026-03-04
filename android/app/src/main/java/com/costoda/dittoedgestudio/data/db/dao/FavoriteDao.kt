package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import com.costoda.dittoedgestudio.data.db.entity.FavoriteEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface FavoriteDao {

    @Query("SELECT * FROM favorites WHERE databaseId = :databaseId ORDER BY createdDate DESC")
    fun observeByDatabase(databaseId: String): Flow<List<FavoriteEntity>>

    @Query("SELECT * FROM favorites WHERE databaseId = :databaseId ORDER BY createdDate DESC")
    suspend fun getByDatabase(databaseId: String): List<FavoriteEntity>

    @Query("SELECT * FROM favorites WHERE databaseId = :databaseId AND query = :query LIMIT 1")
    suspend fun findDuplicate(databaseId: String, query: String): FavoriteEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: FavoriteEntity): Long

    @Query("DELETE FROM favorites WHERE _id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM favorites WHERE databaseId = :databaseId")
    suspend fun deleteByDatabaseId(databaseId: String)
}
