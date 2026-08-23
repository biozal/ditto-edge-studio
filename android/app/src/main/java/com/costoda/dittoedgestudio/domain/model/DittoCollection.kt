package com.costoda.dittoedgestudio.domain.model

data class DittoCollection(
    val name: String,
    val docCount: Int? = null,
    val indexes: List<DittoIndex> = emptyList(),
)

/** One key in a DQL index definition: a field path plus its sort direction.
 * Two or more keys form a composite index (Ditto SDK 5.1+). */
data class IndexField(
    val name: String,
    val ascending: Boolean = true,
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
