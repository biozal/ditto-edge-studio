package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.data.db.entity.FavoriteEntity
import com.costoda.dittoedgestudio.domain.model.AuthMode
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class FavoriteDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: FavoriteDao

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
        dao = db.favoriteDao()
        runTest { db.databaseConfigDao().insert(buildParent("db-1")) }
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun insertAndGetByDatabase() = runTest {
        dao.insert(FavoriteEntity(databaseId = "db-1", query = "SELECT *", createdDate = 1000L))

        val results = dao.getByDatabase("db-1")
        assertEquals(1, results.size)
        assertEquals("SELECT *", results[0].query)
    }

    @Test
    fun findDuplicate_returnsExistingEntry() = runTest {
        dao.insert(FavoriteEntity(databaseId = "db-1", query = "SELECT *", createdDate = 1000L))

        val duplicate = dao.findDuplicate("db-1", "SELECT *")
        assertNotNull(duplicate)
    }

    @Test
    fun findDuplicate_returnsNull_whenNoneExists() = runTest {
        val duplicate = dao.findDuplicate("db-1", "SELECT _id")
        assertNull(duplicate)
    }

    @Test
    fun observeByDatabase_emitsResults() = runTest {
        dao.insert(FavoriteEntity(databaseId = "db-1", query = "SELECT *", createdDate = 1000L))

        val results = dao.observeByDatabase("db-1").first()
        assertEquals(1, results.size)
    }

    @Test
    fun deleteById_removesFavorite() = runTest {
        val id = dao.insert(FavoriteEntity(databaseId = "db-1", query = "SELECT *", createdDate = 1000L))

        dao.deleteById(id)

        assertEquals(0, dao.getByDatabase("db-1").size)
    }

    @Test
    fun cascadeDelete_removesFavoritesWhenParentDeleted() = runTest {
        dao.insert(FavoriteEntity(databaseId = "db-1", query = "Q", createdDate = 1000L))

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
