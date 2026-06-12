package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.data.repository.HistoryRepository
import com.costoda.dittoedgestudio.data.repository.QueryExecutionService
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.data.session.QueryWorkbenchState
import com.costoda.dittoedgestudio.domain.model.QueryResult
import androidx.lifecycle.viewModelScope
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.take
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

/**
 * Unit tests for [QueryEditorViewModel].
 *
 * Primary purpose (Task 4.3e): verify the draft-survival mechanism — two
 * [QueryEditorViewModel]s sharing the same session-scoped [QueryWorkbenchState] must observe
 * each other's writes, so the user's editor draft, results, pagination cursor, and inspector
 * tab selection persist across rail-section switches that destroy and recreate the VM. This
 * mirrors the session-sharing tests in [MainStudioViewModelTest].
 */
@OptIn(ExperimentalCoroutinesApi::class)
class QueryEditorViewModelTest {

    private val testDispatcher = StandardTestDispatcher()

    private lateinit var queryExecutionService: QueryExecutionService
    private lateinit var historyRepository: HistoryRepository
    private lateinit var favoritesRepository: FavoritesRepository
    private lateinit var metricsRepository: QueryMetricsRepository
    private lateinit var appMetricsRepository: AppMetricsRepository

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        queryExecutionService = mockk(relaxed = true)
        historyRepository = mockk(relaxed = true)
        favoritesRepository = mockk(relaxed = true)
        metricsRepository = mockk(relaxed = true)
        appMetricsRepository = mockk(relaxed = true)

        // Empty history/favorites by default — tests that need data override per-case.
        coEvery { historyRepository.observeHistory(any()) } returns flowOf(emptyList())
        coEvery { favoritesRepository.observeFavorites(any()) } returns flowOf(emptyList())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createVm(workbench: QueryWorkbenchState): QueryEditorViewModel =
        QueryEditorViewModel(
            databaseId = "test-db-id",
            workbench = workbench,
            queryExecutionService = queryExecutionService,
            historyRepository = historyRepository,
            favoritesRepository = favoritesRepository,
            metricsRepository = metricsRepository,
            appMetricsRepository = appMetricsRepository,
        )

    // ── Draft survival: shared session-scoped state across VM instances ───────

    /**
     * Core draft-survival test: VM A writes a draft, VM B (a fresh instance constructed from
     * the same [QueryWorkbenchState]) sees it. This is exactly what happens when the user
     * navigates Observers ⇄ Query — the QueryEditorViewModel is destroyed and recreated, but
     * the workbench (living on the StudioSession) is reused.
     */
    @Test
    fun `query draft written via VM A is visible via VM B sharing the same workbench`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vmA = createVm(sharedWorkbench)
        val vmB = createVm(sharedWorkbench)

        vmA.onQueryTextChange("SELECT * FROM movies WHERE rating > 8")
        advanceUntilIdle()

        assertEquals("SELECT * FROM movies WHERE rating > 8", vmB.queryText.value)
    }

    @Test
    fun `pagination cursor written via VM A is visible via VM B sharing the same workbench`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply {
            // Pre-populate a queryResult so setPage has something to coerce against.
            queryResult.value = QueryResult(
                documents = (1..200).map { mapOf("id" to it) },
                totalCount = 200,
                executionTimeMs = 5L,
                explainPlan = null,
            )
        }
        val vmA = createVm(sharedWorkbench)
        val vmB = createVm(sharedWorkbench)

        vmA.setPage(3)
        advanceUntilIdle()

        assertEquals(3, vmB.currentPage.value)
    }

    @Test
    fun `inspector tab selection written via VM A is visible via VM B sharing the same workbench`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vmA = createVm(sharedWorkbench)
        val vmB = createVm(sharedWorkbench)

        vmA.setInspectorTab(QueryInspectorTab.FAVORITES)
        advanceUntilIdle()

        assertEquals(QueryInspectorTab.FAVORITES, vmB.selectedInspectorTab.value)
    }

    @Test
    fun `selected document written via VM A is visible via VM B sharing the same workbench`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vmA = createVm(sharedWorkbench)
        val vmB = createVm(sharedWorkbench)

        val doc = mapOf("id" to 42, "name" to "test")
        vmA.selectDocument(doc)
        advanceUntilIdle()

        assertEquals(doc, vmB.selectedDocument.value)
        // selectDocument should also switch the inspector tab to JSON — also session-scoped.
        assertEquals(QueryInspectorTab.JSON, vmB.selectedInspectorTab.value)
    }

    @Test
    fun `query results survive recreation by living on the workbench`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(
            documents = listOf(mapOf("k" to "v")),
            totalCount = 1,
            executionTimeMs = 12L,
            explainPlan = null,
        )
        coEvery { queryExecutionService.execute(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 7L

        val vmA = createVm(sharedWorkbench)
        vmA.onQueryTextChange("SELECT * FROM c")
        vmA.executeQuery()
        advanceUntilIdle()

        // Simulate the rail-switch: a fresh VM with the same workbench should see the result.
        val vmB = createVm(sharedWorkbench)
        assertEquals(result, vmB.queryResult.value)
    }

    @Test
    fun `independent workbench instances are isolated`() = runTest {
        val workbenchA = QueryWorkbenchState()
        val workbenchB = QueryWorkbenchState()
        val vmA = createVm(workbenchA)
        val vmB = createVm(workbenchB)

        vmA.onQueryTextChange("SELECT * FROM a")
        advanceUntilIdle()

        // Separate workbench instances must not leak state into each other.
        assertEquals("", vmB.queryText.value)
    }

    // ── isExecuting reset on cancellation ────────────────────────────────────

    /**
     * Regression test for the stuck-spinner defect: if the user rail-switches mid-query,
     * viewModelScope is cancelled and the `finally` block in [QueryEditorViewModel.executeQuery]
     * must reset [QueryWorkbenchState.isExecuting] to false, so the next VM instance (sharing
     * the same session-scoped workbench) does not render a permanently stuck spinner.
     *
     * This test exercises the REAL [QueryEditorViewModel.executeQuery] code path:
     * - The [QueryExecutionService] mock suspends forever via [awaitCancellation], keeping the
     *   VM's coroutine alive at the suspension point inside executeQuery.
     * - Cancelling [viewModelScope] (which is what Nav3 entry disposal does) must trigger the
     *   `finally` block in executeQuery, resetting isExecuting to false.
     *
     * If the `finally { workbench.isExecuting.value = false }` is removed from executeQuery,
     * this test will fail — proving it guards against regressions, unlike the previous version
     * that replicated the try/finally pattern independently of the production code.
     */
    @Test
    fun `isExecuting reset to false when viewModelScope is cancelled mid-query`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()

        // Make the service suspend indefinitely — simulates a long-running query in flight.
        coEvery { queryExecutionService.execute(any()) } coAnswers { awaitCancellation() }

        val viewModel = createVm(sharedWorkbench)
        viewModel.onQueryTextChange("SELECT * FROM movies")

        // Call the real executeQuery — it launches a coroutine on viewModelScope.
        viewModel.executeQuery()

        // Drive the dispatcher until the coroutine reaches the awaitCancellation() suspension
        // point inside queryExecutionService.execute(). At this point isExecuting must be true.
        advanceUntilIdle()
        assertEquals(
            "isExecuting must be true while the query is suspended",
            true,
            sharedWorkbench.isExecuting.value,
        )

        // Cancel viewModelScope — this is what Nav3 does when the entry is disposed.
        viewModel.viewModelScope.cancel()

        // Process cancellation so the finally block in executeQuery has a chance to run.
        advanceUntilIdle()

        assertFalse(
            "isExecuting must be reset to false after scope cancellation",
            sharedWorkbench.isExecuting.value,
        )
    }

    @Test
    fun `clearResults wipes session-scoped state and is visible to a sibling VM`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply {
            queryResult.value = QueryResult(
                documents = listOf(mapOf("a" to 1)),
                totalCount = 1,
                executionTimeMs = 1L,
                explainPlan = null,
            )
            selectedDocument.value = mapOf("a" to 1)
            currentPage.value = 2
            executionError.value = "stale error"
        }
        val vmA = createVm(sharedWorkbench)
        val vmB = createVm(sharedWorkbench)

        vmA.clearResults()
        advanceUntilIdle()

        assertNull(vmB.queryResult.value)
        assertNull(vmB.selectedDocument.value)
        assertNull(vmB.executionError.value)
        assertEquals(0, vmB.currentPage.value)
    }
}
