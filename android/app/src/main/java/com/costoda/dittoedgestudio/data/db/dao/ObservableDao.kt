package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.costoda.dittoedgestudio.data.db.entity.ObservableEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface ObservableDao {

    @Query("SELECT * FROM observables WHERE databaseId = :databaseId ORDER BY name ASC")
    fun observeByDatabase(databaseId: String): Flow<List<ObservableEntity>>

    @Query("SELECT * FROM observables WHERE databaseId = :databaseId ORDER BY name ASC")
    suspend fun getByDatabase(databaseId: String): List<ObservableEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: ObservableEntity): Long

    @Update
    suspend fun update(entity: ObservableEntity)

    @Query("DELETE FROM observables WHERE _id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM observables WHERE databaseId = :databaseId")
    suspend fun deleteByDatabaseId(databaseId: String)
}
