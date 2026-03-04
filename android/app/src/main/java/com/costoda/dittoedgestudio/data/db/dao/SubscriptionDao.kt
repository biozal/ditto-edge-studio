package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.costoda.dittoedgestudio.data.db.entity.SubscriptionEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface SubscriptionDao {

    @Query("SELECT * FROM subscriptions WHERE databaseId = :databaseId ORDER BY name ASC")
    fun observeByDatabase(databaseId: String): Flow<List<SubscriptionEntity>>

    @Query("SELECT * FROM subscriptions WHERE databaseId = :databaseId ORDER BY name ASC")
    suspend fun getByDatabase(databaseId: String): List<SubscriptionEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(entity: SubscriptionEntity): Long

    @Update
    suspend fun update(entity: SubscriptionEntity)

    @Query("DELETE FROM subscriptions WHERE _id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM subscriptions WHERE databaseId = :databaseId")
    suspend fun deleteByDatabaseId(databaseId: String)
}
