package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.ditto.kotlin.serialization.DittoCborSerializable
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject

/**
 * Imports JSON documents into a Ditto collection (port of SwiftUI's `ImportService`).
 *
 * Semantics mirrored exactly:
 * - Input must be a JSON array of objects; every object needs an `_id` field.
 * - Batches of 50 documents, `deserialize_json(:docN)` placeholders, per Ditto docs.
 * - `REGULAR` upserts (`ON ID CONFLICT DO UPDATE`); `INITIAL` uses `WITH INITIAL DOCUMENTS`.
 * - A failed batch falls back to per-document inserts so partial success is preserved.
 */
class JsonImportService(private val dittoManager: DittoManager) {

    enum class InsertType { REGULAR, INITIAL }

    data class ImportResult(
        val successCount: Int,
        val failureCount: Int,
        val errors: List<String>,
    )

    class ImportException(message: String) : Exception(message)

    /** Parses and validates the file: array of objects, each with an `_id`. */
    fun validate(jsonData: String): List<JsonObject> {
        val parsed = try {
            Json.parseToJsonElement(jsonData)
        } catch (e: Exception) {
            throw ImportException("File must contain an array of JSON objects")
        }
        val array = try {
            parsed.jsonArray
        } catch (e: Exception) {
            throw ImportException("File must contain an array of JSON objects")
        }
        array.forEachIndexed { index, element ->
            val obj = try {
                element.jsonObject
            } catch (e: Exception) {
                throw ImportException("Document at index $index is not a JSON object")
            }
            if (obj["_id"] == null) {
                throw ImportException("Document at index $index is missing required '_id' field")
            }
        }
        return array.map { it.jsonObject }
    }

    suspend fun importData(
        documentData: String,
        collection: String,
        insertType: InsertType = InsertType.REGULAR,
        onProgress: (current: Int, total: Int, currentDocumentId: String?) -> Unit = { _, _, _ -> },
    ): ImportResult = withContext(Dispatchers.IO) {
        // Validate collection name to prevent DQL injection (SwiftUI parity).
        if (!collection.all { it.isLetterOrDigit() || it == '_' }) {
            throw ImportException(
                "Collection name contains invalid characters. " +
                    "Only letters, numbers, and underscores are allowed.",
            )
        }
        val documents = validate(documentData)
        val ditto = dittoManager.currentInstance()
            ?: throw ImportException("No Ditto instance available")

        val total = documents.size
        var successCount = 0
        var failureCount = 0
        val errors = mutableListOf<String>()

        val batchSize = 50
        documents.chunked(batchSize).forEachIndexed { batchIndex, batch ->
            if (!currentCoroutineContext().isActive) return@withContext ImportResult(successCount, failureCount, errors)
            val batchStartIndex = batchIndex * batchSize
            try {
                val query = buildBatchInsertQuery(collection, batch.size, insertType)
                val arguments = DittoCborSerializable.Dictionary(
                    batch.mapIndexed { index, document ->
                        DittoCborSerializable.Utf8String("doc$index") to
                            DittoCborSerializable.Utf8String(document.toString())
                    }.toMap(),
                )
                ditto.store.execute(query, arguments)
                successCount += batch.size
                onProgress(batchStartIndex + batch.size, total, null)
            } catch (e: Exception) {
                // Batch failed — fall back to individual inserts to identify failures.
                batch.forEachIndexed { indexInBatch, document ->
                    val globalIndex = batchStartIndex + indexInBatch
                    val documentId = document["_id"]?.toString() ?: "unknown"
                    try {
                        val singleArgs = DittoCborSerializable.Dictionary(
                            mapOf(
                                DittoCborSerializable.Utf8String("jsonDoc") to
                                    DittoCborSerializable.Utf8String(document.toString()),
                            ),
                        )
                        ditto.store.execute(buildSingleInsertQuery(collection, insertType), singleArgs)
                        successCount += 1
                    } catch (single: Exception) {
                        failureCount += 1
                        errors.add("Document $documentId: ${single.message}")
                    }
                    onProgress(globalIndex + 1, total, documentId)
                }
            }
        }

        ImportResult(successCount, failureCount, errors)
    }

    // MARK: - Query builders (verbatim DQL shape from Swift's ImportService)

    private fun buildSingleInsertQuery(collection: String, insertType: InsertType): String =
        if (insertType == InsertType.INITIAL) {
            """
            INSERT INTO $collection
            INITIAL DOCUMENTS (deserialize_json(:jsonDoc))
            """.trimIndent()
        } else {
            """
            INSERT INTO $collection
            DOCUMENTS (deserialize_json(:jsonDoc))
            ON ID CONFLICT DO UPDATE
            """.trimIndent()
        }

    private fun buildBatchInsertQuery(collection: String, batchSize: Int, insertType: InsertType): String {
        val placeholders = (0 until batchSize).joinToString(", ") { "(deserialize_json(:doc$it))" }
        return if (insertType == InsertType.INITIAL) {
            """
            INSERT INTO $collection
            INITIAL DOCUMENTS $placeholders
            """.trimIndent()
        } else {
            """
            INSERT INTO $collection
            DOCUMENTS $placeholders
            ON ID CONFLICT DO UPDATE
            """.trimIndent()
        }
    }

}
