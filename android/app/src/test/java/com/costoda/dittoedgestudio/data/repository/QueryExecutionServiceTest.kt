package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.QueryResult
import io.mockk.Runs
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.just
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertSame
import org.junit.Test

class QueryExecutionServiceTest {

    private val local: LocalQueryExecutionService = mockk(relaxed = true)
    private val http: HttpQueryExecutionService = mockk(relaxed = true)
    private val facade = QueryExecutionService(local = local, http = http)

    private val localResult = QueryResult(emptyList(), 0, 1L)
    private val httpResult = QueryResult(emptyList(), 0, 2L)

    @Test
    fun `mode Local delegates to local service only`() = runBlocking {
        coEvery { local.execute("SELECT 1") } returns localResult

        val result = facade.execute("SELECT 1", mode = "Local")

        assertSame(localResult, result)
        coVerify(exactly = 1) { local.execute("SELECT 1") }
        coVerify(exactly = 0) { http.execute(any()) }
    }

    @Test
    fun `mode HTTP delegates to http service only`() = runBlocking {
        coEvery { http.execute("SELECT 1") } returns httpResult

        val result = facade.execute("SELECT 1", mode = "HTTP")

        assertSame(httpResult, result)
        coVerify(exactly = 1) { http.execute("SELECT 1") }
        coVerify(exactly = 0) { local.execute(any()) }
    }

    @Test
    fun `explain always delegates to local`() = runBlocking {
        coEvery { local.explain("SELECT 1") } returns localResult

        val result = facade.explain("SELECT 1")

        assertSame(localResult, result)
        coVerify(exactly = 1) { local.explain("SELECT 1") }
        coVerify(exactly = 0) { http.execute(any()) }
    }

    @Test
    fun `unknown mode falls back to local`() = runBlocking {
        coEvery { local.execute("SELECT 1") } returns localResult

        val result = facade.execute("SELECT 1", mode = "WAT")

        assertSame(localResult, result)
        coVerify(exactly = 1) { local.execute("SELECT 1") }
        coVerify(exactly = 0) { http.execute(any()) }
    }

    @Test
    fun `default mode is Local for backwards compatibility`() = runBlocking {
        coEvery { local.execute("SELECT 1") } returns localResult

        val result = facade.execute("SELECT 1")

        assertSame(localResult, result)
    }
}
