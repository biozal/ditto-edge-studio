package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.impl.annotations.MockK
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DatabaseListViewModelTest {

    @MockK
    private lateinit var repository: DatabaseRepository
    private lateinit var viewModel: DatabaseListViewModel
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

    @Test
    fun `uiState emits Loading then Empty when repository returns empty list`() = runTest {
        coEvery { repository.observeAll() } returns flowOf(emptyList())

        viewModel = DatabaseListViewModel(repository)

        // Subscribe to trigger WhileSubscribed collection
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect {}
        }
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.uiState.value is DatabaseListUiState.Empty)
    }

    @Test
    fun `uiState emits Databases when repository returns items`() = runTest {
        val databases = listOf(
            DittoDatabase(id = 1L, name = "DB1", databaseId = "db-1"),
            DittoDatabase(id = 2L, name = "DB2", databaseId = "db-2"),
        )
        coEvery { repository.observeAll() } returns flowOf(databases)

        viewModel = DatabaseListViewModel(repository)

        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect {}
        }
        testDispatcher.scheduler.advanceUntilIdle()

        val state = viewModel.uiState.value
        assertTrue(state is DatabaseListUiState.Databases)
        assertEquals(2, (state as DatabaseListUiState.Databases).items.size)
        assertEquals("DB1", state.items[0].name)
    }

    @Test
    fun `deleteDatabase calls repository delete with correct id`() = runTest {
        coEvery { repository.observeAll() } returns flowOf(emptyList())
        coEvery { repository.delete(any()) } returns Unit

        viewModel = DatabaseListViewModel(repository)
        viewModel.deleteDatabase(42L)
        testDispatcher.scheduler.advanceUntilIdle()

        coVerify(exactly = 1) { repository.delete(42L) }
    }

    @Test
    fun `uiState updates after delete`() = runTest {
        val db = DittoDatabase(id = 1L, name = "ToDelete", databaseId = "del-db")
        val flowSource = MutableStateFlow(listOf(db))
        coEvery { repository.observeAll() } returns flowSource
        coEvery { repository.delete(1L) } coAnswers { flowSource.value = emptyList() }

        viewModel = DatabaseListViewModel(repository)

        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) {
            viewModel.uiState.collect {}
        }
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.uiState.value is DatabaseListUiState.Databases)

        viewModel.deleteDatabase(1L)
        testDispatcher.scheduler.advanceUntilIdle()

        assertTrue(viewModel.uiState.value is DatabaseListUiState.Empty)
    }
}
