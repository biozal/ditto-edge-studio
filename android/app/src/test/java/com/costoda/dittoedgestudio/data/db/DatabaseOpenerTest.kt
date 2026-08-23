package com.costoda.dittoedgestudio.data.db

import android.content.Context
import android.database.Cursor
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import io.mockk.MockKAnnotations
import io.mockk.clearAllMocks
import io.mockk.every
import io.mockk.impl.annotations.MockK
import io.mockk.mockk
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class DatabaseOpenerTest {

    @MockK
    private lateinit var context: Context

    @MockK
    private lateinit var keyManager: DatabaseKeyManager

    private val key = ByteArray(32) { it.toByte() }

    @Before
    fun setup() {
        MockKAnnotations.init(this)
        every { keyManager.getOrCreateKey() } returns key
    }

    @After
    fun tearDown() = clearAllMocks()

    @Test
    fun `openAndProbe returns KeyFailure with summary when SELECT 1 throws`() {
        // Simulates the SQLCipher decrypt-failure path: build() succeeds but the
        // probe query raises because the passphrase doesn't match the file.
        val sqlDb = mockk<SupportSQLiteDatabase>()
        every { sqlDb.query(any<String>()) } throws IllegalStateException("file is not a database")
        val openHelper = mockk<SupportSQLiteOpenHelper>()
        every { openHelper.readableDatabase } returns sqlDb
        val db = mockk<AppDatabase>()
        every { db.openHelper } returns openHelper

        val opener = DatabaseOpener(context, keyManager, factory = { _, _ -> db })
        val result = opener.openAndProbe()

        assertTrue(
            "Expected KeyFailure, got $result",
            result is DatabaseOpenResult.KeyFailure,
        )
        val failure = result as DatabaseOpenResult.KeyFailure
        // errorSummary includes the throwable class + message for clipboard support
        assertTrue(failure.errorSummary.contains("IllegalStateException"))
        assertTrue(failure.errorSummary.contains("file is not a database"))
    }

    @Test
    fun `openAndProbe returns Ok when probe succeeds`() {
        val cursor = mockk<Cursor>(relaxed = true)
        every { cursor.moveToFirst() } returns true
        val sqlDb = mockk<SupportSQLiteDatabase>()
        every { sqlDb.query("SELECT 1") } returns cursor
        val openHelper = mockk<SupportSQLiteOpenHelper>()
        every { openHelper.readableDatabase } returns sqlDb
        val db = mockk<AppDatabase>()
        every { db.openHelper } returns openHelper

        val opener = DatabaseOpener(context, keyManager, factory = { _, _ -> db })
        val result = opener.openAndProbe()

        assertTrue(result is DatabaseOpenResult.Ok)
        assertSame(db, (result as DatabaseOpenResult.Ok).db)
    }

    @Test
    fun `openAndProbe caches result across repeated calls`() {
        val cursor = mockk<Cursor>(relaxed = true)
        every { cursor.moveToFirst() } returns true
        val sqlDb = mockk<SupportSQLiteDatabase>()
        every { sqlDb.query("SELECT 1") } returns cursor
        val openHelper = mockk<SupportSQLiteOpenHelper>()
        every { openHelper.readableDatabase } returns sqlDb
        val db = mockk<AppDatabase>()
        every { db.openHelper } returns openHelper

        var factoryCalls = 0
        val opener = DatabaseOpener(context, keyManager, factory = { _, _ ->
            factoryCalls++
            db
        })

        val first = opener.openAndProbe()
        val second = opener.openAndProbe()
        assertEquals(1, factoryCalls)
        assertSame(first, second)
    }

    @Test
    fun `invalidate forces a fresh open on the next call`() {
        val cursor = mockk<Cursor>(relaxed = true)
        every { cursor.moveToFirst() } returns true
        val sqlDb = mockk<SupportSQLiteDatabase>()
        every { sqlDb.query("SELECT 1") } returns cursor
        val openHelper = mockk<SupportSQLiteOpenHelper>()
        every { openHelper.readableDatabase } returns sqlDb
        val db = mockk<AppDatabase>()
        every { db.openHelper } returns openHelper

        var factoryCalls = 0
        val opener = DatabaseOpener(context, keyManager, factory = { _, _ ->
            factoryCalls++
            db
        })

        opener.openAndProbe()
        opener.invalidate()
        opener.openAndProbe()
        assertEquals(2, factoryCalls)
    }
}
