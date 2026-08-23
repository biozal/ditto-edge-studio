package com.costoda.dittoedgestudio.domain.model

/**
 * In-result-row representation of a Ditto attachment token. The actual token contents
 * (id/len/metadata) come from the JSON Ditto returns in a query item; [fieldName] is
 * the parent document key that holds the token.
 */
data class AttachmentInfo(
    val id: String,
    val len: Long,
    val fieldName: String,
    val metadata: Map<String, String>,
) {
    companion object {
        /**
         * Structural detection of Ditto attachment tokens in a parsed document map.
         * A field is treated as an attachment when its value is a [Map] with exactly the
         * three keys `id` (String), `len` (Number), and `metadata` (Map). Mirrors
         * SwiftUI's `AttachmentInfo.detectTokens(in:)`.
         */
        fun detectTokens(doc: Map<String, Any?>): List<AttachmentInfo> {
            val out = mutableListOf<AttachmentInfo>()
            for ((field, value) in doc) {
                val token = asAttachmentToken(field, value)
                if (token != null) out += token
            }
            return out
        }

        fun detectTokens(docs: List<Map<String, Any?>>): List<AttachmentInfo> =
            docs.flatMap { detectTokens(it) }

        @Suppress("UNCHECKED_CAST")
        private fun asAttachmentToken(field: String, value: Any?): AttachmentInfo? {
            val map = value as? Map<*, *> ?: return null
            val id = map["id"] as? String ?: return null
            val len = (map["len"] as? Number)?.toLong() ?: return null
            val metaRaw = map["metadata"] as? Map<*, *> ?: return null
            val metadata = metaRaw.entries
                .mapNotNull { (k, v) ->
                    val ks = k as? String ?: return@mapNotNull null
                    ks to (v?.toString() ?: "")
                }
                .toMap()
            return AttachmentInfo(id = id, len = len, fieldName = field, metadata = metadata)
        }
    }
}
