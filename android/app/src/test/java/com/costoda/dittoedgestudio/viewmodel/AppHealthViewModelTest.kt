package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.DatabaseOpenResult
import com.costoda.dittoedgestudio.data.db.DatabaseOpener
import com.costoda.dittoedgestudio.data.db.DatabaseRecovery
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.every
import io.mockk.impl.annotations.MockK
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppHealthViewModelTest {

    @MockK
    private lateinit var opener: DatabaseOpener

    @MockK
    private lateinit var recovery: DatabaseRecovery

    private val testDispatcher = StandardTestDispatcher()

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        Dispatchers.setMain(testDispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        clearAllMocks()
    }

    private fun newViewModel(): AppHealthViewModel =
        AppHealthViewModel(opener, recovery, ioDispatcher = testDispatcher)

    @Test
    fun `init probe transitions to Healthy on Ok`() = runTest {
        val db = mockk<AppDatabase>()
        every { opener.openAndProbe() } returns DatabaseOpenResult.Ok(db)

        val viewModel = newViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.state.value is DbHealthState.Healthy)
    }

    @Test
    fun `init probe transitions to KeyFailure on KeyFailure result`() = runTest {
        val cause = IllegalStateException("file is not a database")
        every { opener.openAndProbe() } returns DatabaseOpenResult.KeyFailure(
            throwable = cause,
            errorSummary = "IllegalStateException: file is not a database",
        )

        val viewModel = newViewModel()
        testDispatcher.scheduler.advanceUntilIdle()

        val state = viewModel.state.value
        assertTrue("Expected KeyFailure, got $state", state is DbHealthState.KeyFailure)
        state as DbHealthState.KeyFailure
        assertEquals("IllegalStateException: file is not a database", state.errorSummary)
        assertEquals(cause, state.throwable)
    }

    @Test
    fun `recover transitions KeyFailure to Healthy when reset and reprobe succeed`() = runTest {
        val cause = IllegalStateException("file is not a database")
        val failure = DatabaseOpenResult.KeyFailure(
            throwable = cause,
            errorSummary = "IllegalStateException: file is not a database",
        )
        val db = mockk<AppDatabase>()
        // First probe: failure. After recover(), next probe: ok.
        every { opener.openAndProbe() } returnsMany listOf(
            failure,
            DatabaseOpenResult.Ok(db),
        )
        every { recovery.reset() } returns true

        val viewModel = newViewModel()
        testDispatcher.scheduler.advanceUntilIdle()
        assertTrue(viewModel.state.value is DbHealthState.KeyFailure)

        var completion: Boolean? = null
        viewModel.recover { success -> completion = success }
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.state.value is DbHealthState.Healthy)
        assertEquals(true, completion)
        verify(exactly = 1) { recovery.reset() }
    }

    @Test
    fun `recover leaves state in KeyFailure when reprobe still fails`() = runTest {
        val cause = IllegalStateException("file is not a database")
        val failure = DatabaseOpenResult.KeyFailure(
            throwable = cause,
            errorSummary = "IllegalStateException: file is not a database",
        )
        every { opener.openAndProbe() } returns failure
        every { recovery.reset() } returns true

        val viewModel = newViewModel()
        testDispatcher.scheduler.advanceUntilIdle()
        assertTrue(viewModel.state.value is DbHealthState.KeyFailure)

        var completion: Boolean? = null
        viewModel.recover { success -> completion = success }
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.state.value is DbHealthState.KeyFailure)
        assertEquals(false, completion)
    }
}
