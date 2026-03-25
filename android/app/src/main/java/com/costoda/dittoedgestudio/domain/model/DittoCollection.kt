package com.costoda.dittoedgestudio.domain.model

data class DittoCollection(
    val name: String,
    val docCount: Int? = null,
    val indexes: List<DittoIndex> = emptyList(),
)

data class DittoIndex(
    val id: String,
    val collection: String,
    val fields: List<String>,
) {
    /** Strips the "collectionName." prefix for display. */
    val displayName: String
        get() = id.substringAfter('.', id)

    /** Fields with backticks stripped, e.g. "`movie_id`" → "movie_id" */
    val displayFields: List<String>
        get() = fields.map { it.removePrefix("`").removeSuffix("`") }
}
