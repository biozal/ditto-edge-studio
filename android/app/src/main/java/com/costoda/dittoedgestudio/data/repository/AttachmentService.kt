package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import java.io.File

/**
 * High-level attachment operations exposed to the VM and UI.
 *
 * Wraps [AttachmentStoreGateway] — the production impl delegates to
 * `ditto.store.newAttachment` / `ditto.store.fetchAttachment`; tests substitute a fake.
 *
 * Deletion is **not** implemented here. Attachment deletion in Ditto is a DQL
 * `UPDATE <c> SET <field> = NULL WHERE _id = ...` issued through the existing
 * [QueryExecutionService] facade — see the `DeleteAttachmentSheet` UI for that codepath.
 */
class AttachmentService internal constructor(
    private val gateway: AttachmentStoreGateway,
    private val cacheDirProvider: () -> File,
) {

    /** Uploads [path] to Ditto and returns the new attachment's id. */
    suspend fun createFromFile(path: String, metadata: Map<String, String>): String =
        gateway.newAttachment(path, metadata)

    /**
     * Downloads the attachment described by [info] to `cacheDir/attachments/<id>`.
     * Idempotent: if a cached file with matching length already exists, the gateway
     * is not invoked.
     */
    suspend fun fetchToCache(info: AttachmentInfo): File {
        val cacheRoot = File(cacheDirProvider(), "attachments").apply { mkdirs() }
        val target = File(cacheRoot, info.id)
        if (target.exists() && target.length() == info.len) return target
        // Defensive: stale cache with wrong length — overwrite.
        if (target.exists()) target.delete()

        val tokenMap: Map<String, Any> = mapOf(
            "id" to info.id,
            "len" to info.len,
            "metadata" to info.metadata,
        )
        gateway.fetchAttachment(tokenMap).use { stream ->
            target.outputStream().use { out -> stream.copyTo(out) }
        }
        return target
    }
}
