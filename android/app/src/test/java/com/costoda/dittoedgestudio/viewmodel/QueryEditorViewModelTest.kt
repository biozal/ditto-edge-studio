package com.costoda.dittoedgestudio.viewmodel

import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.data.repository.AttachmentService
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.data.repository.HistoryRepository
import com.costoda.dittoedgestudio.data.repository.QueryExecutionService
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.data.session.QueryWorkbenchState
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator
import com.costoda.dittoedgestudio.domain.model.QueryProfileTimes
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
import org.junit.Assert.assertTrue
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
    private lateinit var attachmentService: AttachmentService

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        queryExecutionService = mockk(relaxed = true)
        historyRepository = mockk(relaxed = true)
        favoritesRepository = mockk(relaxed = true)
        metricsRepository = mockk(relaxed = true)
        appMetricsRepository = mockk(relaxed = true)
        attachmentService = mockk(relaxed = true)

        // Empty history/favorites by default — tests that need data override per-case.
        coEvery { historyRepository.observeHistory(any()) } returns flowOf(emptyList())
        coEvery { favoritesRepository.observeFavorites(any()) } returns flowOf(emptyList())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun createVm(
        workbench: QueryWorkbenchState,
        appPreferences: com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway =
            FakeAppPreferences(initialMetricsEnabled = true),
    ): QueryEditorViewModel = QueryEditorViewModel(
        databaseId = "test-db-id",
        workbench = workbench,
        queryExecutionService = queryExecutionService,
        historyRepository = historyRepository,
        favoritesRepository = favoritesRepository,
        metricsRepository = metricsRepository,
        appMetricsRepository = appMetricsRepository,
        appPreferences = appPreferences,
        attachmentService = attachmentService,
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
            queryMetrics.value = staleMetrics()
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
        // The metrics record is wiped too — a stale capture must never sit next to
        // cleared (or the next query's) results in the inspector's Metrics tab.
        assertNull(vmB.queryMetrics.value)
        assertEquals(0, vmB.currentPage.value)
    }

    // ── execute-mode wiring ────────────────────────────────────────────────────

    @Test
    fun `setExecuteMode updates session-scoped flow visible across VMs`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vmA = createVm(sharedWorkbench)
        val vmB = createVm(sharedWorkbench)

        vmA.setExecuteMode("HTTP")
        advanceUntilIdle()

        assertEquals("HTTP", vmB.executeMode.value)
    }

    @Test
    fun `setCaptureProfilingData writes through to AppPreferences`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val sharedWorkbench = QueryWorkbenchState()
        val vm = createVm(sharedWorkbench, appPreferences = fakePrefs)
        // Subscribe so WhileSubscribed stateIn begins collecting from the gateway flow.
        val collectedValues = mutableListOf<Boolean>()
        val job = launch { vm.captureProfilingData.collect { collectedValues += it } }
        advanceUntilIdle()

        assertEquals(true, vm.captureProfilingData.value)
        vm.setCaptureProfilingData(false)
        advanceUntilIdle()
        assertEquals(false, fakePrefs.metricsEnabledValue)
        assertEquals(false, vm.captureProfilingData.value)
        job.cancel()
    }

    @Test
    fun `setCaptureQueryMetrics flips session-scoped toggle`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vm = createVm(sharedWorkbench)

        assertEquals(true, vm.captureQueryMetrics.value)
        vm.setCaptureQueryMetrics(false)
        advanceUntilIdle()
        assertEquals(false, vm.captureQueryMetrics.value)
    }

    // ── Capture query metrics toggle ─────────────────────────────────────────

    @Test
    fun `executeQuery skips metrics capture when captureQueryMetrics is disabled`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { captureQueryMetrics.value = false }
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        // History and aggregate counters still record; only the per-query metrics
        // record is gated by the toolbar toggle.
        io.mockk.coVerify(exactly = 0) { metricsRepository.save(any()) }
        io.mockk.coVerify { historyRepository.addToHistory("test-db-id", "SELECT * FROM c") }
        io.mockk.coVerify { appMetricsRepository.incrementQueryCount() }
        assertNull(vm.queryMetrics.value)
    }

    @Test
    fun `explainQuery skips metrics capture and tab switch when captureQueryMetrics is disabled`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { captureQueryMetrics.value = false }
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 0L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        io.mockk.coVerify(exactly = 0) { metricsRepository.save(any()) }
        assertNull(vm.queryMetrics.value)
        assertEquals(QueryInspectorTab.HISTORY, vm.selectedInspectorTab.value)
    }

    @Test
    fun `explainQuery captures metrics and opens Metrics tab when captureQueryMetrics is enabled`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 0L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        io.mockk.coVerify { metricsRepository.save(any()) }
        assertEquals(QueryInspectorTab.METRICS, vm.selectedInspectorTab.value)
    }

    // ── "Collect Metrics" preference gating ──────────────────────────────────

    @Test
    fun `executeQuery skips metrics record and aggregate counters when metricsEnabled is false`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = false)
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L

        val vm = createVm(sharedWorkbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        // History still records; all metrics capture is gated off.
        io.mockk.coVerify { historyRepository.addToHistory("test-db-id", "SELECT * FROM c") }
        io.mockk.coVerify(exactly = 0) { metricsRepository.save(any()) }
        io.mockk.coVerify(exactly = 0) { appMetricsRepository.incrementQueryCount() }
        io.mockk.coVerify(exactly = 0) { appMetricsRepository.recordQueryLatency(any()) }
        assertNull(vm.queryMetrics.value)
    }

    @Test
    fun `explainQuery skips metrics record and aggregate counters when metricsEnabled is false`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = false)
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 0L

        val vm = createVm(sharedWorkbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        io.mockk.coVerify(exactly = 0) { metricsRepository.save(any()) }
        io.mockk.coVerify(exactly = 0) { appMetricsRepository.incrementQueryCount() }
        io.mockk.coVerify(exactly = 0) { appMetricsRepository.recordQueryLatency(any()) }
        assertNull(vm.queryMetrics.value)
        assertEquals(QueryInspectorTab.HISTORY, vm.selectedInspectorTab.value)
    }

    @Test
    fun `executeQuery captures EXPLAIN output and original query text into the metrics record`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { queryExecutionService.explainPlan(any()) } returns "{ \"plan\": { \"index\": \"idx_c_a\" } }"
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L
        val saved = io.mockk.slot<com.costoda.dittoedgestudio.domain.model.QueryMetrics>()
        coEvery { metricsRepository.save(capture(saved)) } returns 1L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        // EXPLAIN runs against the original query text (no PROFILE prefix).
        io.mockk.coVerify { queryExecutionService.explainPlan("SELECT * FROM c") }
        assertEquals("{ \"plan\": { \"index\": \"idx_c_a\" } }", saved.captured.explainPlan)
        assertEquals("SELECT * FROM c", saved.captured.queryText)
        assertEquals(42L, saved.captured.historyId)
        // The capture is scoped to the Ditto databaseId string the VM was built with.
        assertEquals("test-db-id", saved.captured.databaseId)
        // Index-usage heuristic: the plan mentions an index, so the badge shows "Yes".
        assertTrue(saved.captured.indexesUsed.isNotEmpty())
    }

    @Test
    fun `executeQuery records empty indexesUsed when the plan mentions no index`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 3L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { queryExecutionService.explainPlan(any()) } returns "{ \"plan\": { \"operator\": \"scan\" } }"
        coEvery { historyRepository.addToHistory(any(), any()) } returns 1L
        val saved = io.mockk.slot<com.costoda.dittoedgestudio.domain.model.QueryMetrics>()
        coEvery { metricsRepository.save(capture(saved)) } returns 1L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        assertTrue(saved.captured.indexesUsed.isEmpty())
    }

    @Test
    fun `executeQuery in HTTP mode runs no local EXPLAIN and saves no metrics record`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), eq("HTTP")) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        // SwiftUI parity: HTTP queries capture NO metrics at all — the timing comes
        // from the remote HTTP API and a local plan would describe a different
        // execution. No EXPLAIN, no record.
        io.mockk.coVerify(exactly = 0) { queryExecutionService.explainPlan(any()) }
        io.mockk.coVerify(exactly = 0) { metricsRepository.save(any()) }
        assertNull(vm.queryMetrics.value)
    }

    @Test
    fun `executeQuery passes current executeMode to the facade`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[1] as String)
            QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 1L)
        }

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        assertEquals(listOf("HTTP"), captured)
    }

    @Test
    fun `executeQuery in HTTP mode records history and counters but NOT metrics`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), eq("HTTP")) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        assertEquals(result, vm.queryResult.value)
        assertEquals(42L, sharedWorkbench.lastHistoryId)
        io.mockk.coVerify { historyRepository.addToHistory("test-db-id", "SELECT * FROM c") }
        // History + aggregate counters still record; only the per-query metrics
        // record is skipped (SwiftUI captures no metrics for HTTP queries).
        io.mockk.coVerify(exactly = 0) { metricsRepository.save(any()) }
        io.mockk.coVerify { appMetricsRepository.incrementQueryCount() }
        assertNull(vm.queryMetrics.value)
    }

    @Test
    fun `explainQuery always uses Local mode regardless of picker`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 0L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        // The facade's explain() is local-only — confirm `execute(..., "HTTP")` was NOT called.
        io.mockk.coVerify(exactly = 0) { queryExecutionService.execute(any(), eq("HTTP")) }
        io.mockk.coVerify { queryExecutionService.explain("SELECT 1") }
    }

    // ── PROFILE prefix injection (QWP-8) ─────────────────────────────────────

    @Test
    fun `executeQuery prefixes PROFILE for SELECT Local with metricsEnabled true`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT * FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("PROFILE SELECT * FROM tasks"), captured)
    }

    @Test
    fun `executeQuery does NOT prefix when metricsEnabled is false`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = false)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT * FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("SELECT * FROM tasks"), captured)
    }

    @Test
    fun `executeQuery does NOT prefix for HTTP mode`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT * FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("SELECT * FROM tasks"), captured)
    }

    @Test
    fun `executeQuery does NOT prefix for non-SELECT statements`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("UPDATE tasks SET done = true")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("UPDATE tasks SET done = true"), captured)
    }

    @Test
    fun `executeQuery populates queryProfile flow when service returns a profile`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val fakeProfile = QueryProfile(
            id = "p1", appId = "a", featureFlags = "0x1",
            queryType = "select", requestType = "SDK", resultCount = 0,
            state = "completed", text = "PROFILE SELECT 1",
            times = QueryProfileTimes(1L, 2L, 3L, ""),
            plan = QueryProfileOperator("op", "scan", null, emptyList(), emptyList()),
            capturedAtMs = 0L,
        )
        coEvery { queryExecutionService.execute(any(), any()) } returns
            QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 5L, profile = fakeProfile)
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT 1")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(fakeProfile, vm.queryProfile.value)
    }

    // ── isSelectStatement whitespace boundary (SwiftUI parity) ───────────────

    @Test
    fun `executeQuery prefixes PROFILE when a newline follows SELECT`() = runTest {
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench)
        vm.onQueryTextChange("SELECT\n* FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("PROFILE SELECT\n* FROM tasks"), captured)
    }

    @Test
    fun `executeQuery prefixes PROFILE when a tab follows SELECT`() = runTest {
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench)
        vm.onQueryTextChange("SELECT\t* FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("PROFILE SELECT\t* FROM tasks"), captured)
    }

    @Test
    fun `executeQuery does NOT prefix when SELECT is not followed by a whitespace boundary`() = runTest {
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench)
        // "SELECT*" has no keyword boundary — must not be treated as a SELECT.
        vm.onQueryTextChange("SELECT* FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("SELECT* FROM tasks"), captured)
    }

    // ── Stale metrics clearing (finding: capture-off must not show old record) ─

    @Test
    fun `executeQuery clears a stale metrics record when the capture toggle is off`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply {
            captureQueryMetrics.value = false
            queryMetrics.value = staleMetrics()
        }
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        io.mockk.coVerify(exactly = 0) { metricsRepository.save(any()) }
        assertNull(vm.queryMetrics.value)
    }

    @Test
    fun `executeQuery in HTTP mode clears a stale metrics record`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply {
            executeMode.value = "HTTP"
            queryMetrics.value = staleMetrics()
        }
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), eq("HTTP")) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        assertNull(vm.queryMetrics.value)
    }

    @Test
    fun `explainQuery clears a stale metrics record when the capture toggle is off`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply {
            captureQueryMetrics.value = false
            queryMetrics.value = staleMetrics()
        }
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 0L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        assertNull(vm.queryMetrics.value)
    }

    // ── Metrics-save isolation (a Room failure must not mask a successful query) ─

    @Test
    fun `executeQuery keeps the successful result when the metrics save fails`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { queryExecutionService.explainPlan(any()) } returns "{ \"plan\": {} }"
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L
        coEvery { metricsRepository.save(any()) } throws RuntimeException("Room is down")

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        // The query result stands — no error banner — and the capture still shows
        // in the inspector (only persistence was lost).
        assertEquals(result, vm.queryResult.value)
        assertNull(vm.executionError.value)
        assertEquals(42L, vm.queryMetrics.value?.historyId)
    }

    @Test
    fun `explainQuery keeps the successful result when the metrics save fails`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 0L
        coEvery { metricsRepository.save(any()) } throws RuntimeException("Room is down")

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        assertEquals(result, vm.queryResult.value)
        assertNull(vm.executionError.value)
        assertEquals(QueryInspectorTab.METRICS, vm.selectedInspectorTab.value)
    }

    // ── Post-execution bookkeeping isolation (a Room/DataStore failure in the tail ─
    //    must not crash the coroutine or mask the successful result) ────────────────

    @Test
    fun `executeQuery keeps the successful result when the history write fails`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } throws RuntimeException("Room is down")

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        // advanceUntilIdle completing without an uncaught-exception failure IS the
        // no-crash assertion: before the fix, the Room throw escaped viewModelScope.
        advanceUntilIdle()

        assertEquals(result, vm.queryResult.value)
        assertNull(vm.executionError.value)
        assertFalse(vm.isExecuting.value)
    }

    @Test
    fun `explainQuery keeps the successful result when the history write fails`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } throws RuntimeException("Room is down")

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        assertEquals(result, vm.queryResult.value)
        assertNull(vm.executionError.value)
        assertFalse(vm.isExecuting.value)
    }

    @Test
    fun `executeQuery keeps the successful result when the aggregate counters fail`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L
        coEvery { appMetricsRepository.incrementQueryCount() } throws RuntimeException("DataStore is down")

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        assertEquals(result, vm.queryResult.value)
        assertNull(vm.executionError.value)
        assertFalse(vm.isExecuting.value)
    }

    // ── Capture-toggle clearing ──────────────────────────────────────────────────

    @Test
    fun `setCaptureQueryMetrics false clears the inspector's current capture`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply {
            queryMetrics.value = staleMetrics()
        }
        val vm = createVm(sharedWorkbench)

        vm.setCaptureQueryMetrics(false)
        advanceUntilIdle()

        assertEquals(false, vm.captureQueryMetrics.value)
        assertNull(vm.queryMetrics.value)
    }

    @Test
    fun `setCaptureQueryMetrics true keeps the inspector's current capture`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply {
            captureQueryMetrics.value = false
            queryMetrics.value = staleMetrics()
        }
        val vm = createVm(sharedWorkbench)

        vm.setCaptureQueryMetrics(true)
        advanceUntilIdle()

        assertEquals(true, vm.captureQueryMetrics.value)
        // Re-enabling capture must not wipe the record the user is inspecting.
        assertEquals(99L, vm.queryMetrics.value?.id)
    }
}

private fun staleMetrics() = com.costoda.dittoedgestudio.domain.model.QueryMetrics(
    id = 99L,
    historyId = 1L,
    databaseId = "test-db-id",
    executionTimeMs = 5L,
    docsExamined = 1,
    docsReturned = 1,
    indexesUsed = emptyList(),
    bytesRead = 0L,
    explainPlan = null,
    capturedAt = 1L,
    queryText = "SELECT stale",
)

private class FakeAppPreferences(initialMetricsEnabled: Boolean) :
    com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway {
    private val _metricsEnabled = kotlinx.coroutines.flow.MutableStateFlow(initialMetricsEnabled)
    override val metricsEnabled = _metricsEnabled
    val metricsEnabledValue: Boolean get() = _metricsEnabled.value
    override suspend fun setMetricsEnabled(enabled: Boolean) {
        _metricsEnabled.value = enabled
    }

    // Not exercised by these tests — presence layout is a navigation concern.
    override val presenceSplitView = kotlinx.coroutines.flow.MutableStateFlow(false)
    override suspend fun setPresenceSplitView(enabled: Boolean) {
        presenceSplitView.value = enabled
    }

    // Not exercised by these tests — the welcome tour is a navigation concern.
    override val showWelcomeOnNewDatabase = kotlinx.coroutines.flow.MutableStateFlow(true)
    override suspend fun setShowWelcomeOnNewDatabase(enabled: Boolean) {
        showWelcomeOnNewDatabase.value = enabled
    }

    // Not exercised by these tests — the system:metrics exporter hook lives in DittoManager.
    override val collectSystemMetrics = kotlinx.coroutines.flow.MutableStateFlow(true)
    override suspend fun setCollectSystemMetrics(enabled: Boolean) {
        collectSystemMetrics.value = enabled
    }
}
