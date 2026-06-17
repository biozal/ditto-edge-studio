package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test

class HttpQueryExecutionServiceTest {

    private lateinit var server: MockWebServer
    private lateinit var json: Json
    private lateinit var client: OkHttpClient

    @Before
    fun setUp() {
        server = MockWebServer().apply { start() }
        json = Json { ignoreUnknownKeys = true }
        client = OkHttpClient()
    }

    @After
    fun tearDown() {
        server.shutdown()
    }

    /** Build a DittoDatabase whose `httpApiUrl` points at the running MockWebServer. */
    private fun database(allowUntrusted: Boolean = false): DittoDatabase {
        // host:port — the service prefixes "https://" so we strip the scheme here to
        // mirror the SwiftUI behavior. Both schemes are exercised by the negative-cert test.
        val hostPort = "${server.hostName}:${server.port}"
        return DittoDatabase(
            id = 1L,
            databaseId = "test-db",
            httpApiUrl = hostPort,
            httpApiKey = "test-key",
            allowUntrustedCerts = allowUntrusted,
        )
    }

    private fun service(db: DittoDatabase = database()): HttpQueryExecutionService =
        HttpQueryExecutionService(
            client = client,
            json = json,
            databaseProvider = { db },
            urlScheme = "http",
        )

    // ── happy-path: items response ───────────────────────────────────────────

    @Test
    fun `posts to v5_store_execute with bearer auth and statement body`() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"items":[{"_id":"a","name":"X"}]}""")
        )

        val result = service().execute("SELECT * FROM things")

        val recorded = server.takeRequest()
        assertEquals("POST", recorded.method)
        assertEquals("/api/v5/store/execute", recorded.path)
        assertEquals("Bearer test-key", recorded.getHeader("Authorization"))
        assertEquals("application/json", recorded.getHeader("Content-Type"))
        val sentBody = JSONObject(recorded.body.readUtf8())
        assertEquals("SELECT * FROM things", sentBody.getString("statement"))
        assertEquals(1, result.documents.size)
        assertEquals("a", result.documents[0]["_id"])
        assertEquals("X", result.documents[0]["name"])
        assertEquals(1, result.totalCount)
        assertTrue(result.executionTimeMs >= 0)
    }

    // ── mutation response: synthesises one doc per mutatedDocumentId + commitId sentinel ─

    @Test
    fun `mutatedDocumentIds yield synthetic docs plus commitId sentinel`() = runBlocking {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"mutatedDocumentIds":["abc","def"],"commitId":"c1"}"""
            )
        )

        val result = service().execute("UPDATE c SET x = 1")

        // 2 synthetic ID docs + 1 commitId sentinel doc = 3 rows total
        assertEquals(3, result.documents.size)
        assertEquals("abc", result.documents[0]["_id"])
        assertEquals("def", result.documents[1]["_id"])
        assertEquals("c1", result.documents[2]["commitId"])
    }

    @Test
    fun `mutatedDocumentIds without commitId yields only id docs`() = runBlocking {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"mutatedDocumentIds":["abc"]}"""
            )
        )

        val result = service().execute("UPDATE c SET x = 1")

        assertEquals(1, result.documents.size)
        assertEquals("abc", result.documents[0]["_id"])
    }

    // ── non-2xx surfaces as QueryExecutionException with body in message ────

    @Test
    fun `non-2xx response throws QueryExecutionException with body`() = runBlocking {
        server.enqueue(
            MockResponse().setResponseCode(401).setBody("""{"error":"unauthorized"}""")
        )

        try {
            service().execute("SELECT * FROM c")
            fail("expected QueryExecutionException")
        } catch (e: QueryExecutionException) {
            assertEquals(401, e.httpStatus)
            assertTrue(e.body.contains("unauthorized"))
            assertTrue(e.message!!.contains("401"))
            assertTrue(e.message!!.contains("unauthorized"))
        }
    }

    // ── unparseable body falls back to {"_raw": "<text>"} doc ───────────────

    @Test
    fun `non-json successful body yields _raw sentinel doc`() = runBlocking {
        server.enqueue(MockResponse().setResponseCode(200).setBody("hello, world"))

        val result = service().execute("SELECT * FROM c")

        assertEquals(1, result.documents.size)
        assertEquals("hello, world", result.documents[0]["_raw"])
    }

    // ── missing credentials throws immediately ──────────────────────────────

    @Test
    fun `blank httpApiUrl throws IllegalArgumentException`() = runBlocking {
        val noUrl = database().copy(httpApiUrl = "")
        try {
            service(noUrl).execute("SELECT * FROM c")
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertNotNull(e.message)
        }
    }

    @Test
    fun `blank httpApiKey throws IllegalArgumentException`() = runBlocking {
        val noKey = database().copy(httpApiKey = "")
        try {
            service(noKey).execute("SELECT * FROM c")
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertNotNull(e.message)
        }
    }

    // ── allowUntrustedCerts builds a permissive client ──────────────────────

    @Test
    fun `allowUntrustedCerts true builds a trust-all client`() = runBlocking {
        // Smoke test: the trust-all client wrapper must construct without throwing.
        // (Full TLS handshake against MockWebServer's self-signed cert is exercised by
        // the e2e test in androidTest where MockWebServer.useHttps is enabled.)
        val db = database(allowUntrusted = true)
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"items":[]}"""))
        val result = service(db).execute("SELECT * FROM c")
        assertEquals(0, result.documents.size)
    }

    @Test
    fun `null databaseProvider result throws`() = runBlocking {
        // Inline construction for this special case: testing null provider behavior.
        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { null }, urlScheme = "http",
        )
        try {
            httpSvc.execute("SELECT * FROM c")
            fail("expected IllegalStateException")
        } catch (e: IllegalStateException) {
            assertNotNull(e.message)
        }
    }
}
