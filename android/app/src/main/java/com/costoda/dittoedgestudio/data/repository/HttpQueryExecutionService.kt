package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import com.costoda.dittoedgestudio.domain.model.QueryResult
import java.security.cert.X509Certificate
import javax.net.ssl.SSLContext
import javax.net.ssl.X509TrustManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * HTTP execution path mirroring SwiftUI's `QueryService.executeSelectedAppQueryHttp`.
 *
 * Build URL as `<urlScheme>://<httpApiUrl>/api/v5/store/execute`, POST with
 * `Authorization: Bearer <httpApiKey>` and `{"statement":"<query>"}` body. Result rows
 * are normalized to `Map<String, Any?>` via [parseJsonToMap] so the results pane renders
 * identically across the local-Ditto and HTTP modes.
 *
 * `urlScheme` defaults to `"https"`. Tests pass `"http"` to target MockWebServer without
 * the TLS plumbing; production callers should leave it at the default.
 *
 * **DEV/TEST-ONLY**: when [DittoDatabase.allowUntrustedCerts] is true, the per-execute
 * client installs a trust-all X509 manager and permissive hostname verifier. This must NEVER
 * be enabled in production — it disables certificate validation entirely.
 */
class HttpQueryExecutionService(
    private val client: OkHttpClient,
    private val json: Json,
    private val databaseProvider: () -> DittoDatabase?,
    private val urlScheme: String = "https",
) {

    suspend fun execute(query: String): QueryResult = withContext(Dispatchers.IO) {
        val db = databaseProvider()
            ?: error("No active database for HTTP query execution")
        require(db.httpApiUrl.isNotBlank()) { "HTTP execution requires non-blank httpApiUrl" }
        require(db.httpApiKey.isNotBlank()) { "HTTP execution requires non-blank httpApiKey" }

        val url = "$urlScheme://${db.httpApiUrl}/api/v5/store/execute"
        val payload = JsonObject(mapOf("statement" to JsonPrimitive(query)))
        val bodyBytes = json.encodeToString(JsonObject.serializer(), payload)
            .toByteArray(Charsets.UTF_8)
        val body = bodyBytes.toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(url)
            .post(body)
            .header("Authorization", "Bearer ${db.httpApiKey}")
            .build()
        val effectiveClient = if (db.allowUntrustedCerts) trustAllClient(client) else client
        val start = System.currentTimeMillis()
        effectiveClient.newCall(request).execute().use { response ->
            val elapsed = System.currentTimeMillis() - start
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) throw QueryExecutionException(response.code, text)
            parseResponse(text, elapsed)
        }
    }

    private fun parseResponse(text: String, elapsedMs: Long): QueryResult {
        val docs: List<Map<String, Any?>> = runCatching {
            val obj = JSONObject(text)
            val mutated = obj.optJSONArray("mutatedDocumentIds")
            if (mutated != null && mutated.length() > 0) {
                buildList {
                    for (i in 0 until mutated.length()) add(mapOf("_id" to mutated.optString(i)))
                    val commit = obj.optString("commitId", "")
                    if (commit.isNotBlank()) add(mapOf("commitId" to commit))
                }
            } else {
                val items = obj.optJSONArray("items")
                if (items != null) parseItems(items) else listOf(mapOf("_raw" to text))
            }
        }.getOrElse { listOf(mapOf("_raw" to text)) }

        return QueryResult(
            documents = docs,
            totalCount = docs.size,
            executionTimeMs = elapsedMs,
        )
    }

    private fun parseItems(items: JSONArray): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>(items.length())
        for (i in 0 until items.length()) {
            val obj = items.optJSONObject(i)
            out += if (obj != null) parseJsonToMap(obj) else mapOf("_raw" to items.opt(i).toString())
        }
        return out
    }

    private fun trustAllClient(base: OkHttpClient): OkHttpClient {
        val trustAll = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = Unit
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val ctx = SSLContext.getInstance("TLS").apply { init(null, arrayOf(trustAll), null) }
        return base.newBuilder()
            .sslSocketFactory(ctx.socketFactory, trustAll)
            .hostnameVerifier { _, _ -> true }
            .build()
    }
}
