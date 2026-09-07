package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DqlGeneratorTest {

    @Test
    fun `select with fields`() {
        assertEquals(
            "SELECT _id, name FROM cars",
            DqlGenerator.generateSelect("cars", listOf("_id", "name")),
        )
        assertEquals("SELECT * FROM cars", DqlGenerator.generateSelectAll("cars"))
    }

    @Test
    fun `insert builds typed placeholders from sample document`() {
        val sample = mapOf(
            "_id" to "abc",
            "name" to "ford",
            "year" to 2020,
            "active" to true,
            "deleted" to null,
            "meta" to mapOf("a" to 1),
        )
        val fields = DqlGenerator.fieldNames(sample)
        assertEquals(
            "INSERT INTO cars DOCUMENTS ({ \"_id\": \"<document-id>\", \"active\": true, \"deleted\": null, " +
                "\"meta\": {}, \"name\": \"<value>\", \"year\": 0 })",
            DqlGenerator.generateInsert("cars", fields, sample),
        )
    }

    @Test
    fun `update excludes _id from SET clause`() {
        val fields = listOf("_id", "name")
        assertEquals(
            "UPDATE cars SET name = \"<value>\" WHERE _id = '<document-id>'",
            DqlGenerator.generateUpdate("cars", fields),
        )
    }

    @Test
    fun `delete and evict templates`() {
        assertEquals("DELETE FROM cars WHERE _id = '<document-id>'", DqlGenerator.generateDelete("cars"))
        assertEquals("EVICT FROM cars WHERE _id = '<document-id>'", DqlGenerator.generateEvict("cars"))
    }

    @Test
    fun `collection name extracted from query, case-insensitive FROM`() {
        assertEquals("cars", DqlGenerator.collectionName("SELECT * FROM cars WHERE year > 2"))
        assertEquals("Cars", DqlGenerator.collectionName("select * from Cars"))
        assertNull(DqlGenerator.collectionName("INSERT INTO cars"))
    }

    @Test
    fun `field names sorted with id first and missing id not injected`() {
        val doc = mapOf("z" to 1, "a" to 2, "_id" to "x")
        assertEquals(listOf("_id", "a", "z"), DqlGenerator.fieldNames(doc))
        assertEquals(listOf("a", "z"), DqlGenerator.fieldNames(mapOf("z" to 1, "a" to 2)))
        assertEquals(emptyList<String>(), DqlGenerator.fieldNames(null))
    }
}
