package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.ObservableDao
import com.costoda.dittoedgestudio.data.db.entity.ObservableEntity
import com.costoda.dittoedgestudio.domain.model.DittoObservable
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

class ObservableRepositoryTest {

    @MockK
    private lateinit var dao: ObservableDao
    private lateinit var repository: ObservableRepositoryImpl

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        repository = ObservableRepositoryImpl(dao)
    }

    @After
    fun tearDown() = clearAllMocks()

    @Test
    fun `observeObservables emits mapped domain models`() = runTest {
        val entity = ObservableEntity(id = 1L, databaseId = "db1", name = "Obs", query = "SELECT *", isActive = false, lastUpdated = null)
        coEvery { dao.observeByDatabase("db1") } returns flowOf(listOf(entity))

        val result = repository.observeObservables("db1").first()

        assertEquals(1, result.size)
        assertEquals("Obs", result[0].name)
        assertEquals("SELECT *", result[0].query)
    }

    @Test
    fun `loadObservables returns empty list`() = runTest {
        coEvery { dao.getByDatabase("db1") } returns emptyList()

        val result = repository.loadObservables("db1")

        assertEquals(emptyList<DittoObservable>(), result)
    }

    @Test
    fun `saveObservable delegates to dao insert`() = runTest {
        val obs = DittoObservable(id = 0L, databaseId = "db1", name = "Obs", query = "Q")
        coEvery { dao.insert(any()) } returns 9L

        val id = repository.saveObservable(obs)

        assertEquals(9L, id)
        coVerify(exactly = 1) { dao.insert(any()) }
    }

    @Test
    fun `updateObservable delegates to dao update`() = runTest {
        val obs = DittoObservable(id = 2L, databaseId = "db1", name = "Obs", query = "Q", isActive = true)
        coEvery { dao.update(any()) } returns Unit

        repository.updateObservable(obs)

        coVerify(exactly = 1) { dao.update(any()) }
    }

    @Test
    fun `removeObservable delegates to dao`() = runTest {
        coEvery { dao.deleteById(3L) } returns Unit

        repository.removeObservable(3L)

        coVerify(exactly = 1) { dao.deleteById(3L) }
    }

    @Test
    fun `removeAllObservables delegates to dao`() = runTest {
        coEvery { dao.deleteByDatabaseId("db1") } returns Unit

        repository.removeAllObservables("db1")

        coVerify(exactly = 1) { dao.deleteByDatabaseId("db1") }
    }
}
