package com.costoda.dittoedgestudio.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.data.repository.HistoryRepository
import com.costoda.dittoedgestudio.data.repository.QueryExecutionService
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import com.costoda.dittoedgestudio.domain.model.QueryResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

enum class QueryInspectorTab { HISTORY, FAVORITES, JSON, METRICS }

class QueryEditorViewModel(
    private val databaseId: String,
    private val queryExecutionService: QueryExecutionService,
    private val historyRepository: HistoryRepository,
    private val favoritesRepository: FavoritesRepository,
    private val metricsRepository: QueryMetricsRepository,
) : ViewModel() {

    // ── Editor state ─────────────────────────────────────────────────────────
    private val _queryText = MutableStateFlow("")
    val queryText: StateFlow<String> = _queryText.asStateFlow()

    private val _isExecuting = MutableStateFlow(false)
    val isExecuting: StateFlow<Boolean> = _isExecuting.asStateFlow()

    private val _executionError = MutableStateFlow<String?>(null)
    val executionError: StateFlow<String?> = _executionError.asStateFlow()

    // ── Results state ─────────────────────────────────────────────────────────
    private val _queryResult = MutableStateFlow<QueryResult?>(null)
    val queryResult: StateFlow<QueryResult?> = _queryResult.asStateFlow()

    private val _currentPage = MutableStateFlow(0)
    val currentPage: StateFlow<Int> = _currentPage.asStateFlow()

    private val _pageSize = MutableStateFlow(25)
    val pageSize: StateFlow<Int> = _pageSize.asStateFlow()

    val displayedDocuments: StateFlow<List<Map<String, Any?>>> =
        combine(_queryResult, _currentPage, _pageSize) { result, page, size ->
            val docs = result?.documents ?: return@combine emptyList()
            val from = page * size
            val to = minOf(from + size, docs.size)
            if (from >= docs.size) emptyList() else docs.subList(from, to)
        }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val pageSizeOptions: StateFlow<List<Int>> =
        _queryResult.combine(_queryResult) { r, _ -> r }.let { flow ->
            combine(_queryResult, _queryResult) { r, _ ->
                val total = r?.totalCount ?: 0
                buildList {
                    add(10)
                    if (total > 10) add(25)
                    if (total > 25) add(50)
                    if (total > 50) add(100)
                    if (total > 100) add(200)
                }
            }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), listOf(10, 25, 50))
        }

    // ── Inspector state ───────────────────────────────────────────────────────
    private val _selectedInspectorTab = MutableStateFlow(QueryInspectorTab.HISTORY)
    val selectedInspectorTab: StateFlow<QueryInspectorTab> = _selectedInspectorTab.asStateFlow()

    private val _selectedDocument = MutableStateFlow<Map<String, Any?>?>(null)
    val selectedDocument: StateFlow<Map<String, Any?>?> = _selectedDocument.asStateFlow()

    private val _queryMetrics = MutableStateFlow<QueryMetrics?>(null)
    val queryMetrics: StateFlow<QueryMetrics?> = _queryMetrics.asStateFlow()

    private val _isFavorited = MutableStateFlow(false)
    val isFavorited: StateFlow<Boolean> = _isFavorited.asStateFlow()

    // ── History / favorites ───────────────────────────────────────────────────
    val history: StateFlow<List<DittoQueryHistory>> =
        historyRepository.observeHistory(databaseId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val favorites: StateFlow<List<DittoQueryHistory>> =
        favoritesRepository.observeFavorites(databaseId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // ── Last saved history ID (for linking metrics) ───────────────────────────
    private var lastHistoryId: Long = -1L

    // ── Public API ────────────────────────────────────────────────────────────

    fun onQueryTextChange(text: String) {
        _queryText.value = text
        checkFavorited(text)
    }

    fun executeQuery() {
        val query = _queryText.value.trim()
        if (query.isBlank()) return
        viewModelScope.launch {
            _isExecuting.value = true
            _executionError.value = null
            runCatching {
                val result = queryExecutionService.execute(query)
                _queryResult.value = result
                _currentPage.value = 0
                // Save to history and record metrics
                val historyId = historyRepository.addToHistory(databaseId, query)
                lastHistoryId = historyId
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
                _queryMetrics.value = metrics
            }.onFailure { e ->
                _executionError.value = e.message ?: "Unknown error"
            }
            _isExecuting.value = false
        }
    }

    fun explainQuery() {
        val query = _queryText.value.trim()
        if (query.isBlank()) return
        viewModelScope.launch {
            _isExecuting.value = true
            _executionError.value = null
            runCatching {
                val result = queryExecutionService.explain(query)
                _queryResult.value = result
                _currentPage.value = 0
                val historyId = historyRepository.addToHistory(databaseId, "EXPLAIN $query")
                lastHistoryId = historyId
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
                _queryMetrics.value = metrics
                _selectedInspectorTab.value = QueryInspectorTab.METRICS
            }.onFailure { e ->
                _executionError.value = e.message ?: "Unknown error"
            }
            _isExecuting.value = false
        }
    }

    fun clearResults() {
        _queryResult.value = null
        _executionError.value = null
        _selectedDocument.value = null
        _currentPage.value = 0
    }

    fun setPage(page: Int) {
        val result = _queryResult.value ?: return
        val maxPage = if (result.totalCount == 0) 0
        else (result.totalCount - 1) / _pageSize.value
        _currentPage.value = page.coerceIn(0, maxPage)
    }

    fun setPageSize(size: Int) {
        _pageSize.value = size
        _currentPage.value = 0
    }

    fun selectDocument(doc: Map<String, Any?>) {
        _selectedDocument.value = doc
        _selectedInspectorTab.value = QueryInspectorTab.JSON
    }

    fun toggleFavorite() {
        val query = _queryText.value.trim()
        if (query.isBlank()) return
        viewModelScope.launch {
            if (_isFavorited.value) {
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
            checkFavorited(_queryText.value.trim())
        }
    }

    fun deleteHistory(id: Long) {
        viewModelScope.launch { historyRepository.removeHistoryItem(id) }
    }

    fun deleteFavorite(id: Long) {
        viewModelScope.launch { favoritesRepository.removeFavorite(id) }
    }

    fun restoreQuery(text: String) {
        _queryText.value = text
        checkFavorited(text)
    }

    fun setInspectorTab(tab: QueryInspectorTab) {
        _selectedInspectorTab.value = tab
    }

    fun clearHistory() {
        viewModelScope.launch { historyRepository.clearHistory(databaseId) }
    }

    private fun checkFavorited(query: String) {
        _isFavorited.value = favorites.value.any { it.query == query }
    }
}
