package com.costoda.dittoedgestudio.data.repository

import java.io.InputStream

/**
 * Test seam over the live Ditto SDK's attachment operations on [com.ditto.kotlin.DittoStore].
 *
 * Unit tests substitute a fake; the production implementation in [com.costoda.dittoedgestudio.data.di.dataModule]
 * delegates to `ditto.store.newAttachment(...)` and `ditto.store.fetchAttachment(...)`.
 *
 * The gateway intentionally trades the rich SDK types for plain Kotlin (`Map<String, String>`
 * for metadata, `InputStream` for download streams) so the test layer can avoid pulling in
 * the SDK's CBOR serialization helpers.
 */
interface AttachmentStoreGateway {
    /** Uploads a file at [path] to Ditto. Returns the new attachment's id. */
    suspend fun newAttachment(path: String, metadata: Map<String, String>): String

    /**
     * Creates an attachment from [path] and immediately links it to a document via a
     * DQL UPDATE, keeping the [DittoAttachment] object in scope so it can be bound as a
     * typed CBOR argument rather than a raw string literal.
     *
     * This combined method exists because the Kotlin SDK's `execute(query, Map<String,Any?>)`
     * overload calls `toCborOrThrow()` which does NOT accept [com.ditto.kotlin.DittoAttachment]
     * as a value type. The only correct binding path is the
     * `execute(query, DittoCborSerializable.Dictionary)` overload with the attachment converted
     * via `DittoAttachment.toDittoCbor()` — which requires the attachment object to still be
     * in scope after `newAttachment` returns. Keeping both steps inside the gateway avoids
     * leaking SDK-internal types through the service boundary.
     *
     * @param path Absolute path to the local file to attach.
     * @param metadata Attachment metadata (e.g. `{"type": "image/png"}`).
     * @param collection Ditto collection name.
     * @param fieldName Document field to set.
     * @param documentId The `_id` of the target document (used verbatim in the WHERE clause).
     */
    suspend fun createAndLink(
        path: String,
        metadata: Map<String, String>,
        collection: String,
        fieldName: String,
        documentId: String,
    )

    /**
     * Fetches an attachment by token map (the same shape the JSON result row carries).
     * Returns an [InputStream] over the attachment bytes; caller is responsible for closing.
     * Throws if the attachment was deleted before the fetch completed.
     */
    suspend fun fetchAttachment(tokenMap: Map<String, Any>): InputStream
}
