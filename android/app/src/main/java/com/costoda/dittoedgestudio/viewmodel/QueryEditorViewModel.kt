package com.costoda.dittoedgestudio.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.costoda.dittoedgestudio.data.preferences.AppPreferencesGateway
import com.costoda.dittoedgestudio.data.repository.AppMetricsRepository
import com.costoda.dittoedgestudio.data.repository.AttachmentService
import com.costoda.dittoedgestudio.data.repository.FavoritesRepository
import com.costoda.dittoedgestudio.data.repository.HistoryRepository
import com.costoda.dittoedgestudio.data.repository.QueryExecutionService
import com.costoda.dittoedgestudio.data.repository.QueryMetricsRepository
import com.costoda.dittoedgestudio.data.repository.toSortedPrettyJson
import com.costoda.dittoedgestudio.data.session.QueryWorkbenchState
import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import com.costoda.dittoedgestudio.domain.model.DittoQueryHistory
import com.costoda.dittoedgestudio.domain.model.QueryMetrics
import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.domain.model.QueryResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class QueryInspectorTab { HISTORY, FAVORITES, JSON, METRICS, HELP }

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
    private val appPreferences: AppPreferencesGateway,
    private val attachmentService: AttachmentService,
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
        workbench.queryResult.map { r ->
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
    val queryProfile: StateFlow<QueryProfile?> = workbench.queryProfile.asStateFlow()
    val isFavorited: StateFlow<Boolean> = workbench.isFavorited.asStateFlow()

    // ── Attachment cache ──────────────────────────────────────────────────────
    private val _cachedAttachments = MutableStateFlow<Map<String, java.io.File>>(emptyMap())
    val cachedAttachments: StateFlow<Map<String, java.io.File>> = _cachedAttachments.asStateFlow()

    // ── History / favorites ───────────────────────────────────────────────────
    val history: StateFlow<List<DittoQueryHistory>> =
        historyRepository.observeHistory(databaseId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val favorites: StateFlow<List<DittoQueryHistory>> =
        favoritesRepository.observeFavorites(databaseId)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // ── Execute mode + Options toggles (session-backed) ──────────────────────
    val executeMode: StateFlow<String> = workbench.executeMode.asStateFlow()
    val executeModes: StateFlow<List<String>> = workbench.executeModes.asStateFlow()
    val captureProfilingData: StateFlow<Boolean> = appPreferences.metricsEnabled
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)
    val captureQueryMetrics: StateFlow<Boolean> = workbench.captureQueryMetrics.asStateFlow()

    // ── Public API ────────────────────────────────────────────────────────────

    fun viewAttachment(info: AttachmentInfo) {
        viewModelScope.launch {
            runCatching {
                val file = attachmentService.fetchToCache(info)
                _cachedAttachments.update { it + (info.id to file) }
            }.onFailure { e ->
                // Never surface cancellation as a phantom "… Job was cancelled" banner.
                if (e is CancellationException) throw e
                workbench.executionError.value = "Attachment fetch failed: ${e.message}"
            }
        }
    }

    /**
     * Adds an attachment to the document identified by [documentId] in [collection], storing
     * it at field [fieldName].
     *
     * Pipeline:
     *   1. Copy the picked content Uri to a local cache temp file (Ditto's newAttachment
     *      takes a file path, not a Uri).
     *   2. Call [AttachmentService.createAndLink] which: (a) calls newAttachment to upload
     *      the file to Ditto's store, (b) immediately binds the resulting DittoAttachment
     *      to the document via a DQL UPDATE using the CBOR Dictionary execute overload with
     *      `attachment.toDittoCbor()`. This two-step combined operation is necessary because
     *      the Kotlin SDK's Map<String,Any?> execute path does not accept DittoAttachment
     *      values — only the DittoCborSerializable.Dictionary overload supports attachment
     *      binding (see AttachmentStoreGateway.createAndLink KDoc for full rationale).
     *   3. Delete the temp file after the upload completes.
     *
     * Errors are surfaced to the UI via [workbench.executionError].
     */
    /**
     * Remove the given attachments from [documentId] in [collection] by issuing a DQL UPDATE per
     * attachment that nulls the field holding the token.
     *
     * The DQL identifier rules in Ditto permit unquoted collection/field names as long as they're
     * valid identifiers (alpha + underscore start, alphanumeric thereafter). For safety we apply
     * [isSafeIdentifier] — anything else fails fast rather than risking an injection-style misparse.
     */
    fun deleteAttachments(
        documentId: String,
        collection: String,
        attachments: List<AttachmentInfo>,
    ) {
        viewModelScope.launch {
            runCatching {
                require(documentId.isNotBlank()) { "documentId required" }
                require(isSafeDocumentId(documentId)) {
                    "Unsafe document id (must contain only printable, non-control characters " +
                        "and no embedded newlines): $documentId"
                }
                require(isSafeIdentifier(collection)) { "Unsafe collection identifier: $collection" }
                for (att in attachments) {
                    require(isSafeIdentifier(att.fieldName)) {
                        "Unsafe field identifier: ${att.fieldName}"
                    }
                }
                // documentId is rendered as a DQL string literal. DQL follows the ANSI SQL rule:
                // embedded single quotes are doubled (`''`) — NOT backslash-escaped. The doc-id
                // shape guard above also rejects control chars / newlines, so a single-line
                // literal is sufficient. Identifiers (collection, fieldName) are not quoted —
                // both are pre-validated by isSafeIdentifier.
                val escapedDocId = documentId.replace("'", "''")
                for (att in attachments) {
                    queryExecutionService.execute(
                        "UPDATE $collection SET ${att.fieldName} = NULL WHERE _id = '$escapedDocId'",
                        mode = "Local",
                    )
                }
                // Re-fetch note: the caller is responsible for triggering a result refresh. For v1
                // we leave this as a known follow-up — the document row must be re-queried to
                // reflect cleared fields.
            }.onFailure { e ->
                // Never surface cancellation as a phantom "… Job was cancelled" banner.
                if (e is CancellationException) throw e
                workbench.executionError.value = "Delete attachment failed: ${e.message}"
            }
        }
    }

    private fun isSafeIdentifier(s: String): Boolean {
        if (s.isBlank()) return false
        if (!(s[0].isLetter() || s[0] == '_')) return false
        return s.all { it.isLetterOrDigit() || it == '_' }
    }

    /**
     * Doc-id shape guard. Rejects empty strings, anything containing ISO control characters
     * (newlines, tabs, NULs etc.), and the literal backslash to prevent dialect-specific
     * escape interactions. The single-quote IS allowed and is handled by doubling at the
     * call site.
     */
    private fun isSafeDocumentId(s: String): Boolean {
        if (s.isEmpty()) return false
        return s.none { it.isISOControl() || it == '\\' }
    }

    fun addAttachment(
        contentUri: android.net.Uri,
        documentId: String,
        collection: String,
        fieldName: String,
        metadata: Map<String, String>,
        context: android.content.Context,
    ) {
        viewModelScope.launch {
            runCatching {
                // Step 1: Copy the picked content Uri to a temp file (SDK needs a path).
                val tempFile = java.io.File.createTempFile("ditto-pick-", ".bin", context.cacheDir)
                try {
                    context.contentResolver.openInputStream(contentUri)?.use { input ->
                        tempFile.outputStream().use { input.copyTo(it) }
                    } ?: error("Could not read content uri: $contentUri")

                    // Step 2: Upload to Ditto and link to the document in one gateway call.
                    attachmentService.createAndLink(
                        path = tempFile.absolutePath,
                        metadata = metadata,
                        collection = collection,
                        fieldName = fieldName,
                        documentId = documentId,
                    )
                } finally {
                    // Step 3: Clean up — temp file was only needed for the SDK upload call.
                    tempFile.delete()
                }
            }.onFailure { e ->
                // Never surface cancellation as a phantom "… Job was cancelled" banner.
                // The temp-file cleanup above lives in a finally, so it still runs.
                if (e is CancellationException) throw e
                workbench.executionError.value = "Add attachment failed: ${e.message}"
            }
        }
    }

    fun onQueryTextChange(text: String) {
        workbench.queryText.value = text
        checkFavorited(text)
    }

    fun executeQuery() {
        val rawQuery = workbench.queryText.value.trim()
        if (rawQuery.isBlank()) return
        val mode = workbench.executeMode.value
        viewModelScope.launch {
            // Read the preference inside the coroutine so the live value is used even when
            // captureProfilingData (a WhileSubscribed stateIn) has no active subscribers.
            val captureProfile = appPreferences.metricsEnabled.first()
            val effectiveQuery = if (
                captureProfile &&
                mode == "Local" &&
                isSelectStatement(rawQuery) &&
                !rawQuery.uppercase().trimStart().startsWith("PROFILE")
            ) {
                "PROFILE $rawQuery"
            } else {
                rawQuery
            }
            workbench.isExecuting.value = true
            workbench.executionError.value = null
            try {
                val result = try {
                    queryExecutionService.execute(effectiveQuery, mode = mode)
                } catch (c: CancellationException) {
                    // Never swallow cancellation — the scope is being torn down
                    // (e.g. rail switch); the finally block still resets isExecuting.
                    throw c
                } catch (e: Exception) {
                    workbench.executionError.value = e.message ?: "Unknown error"
                    return@launch
                }
                workbench.queryResult.value = result
                workbench.queryProfile.value = result.profile
                workbench.currentPage.value = 0
                // Post-execution bookkeeping (history write, metrics capture, aggregate
                // counters) is isolated from the execution result: a Room/DataStore
                // failure here must NOT escape this coroutine uncaught (→ crash AFTER a
                // successful query) or flip the success into an error banner. At most we
                // log; the result assigned above stands.
                try {
                    // Save to history and record metrics using the ORIGINAL query text so
                    // history doesn't fill up with "PROFILE …" entries.
                    val historyId = historyRepository.addToHistory(databaseId, rawQuery)
                    workbench.lastHistoryId = historyId
                    // Per-query metrics capture requires BOTH the app-wide "Collect
                    // Metrics" preference (captureProfile) AND the toolbar's session-scoped
                    // "Capture query metrics" toggle — mirrors SwiftUI's QueryService gating.
                    // Local mode only: SwiftUI captures NO metrics for HTTP queries — the
                    // timing comes from the remote HTTP API, and a plan from the local store
                    // would describe a different execution.
                    if (captureProfile && workbench.captureQueryMetrics.value && mode == "Local") {
                        // Run EXPLAIN against the ORIGINAL query text (no PROFILE prefix) —
                        // mirrors SwiftUI's QueryService, which captures explain output
                        // separately from execution.
                        val explainOutput = queryExecutionService.explainPlan(rawQuery)
                        val metrics = QueryMetrics(
                            historyId = historyId,
                            databaseId = databaseId,
                            executionTimeMs = result.executionTimeMs,
                            docsExamined = result.totalCount,
                            docsReturned = result.totalCount,
                            indexesUsed = QueryMetrics.indexesUsedFromExplain(explainOutput),
                            bytesRead = 0L,
                            explainPlan = explainOutput,
                            capturedAt = System.currentTimeMillis(),
                            queryText = rawQuery,
                        )
                        // Isolated from the execution result: a Room failure here must not
                        // flip a SUCCESSFUL query into a user-facing error banner. The
                        // capture still shows in the inspector; only persistence is lost.
                        try {
                            metricsRepository.save(metrics)
                        } catch (c: CancellationException) {
                            throw c
                        } catch (e: Exception) {
                            Log.w(TAG, "Metrics save failed: ${e.message}")
                        }
                        workbench.queryMetrics.value = metrics
                    } else {
                        // No fresh capture (toggle off, preference off, or HTTP mode) — clear
                        // any previous record so the inspector's Metrics tab never shows a
                        // stale capture next to the new results.
                        workbench.queryMetrics.value = null
                    }
                    // Aggregate counters are also gated on "Collect Metrics" (SwiftUI parity).
                    if (captureProfile) {
                        appMetricsRepository.incrementQueryCount()
                        appMetricsRepository.recordQueryLatency(result.executionTimeMs.toDouble())
                    }
                } catch (c: CancellationException) {
                    // Never swallow cancellation — the scope is being torn down
                    // (e.g. rail switch); the finally block still resets isExecuting.
                    throw c
                } catch (e: Exception) {
                    Log.w(TAG, "Post-execution bookkeeping failed: ${e.message}")
                }
            } finally {
                workbench.isExecuting.value = false
            }
        }
    }

    private fun isSelectStatement(q: String): Boolean {
        val upper = q.trimStart().uppercase()
        if (!upper.startsWith("SELECT")) return false
        // SwiftUI QueryService.isSelectStatement parity: the keyword must be followed by
        // ANY whitespace boundary (space, newline, tab, …) or be the entire statement —
        // a literal space is not required ("SELECT\n* FROM c" is a SELECT).
        val next = upper.getOrNull("SELECT".length) ?: return true
        return next.isWhitespace()
    }

    fun explainQuery() {
        val query = workbench.queryText.value.trim()
        if (query.isBlank()) return
        viewModelScope.launch {
            val metricsEnabled = appPreferences.metricsEnabled.first()
            workbench.isExecuting.value = true
            workbench.executionError.value = null
            try {
                val result = try {
                    queryExecutionService.explain(query)
                } catch (c: CancellationException) {
                    // Never swallow cancellation — the finally block resets isExecuting.
                    throw c
                } catch (e: Exception) {
                    workbench.executionError.value = e.message ?: "Unknown error"
                    return@launch
                }
                workbench.queryResult.value = result
                workbench.currentPage.value = 0
                // Post-execution bookkeeping is isolated from the execution result —
                // a Room/DataStore failure here must not escape uncaught (→ crash after
                // a successful EXPLAIN) or surface as an error banner (see executeQuery).
                try {
                    val historyId = historyRepository.addToHistory(databaseId, "EXPLAIN $query")
                    workbench.lastHistoryId = historyId
                    if (metricsEnabled && workbench.captureQueryMetrics.value) {
                        // The explain result is already in hand — serialize its first row
                        // rather than running EXPLAIN a second time.
                        val explainOutput = result.documents.firstOrNull()
                            ?.let { toSortedPrettyJson(it) }
                            ?: "No explain output"
                        val metrics = QueryMetrics(
                            historyId = historyId,
                            databaseId = databaseId,
                            executionTimeMs = result.executionTimeMs,
                            docsExamined = result.totalCount,
                            docsReturned = result.totalCount,
                            indexesUsed = QueryMetrics.indexesUsedFromExplain(explainOutput),
                            bytesRead = 0L,
                            explainPlan = explainOutput,
                            capturedAt = System.currentTimeMillis(),
                            queryText = query,
                        )
                        // Isolated from the execution result: a Room failure must not turn
                        // a successful EXPLAIN into an error banner (see executeQuery).
                        try {
                            metricsRepository.save(metrics)
                        } catch (c: CancellationException) {
                            throw c
                        } catch (e: Exception) {
                            Log.w(TAG, "Metrics save failed: ${e.message}")
                        }
                        workbench.queryMetrics.value = metrics
                        // Only auto-open the Metrics inspector tab when fresh metrics
                        // were actually captured — otherwise it would show a stale record.
                        workbench.selectedInspectorTab.value = QueryInspectorTab.METRICS
                    } else {
                        // Capture skipped — clear any previous record so the inspector's
                        // Metrics tab never shows a stale capture next to new results.
                        workbench.queryMetrics.value = null
                    }
                    if (metricsEnabled) {
                        appMetricsRepository.incrementQueryCount()
                        appMetricsRepository.recordQueryLatency(result.executionTimeMs.toDouble())
                    }
                } catch (c: CancellationException) {
                    // Never swallow cancellation — the finally block resets isExecuting.
                    throw c
                } catch (e: Exception) {
                    Log.w(TAG, "Post-execution bookkeeping failed: ${e.message}")
                }
            } finally {
                workbench.isExecuting.value = false
            }
        }
    }

    fun clearResults() {
        workbench.queryResult.value = null
        workbench.executionError.value = null
        workbench.selectedDocument.value = null
        workbench.queryMetrics.value = null
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

    // ── DQL statement generator (SwiftUI queryGenerateAndInsert parity) ───────

    /**
     * Generates a [kind] statement template from the current query's collection and
     * the first result row's fields, and replaces the editor draft with it.
     * Returns an error message or null on success.
     */
    fun insertGeneratedStatement(kind: com.costoda.dittoedgestudio.domain.model.DqlStatementKind): String? {
        val query = workbench.queryText.value
        if (query.isBlank()) return "No query available"
        val collection = com.costoda.dittoedgestudio.domain.model.DqlGenerator.collectionName(query)
            ?: return "Could not extract collection name from query"
        val sample = workbench.queryResult.value?.documents?.firstOrNull()
        val fields = com.costoda.dittoedgestudio.domain.model.DqlGenerator.fieldNames(sample)
        val gen = com.costoda.dittoedgestudio.domain.model.DqlGenerator
        val statement = when (kind) {
            com.costoda.dittoedgestudio.domain.model.DqlStatementKind.SELECT ->
                gen.generateSelect(collection, fields)
            com.costoda.dittoedgestudio.domain.model.DqlStatementKind.INSERT ->
                gen.generateInsert(collection, fields, sample)
            com.costoda.dittoedgestudio.domain.model.DqlStatementKind.UPDATE ->
                gen.generateUpdate(collection, fields, sample)
            com.costoda.dittoedgestudio.domain.model.DqlStatementKind.DELETE ->
                gen.generateDelete(collection)
            com.costoda.dittoedgestudio.domain.model.DqlStatementKind.EVICT ->
                gen.generateEvict(collection)
        }
        workbench.queryText.value = statement
        return null
    }

    /** Full result set as a JSON array string for export (not just the visible page). */
    fun resultsJsonForExport(): String? =
        workbench.queryResult.value?.documents?.let {
            if (it.isEmpty()) null
            else com.costoda.dittoedgestudio.domain.model.queryDocumentsToJson(it)
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

    fun setExecuteMode(mode: String) { workbench.executeMode.value = mode }
    fun setCaptureProfilingData(enabled: Boolean) {
        viewModelScope.launch { appPreferences.setMetricsEnabled(enabled) }
    }
    fun setCaptureQueryMetrics(enabled: Boolean) {
        workbench.captureQueryMetrics.value = enabled
        if (!enabled) {
            // Toggling capture off must also drop the inspector's current capture —
            // otherwise the last record keeps showing until the next run.
            workbench.queryMetrics.value = null
        }
    }

    private fun checkFavorited(query: String) {
        workbench.isFavorited.value = favorites.value.any { it.query == query }
    }

    private companion object {
        const val TAG = "QueryEditorViewModel"
    }
}
