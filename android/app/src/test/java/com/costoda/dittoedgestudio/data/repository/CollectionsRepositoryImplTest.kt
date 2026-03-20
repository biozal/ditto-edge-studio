package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoIndex
import org.junit.Assert.assertEquals
import org.junit.Test

class CollectionsRepositoryImplTest {

    @Test
    fun `stopObserving without startObserving does not crash`() {
        val repo = CollectionsRepositoryImpl(kotlinx.coroutines.test.TestScope())
        repo.stopObserving() // Must not throw
    }

    @Test
    fun `stopObserving clears collections StateFlow`() {
        val repo = CollectionsRepositoryImpl(kotlinx.coroutines.test.TestScope())
        repo.stopObserving()
        assertEquals(emptyList<Any>(), repo.collections.value)
    }

    @Test
    fun `DittoIndex displayName strips collection prefix`() {
        val index = DittoIndex(
            id = "comments.idx_comments_movie_id",
            collection = "comments",
            fields = listOf("movie_id"),
        )
        assertEquals("idx_comments_movie_id", index.displayName)
    }

    @Test
    fun `DittoIndex displayName returns id unchanged when no dot present`() {
        val index = DittoIndex(
            id = "orphan_index",
            collection = "comments",
            fields = listOf("id"),
        )
        assertEquals("orphan_index", index.displayName)
    }

    @Test
    fun `DittoIndex displayFields strips backtick wrapping`() {
        val index = DittoIndex(
            id = "movies.idx_movies_year",
            collection = "movies",
            fields = listOf("`movie_id`", "`year`"),
        )
        assertEquals(listOf("movie_id", "year"), index.displayFields)
    }

    @Test
    fun `DittoIndex displayFields leaves plain fields unchanged`() {
        val index = DittoIndex(
            id = "movies.idx_movies_title",
            collection = "movies",
            fields = listOf("title", "year"),
        )
        assertEquals(listOf("title", "year"), index.displayFields)
    }

    @Test
    fun `DittoIndex displayName with multiple dots keeps only first prefix stripped`() {
        val index = DittoIndex(
            id = "my.collection.idx_name",
            collection = "my",
            fields = emptyList(),
        )
        // substringAfter('.', id) returns "collection.idx_name"
        assertEquals("collection.idx_name", index.displayName)
    }
}
