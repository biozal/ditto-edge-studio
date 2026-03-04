package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.FavoriteDao
import com.costoda.dittoedgestudio.data.db.entity.FavoriteEntity
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
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class FavoritesRepositoryTest {

    @MockK
    private lateinit var dao: FavoriteDao
    private lateinit var repository: FavoritesRepositoryImpl

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        repository = FavoritesRepositoryImpl(dao)
    }

    @After
    fun tearDown() = clearAllMocks()

    @Test
    fun `observeFavorites emits mapped favorites`() = runTest {
        val entity = FavoriteEntity(id = 1L, databaseId = "db1", query = "SELECT *", createdDate = 1000L)
        coEvery { dao.observeByDatabase("db1") } returns flowOf(listOf(entity))

        val result = repository.observeFavorites("db1").first()

        assertEquals(1, result.size)
        assertEquals("SELECT *", result[0].query)
    }

    @Test
    fun `saveFavorite inserts when no duplicate`() = runTest {
        coEvery { dao.findDuplicate("db1", "SELECT *") } returns null
        coEvery { dao.insert(any()) } returns 7L

        val id = repository.saveFavorite("db1", "SELECT *")

        assertEquals(7L, id)
        coVerify(exactly = 1) { dao.insert(any()) }
    }

    @Test
    fun `saveFavorite returns null when duplicate exists`() = runTest {
        val existing = FavoriteEntity(id = 3L, databaseId = "db1", query = "SELECT *", createdDate = 500L)
        coEvery { dao.findDuplicate("db1", "SELECT *") } returns existing

        val id = repository.saveFavorite("db1", "SELECT *")

        assertNull(id)
        coVerify(exactly = 0) { dao.insert(any()) }
    }

    @Test
    fun `removeFavorite delegates to dao`() = runTest {
        coEvery { dao.deleteById(2L) } returns Unit

        repository.removeFavorite(2L)

        coVerify(exactly = 1) { dao.deleteById(2L) }
    }

    @Test
    fun `removeAllFavorites delegates to dao`() = runTest {
        coEvery { dao.deleteByDatabaseId("db1") } returns Unit

        repository.removeAllFavorites("db1")

        coVerify(exactly = 1) { dao.deleteByDatabaseId("db1") }
    }
}
