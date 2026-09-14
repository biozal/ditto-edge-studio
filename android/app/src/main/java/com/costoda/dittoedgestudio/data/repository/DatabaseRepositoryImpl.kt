package com.costoda.dittoedgestudio.data.repository

import android.util.Log
import com.costoda.dittoedgestudio.BuildConfig
import com.costoda.dittoedgestudio.data.db.dao.DatabaseConfigDao
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.domain.model.AdvancedSettingsJson
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext

private const val TAG = "DatabaseRepository"

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
            // A config arriving with no row id is not necessarily NEW — a QR import or a
            // hand-typed config can carry a databaseId that is already registered.
            //
            // Inserting it used to hit the unique `databaseId` index under
            // `OnConflictStrategy.REPLACE`, and SQLite REPLACE *deletes* the conflicting
            // parent row: every subscription, observer, favorite and history row for that
            // databaseId went with it via `ON DELETE CASCADE`, silently, while the scanner
            // reported success. Re-sharing a database config is the feature's main use, so
            // this destroyed exactly the users who used it as intended.
            //
            // Resolve the conflict here instead: adopt the existing row's id and UPDATE it,
            // which leaves the row (and therefore its children) in place. The DAO's insert
            // is now ABORT, so any conflict this lookup misses fails loudly rather than
            // deleting data.
            val existing = dao.getByDatabaseId(database.databaseId)
            if (existing != null) {
                if (BuildConfig.DEBUG) {
                    Log.d(
                        TAG,
                        "save MERGE: dbId='${database.databaseId}' already registered as " +
                            "rowId=${existing.id} — updating in place, children preserved",
                    )
                }
                dao.update(database.toEntity().copy(id = existing.id))
                return@withContext existing.id
            }
            if (BuildConfig.DEBUG) {
                Log.d(TAG, "save INSERT: dbId='${database.databaseId}' name='${database.name}'")
            }
            dao.insert(database.toEntity())
        } else {
            if (BuildConfig.DEBUG) {
                Log.d(TAG, "save UPDATE: rowId=${database.id} dbId='${database.databaseId}'")
            }
            dao.update(database.toEntity())
            database.id
        }
    }

    override suspend fun delete(id: Long) = withContext(Dispatchers.IO) {
        if (BuildConfig.DEBUG) {
            Log.w(TAG, "DELETE rowId=$id — this CASCADE-deletes all subscriptions/observers/favorites for the dbId of this row")
        }
        dao.deleteById(id)
    }

    override suspend fun deleteByDatabaseId(databaseId: String) = withContext(Dispatchers.IO) {
        if (BuildConfig.DEBUG) {
            Log.w(TAG, "DELETE BY dbId='$databaseId' — this CASCADE-deletes all subscriptions/observers/favorites for this dbId")
        }
        dao.deleteByDatabaseId(databaseId)
    }
}

private fun DatabaseConfigEntity.toDomain(): DittoDatabase {
    // Fail-closed on unreadable scopes (see DittoDatabase.hasCorruptSyncScopes):
    // the config still loads so the rest of the list is usable, but it cannot be
    // opened until the scopes are re-entered or the loss is explicitly confirmed.
    val decodedScopes = runCatching { AdvancedSettingsJson.decodeScopes(collectionSyncScopes) }
    // Startup settings are best-effort by contrast: unreadable rows decode as empty.
    val decodedSettings = runCatching { AdvancedSettingsJson.decodeSettings(startupSettings) }
        .getOrDefault(emptyList())
    return DittoDatabase(
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
        isMulticastEnabled = isMulticastEnabled,
        multicastGroupAddress = multicastGroupAddress,
        multicastPort = multicastPort,
        multicastInterfaceName = multicastInterfaceName,
        logLevel = logLevel,
        isStrictModeEnabled = isStrictModeEnabled,
        collectionSyncScopes = decodedScopes.getOrDefault(emptyList()),
        startupSettings = decodedSettings,
        hasCorruptSyncScopes = decodedScopes.isFailure,
    )
}

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
    isMulticastEnabled = isMulticastEnabled,
    multicastGroupAddress = multicastGroupAddress,
    multicastPort = multicastPort,
    multicastInterfaceName = multicastInterfaceName,
    logLevel = logLevel,
    isStrictModeEnabled = isStrictModeEnabled,
    collectionSyncScopes = AdvancedSettingsJson.encodeScopes(collectionSyncScopes),
    startupSettings = AdvancedSettingsJson.encodeSettings(startupSettings),
)
