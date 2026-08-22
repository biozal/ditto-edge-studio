package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.DatabaseConfigDao
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.CollectionSyncScope
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.StartupSetting
import com.costoda.dittoedgestudio.domain.model.StartupSettingType
import com.costoda.dittoedgestudio.domain.model.SyncScope
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.impl.annotations.MockK
import io.mockk.slot
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class DatabaseRepositoryTest {

    @MockK
    private lateinit var dao: DatabaseConfigDao
    private lateinit var repository: DatabaseRepositoryImpl

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        repository = DatabaseRepositoryImpl(dao)
    }

    @After
    fun tearDown() = clearAllMocks()

    @Test
    fun `observeAll emits mapped domain models`() = runTest {
        val entity = buildEntity(id = 1L, name = "TestDB", databaseId = "db-1")
        coEvery { dao.observeAll() } returns flowOf(listOf(entity))

        val result = repository.observeAll().first()

        assertEquals(1, result.size)
        assertEquals("TestDB", result[0].name)
        assertEquals("db-1", result[0].databaseId)
    }

    @Test
    fun `getAll returns empty list when no databases`() = runTest {
        coEvery { dao.getAll() } returns emptyList()

        val result = repository.getAll()

        assertEquals(emptyList<DittoDatabase>(), result)
    }

    @Test
    fun `getByDatabaseId returns null when not found`() = runTest {
        coEvery { dao.getByDatabaseId("missing") } returns null

        val result = repository.getByDatabaseId("missing")

        assertNull(result)
    }

    @Test
    fun `save inserts when id is zero`() = runTest {
        val database = DittoDatabase(id = 0L, name = "New", databaseId = "new-db")
        coEvery { dao.insert(any()) } returns 42L

        val id = repository.save(database)

        assertEquals(42L, id)
        coVerify(exactly = 1) { dao.insert(any()) }
    }

    @Test
    fun `save updates when id is non-zero`() = runTest {
        val database = DittoDatabase(id = 5L, name = "Existing", databaseId = "ex-db")
        coEvery { dao.update(any()) } returns Unit

        val id = repository.save(database)

        assertEquals(5L, id)
        coVerify(exactly = 1) { dao.update(any()) }
    }

    @Test
    fun `delete calls dao deleteById`() = runTest {
        coEvery { dao.deleteById(3L) } returns Unit

        repository.delete(3L)

        coVerify(exactly = 1) { dao.deleteById(3L) }
    }

    @Test
    fun `deleteByDatabaseId delegates to dao`() = runTest {
        coEvery { dao.deleteByDatabaseId("db-1") } returns Unit

        repository.deleteByDatabaseId("db-1")

        coVerify(exactly = 1) { dao.deleteByDatabaseId("db-1") }
    }

    @Test
    fun `advanced configuration round-trips through the entity mappers`() = runTest {
        val scopes = listOf(
            CollectionSyncScope(collection = "orders", scope = SyncScope.LocalPeerOnly),
        )
        val settings = listOf(
            StartupSetting(
                parameter = "sqlite3_synchronous",
                type = StartupSettingType.String,
                value = "FULL",
                isAcknowledged = true,
            ),
        )
        val database = DittoDatabase(
            id = 7L,
            name = "Adv",
            databaseId = "adv-db",
            collectionSyncScopes = scopes,
            startupSettings = settings,
        )
        val captured = slot<DatabaseConfigEntity>()
        coEvery { dao.update(capture(captured)) } returns Unit
        coEvery { dao.getById(7L) } answers { captured.captured }

        repository.save(database)
        val result = repository.getById(7L)

        assertEquals(scopes, result?.collectionSyncScopes)
        assertEquals(settings, result?.startupSettings)
        assertEquals(false, result?.hasCorruptSyncScopes)
    }

    @Test
    fun `unreadable stored scopes mark the config corrupt and decode as empty`() = runTest {
        val entity = buildEntity(id = 8L, name = "Corrupt", databaseId = "corrupt-db")
            .copy(collectionSyncScopes = "{not valid json")
        coEvery { dao.getById(8L) } returns entity

        val result = repository.getById(8L)

        assertEquals(emptyList<CollectionSyncScope>(), result?.collectionSyncScopes)
        assertEquals(true, result?.hasCorruptSyncScopes)
    }

    @Test
    fun `unreadable stored settings decode as empty without blocking the config`() = runTest {
        val entity = buildEntity(id = 9L, name = "BadSettings", databaseId = "bad-settings-db")
            .copy(startupSettings = "{not valid json")
        coEvery { dao.getById(9L) } returns entity

        val result = repository.getById(9L)

        assertEquals(emptyList<StartupSetting>(), result?.startupSettings)
        assertEquals(false, result?.hasCorruptSyncScopes)
    }

    private fun buildEntity(id: Long, name: String, databaseId: String) = DatabaseConfigEntity(
        id = id,
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
        logLevel = "info"
    )
}
