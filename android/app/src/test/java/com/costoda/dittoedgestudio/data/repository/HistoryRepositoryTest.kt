package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.HistoryDao
import com.costoda.dittoedgestudio.data.db.entity.HistoryEntity
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.impl.annotations.MockK
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class HistoryRepositoryTest {

    @MockK
    private lateinit var dao: HistoryDao
    private lateinit var repository: HistoryRepositoryImpl

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        repository = HistoryRepositoryImpl(dao)
    }

    @After
    fun tearDown() = clearAllMocks()

    @Test
    fun `observeHistory emits mapped history items`() = runTest {
        val entity = HistoryEntity(id = 1L, databaseId = "db1", query = "SELECT *", createdDate = 1000L)
        coEvery { dao.observeByDatabase("db1") } returns flowOf(listOf(entity))

        val result = repository.observeHistory("db1").first()

        assertEquals(1, result.size)
        assertEquals("SELECT *", result[0].query)
        assertEquals(1000L, result[0].createdDate)
    }

    @Test
    fun `addToHistory inserts new entry when no duplicate`() = runTest {
        coEvery { dao.findDuplicate("db1", "SELECT *") } returns null
        coEvery { dao.countByDatabase("db1") } returns 0
        coEvery { dao.insert(any()) } returns 5L

        val id = repository.addToHistory("db1", "SELECT *")

        assertEquals(5L, id)
        coVerify(exactly = 1) { dao.insert(any()) }
    }

    @Test
    fun `addToHistory updates timestamp when duplicate exists`() = runTest {
        val existing = HistoryEntity(id = 3L, databaseId = "db1", query = "SELECT *", createdDate = 500L)
        coEvery { dao.findDuplicate("db1", "SELECT *") } returns existing
        coEvery { dao.insert(any()) } returns 3L

        repository.addToHistory("db1", "SELECT *")

        coVerify(exactly = 1) { dao.insert(match { it.id == 3L && it.createdDate > 500L }) }
    }

    @Test
    fun `addToHistory trims oldest when at max capacity`() = runTest {
        coEvery { dao.findDuplicate("db1", any()) } returns null
        coEvery { dao.countByDatabase("db1") } returns 1000
        coEvery { dao.deleteOldest("db1", 1) } returns Unit
        coEvery { dao.insert(any()) } returns 1001L

        repository.addToHistory("db1", "SELECT new")

        coVerify(exactly = 1) { dao.deleteOldest("db1", 1) }
    }

    @Test
    fun `removeHistoryItem delegates to dao`() = runTest {
        coEvery { dao.deleteById(4L) } returns Unit

        repository.removeHistoryItem(4L)

        coVerify(exactly = 1) { dao.deleteById(4L) }
    }

    @Test
    fun `clearHistory delegates to dao`() = runTest {
        coEvery { dao.deleteByDatabaseId("db1") } returns Unit

        repository.clearHistory("db1")

        coVerify(exactly = 1) { dao.deleteByDatabaseId("db1") }
    }
}
