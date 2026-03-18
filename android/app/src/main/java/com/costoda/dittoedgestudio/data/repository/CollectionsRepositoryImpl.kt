package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.DittoIndex
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoStoreObserver
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

private const val QUERY_COLLECTIONS = "SELECT * FROM __collections"
private const val QUERY_INDEXES = "SELECT * FROM system:indexes"
private const val QUERY_COUNT_TMPL = "SELECT COUNT(*) as numDocs FROM %s"

class CollectionsRepositoryImpl(
    private val scope: CoroutineScope,
) : CollectionsRepository {

    private val _collections = MutableStateFlow<List<DittoCollection>>(emptyList())
    override val collections: StateFlow<List<DittoCollection>> = _collections.asStateFlow()

    private var observer: DittoStoreObserver? = null
    private var activeDitto: Ditto? = null

    override fun startObserving(ditto: Ditto) {
        activeDitto = ditto
        observer?.close()

        // Initial load
        scope.launch(Dispatchers.IO) { refreshInternal() }

        // Register live observer — fires on any __collections change
        observer = ditto.store.registerObserver(QUERY_COLLECTIONS) { _ ->
            scope.launch(Dispatchers.IO) { refreshInternal() }
        }
    }

    override fun stopObserving() {
        observer?.close()
        observer = null
        activeDitto = null
        _collections.value = emptyList()
    }

    override suspend fun refresh() {
        scope.launch(Dispatchers.IO) { refreshInternal() }
    }

    override suspend fun createIndex(collection: String, fieldName: String) {
        val safeName = "idx_${collection}_${fieldName}"
            .replace('.', '_')
            .replace(' ', '_')
            .replace('-', '_')
        val dql = "CREATE INDEX IF NOT EXISTS $safeName ON $collection ($fieldName)"
        activeDitto?.store?.execute(dql)
        refreshInternal()
    }

    private suspend fun refreshInternal() {
        val ditto = activeDitto ?: return
        val updated = fetchCollections(ditto)
        _collections.value = updated
    }

    private suspend fun fetchCollections(ditto: Ditto): List<DittoCollection> {
        // 1. Fetch collection names
        val rawNames = runCatching {
            val result = ditto.store.execute(QUERY_COLLECTIONS)
            val names = result.items.mapNotNull { item ->
                runCatching { JSONObject(item.jsonString()).optString("_id") }
                    .getOrNull()
                    ?.takeIf { it.isNotBlank() && !it.startsWith("__") }
            }
            result.close()
            names
        }.getOrDefault(emptyList())

        // 2. Fetch all indexes in one query
        val indexesByCollection = fetchIndexes(ditto)

        // 3. Fetch doc counts sequentially
        val countsByName = fetchDocCounts(ditto, rawNames)

        // 4. Assemble and return sorted
        return rawNames.map { name ->
            DittoCollection(
                name = name,
                docCount = countsByName[name],
                indexes = indexesByCollection[name] ?: emptyList(),
            )
        }.sortedBy { it.name }
    }

    private suspend fun fetchIndexes(ditto: Ditto): Map<String, List<DittoIndex>> {
        val map = mutableMapOf<String, MutableList<DittoIndex>>()
        runCatching {
            val result = ditto.store.execute(QUERY_INDEXES)
            for (item in result.items) {
                runCatching {
                    val json = JSONObject(item.jsonString())
                    val id = json.optString("_id").takeIf { it.isNotBlank() } ?: return@runCatching
                    val collection = json.optString("collection").takeIf { it.isNotBlank() } ?: return@runCatching
                    val fieldsJson = json.optJSONArray("fields")
                    val fields = buildList {
                        if (fieldsJson != null) {
                            for (i in 0 until fieldsJson.length()) {
                                fieldsJson.optString(i).takeIf { it.isNotBlank() }?.let { add(it) }
                            }
                        }
                    }
                    map.getOrPut(collection) { mutableListOf() }
                        .add(DittoIndex(id = id, collection = collection, fields = fields))
                }
                item.dematerialize()
            }
            result.close()
        }
        return map
    }

    private suspend fun fetchDocCounts(ditto: Ditto, names: List<String>): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()
        for (name in names) {
            runCatching {
                val result = ditto.store.execute(QUERY_COUNT_TMPL.format(name))
                val count = result.items.firstOrNull()?.let {
                    JSONObject(it.jsonString()).optInt("numDocs", 0)
                } ?: 0
                result.close()
                counts[name] = count
            }
            // One failing collection doesn't block others
        }
        return counts
    }
}
