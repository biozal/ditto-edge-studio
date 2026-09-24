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
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

/**
 * Guards the duplicate-`databaseId` path in [DatabaseRepositoryImpl.save].
 *
 * `databaseId` carries a unique index and is the parent key that `subscriptions`,
 * `observables`, `favorites` and `history` all reference with `ON DELETE CASCADE`. Saving
 * an unregistered-looking config (`id == 0`) whose `databaseId` already existed used to go
 * through `@Insert(onConflict = REPLACE)`, and SQLite REPLACE *deletes* the conflicting
 * parent row — cascading every one of those child rows away, silently, while the QR scanner
 * reported success.
 *
 * These tests assert the contract that makes that impossible: a duplicate adopts the
 * existing row id and goes to UPDATE, and `insert` is never reached. They drive
 * `repository.save(...)` — the same entry point `QrScannerViewModel`, `DatabaseEditorViewModel`,
 * `StudioSession` and `LoggingScreen` all call — not a parallel helper.
 */
class DatabaseRepositoryImplTest {

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

    private fun database(id: Long = 0L, databaseId: String = "abc", name: String = "Prod") =
        DittoDatabase(
            id = id,
            name = name,
            databaseId = databaseId,
            token = "token",
            authUrl = "",
            websocketUrl = "",
            httpApiUrl = "",
            httpApiKey = "",
            mode = AuthMode.SERVER,
            allowUntrustedCerts = false,
            secretKey = "",
        )

    private fun entity(id: Long, databaseId: String = "abc", name: String = "Prod") =
        DatabaseConfigEntity(
            id = id,
            name = name,
            databaseId = databaseId,
            mode = AuthMode.SERVER.value,
            allowUntrustedCerts = false,
            isBluetoothLeEnabled = true,
            isLanEnabled = true,
            isAwdlEnabled = true,
            isCloudSyncEnabled = true,
            token = "token",
            authUrl = "",
            websocketUrl = "",
            httpApiUrl = "",
            httpApiKey = "",
            secretKey = "",
            logLevel = "info",
        )

    @Test
    fun `saving a duplicate databaseId updates the existing row instead of replacing it`() = runTest {
        // Arrange: "abc" is already registered as row 7 (with children hanging off it).
        coEvery { dao.getByDatabaseId("abc") } returns entity(id = 7L, name = "Prod")
        val updated = slot<DatabaseConfigEntity>()
        coEvery { dao.update(capture(updated)) } returns Unit

        // Act: a QR import of the same database arrives with no row id.
        val savedId = repository.save(database(id = 0L, databaseId = "abc", name = "Prod (shared)"))

        // Assert: the existing row is adopted and updated in place — nothing is deleted.
        assertEquals(7L, savedId)
        assertEquals(7L, updated.captured.id)
        assertEquals("Prod (shared)", updated.captured.name)
        coVerify(exactly = 0) { dao.insert(any()) }
    }

    @Test
    fun `saving a genuinely new databaseId still inserts`() = runTest {
        coEvery { dao.getByDatabaseId("new-id") } returns null
        coEvery { dao.insert(any()) } returns 42L

        val savedId = repository.save(database(id = 0L, databaseId = "new-id"))

        assertEquals(42L, savedId)
        coVerify(exactly = 1) { dao.insert(any()) }
        coVerify(exactly = 0) { dao.update(any()) }
    }

    @Test
    fun `saving an existing row keeps taking the update branch without a lookup`() = runTest {
        val updated = slot<DatabaseConfigEntity>()
        coEvery { dao.update(capture(updated)) } returns Unit

        val savedId = repository.save(database(id = 3L, databaseId = "abc"))

        assertEquals(3L, savedId)
        assertEquals(3L, updated.captured.id)
        coVerify(exactly = 0) { dao.insert(any()) }
        coVerify(exactly = 0) { dao.getByDatabaseId(any()) }
    }
}
