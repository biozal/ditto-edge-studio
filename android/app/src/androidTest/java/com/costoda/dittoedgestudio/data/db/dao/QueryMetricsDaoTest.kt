package com.costoda.dittoedgestudio.data.db.dao

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.data.db.AppDatabase
import com.costoda.dittoedgestudio.data.db.entity.QueryMetricsEntity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for [QueryMetricsDao] (in-memory Room, no SQLCipher).
 *
 * Unlike the other DAO tests, no parent `DatabaseConfigEntity` row is needed:
 * schema v6 dropped the `history_id` foreign key, so `query_metrics` has no FK
 * constraints at all (history housekeeping must never cascade-wipe captures).
 */
@RunWith(AndroidJUnit4::class)
class QueryMetricsDaoTest {

    private lateinit var db: AppDatabase
    private lateinit var dao: QueryMetricsDao

    @Before
    fun setup() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            AppDatabase::class.java
        ).allowMainThreadQueries().build()
        dao = db.queryMetricsDao()
    }

    @After
    fun tearDown() = db.close()

    @Test
    fun insertAndTrim_evictsOldestBeyondKeep() = runTest {
        // Insert 205 rows with strictly increasing captured_at; cap is 200.
        for (i in 1..205) {
            dao.insertAndTrim(buildRow(databaseId = "db-1", capturedAt = i.toLong()), keep = 200)
        }

        val survivors = dao.getAllByDatabase("db-1")
        assertEquals(200, survivors.size)
        // Exactly the 200 NEWEST survive: captured_at 6..205 (1..5 evicted).
        assertTrue(survivors.none { it.capturedAt < 6L })
        assertEquals(205L, survivors.first().capturedAt) // DESC order
        assertEquals(6L, survivors.last().capturedAt)
    }

    @Test
    fun insertAndTrim_isScopedPerDatabase() = runTest {
        for (i in 1..205) {
            dao.insertAndTrim(buildRow(databaseId = "db-1", capturedAt = i.toLong()), keep = 200)
        }
        dao.insertAndTrim(buildRow(databaseId = "db-2", capturedAt = 1L), keep = 200)

        // Trimming db-1 must never evict db-2's rows.
        assertEquals(200, dao.getAllByDatabase("db-1").size)
        assertEquals(1, dao.getAllByDatabase("db-2").size)
    }

    @Test
    fun getById_returnsTheExactRow() = runTest {
        val id = dao.insert(buildRow(databaseId = "db-1", historyId = 7L, capturedAt = 100L))

        val row = dao.getById(id)
        assertNotNull(row)
        assertEquals(id, row!!.id)
        assertEquals(7L, row.historyId)
        assertEquals("db-1", row.databaseId)
    }

    @Test
    fun getById_returnsNullForUnknownId() = runTest {
        assertNull(dao.getById(999L))
    }

    @Test
    fun getAllByDatabase_filtersAndOrdersDescending() = runTest {
        dao.insert(buildRow(databaseId = "db-1", capturedAt = 100L, queryText = "Q1"))
        dao.insert(buildRow(databaseId = "db-2", capturedAt = 200L, queryText = "Q2"))
        dao.insert(buildRow(databaseId = "db-1", capturedAt = 300L, queryText = "Q3"))

        val results = dao.getAllByDatabase("db-1")
        assertEquals(listOf("Q3", "Q1"), results.map { it.queryText })
    }

    @Test
    fun observeByDatabase_emitsPerDatabaseAndUpdatesLive() = runTest {
        dao.insert(buildRow(databaseId = "db-1", capturedAt = 100L, queryText = "Q1"))
        dao.insert(buildRow(databaseId = "db-2", capturedAt = 200L, queryText = "Q2"))

        val first = dao.observeByDatabase("db-1").first()
        assertEquals(listOf("Q1"), first.map { it.queryText })
    }

    @Test
    fun deleteAllByDatabase_removesOnlyThatDatabase() = runTest {
        dao.insert(buildRow(databaseId = "db-1", capturedAt = 100L))
        dao.insert(buildRow(databaseId = "db-1", capturedAt = 200L))
        dao.insert(buildRow(databaseId = "db-2", capturedAt = 300L))

        dao.deleteAllByDatabase("db-1")

        assertEquals(0, dao.getAllByDatabase("db-1").size)
        assertEquals(1, dao.getAllByDatabase("db-2").size)
    }

    private fun buildRow(
        databaseId: String,
        capturedAt: Long,
        historyId: Long = 1L,
        queryText: String = "SELECT * FROM c",
    ) = QueryMetricsEntity(
        historyId = historyId,
        databaseId = databaseId,
        executionTimeMs = 7L,
        docsExamined = 3,
        docsReturned = 3,
        indexesUsed = "[]",
        bytesRead = 0L,
        explainPlan = null,
        capturedAt = capturedAt,
        queryText = queryText,
    )
}
