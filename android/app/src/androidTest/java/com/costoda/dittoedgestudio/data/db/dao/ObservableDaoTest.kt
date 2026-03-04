package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.data.db.entity.ObservableEntity
import com.costoda.dittoedgestudio.domain.model.AuthMode
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ObservableDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: ObservableDao

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
        dao = db.observableDao()
        runTest { db.databaseConfigDao().insert(buildParent("db-1")) }
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun insertAndGetByDatabase() = runTest {
        dao.insert(ObservableEntity(databaseId = "db-1", name = "Obs1", query = "SELECT *", isActive = false, lastUpdated = null))

        val results = dao.getByDatabase("db-1")
        assertEquals(1, results.size)
        assertEquals("Obs1", results[0].name)
    }

    @Test
    fun observeByDatabase_emitsResults() = runTest {
        dao.insert(ObservableEntity(databaseId = "db-1", name = "Obs1", query = "Q", isActive = true, lastUpdated = 1000L))

        val results = dao.observeByDatabase("db-1").first()
        assertEquals(1, results.size)
        assertTrue(results[0].isActive)
    }

    @Test
    fun update_modifiesIsActive() = runTest {
        val id = dao.insert(ObservableEntity(databaseId = "db-1", name = "Obs", query = "Q", isActive = false, lastUpdated = null))
        val inserted = dao.getByDatabase("db-1").first()

        dao.update(inserted.copy(isActive = true, lastUpdated = 2000L))

        val updated = dao.getByDatabase("db-1").first()
        assertTrue(updated.isActive)
        assertEquals(2000L, updated.lastUpdated)
    }

    @Test
    fun deleteById_removesObservable() = runTest {
        val id = dao.insert(ObservableEntity(databaseId = "db-1", name = "ToDelete", query = "Q", isActive = false, lastUpdated = null))

        dao.deleteById(id)

        assertEquals(0, dao.getByDatabase("db-1").size)
    }

    @Test
    fun cascadeDelete_removesObservablesWhenParentDeleted() = runTest {
        dao.insert(ObservableEntity(databaseId = "db-1", name = "Obs", query = "Q", isActive = false, lastUpdated = null))

        db.databaseConfigDao().deleteByDatabaseId("db-1")

        assertEquals(0, dao.getByDatabase("db-1").size)
    }

    private fun buildParent(databaseId: String) = DatabaseConfigEntity(
        name = "Parent",
        databaseId = databaseId,
        mode = AuthMode.SERVER.value,
        allowUntrustedCerts = false,
        isBluetoothLeEnabled = true,
        isLanEnabled = true,
        isAwdlEnabled = false,
        isCloudSyncEnabled = true,
        token = "", authUrl = "", websocketUrl = "", httpApiUrl = "", httpApiKey = "",
        secretKey = "", logLevel = "info"
    )
}
