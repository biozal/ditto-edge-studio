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
     * Fetches an attachment by token map (the same shape the JSON result row carries).
     * Returns an [InputStream] over the attachment bytes; caller is responsible for closing.
     * Throws if the attachment was deleted before the fetch completed.
     */
    suspend fun fetchAttachment(tokenMap: Map<String, Any>): InputStream
}
