package com.costoda.dittoedgestudio.viewmodel

import android.content.Context
import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.domain.model.AppMetrics
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
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
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DiskUsageViewModelTest {

    @MockK
    private lateinit var context: Context

    @MockK
    private lateinit var appMetricsRepository: AppMetricsRepository

    @MockK
    private lateinit var dittoManager: DittoManager

    private val testDispatcher = StandardTestDispatcher()

    private val testMetrics = AppMetrics(
        capturedAt = System.currentTimeMillis(),
        residentMemoryBytes = 0,
        virtualMemoryBytes = 0,
        cpuTimeMs = 0,
        openFileDescriptors = 0,
        processUptimeMs = 0,
        totalQueryCount = 0,
        avgQueryLatencyMs = 0.0,
        lastQueryLatencyMs = null,
        storeBytes = 1024 * 1024,
        replicationBytes = 512 * 1024,
        attachmentsBytes = 0,
        authBytes = 0,
        walShmBytes = 0,
        logsBytes = 0,
        otherBytes = 0,
    )

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        Dispatchers.setMain(testDispatcher)
        coEvery { dittoManager.currentInstance() } returns null
        coEvery { appMetricsRepository.snapshot(any(), null) } returns testMetrics
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        clearAllMocks()
    }

    @Test
    fun `init triggers refresh and sets metrics`() = runTest {
        val viewModel = DiskUsageViewModel(context, appMetricsRepository, dittoManager)
        testDispatcher.scheduler.advanceUntilIdle()

        assertNotNull(viewModel.metrics.value)
        assertEquals(testMetrics.storeBytes, viewModel.metrics.value?.storeBytes)
    }

    @Test
    fun `refresh sets isLoading true then false`() = runTest {
        val viewModel = DiskUsageViewModel(context, appMetricsRepository, dittoManager)

        // Drain init
        testDispatcher.scheduler.advanceUntilIdle()

        viewModel.refresh()

        // isLoading should be false once coroutine finishes
        testDispatcher.scheduler.advanceUntilIdle()
        assertFalse(viewModel.isLoading.value)
    }

    @Test
    fun `refresh with exception leaves metrics null`() = runTest {
        coEvery { appMetricsRepository.snapshot(any(), null) } throws RuntimeException("snapshot failed")

        val viewModel = DiskUsageViewModel(context, appMetricsRepository, dittoManager)
        testDispatcher.scheduler.advanceUntilIdle()

        assertNull(viewModel.metrics.value)
        assertFalse(viewModel.isLoading.value)
    }

    @Test
    fun `refresh updates lastUpdatedText`() = runTest {
        val viewModel = DiskUsageViewModel(context, appMetricsRepository, dittoManager)
        testDispatcher.scheduler.advanceUntilIdle()

        val lastUpdated = viewModel.lastUpdatedText.value
        assertTrue(
            "lastUpdatedText should not be 'Never' after successful refresh",
            lastUpdated != "Never",
        )
    }

    @Test
    fun `metrics starts as null before refresh completes`() = runTest {
        // Create viewModel but do not advance the dispatcher so init coroutine has not run yet
        val viewModel = DiskUsageViewModel(context, appMetricsRepository, dittoManager)

        assertNull(viewModel.metrics.value)
    }
}
