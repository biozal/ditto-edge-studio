package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.db.dao.SubscriptionDao
import com.costoda.dittoedgestudio.data.db.entity.SubscriptionEntity
import com.costoda.dittoedgestudio.domain.model.DittoSubscription
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

class SubscriptionsRepositoryTest {

    @MockK
    private lateinit var dao: SubscriptionDao
    private lateinit var repository: SubscriptionsRepositoryImpl

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        repository = SubscriptionsRepositoryImpl(dao)
    }

    @After
    fun tearDown() = clearAllMocks()

    @Test
    fun `observeSubscriptions emits mapped domain models`() = runTest {
        val entity = SubscriptionEntity(id = 1L, databaseId = "db1", name = "Sub", query = "SELECT *")
        coEvery { dao.observeByDatabase("db1") } returns flowOf(listOf(entity))

        val result = repository.observeSubscriptions("db1").first()

        assertEquals(1, result.size)
        assertEquals("Sub", result[0].name)
        assertEquals("SELECT *", result[0].query)
    }

    @Test
    fun `loadSubscriptions returns empty list`() = runTest {
        coEvery { dao.getByDatabase("db1") } returns emptyList()

        val result = repository.loadSubscriptions("db1")

        assertEquals(emptyList<DittoSubscription>(), result)
    }

    @Test
    fun `saveSubscription delegates to dao insert`() = runTest {
        val sub = DittoSubscription(id = 0L, databaseId = "db1", name = "S", query = "Q")
        coEvery { dao.insert(any()) } returns 10L

        val id = repository.saveSubscription(sub)

        assertEquals(10L, id)
        coVerify(exactly = 1) { dao.insert(any()) }
    }

    @Test
    fun `removeSubscription calls dao deleteById`() = runTest {
        coEvery { dao.deleteById(5L) } returns Unit

        repository.removeSubscription(5L)

        coVerify(exactly = 1) { dao.deleteById(5L) }
    }

    @Test
    fun `removeAllSubscriptions calls dao deleteByDatabaseId`() = runTest {
        coEvery { dao.deleteByDatabaseId("db1") } returns Unit

        repository.removeAllSubscriptions("db1")

        coVerify(exactly = 1) { dao.deleteByDatabaseId("db1") }
    }
}
