package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.repository.DatabaseMetricsRepository
import com.costoda.dittoedgestudio.domain.model.CollectionPayloadInfo
import com.costoda.dittoedgestudio.domain.model.DatabaseMetrics
import com.costoda.dittoedgestudio.domain.model.StorageCategory
import com.costoda.dittoedgestudio.domain.model.StorageCategoryKey
import com.ditto.kotlin.Ditto
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.every
import io.mockk.impl.annotations.MockK
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DiskUsageViewModelTest {

    @MockK
    private lateinit var dittoManager: DittoManager

    @MockK
    private lateinit var repo: DatabaseMetricsRepository

    @MockK
    private lateinit var ditto: Ditto

    private val testDispatcher = StandardTestDispatcher()

    private val testMetrics = DatabaseMetrics(
        capturedAt = 1_700_000_000_000L,
        storage = listOf(
            StorageCategory(StorageCategoryKey.STORE, 1024L * 1024),
            StorageCategory(StorageCategoryKey.REPLICATION, 512L * 1024),
            StorageCategory(StorageCategoryKey.ATTACHMENTS, 0L),
            StorageCategory(StorageCategoryKey.AUTH, 0L),
            StorageCategory(StorageCategoryKey.WAL_SHM, 0L),
            StorageCategory(StorageCategoryKey.LOGS, 0L),
            StorageCategory(StorageCategoryKey.OTHER, 0L),
        ),
        collections = listOf(
            CollectionPayloadInfo("tasks", 163, 12_700L),
            CollectionPayloadInfo("__presence", 33, 16_300L),
        ),
    )

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        Dispatchers.setMain(testDispatcher)
        every { dittoManager.currentInstance() } returns ditto
        coEvery { repo.snapshot(any()) } returns testMetrics
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        clearAllMocks()
    }

    @Test
    fun `init triggers refresh and sets metrics`() = runTest {
        val vm = DiskUsageViewModel(dittoManager, repo)
        testDispatcher.scheduler.advanceUntilIdle()

        assertNotNull(vm.metrics.value)
        assertEquals(testMetrics.totalStorageBytes, vm.metrics.value?.totalStorageBytes)
    }

    @Test
    fun `init populates lastUpdatedAt with capturedAt`() = runTest {
        val vm = DiskUsageViewModel(dittoManager, repo)
        testDispatcher.scheduler.advanceUntilIdle()

        assertEquals(testMetrics.capturedAt, vm.lastUpdatedAt.value)
    }

    @Test
    fun `refresh ends with isLoading false on success`() = runTest {
        val vm = DiskUsageViewModel(dittoManager, repo)
        testDispatcher.scheduler.advanceUntilIdle()

        vm.refresh()
        testDispatcher.scheduler.advanceUntilIdle()

        assertFalse(vm.isLoading.value)
    }

    @Test
    fun `refresh ends with isLoading false even on repo failure`() = runTest {
        coEvery { repo.snapshot(any()) } throws RuntimeException("snapshot failed")
        val vm = DiskUsageViewModel(dittoManager, repo)
        testDispatcher.scheduler.advanceUntilIdle()

        assertNull(vm.metrics.value)
        assertNull(vm.lastUpdatedAt.value)
        assertFalse(vm.isLoading.value)
    }

    @Test
    fun `refresh with null ditto instance leaves previous snapshot intact`() = runTest {
        val vm = DiskUsageViewModel(dittoManager, repo)
        testDispatcher.scheduler.advanceUntilIdle()
        val firstSnapshot = vm.metrics.value
        assertNotNull(firstSnapshot)

        every { dittoManager.currentInstance() } returns null
        vm.refresh()
        testDispatcher.scheduler.advanceUntilIdle()

        // Previous snapshot remains in place; isLoading flipped back to false; no crash.
        assertEquals(firstSnapshot, vm.metrics.value)
        assertFalse(vm.isLoading.value)
    }

    @Test
    fun `metrics is null before init coroutine drains`() = runTest {
        val vm = DiskUsageViewModel(dittoManager, repo)
        // Intentionally do not advance the dispatcher.
        assertNull(vm.metrics.value)
        assertNull(vm.lastUpdatedAt.value)
    }
}
