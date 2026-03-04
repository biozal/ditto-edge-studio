package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.data.db.entity.SubscriptionEntity
import com.costoda.dittoedgestudio.domain.model.AuthMode
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class SubscriptionDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: SubscriptionDao

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
        dao = db.subscriptionDao()
        // Insert parent row required for FK
        runTest { db.databaseConfigDao().insert(buildParent("db-1")) }
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun insertAndGetByDatabase() = runTest {
        dao.insert(SubscriptionEntity(databaseId = "db-1", name = "Sub1", query = "SELECT *"))

        val results = dao.getByDatabase("db-1")
        assertEquals(1, results.size)
        assertEquals("Sub1", results[0].name)
    }

    @Test
    fun observeByDatabase_emitsUpdates() = runTest {
        dao.insert(SubscriptionEntity(databaseId = "db-1", name = "Sub1", query = "SELECT *"))

        val results = dao.observeByDatabase("db-1").first()
        assertEquals(1, results.size)
    }

    @Test
    fun deleteById_removesSubscription() = runTest {
        val id = dao.insert(SubscriptionEntity(databaseId = "db-1", name = "ToDelete", query = "Q"))

        dao.deleteById(id)

        assertEquals(0, dao.getByDatabase("db-1").size)
    }

    @Test
    fun cascadeDelete_removesSubscriptionsWhenParentDeleted() = runTest {
        dao.insert(SubscriptionEntity(databaseId = "db-1", name = "Sub", query = "Q"))

        db.databaseConfigDao().deleteByDatabaseId("db-1")

        assertEquals(0, dao.getByDatabase("db-1").size)
    }

    @Test
    fun deleteByDatabaseId_removesAllForDatabase() = runTest {
        dao.insert(SubscriptionEntity(databaseId = "db-1", name = "Sub1", query = "Q1"))
        dao.insert(SubscriptionEntity(databaseId = "db-1", name = "Sub2", query = "Q2"))

        dao.deleteByDatabaseId("db-1")

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
