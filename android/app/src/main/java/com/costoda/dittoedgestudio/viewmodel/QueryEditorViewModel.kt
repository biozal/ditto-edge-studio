package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.data.repository.HistoryRepository
import com.costoda.dittoedgestudio.data.repository.QueryExecutionService
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.data.session.QueryWorkbenchState
import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import com.costoda.dittoedgestudio.domain.model.QueryResult
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class QueryInspectorTab { HISTORY, FAVORITES, JSON, METRICS }

/**
 * ViewModel for the Query Workbench (Task 4.3e).
 *
 * Editor draft, results, pagination, and inspector state are owned by [workbench] — a
 * session-scoped [QueryWorkbenchState] living on [com.costoda.dittoedgestudio.data.session.StudioUiState].
 * This VM exposes those flows verbatim so any number of VM instances sharing the same
 * session (e.g. recreated each time the user navigates to `QueryKey`) see identical state.
 *
 * Repository-backed flows (history, favorites) are derived from the repositories themselves —
 * they re-share inside this VM's [viewModelScope] but the underlying source-of-truth is Room,
 * not VM-local state, so a new VM instance reproduces the same flows from the same data.
 *
 * Derived flows ([displayedDocuments], [pageSizeOptions]) `combine` session-scoped state flows
 * and re-share in [viewModelScope]; the upstream state lives in [workbench] so re-derivation
 * is trivial.
 */
class QueryEditorViewModel(
    private val databaseId: String,
    private val workbench: QueryWorkbenchState,
    private val queryExecutionService: QueryExecutionService,
    private val historyRepository: HistoryRepository,
    private val favoritesRepository: FavoritesRepository,
    private val metricsRepository: QueryMetricsRepository,
    private val appMetricsRepository: AppMetricsRepository,
) : ViewModel() {

    // ── Editor state (session-backed) ─────────────────────────────────────────
    val queryText: StateFlow<String> = workbench.queryText.asStateFlow()
    val isExecuting: StateFlow<Boolean> = workbench.isExecuting.asStateFlow()
    val executionError: StateFlow<String?> = workbench.executionError.asStateFlow()

    // ── Results state (session-backed) ────────────────────────────────────────
    val queryResult: StateFlow<QueryResult?> = workbench.queryResult.asStateFlow()
    val currentPage: StateFlow<Int> = workbench.currentPage.asStateFlow()
    val pageSize: StateFlow<Int> = workbench.pageSize.asStateFlow()

    val displayedDocuments: StateFlow<List<Map<String, Any?>>> =
        combine(workbench.queryResult, workbench.currentPage, workbench.pageSize) { result, page, size ->
            val docs = result?.documents ?: return@combine emptyList()
            val from = page * size
            val to = minOf(from + size, docs.size)
            if (from >= docs.size) emptyList() else docs.subList(from, to)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val pageSizeOptions: StateFlow<List<Int>> =
        combine(workbench.queryResult, workbench.queryResult) { r, _ ->
            val total = r?.totalCount ?: 0
            buildList {
                add(10)
                if (total > 10) add(25)
                if (total > 25) add(50)
                if (total > 50) add(100)
                if (total > 100) add(200)
            }
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), listOf(10, 25, 50))

    // ── Inspector state (session-backed) ──────────────────────────────────────
    val selectedInspectorTab: StateFlow<QueryInspectorTab> = workbench.selectedInspectorTab.asStateFlow()
    val selectedDocument: StateFlow<Map<String, Any?>?> = workbench.selectedDocument.asStateFlow()
    val queryMetrics: StateFlow<QueryMetrics?> = workbench.queryMetrics.asStateFlow()
    val isFavorited: StateFlow<Boolean> = workbench.isFavorited.asStateFlow()

    // ── History / favorites ───────────────────────────────────────────────────
    val history: StateFlow<List<DittoQueryHistory>> =
        historyRepository.observeHistory(databaseId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val favorites: StateFlow<List<DittoQueryHistory>> =
        favoritesRepository.observeFavorites(databaseId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // ── Public API ────────────────────────────────────────────────────────────

    fun onQueryTextChange(text: String) {
        workbench.queryText.value = text
        checkFavorited(text)
    }

    fun executeQuery() {
        val query = workbench.queryText.value.trim()
        if (query.isBlank()) return
        viewModelScope.launch {
            workbench.isExecuting.value = true
            workbench.executionError.value = null
            runCatching {
                val result = queryExecutionService.execute(query)
                workbench.queryResult.value = result
                workbench.currentPage.value = 0
                // Save to history and record metrics
                val historyId = historyRepository.addToHistory(databaseId, query)
                workbench.lastHistoryId = historyId
                val metrics = QueryMetrics(
                    historyId = historyId,
                    executionTimeMs = result.executionTimeMs,
                    docsExamined = result.totalCount,
                    docsReturned = result.totalCount,
                    indexesUsed = emptyList(),
                    bytesRead = 0L,
                    explainPlan = result.explainPlan,
                    capturedAt = System.currentTimeMillis(),
                    queryText = query,
                )
                metricsRepository.save(metrics)
                workbench.queryMetrics.value = metrics
                appMetricsRepository.incrementQueryCount()
                appMetricsRepository.recordQueryLatency(result.executionTimeMs.toDouble())
            }.onFailure { e ->
                workbench.executionError.value = e.message ?: "Unknown error"
            }
            workbench.isExecuting.value = false
        }
    }

    fun explainQuery() {
        val query = workbench.queryText.value.trim()
        if (query.isBlank()) return
        viewModelScope.launch {
            workbench.isExecuting.value = true
            workbench.executionError.value = null
            runCatching {
                val result = queryExecutionService.explain(query)
                workbench.queryResult.value = result
                workbench.currentPage.value = 0
                val historyId = historyRepository.addToHistory(databaseId, "EXPLAIN $query")
                workbench.lastHistoryId = historyId
                val metrics = QueryMetrics(
                    historyId = historyId,
                    executionTimeMs = result.executionTimeMs,
                    docsExamined = result.totalCount,
                    docsReturned = result.totalCount,
                    indexesUsed = emptyList(),
                    bytesRead = 0L,
                    explainPlan = result.explainPlan,
                    capturedAt = System.currentTimeMillis(),
                    queryText = query,
                )
                metricsRepository.save(metrics)
                workbench.queryMetrics.value = metrics
                appMetricsRepository.incrementQueryCount()
                appMetricsRepository.recordQueryLatency(result.executionTimeMs.toDouble())
                workbench.selectedInspectorTab.value = QueryInspectorTab.METRICS
            }.onFailure { e ->
                workbench.executionError.value = e.message ?: "Unknown error"
            }
            workbench.isExecuting.value = false
        }
    }

    fun clearResults() {
        workbench.queryResult.value = null
        workbench.executionError.value = null
        workbench.selectedDocument.value = null
        workbench.currentPage.value = 0
    }

    fun setPage(page: Int) {
        val result = workbench.queryResult.value ?: return
        val maxPage = if (result.totalCount == 0) 0
        else (result.totalCount - 1) / workbench.pageSize.value
        workbench.currentPage.value = page.coerceIn(0, maxPage)
    }

    fun setPageSize(size: Int) {
        workbench.pageSize.value = size
        workbench.currentPage.value = 0
    }

    fun selectDocument(doc: Map<String, Any?>) {
        workbench.selectedDocument.value = doc
        workbench.selectedInspectorTab.value = QueryInspectorTab.JSON
    }

    fun toggleFavorite() {
        val query = workbench.queryText.value.trim()
        if (query.isBlank()) return
        viewModelScope.launch {
            if (workbench.isFavorited.value) {
                val fav = favorites.value.firstOrNull { it.query == query }
                if (fav != null) favoritesRepository.removeFavorite(fav.id)
            } else {
                favoritesRepository.saveFavorite(databaseId, query)
            }
            checkFavorited(query)
        }
    }

    fun addHistoryToFavorites(query: String) {
        viewModelScope.launch {
            favoritesRepository.saveFavorite(databaseId, query)
            checkFavorited(workbench.queryText.value.trim())
        }
    }

    fun deleteHistory(id: Long) {
        viewModelScope.launch { historyRepository.removeHistoryItem(id) }
    }

    fun deleteFavorite(id: Long) {
        viewModelScope.launch { favoritesRepository.removeFavorite(id) }
    }

    fun restoreQuery(text: String) {
        workbench.queryText.value = text
        checkFavorited(text)
    }

    fun setInspectorTab(tab: QueryInspectorTab) {
        workbench.selectedInspectorTab.value = tab
    }

    fun clearHistory() {
        viewModelScope.launch { historyRepository.clearHistory(databaseId) }
    }

    private fun checkFavorited(query: String) {
        workbench.isFavorited.value = favorites.value.any { it.query == query }
    }
}
