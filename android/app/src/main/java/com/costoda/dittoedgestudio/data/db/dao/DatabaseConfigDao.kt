package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface DatabaseConfigDao {

    @Query("SELECT * FROM databaseConfigs ORDER BY name ASC")
    fun observeAll(): Flow<List<DatabaseConfigEntity>>

    @Query("SELECT * FROM databaseConfigs ORDER BY name ASC")
    suspend fun getAll(): List<DatabaseConfigEntity>

    @Query("SELECT * FROM databaseConfigs WHERE _id = :id LIMIT 1")
    suspend fun getById(id: Long): DatabaseConfigEntity?

    @Query("SELECT * FROM databaseConfigs WHERE databaseId = :databaseId LIMIT 1")
    suspend fun getByDatabaseId(databaseId: String): DatabaseConfigEntity?

    /**
     * ABORT, deliberately — never REPLACE.
     *
     * `databaseId` carries a unique index and is the parent key four child tables
     * reference with `ON DELETE CASCADE`. Under REPLACE, SQLite resolves a conflict by
     * DELETING the existing config row, which cascade-wipes every subscription, observer,
     * favorite and history row for that database before inserting the replacement — with
     * no warning and no undo.
     *
     * Callers must resolve a duplicate `databaseId` before inserting;
     * [DatabaseRepositoryImpl.save] does this by adopting the existing row and updating it.
     * With ABORT, anything that slips through raises `SQLiteConstraintException` instead of
     * silently destroying the user's work.
     */
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(entity: DatabaseConfigEntity): Long

    @Update
    suspend fun update(entity: DatabaseConfigEntity)

    @Query("DELETE FROM databaseConfigs WHERE _id = :id")
    suspend fun deleteById(id: Long)

    @Query("DELETE FROM databaseConfigs WHERE databaseId = :databaseId")
    suspend fun deleteByDatabaseId(databaseId: String)
}
