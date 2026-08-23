package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoIndex
import com.costoda.dittoedgestudio.domain.model.IndexField
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class CollectionsRepositoryImplTest {

    @Test
    fun `buildCreateIndexDql with single field produces single-key statement`() {
        val dql = buildCreateIndexDql("tasks", listOf(IndexField("status")))
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_tasks_status` ON `tasks` (`status` ASC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql with multiple fields produces composite index preserving order`() {
        val dql = buildCreateIndexDql(
            "tasks",
            listOf(
                IndexField("status", ascending = true),
                IndexField("createdAt", ascending = false),
            ),
        )
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_tasks_status_createdAt` ON `tasks` (`status` ASC, `createdAt` DESC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql quotes each path segment so dotted and dashed fields parse`() {
        val dql = buildCreateIndexDql(
            "users",
            listOf(IndexField("address.city"), IndexField("last-name")),
        )
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_users_address_city_last_name` ON `users` (`address`.`city` ASC, `last-name` ASC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql quotes fields containing spaces`() {
        val dql = buildCreateIndexDql("users", listOf(IndexField("last name")))
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_users_last_name` ON `users` (`last name` ASC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql escapes embedded backticks by doubling`() {
        val dql = buildCreateIndexDql("users", listOf(IndexField("we`ird")))
        assertTrue(dql.contains("(`we``ird` ASC)"))
    }

    @Test
    fun `buildCreateIndexDql quotes the index name so hostile field names cannot break the statement`() {
        // A backtick in a field name flows into the derived index name; unquoted it
        // would terminate the identifier and break (or inject into) the statement.
        val dql = buildCreateIndexDql("users", listOf(IndexField("we`ird")))
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_users_we``ird` ON `users` (`we``ird` ASC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql quotes index names containing parens`() {
        val dql = buildCreateIndexDql("tasks", listOf(IndexField("fn(x)")))
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_tasks_fn(x)` ON `tasks` (`fn(x)` ASC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql quotes index names containing quotes`() {
        val dql = buildCreateIndexDql("tasks", listOf(IndexField("it's")))
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_tasks_it's` ON `tasks` (`it's` ASC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql quotes index names containing spaces`() {
        val dql = buildCreateIndexDql("tasks", listOf(IndexField("last name")))
        assertTrue(dql.startsWith("CREATE INDEX IF NOT EXISTS `idx_tasks_last_name` ON "))
    }

    @Test
    fun `buildCreateIndexDql drops blank fields`() {
        val dql = buildCreateIndexDql(
            "tasks",
            listOf(IndexField("   "), IndexField(" status ")),
        )
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_tasks_status` ON `tasks` (`status` ASC)",
            dql,
        )
    }

    @Test
    fun `buildCreateIndexDql throws when all fields are blank`() {
        assertThrows(IllegalArgumentException::class.java) {
            buildCreateIndexDql("tasks", listOf(IndexField(""), IndexField("  ")))
        }
    }

    @Test
    fun `buildCreateIndexDql throws on empty field list`() {
        assertThrows(IllegalArgumentException::class.java) {
            buildCreateIndexDql("tasks", emptyList())
        }
    }

    @Test
    fun `buildCreateIndexDql quotes collection names containing spaces`() {
        val dql = buildCreateIndexDql("my collection", listOf(IndexField("status")))
        assertEquals(
            "CREATE INDEX IF NOT EXISTS `idx_my_collection_status` ON `my collection` (`status` ASC)",
            dql,
        )
    }

    // MARK: - buildDocCountQuery (per-collection COUNT(*) statement)

    @Test
    fun `buildDocCountQuery quotes a plain collection name`() {
        assertEquals(
            "SELECT COUNT(*) as numDocs FROM `tasks`",
            buildDocCountQuery("tasks"),
        )
    }

    @Test
    fun `buildDocCountQuery quotes collection names containing dots and spaces`() {
        // Bare interpolation would misparse `foo.bar` as a qualified identifier and
        // break on `foo bar` — the failure was silently swallowed into a null docCount.
        assertEquals(
            "SELECT COUNT(*) as numDocs FROM `foo.bar`",
            buildDocCountQuery("foo.bar"),
        )
        assertEquals(
            "SELECT COUNT(*) as numDocs FROM `foo bar`",
            buildDocCountQuery("foo bar"),
        )
    }

    @Test
    fun `buildDocCountQuery escapes embedded backticks by doubling`() {
        assertEquals(
            "SELECT COUNT(*) as numDocs FROM `we``ird`",
            buildDocCountQuery("we`ird"),
        )
    }

    // MARK: - parseIndexFields (system:indexes row parsing)

    @Test
    fun `parseIndexFields parses SDK 5-x object format with directions`() {
        val json = JSONObject(
            """
            {"fields": [
              {"direction": "asc", "key": ["status"]},
              {"direction": "desc", "key": ["createdAt"]}
            ]}
            """.trimIndent(),
        )
        assertEquals(
            listOf(IndexField("status", ascending = true), IndexField("createdAt", ascending = false)),
            parseIndexFields(json),
        )
    }

    @Test
    fun `parseIndexFields joins nested path segments with dots`() {
        val json = JSONObject(
            """{"fields": [{"direction": "asc", "key": ["properties", "engine", "type"]}]}""",
        )
        assertEquals(listOf(IndexField("properties.engine.type")), parseIndexFields(json))
    }

    @Test
    fun `parseIndexFields strips backticks emitted by older SDKs`() {
        val json = JSONObject(
            """{"fields": [{"direction": "desc", "key": ["`createdAt`"]}]}""",
        )
        assertEquals(listOf(IndexField("createdAt", ascending = false)), parseIndexFields(json))
    }

    @Test
    fun `parseIndexFields collapses escaped backticks only in quoted segments`() {
        val json = JSONObject(
            """{"fields": [{"direction": "asc", "key": ["`we``ird`", "we`ird"]}]}""",
        )
        // Quoted segment is unwrapped and un-escaped; raw 5.1 segment passes through.
        assertEquals(listOf(IndexField("we`ird.we`ird")), parseIndexFields(json))
    }

    @Test
    fun `parseIndexFields accepts legacy plain string arrays`() {
        val json = JSONObject("""{"fields": ["status", "`priority`"]}""")
        assertEquals(
            listOf(IndexField("status"), IndexField("priority")),
            parseIndexFields(json),
        )
    }

    @Test
    fun `parseIndexFields drops malformed entries`() {
        val json = JSONObject(
            """{"fields": [{"direction": "asc"}, {"key": []}, 42, {"direction": "asc", "key": ["ok"]}]}""",
        )
        assertEquals(listOf(IndexField("ok")), parseIndexFields(json))
    }

    @Test
    fun `parseIndexFields returns empty when fields missing`() {
        assertEquals(emptyList<IndexField>(), parseIndexFields(JSONObject("{}")))
    }

    // MARK: - indexDefinitionsMatch

    @Test
    fun `indexDefinitionsMatch identical definitions match`() {
        val a = listOf(IndexField("status"), IndexField("createdAt", ascending = false))
        assertTrue(indexDefinitionsMatch(a, a))
    }

    @Test
    fun `indexDefinitionsMatch flipped direction does not match`() {
        val existing = listOf(IndexField("status"), IndexField("createdAt", ascending = false))
        val requested = listOf(IndexField("status"), IndexField("createdAt", ascending = true))
        assertFalse(indexDefinitionsMatch(existing, requested))
    }

    @Test
    fun `indexDefinitionsMatch different order or count does not match`() {
        val a = listOf(IndexField("status"), IndexField("createdAt"))
        assertFalse(indexDefinitionsMatch(a, a.reversed()))
        assertFalse(indexDefinitionsMatch(a, a.dropLast(1)))
    }

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
