package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoCollection
import com.costoda.dittoedgestudio.domain.model.IndexField
import com.ditto.kotlin.Ditto
import kotlinx.coroutines.flow.StateFlow

interface CollectionsRepository {
    /** Live list of user collections, updated by the Ditto store observer. */
    val collections: StateFlow<List<DittoCollection>>

    /** Start observing the Ditto store. Call after a Ditto instance is ready. */
    fun startObserving(ditto: Ditto)

    /** Stop observing and clear state. Call when closing the database. */
    fun stopObserving()

    /** Manually re-fetch all collection data (for pull-to-refresh). */
    suspend fun refresh()

    /**
     * Create an index on a collection. Two or more [fields] create a composite
     * index (Ditto SDK 5.1+).
     * Index is named `idx_{collection}_{field…}` with dots/spaces/dashes → underscores.
     */
    suspend fun createIndex(collection: String, fields: List<IndexField>)
}
