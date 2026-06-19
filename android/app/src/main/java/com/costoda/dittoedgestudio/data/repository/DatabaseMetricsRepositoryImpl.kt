package com.costoda.dittoedgestudio.data.repository

import android.util.Log
import com.costoda.dittoedgestudio.domain.model.CollectionPayloadInfo
import com.costoda.dittoedgestudio.domain.model.DatabaseMetrics
import com.costoda.dittoedgestudio.domain.model.StorageCategory
import com.costoda.dittoedgestudio.domain.model.StorageCategoryKey
import com.ditto.kotlin.Ditto
import com.ditto.kotlin.DittoDiskUsageItem
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

class DatabaseMetricsRepositoryImpl : DatabaseMetricsRepository {

    override suspend fun snapshot(ditto: Ditto): DatabaseMetrics = withContext(Dispatchers.IO) {
        val root: DittoDiskUsageItem = ditto.diskUsage.item
        val flat = flattenTree(root)
        val storage = categorize(flat)
        val collections = computeCollectionBreakdown(ditto)
        DatabaseMetrics(
            capturedAt = System.currentTimeMillis(),
            storage = storage,
            collections = collections,
        )
    }

    private fun flattenTree(item: DittoDiskUsageItem): List<Pair<String, Long>> {
        val out = ArrayList<Pair<String, Long>>()
        flattenInto(item, out)
        return out
    }

    private fun flattenInto(item: DittoDiskUsageItem, out: MutableList<Pair<String, Long>>) {
        out.add(item.path to item.sizeInBytes)
        item.childItems?.forEach { flattenInto(it, out) }
    }

    private suspend fun computeCollectionBreakdown(ditto: Ditto): List<CollectionPayloadInfo> {
        // We query `__collections` instead of `system:collections` because under SDK
        // 5.1.0-preview.1 on Android the `system:collections` virtual table only returns
        // rows on the first execute() call per Ditto lifetime — subsequent calls return
        // an empty result with no error. Confirmed via diagnostic logging on 2026-06-19
        // against a populated store: first refresh found 3 collections, second returned 0.
        //
        // Attempted downgrade to 5.0.1 to test if it fixed the bug — but downgrading
        // across an on-disk schema migration is irreversible (DittoCore::new throws
        // "Failed to determine Backend version"). So 5.1.0-preview.1 is the pinned
        // version and `__collections` is the workaround until the SDK bug is fixed.
        //
        // `__collections` is the same source CollectionsRepository observes for the
        // sidebar — proven to behave identically across repeat queries. The id of each
        // row in `__collections` is the collection name (exposed as `_id`). Unlike the
        // sidebar we keep system-prefixed entries (`__presence`, `__feature_flags`)
        // because the metrics view is intended to account for *all* on-disk payload.
        val names: List<String> = try {
            ditto.store.execute("SELECT * FROM __collections") { result ->
                result.items.mapNotNull { item ->
                    val name = runCatching {
                        JSONObject(item.jsonString()).optString("_id").takeIf { it.isNotBlank() }
                    }.getOrNull()
                    item.dematerialize()
                    name
                }
            }
        } catch (c: CancellationException) {
            throw c
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to list __collections", t)
            return emptyList()
        }
        Log.i(TAG, "Found ${names.size} collection names: $names")

        val breakdown = names.mapNotNull { name ->
            try {
                val escaped = name.replace("`", "``")
                ditto.store.execute("SELECT * FROM `$escaped`") { result ->
                    var cborBytes = 0L
                    var docCount = 0
                    for (item in result.items) {
                        cborBytes += item.cborData().size.toLong()
                        docCount++
                        item.dematerialize()
                    }
                    Log.i(TAG, "Collection '$name': $docCount docs, $cborBytes bytes")
                    CollectionPayloadInfo(
                        name = name,
                        documentCount = docCount,
                        cborPayloadBytes = cborBytes,
                    )
                }
            } catch (c: CancellationException) {
                throw c
            } catch (t: Throwable) {
                Log.w(TAG, "Skipping collection '$name': ${t.message}")
                null
            }
        }
        return breakdown.sortedByDescending { it.cborPayloadBytes }
    }

    private companion object {
        const val TAG = "DatabaseMetricsRepo"
    }
}

/**
 * Pure categorisation of a flat (path, sizeInBytes) list into the seven storage buckets.
 *
 * Exposed at package level so unit tests can drive it without a live [Ditto] instance.
 *
 * Categorisation order matters: the `-wal` / `-shm` suffix is checked first, because Ditto
 * stores SQLite journal files inside every ditto_xxx directory; matching on the parent
 * directory first would double-count them into Store / Replication / etc.
 */
internal fun categorize(files: List<Pair<String, Long>>): List<StorageCategory> {
    var store = 0L
    var replication = 0L
    var attachments = 0L
    var auth = 0L
    var walShm = 0L
    var logs = 0L
    var other = 0L

    for ((rawPath, size) in files) {
        val p = rawPath.lowercase()
        when {
            p.endsWith("-wal") || p.endsWith("-shm") -> walShm += size
            "/ditto_logs/" in p || p.endsWith(".log") || p.endsWith(".log.gz") -> logs += size
            "/ditto_store/" in p -> store += size
            "/ditto_attachments/" in p -> attachments += size
            // Matches both ditto_auth/ and ditto_auth_tmp/.
            "/ditto_auth" in p -> auth += size
            "/ditto_replication/" in p -> replication += size
            else -> other += size
        }
    }

    return listOf(
        StorageCategory(StorageCategoryKey.STORE, store),
        StorageCategory(StorageCategoryKey.REPLICATION, replication),
        StorageCategory(StorageCategoryKey.ATTACHMENTS, attachments),
        StorageCategory(StorageCategoryKey.AUTH, auth),
        StorageCategory(StorageCategoryKey.WAL_SHM, walShm),
        StorageCategory(StorageCategoryKey.LOGS, logs),
        StorageCategory(StorageCategoryKey.OTHER, other),
    )
}
