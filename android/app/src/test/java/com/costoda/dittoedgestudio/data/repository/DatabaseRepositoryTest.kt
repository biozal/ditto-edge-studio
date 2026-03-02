package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.DatabaseConfigDao
import com.costoda.dittoedgestudio.data.db.entity.DatabaseConfigEntity
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.impl.annotations.MockK
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
