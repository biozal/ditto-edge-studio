package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.domain.model.AuthMode
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DatabaseConfigDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: DatabaseConfigDao

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
        dao = db.databaseConfigDao()
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun insertAndGetAll() = runTest {
        val entity = buildEntity(databaseId = "db-1", name = "TestDB")
        dao.insert(entity)

        val results = dao.getAll()
        assertEquals(1, results.size)
        assertEquals("TestDB", results[0].name)
    }

    @Test
    fun getByDatabaseId_returnsCorrectEntity() = runTest {
        dao.insert(buildEntity(databaseId = "db-1", name = "First"))
        dao.insert(buildEntity(databaseId = "db-2", name = "Second"))

        val result = dao.getByDatabaseId("db-2")
        assertEquals("Second", result?.name)
    }

    @Test
    fun getByDatabaseId_returnsNull_whenNotFound() = runTest {
        val result = dao.getByDatabaseId("missing")
        assertNull(result)
    }

    @Test
    fun observeAll_emitsUpdates() = runTest {
        val entity = buildEntity(databaseId = "db-1", name = "TestDB")
        dao.insert(entity)

        val results = dao.observeAll().first()
        assertEquals(1, results.size)
    }

    @Test
    fun deleteById_removesEntity() = runTest {
        val id = dao.insert(buildEntity(databaseId = "db-1", name = "ToDelete"))

        dao.deleteById(id)

        assertEquals(0, dao.getAll().size)
    }

    @Test
    fun update_modifiesExistingEntity() = runTest {
        val id = dao.insert(buildEntity(databaseId = "db-1", name = "Original"))
        val inserted = dao.getAll().first()

        dao.update(inserted.copy(name = "Updated"))

        val updated = dao.getByDatabaseId("db-1")
        assertEquals("Updated", updated?.name)
    }

    @Test
    fun insertAndGetPreservesStrictModeEnabled() = runTest {
        val entity = buildEntity(databaseId = "db-strict", name = "StrictDB", isStrictModeEnabled = true)
        dao.insert(entity)

        val result = dao.getByDatabaseId("db-strict")
        assertEquals(true, result?.isStrictModeEnabled)
    }

    private fun buildEntity(
        databaseId: String,
        name: String,
        isStrictModeEnabled: Boolean = false,
    ) = DatabaseConfigEntity(
        name = name,
        databaseId = databaseId,
        mode = AuthMode.SERVER.value,
        allowUntrustedCerts = false,
        isBluetoothLeEnabled = true,
        isLanEnabled = true,
        isAwdlEnabled = false,
        isCloudSyncEnabled = true,
        token = "",
        authUrl = "",
        websocketUrl = "",
        httpApiUrl = "",
        httpApiKey = "",
        secretKey = "",
        logLevel = "info",
        isStrictModeEnabled = isStrictModeEnabled,
    )
}
