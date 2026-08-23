package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.DittoIndex
import com.costoda.dittoedgestudio.domain.model.IndexField
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

/**
 * Builds the per-collection doc-count DQL. The collection name is backtick-quoted via
 * [quoteIdentifier] so names containing dots, spaces, or backticks parse — a bare
 * `%s` interpolation would break (or misparse) on e.g. `foo.bar`.
 */
internal fun buildDocCountQuery(collection: String): String =
    QUERY_COUNT_TMPL.format(quoteIdentifier(collection))

/**
 * Trims whitespace and drops blank field names. Throws when nothing remains.
 */
internal fun normalizeIndexFields(fields: List<IndexField>): List<IndexField> {
    val cleaned = fields.map { it.copy(name = it.name.trim()) }.filter { it.name.isNotEmpty() }
    require(cleaned.isNotEmpty()) { "At least one field is required to create an index" }
    return cleaned
}

/**
 * Builds the `idx_{collection}_{field…}` name for an index. Dots/spaces/dashes →
 * underscores (dots separate collection from index name in DQL identifiers).
 */
internal fun buildIndexName(collection: String, fields: List<IndexField>): String =
    (listOf(collection) + fields.map { it.name })
        .joinToString(separator = "_", prefix = "idx_")
        .replace('.', '_')
        .replace(' ', '_')
        .replace('-', '_')

/**
 * Backtick-quotes a single DQL identifier, escaping embedded backticks by
 * doubling — per the DQL tokenizer grammar.
 */
internal fun quoteIdentifier(name: String): String = "`${name.replace("`", "``")}`"

/**
 * Backtick-quotes one field path for DQL. Each dot-separated segment is quoted
 * individually (`address.city` → `` `address`.`city` ``).
 */
internal fun quoteFieldPath(name: String): String =
    name.split('.').joinToString(".") { quoteIdentifier(it) }

/**
 * Builds the CREATE INDEX DQL for one or more fields. Two or more fields produce a
 * composite index; each key is emitted backtick-quoted with an explicit ASC/DESC
 * direction. Blank field names are dropped. Collection, field, and index names are
 * backtick-quoted so names with spaces, dashes, or backticks parse.
 */
internal fun buildCreateIndexDql(collection: String, fields: List<IndexField>): String {
    val cleaned = normalizeIndexFields(fields)
    val keys = cleaned.joinToString(", ") { "${quoteFieldPath(it.name)} ${if (it.ascending) "ASC" else "DESC"}" }
    return "CREATE INDEX IF NOT EXISTS ${quoteIdentifier(buildIndexName(collection, cleaned))} ON ${quoteIdentifier(collection)} ($keys)"
}

/**
 * Parses the `fields` array of a `system:indexes` row into index keys. Each entry is
 * `{"direction": "asc"|"desc", "key": [path segments]}`; segments are joined with dots.
 * Backticks around segments (emitted by older SDKs) are stripped. A plain string array
 * is accepted as a legacy fallback.
 */
internal fun parseIndexFields(json: JSONObject): List<IndexField> {
    val fieldsJson = json.optJSONArray("fields") ?: return emptyList()
    return buildList {
        for (i in 0 until fieldsJson.length()) {
            when (val entry = fieldsJson.opt(i)) {
                // SDK 5.x: {"direction": "asc", "key": ["fieldName"]}
                is JSONObject -> {
                    val keyArray = entry.optJSONArray("key")
                    if (keyArray != null && keyArray.length() > 0) {
                        val segments = buildList {
                            for (j in 0 until keyArray.length()) {
                                keyArray.optString(j)
                                    .takeIf { it.isNotBlank() }
                                    ?.let { add(unquoteSegment(it)) }
                            }
                        }
                        if (segments.isNotEmpty()) {
                            add(
                                IndexField(
                                    name = segments.joinToString("."),
                                    ascending = !entry.optString("direction").equals("desc", ignoreCase = true),
                                ),
                            )
                        }
                    }
                }
                // Legacy: plain string array
                is String -> entry.takeIf { it.isNotBlank() }?.let { add(IndexField(unquoteSegment(it))) }
            }
        }
    }
}

/**
 * Whether an existing index's keys exactly match the requested definition
 * (same fields, same order, same directions).
 */
internal fun indexDefinitionsMatch(existing: List<IndexField>, requested: List<IndexField>): Boolean =
    existing == requested

/**
 * Undoes DQL backtick-quoting for one stored path segment. Only segments that are
 * actually quoted (older SDKs wrapped them; 5.1 stores raw values) are unwrapped,
 * and escaped double-backticks inside them are collapsed. Raw segments pass through
 * untouched.
 */
private fun unquoteSegment(segment: String): String {
    if (segment.length < 2 || !segment.startsWith("`") || !segment.endsWith("`")) return segment
    return segment.substring(1, segment.length - 1).replace("``", "`")
}

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

    override suspend fun createIndex(collection: String, fields: List<IndexField>) {
        val ditto = activeDitto ?: throw IllegalStateException("No active Ditto instance")
        val cleaned = normalizeIndexFields(fields)
        val safeName = buildIndexName(collection, cleaned)

        // IF NOT EXISTS only compares index NAMES — it silently succeeds without
        // changing anything when an index of the same name exists with a different
        // definition (e.g. flipped sort direction, or a field-name collision after
        // sanitization). Detect that case and surface it instead of no-oping.
        // Fail-closed: if this read fails, the error propagates rather than risking
        // the silent no-op this check exists to prevent.
        val existing = ditto.store.execute(
            "SELECT * FROM system:indexes WHERE _id = :id",
            mapOf("id" to "$collection.$safeName"),
        ) { result ->
            result.items.firstOrNull()?.let { item ->
                // Dematerialize in finally so a parse throw can't leak the native item.
                try {
                    parseIndexFields(JSONObject(item.jsonString()))
                } finally {
                    item.dematerialize()
                }
            }
        }

        if (existing != null) {
            if (indexDefinitionsMatch(existing, cleaned)) {
                refreshInternal()
                return // identical index already exists — idempotent success
            }
            throw IllegalStateException(
                "An index named '$safeName' already exists on '$collection' with a different " +
                    "field definition. Drop it before re-creating.",
            )
        }

        ditto.store.execute(buildCreateIndexDql(collection, cleaned))
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
            ditto.store.execute(QUERY_COLLECTIONS) { result ->
                result.items.mapNotNull { item ->
                    try {
                        runCatching { JSONObject(item.jsonString()).optString("_id") }
                            .getOrNull()
                            ?.takeIf { it.isNotBlank() && !it.startsWith("__") }
                    } finally {
                        item.dematerialize()
                    }
                }
            }
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
            ditto.store.execute(QUERY_INDEXES) { result ->
                for (item in result.items) {
                    runCatching {
                        val json = JSONObject(item.jsonString())
                        val id = json.optString("_id").takeIf { it.isNotBlank() } ?: return@runCatching
                        val collection = json.optString("collection").takeIf { it.isNotBlank() } ?: return@runCatching
                        val fields = parseIndexFields(json).map { it.name }
                        map.getOrPut(collection) { mutableListOf() }
                            .add(DittoIndex(id = id, collection = collection, fields = fields))
                    }
                    item.dematerialize()
                }
            }
        }
        return map
    }

    private suspend fun fetchDocCounts(ditto: Ditto, names: List<String>): Map<String, Int> {
        val counts = mutableMapOf<String, Int>()
        for (name in names) {
            runCatching {
                val count = ditto.store.execute(buildDocCountQuery(name)) { result ->
                    result.items.firstOrNull()?.let { item ->
                        try {
                            JSONObject(item.jsonString()).optInt("numDocs", 0)
                        } finally {
                            item.dematerialize()
                        }
                    } ?: 0
                }
                counts[name] = count
            }
            // One failing collection doesn't block others
        }
        return counts
    }
}
