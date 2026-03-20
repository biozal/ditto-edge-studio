package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.DatabaseConfigDao
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

class DatabaseRepositoryImpl(private val dao: DatabaseConfigDao) : DatabaseRepository {

    override fun observeAll(): Flow<List<DittoDatabase>> =
        dao.observeAll().map { list -> list.map { it.toDomain() } }

    override suspend fun getAll(): List<DittoDatabase> = withContext(Dispatchers.IO) {
        dao.getAll().map { it.toDomain() }
    }

    override suspend fun getById(id: Long): DittoDatabase? = withContext(Dispatchers.IO) {
        dao.getById(id)?.toDomain()
    }

    override suspend fun getByDatabaseId(databaseId: String): DittoDatabase? =
        withContext(Dispatchers.IO) {
            dao.getByDatabaseId(databaseId)?.toDomain()
        }

    override suspend fun save(database: DittoDatabase): Long = withContext(Dispatchers.IO) {
        if (database.id == 0L) {
            dao.insert(database.toEntity())
        } else {
            dao.update(database.toEntity())
            database.id
        }
    }

    override suspend fun delete(id: Long) = withContext(Dispatchers.IO) {
        dao.deleteById(id)
    }

    override suspend fun deleteByDatabaseId(databaseId: String) = withContext(Dispatchers.IO) {
        dao.deleteByDatabaseId(databaseId)
    }
}

private fun DatabaseConfigEntity.toDomain() = DittoDatabase(
    id = id,
    name = name,
    databaseId = databaseId,
    token = token,
    authUrl = authUrl,
    websocketUrl = websocketUrl,
    httpApiUrl = httpApiUrl,
    httpApiKey = httpApiKey,
    mode = AuthMode.fromValue(mode),
    allowUntrustedCerts = allowUntrustedCerts,
    secretKey = secretKey,
    isBluetoothLeEnabled = isBluetoothLeEnabled,
    isLanEnabled = isLanEnabled,
    isAwdlEnabled = isAwdlEnabled,
    isCloudSyncEnabled = isCloudSyncEnabled,
    logLevel = logLevel,
    isStrictModeEnabled = isStrictModeEnabled,
)

private fun DittoDatabase.toEntity() = DatabaseConfigEntity(
    id = id,
    name = name,
    databaseId = databaseId,
    token = token,
    authUrl = authUrl,
    websocketUrl = websocketUrl,
    httpApiUrl = httpApiUrl,
    httpApiKey = httpApiKey,
    mode = mode.value,
    allowUntrustedCerts = allowUntrustedCerts,
    secretKey = secretKey,
    isBluetoothLeEnabled = isBluetoothLeEnabled,
    isLanEnabled = isLanEnabled,
    isAwdlEnabled = isAwdlEnabled,
    isCloudSyncEnabled = isCloudSyncEnabled,
    logLevel = logLevel,
    isStrictModeEnabled = isStrictModeEnabled,
)
