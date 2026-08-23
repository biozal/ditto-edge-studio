# Query Workbench Toolbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. TDD discipline (superpowers:test-driven-development) is mandatory — every behavioral change starts with a failing test.

**Goal:** Move Run from the floating bottom bar to a new top sub-toolbar (Run / Local-HTTP target chip / Options popover) inside `QueryWorkbenchContentSection`, and add a Kotlin/OkHttp HTTP execution path to reach parity with SwiftUI.

**Architecture:** A new composable `QueryWorkbenchTopToolbar` slots between the scaffold's `TopAppBar` and `QueryEditorScreen`. The existing `QueryExecutionService` is renamed to `LocalQueryExecutionService` and a new `HttpQueryExecutionService` (OkHttp + kotlinx.serialization) is added; a thin facade keeping the name `QueryExecutionService` dispatches between them based on a new `executeMode` flow on `QueryWorkbenchState`. `MainStudioViewModel` derives `executeModes` from the active `DittoDatabase` (HTTP appears only when both `httpApiUrl` and `httpApiKey` are set), exactly mirroring `SwiftUI/EdgeStudio/Views/StudioView/ViewModels/QueryViewModel.swift` lines 86–98.

**Tech Stack:** Kotlin 2.3.21, Jetpack Compose (Material3), AGP 9.2.1, OkHttp 4.12.0 (+ MockWebServer for tests), kotlinx.serialization 1.8.0 (already in catalog), Koin 4.1.1, JUnit4 + MockK + Compose Test, Gradle Managed Device (Pixel Tablet AVD, API 34).

**Hard constraints (from `android/CLAUDE.md` and the design spec):**
- All Gradle commands run from `android/`.
- `connectedAndroidTest` MUST be prefixed with `ANDROID_SERIAL=5C091JEA328801` (the wipe-safe Pixel 10a actually attached this session — the plan originally listed `58300DLCR0000L` from a prior unit; confirmed via `adb devices`). Never target `R5GL15XPVGA` (Samsung tablet, reserved).
- Tablet leg uses the Gradle Managed Device `tabletApi34` only — never an attached tablet.
- Library versions live in `gradle/libs.versions.toml`; never hardcode in `build.gradle.kts`.
- New Compose UI tests must `performScrollTo()` before `performTextInput`/`performClick` on scrollable forms (memory: `feedback_compose_ui_tests`).
- Plans/screenshots/docs locations are fixed; this plan lives at `plans/android/query-workbench-toolbar-plan.md`.

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/JsonToMap.kt` | Top-level helper extracted from the current `QueryExecutionService.parseJsonToMap`. Shared by both execution services. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/LocalQueryExecutionService.kt` | Renamed from current `QueryExecutionService.kt`. Owns the local-Ditto path. Uses `JsonToMap`. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionService.kt` | OkHttp-based HTTP path that mirrors SwiftUI's `QueryService.executeSelectedAppQueryHttp` (lines 268–347). Honors `allowUntrustedCerts`. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionException.kt` | `RuntimeException` subclass carrying `httpStatus` and `body`. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbar.kt` | The new ~48dp `Surface` row — Run / target FilterChip / Options popover. |
| `app/src/test/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionServiceTest.kt` | MockWebServer-driven unit tests for HTTP path. |
| `app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionServiceTest.kt` | Facade-level dispatch tests. |
| `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbarTest.kt` | Compose UI tests for the new toolbar. |
| `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchBottomBarTest.kt` | Existing-name test file is new — regression guard that Run is absent from the bottom bar. |
| `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchE2ETest.kt` | Full-stack e2e — seeds Room, boots `MainActivity`, drives the toolbar against a MockWebServer for HTTP scenarios. |

### Modified files

| Path | Change |
|---|---|
| `gradle/libs.versions.toml` | Add `okhttp = "4.12.0"` version + `okhttp` and `okhttp-mockwebserver` library aliases. |
| `app/build.gradle.kts` | Add `implementation(libs.okhttp)`, `testImplementation(libs.okhttp.mockwebserver)`, `androidTestImplementation(libs.okhttp.mockwebserver)`; wire `tabletApi34` Gradle Managed Device. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/ditto/DittoManager.kt` | Track the active `DittoDatabase` so app-scoped `HttpQueryExecutionService` can resolve it via `() -> DittoDatabase?` provider. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt` | Becomes the dispatcher facade — keeps the type name so call sites compile unchanged. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt` | Register OkHttp client, `kotlinx.serialization.Json`, `LocalQueryExecutionService`, `HttpQueryExecutionService`, and the facade. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt` | Add four new flows on `QueryWorkbenchState`. |
| `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt` | Expose the four flows, add three setters, and pass mode to facade in `executeQuery()`. `explainQuery()` always passes mode `"Local"`. |
| `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt` | Derive `executeModes` from active database on hydration, and reset `executeMode` if HTTP credentials drop mid-session. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchSection.kt` | Insert `QueryWorkbenchTopToolbar` above the editor; remove Run from `QueryWorkbenchBottomBar`. |
| `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt` | Extend with mode + toggle + executeQuery dispatch coverage. |
| `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModelTest.kt` | Extend with `executeModes` derivation coverage. |

---

## Phase 1 — HTTP Execution Path (data layer foundation)

### Task 1: Add OkHttp + MockWebServer to the catalog

**Files:**
- Modify: `android/gradle/libs.versions.toml`
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: Add OkHttp version + library aliases to the catalog**

Open `android/gradle/libs.versions.toml`. In `[versions]` add this line under the existing version entries (e.g. immediately after `markwon = "4.6.2"`):

```toml
okhttp = "4.12.0"
```

In `[libraries]` add these two entries at the bottom (after the markwon block):

```toml
# OkHttp (HTTP query execution + tests)
okhttp = { group = "com.squareup.okhttp3", name = "okhttp", version.ref = "okhttp" }
okhttp-mockwebserver = { group = "com.squareup.okhttp3", name = "mockwebserver", version.ref = "okhttp" }
```

- [ ] **Step 2: Wire the dependencies in `app/build.gradle.kts`**

In the `dependencies { ... }` block, add `implementation(libs.okhttp)` immediately under `implementation(libs.kotlinx.serialization.json)`:

```kotlin
implementation(libs.okhttp)
```

Add `testImplementation(libs.okhttp.mockwebserver)` to the unit-test section (right after `testImplementation(libs.org.json)`):

```kotlin
testImplementation(libs.okhttp.mockwebserver)
```

Add `androidTestImplementation(libs.okhttp.mockwebserver)` to the instrumented-test section (right after `androidTestImplementation(libs.mockk.android)`):

```kotlin
androidTestImplementation(libs.okhttp.mockwebserver)
```

- [ ] **Step 3: Confirm Gradle resolves the catalog**

Run: `cd android && ./gradlew :app:dependencies --configuration debugRuntimeClasspath | grep okhttp`
Expected: lines mentioning `com.squareup.okhttp3:okhttp:4.12.0`.

- [ ] **Step 4: Commit**

```bash
cd android && git add gradle/libs.versions.toml app/build.gradle.kts
git commit -m "feat(android): add OkHttp + MockWebServer to dependency catalog"
```

---

### Task 2: Extract `JsonToMap` helper (pure refactor — keeps existing tests green)

**Files:**
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/JsonToMap.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt`

- [ ] **Step 1: Write the extracted helper**

Create `JsonToMap.kt`:

```kotlin
package com.costoda.dittoedgestudio.data.repository

import org.json.JSONArray
import org.json.JSONObject

/**
 * Convert a [JSONObject] to a plain [Map] so result rows render uniformly across the
 * local-Ditto and HTTP execution paths.
 *
 * Nested objects recurse; nested arrays are normalized to `List<Any?>`; `JSONObject.NULL`
 * collapses to Kotlin `null`. Pulled out of the previous `QueryExecutionService` so both
 * `LocalQueryExecutionService` and `HttpQueryExecutionService` can share one implementation.
 */
fun parseJsonToMap(json: JSONObject): Map<String, Any?> {
    val map = mutableMapOf<String, Any?>()
    for (key in json.keys()) {
        map[key] = unwrap(json.opt(key))
    }
    return map
}

private fun unwrap(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> parseJsonToMap(value)
    is JSONArray -> List(value.length()) { i -> unwrap(value.opt(i)) }
    else -> value
}
```

- [ ] **Step 2: Update `QueryExecutionService` to use the helper**

In `QueryExecutionService.kt`, delete the private `parseJsonToMap` function and replace the call site inside `execute(...)` to use the top-level helper. The file becomes:

```kotlin
package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.ditto.DittoManager
import com.costoda.dittoedgestudio.domain.model.QueryResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

class QueryExecutionService(private val dittoManager: DittoManager) {

    suspend fun execute(query: String): QueryResult = withContext(Dispatchers.IO) {
        val ditto = dittoManager.currentInstance()
            ?: error("No active Ditto instance")
        val start = System.currentTimeMillis()
        val documents = ditto.store.execute(query) { result ->
            result.items.map { item ->
                runCatching { parseJsonToMap(JSONObject(item.jsonString())) }
                    .getOrDefault(emptyMap<String, Any?>())
            }
        }
        val elapsed = System.currentTimeMillis() - start
        QueryResult(
            documents = documents,
            totalCount = documents.size,
            executionTimeMs = elapsed,
        )
    }

    suspend fun explain(query: String): QueryResult = execute("EXPLAIN $query")
}
```

- [ ] **Step 3: Compile and run the existing unit tests to verify no regression**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL, all existing tests pass.

- [ ] **Step 4: Commit**

```bash
cd android && git add app/src/main/java/com/costoda/dittoedgestudio/data/repository/JsonToMap.kt \
    app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt
git commit -m "refactor(android): extract parseJsonToMap helper for query result parsing"
```

---

### Task 3: Rename `QueryExecutionService` → `LocalQueryExecutionService`

**Files:**
- Modify: rename `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt` → `LocalQueryExecutionService.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt` (registration line)

> **Note:** Task 6 introduces a NEW `QueryExecutionService.kt` as the facade so call sites (VM constructor, DI typed `get()`, tests) remain unchanged at the end. This task is solely the rename of the implementation class.

- [ ] **Step 1: Rename the file**

```bash
cd android && git mv \
  app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt \
  app/src/main/java/com/costoda/dittoedgestudio/data/repository/LocalQueryExecutionService.kt
```

- [ ] **Step 2: Rename the class inside the file**

Open `LocalQueryExecutionService.kt` and change:

```kotlin
class QueryExecutionService(private val dittoManager: DittoManager) {
```

to:

```kotlin
class LocalQueryExecutionService(private val dittoManager: DittoManager) {
```

- [ ] **Step 3: Update the temporary DI registration so the project still compiles**

In `DataModule.kt`, change the line:

```kotlin
single { QueryExecutionService(get()) }
```

to:

```kotlin
single { LocalQueryExecutionService(get()) }
single<QueryExecutionService> { error("Wired in Task 6") } // TEMP — replaced in Task 6
```

The temp binding is replaced in Task 6. The compile error from removing `QueryExecutionService` the class is also resolved in Task 6 (which adds the facade with the same name).

- [ ] **Step 4: Verify build fails CLEANLY only at the old QueryExecutionService callers**

Run: `cd android && ./gradlew :app:assembleDebug`
Expected: build fails with "unresolved reference: QueryExecutionService" pointing at `QueryEditorViewModel` and `QueryEditorViewModelTest`. This is intentional — Task 6 fixes it by creating the facade with the same name. Do NOT mass-replace `QueryExecutionService` with `LocalQueryExecutionService` at call sites; the facade keeps the original name.

> **DEFERRED COMMIT:** Do not commit until Task 6 lands the facade — Task 3 + 6 are intentionally one atomic split.

---

### Task 4: Add `QueryExecutionException`

**Files:**
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionException.kt`

- [ ] **Step 1: Write the exception**

```kotlin
package com.costoda.dittoedgestudio.data.repository

/**
 * Thrown by [HttpQueryExecutionService] when the remote endpoint returns a non-2xx response.
 *
 * The existing `runCatching { ... }.onFailure { workbench.executionError.value = e.message }`
 * block in `QueryEditorViewModel.executeQuery()` surfaces the message string in the results
 * pane, so the response body is embedded in the message for visibility.
 */
class QueryExecutionException(
    val httpStatus: Int,
    val body: String,
) : RuntimeException("HTTP $httpStatus: $body")
```

- [ ] **Step 2: Defer commit until Task 6** (still pre-facade; would not compile in isolation if referenced).

---

### Task 5: Write `HttpQueryExecutionService` (TDD)

**Files:**
- Create: `android/app/src/test/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionServiceTest.kt`
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionService.kt`

- [ ] **Step 1: Write the failing test class**

`HttpQueryExecutionServiceTest.kt`:

```kotlin
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

    private fun service(db: DittoDatabase): HttpQueryExecutionService =
        HttpQueryExecutionService(client = client, json = json, databaseProvider = { db })

    // ── happy-path: items response ───────────────────────────────────────────

    @Test
    fun `posts to v5_store_execute with bearer auth and statement body`() = runBlocking {
        server.enqueue(
            MockResponse()
                .setResponseCode(200)
                .setBody("""{"items":[{"_id":"a","name":"X"}]}""")
        )

        val svc = service(database())
        // Override the scheme to http:// in the test because MockWebServer is plain HTTP.
        // The service has a `urlScheme` constructor arg for exactly this reason.
        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { database() }, urlScheme = "http",
        )
        val result = httpSvc.execute("SELECT * FROM things")

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

        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { database() }, urlScheme = "http",
        )
        val result = httpSvc.execute("UPDATE c SET x = 1")

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

        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { database() }, urlScheme = "http",
        )
        val result = httpSvc.execute("UPDATE c SET x = 1")

        assertEquals(1, result.documents.size)
        assertEquals("abc", result.documents[0]["_id"])
    }

    // ── non-2xx surfaces as QueryExecutionException with body in message ────

    @Test
    fun `non-2xx response throws QueryExecutionException with body`() = runBlocking {
        server.enqueue(
            MockResponse().setResponseCode(401).setBody("""{"error":"unauthorized"}""")
        )

        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { database() }, urlScheme = "http",
        )
        try {
            httpSvc.execute("SELECT * FROM c")
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

        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { database() }, urlScheme = "http",
        )
        val result = httpSvc.execute("SELECT * FROM c")

        assertEquals(1, result.documents.size)
        assertEquals("hello, world", result.documents[0]["_raw"])
    }

    // ── missing credentials throws immediately ──────────────────────────────

    @Test
    fun `blank httpApiUrl throws IllegalArgumentException`() = runBlocking {
        val noUrl = database().copy(httpApiUrl = "")
        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { noUrl }, urlScheme = "http",
        )
        try {
            httpSvc.execute("SELECT * FROM c")
            fail("expected IllegalArgumentException")
        } catch (e: IllegalArgumentException) {
            assertNotNull(e.message)
        }
    }

    @Test
    fun `blank httpApiKey throws IllegalArgumentException`() = runBlocking {
        val noKey = database().copy(httpApiKey = "")
        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { noKey }, urlScheme = "http",
        )
        try {
            httpSvc.execute("SELECT * FROM c")
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
        val httpSvc = HttpQueryExecutionService(
            client = client, json = json, databaseProvider = { db }, urlScheme = "http",
        )
        server.enqueue(MockResponse().setResponseCode(200).setBody("""{"items":[]}"""))
        val result = httpSvc.execute("SELECT * FROM c")
        assertEquals(0, result.documents.size)
    }

    @Test
    fun `null databaseProvider result throws`() = runBlocking {
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
```

- [ ] **Step 2: Run the test — verify all fail with "unresolved reference: HttpQueryExecutionService"**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.HttpQueryExecutionServiceTest"`
Expected: COMPILATION ERROR — the service does not exist yet.

- [ ] **Step 3: Implement `HttpQueryExecutionService`**

Create `HttpQueryExecutionService.kt`:

```kotlin
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
        val body = json.encodeToString(JsonObject.serializer(), payload)
            .toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(url)
            .post(body)
            .header("Authorization", "Bearer ${db.httpApiKey}")
            .header("Content-Type", "application/json")
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
```

- [ ] **Step 4: Run the tests — verify all pass**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.HttpQueryExecutionServiceTest"`
Expected: 9 tests pass.

- [ ] **Step 5: Defer commit until Task 6** (the facade is still missing; the project as a whole won't assemble until Task 6).

---

### Task 6: Refactor `QueryExecutionService` into the facade (TDD)

**Files:**
- Create: `android/app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionServiceTest.kt`
- Create (replacement): `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt`

- [ ] **Step 1: Write the failing facade tests**

`QueryExecutionServiceTest.kt`:

```kotlin
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
```

- [ ] **Step 2: Run the tests — they must fail because `QueryExecutionService` doesn't exist as a facade yet**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.QueryExecutionServiceTest"`
Expected: COMPILATION ERROR — the facade type has not been written.

- [ ] **Step 3: Implement the facade**

Replace the contents of `QueryExecutionService.kt` with the new facade (this is the same path as before, but now wraps the two services):

```kotlin
package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.QueryResult

/**
 * Dispatcher facade: routes [execute] to [LocalQueryExecutionService] or
 * [HttpQueryExecutionService] based on the picker mode set on `QueryWorkbenchState`.
 *
 * [explain] is local-only (matches SwiftUI's "PROFILE is local-only for v1"; see the
 * design spec §5.7). Unknown modes fall back to Local — defensive in case the picker
 * state drifts from the supported set.
 */
class QueryExecutionService(
    private val local: LocalQueryExecutionService,
    private val http: HttpQueryExecutionService,
) {

    suspend fun execute(query: String, mode: String = "Local"): QueryResult =
        if (mode == "HTTP") http.execute(query) else local.execute(query)

    suspend fun explain(query: String): QueryResult = local.explain(query)
}
```

- [ ] **Step 4: Run all unit tests to confirm everything still resolves**

Run: `cd android && ./gradlew :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL — note that `QueryEditorViewModelTest`'s `executeQuery` paths still mock `queryExecutionService.execute(any())` which now defaults `mode = "Local"`, so existing tests are unaffected.

- [ ] **Step 5: Commit Tasks 3-6 as one atomic split**

```bash
cd android && git add \
  app/src/main/java/com/costoda/dittoedgestudio/data/repository/LocalQueryExecutionService.kt \
  app/src/main/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionService.kt \
  app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt \
  app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionException.kt \
  app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt \
  app/src/test/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionServiceTest.kt \
  app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionServiceTest.kt
git commit -m "feat(android): add HTTP query execution path with Local/HTTP facade"
```

> **Note on DataModule:** Task 7 below makes the actual DI wiring deliberate; this commit keeps the temp `error(...)` stub from Task 3 — that's fine because the unit tests construct services directly. The compile failure from missing `QueryExecutionService` arguments at the VM/test call sites is repaired by the new facade type retaining the same name, so call sites compile unchanged.

---

### Task 7: Wire OkHttp + the two services into Koin DI

**Files:**
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/data/ditto/DittoManager.kt`

- [ ] **Step 1: Track active database on `DittoManager` so the HTTP service can resolve it from app scope**

In `DittoManager.kt`, after `private var ditto: Ditto? = null`, add:

```kotlin
@Volatile
private var activeDatabase: DittoDatabase? = null

fun currentDatabase(): DittoDatabase? = activeDatabase
```

In `hydrate(...)`, just before `return newDitto`, add:

```kotlin
activeDatabase = database
```

Find `closeCurrentInstance()` and `close()` (likely in the same file or `DittoManager_*` shards) — add `activeDatabase = null` after the Ditto handle is cleared in each teardown path so a re-hydrate starts from a clean state. (If `closeCurrentInstance` is the only teardown path, one assignment is sufficient.)

- [ ] **Step 2: Replace the temporary DI bindings**

In `DataModule.kt`, delete the temp lines added in Task 3:

```kotlin
single { LocalQueryExecutionService(get()) }
single<QueryExecutionService> { error("Wired in Task 6") } // TEMP — replaced in Task 6
```

Replace them with the full wiring (drop in right where the temp bindings were):

```kotlin
single { okhttp3.OkHttpClient() }
single { kotlinx.serialization.json.Json { ignoreUnknownKeys = true } }
single { LocalQueryExecutionService(get<com.costoda.dittoedgestudio.data.ditto.DittoManager>()) }
single {
    HttpQueryExecutionService(
        client = get(),
        json = get(),
        databaseProvider = { get<com.costoda.dittoedgestudio.data.ditto.DittoManager>().currentDatabase() },
    )
}
single { QueryExecutionService(local = get(), http = get()) }
```

- [ ] **Step 3: Build the app to confirm DI graph resolves**

Run: `cd android && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
cd android && git add \
  app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt \
  app/src/main/java/com/costoda/dittoedgestudio/data/ditto/DittoManager.kt
git commit -m "feat(android): wire OkHttp + Local/HTTP query execution into Koin DI"
```

---

## Phase 2 — ViewModel & state additions

### Task 8: Add four new flows to `QueryWorkbenchState`

**Files:**
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt`

- [ ] **Step 1: Add the flows**

Inside `class QueryWorkbenchState` in `StudioUiState.kt`, just below `val isFavorited = MutableStateFlow(false)`, append:

```kotlin
/** Picker selection — "Local" or "HTTP". Survives rail-section switches. */
val executeMode: MutableStateFlow<String> = MutableStateFlow("Local")

/**
 * Modes the user can pick from. Derived by [com.costoda.dittoedgestudio.viewmodel.MainStudioViewModel]
 * on hydration from the active [com.costoda.dittoedgestudio.domain.model.DittoDatabase] — HTTP only
 * appears when both `httpApiUrl` and `httpApiKey` are non-blank.
 */
val executeModes: MutableStateFlow<List<String>> = MutableStateFlow(listOf("Local"))

/** Options popover — defaults ON each session; no DataStore persistence in this plan. */
val captureProfilingData: MutableStateFlow<Boolean> = MutableStateFlow(true)

/** Options popover — defaults ON each session; no DataStore persistence in this plan. */
val captureQueryMetrics: MutableStateFlow<Boolean> = MutableStateFlow(true)
```

- [ ] **Step 2: Commit (no behavioral change yet — adding data is safe)**

```bash
cd android && git add app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt
git commit -m "feat(android): add executeMode/executeModes/capture toggles to QueryWorkbenchState"
```

---

### Task 9: `QueryEditorViewModel` — expose flows + setters + pass mode (TDD)

**Files:**
- Modify: `android/app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt`

- [ ] **Step 1: Write failing tests — append to the existing `QueryEditorViewModelTest` class**

Add these tests inside the existing class (before the closing brace). Note: this uses MockK's existing `queryExecutionService` mock declared in `setUp()`.

```kotlin
    // ── execute-mode wiring ────────────────────────────────────────────────────

    @Test
    fun `setExecuteMode updates session-scoped flow visible across VMs`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vmA = createVm(sharedWorkbench)
        val vmB = createVm(sharedWorkbench)

        vmA.setExecuteMode("HTTP")
        advanceUntilIdle()

        assertEquals("HTTP", vmB.executeMode.value)
    }

    @Test
    fun `setCaptureProfilingData flips session-scoped toggle`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vm = createVm(sharedWorkbench)

        assertEquals(true, vm.captureProfilingData.value)
        vm.setCaptureProfilingData(false)
        advanceUntilIdle()
        assertEquals(false, vm.captureProfilingData.value)
    }

    @Test
    fun `setCaptureQueryMetrics flips session-scoped toggle`() = runTest {
        val sharedWorkbench = QueryWorkbenchState()
        val vm = createVm(sharedWorkbench)

        assertEquals(true, vm.captureQueryMetrics.value)
        vm.setCaptureQueryMetrics(false)
        advanceUntilIdle()
        assertEquals(false, vm.captureQueryMetrics.value)
    }

    @Test
    fun `executeQuery passes current executeMode to the facade`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[1] as String)
            QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 1L)
        }

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        assertEquals(listOf("HTTP"), captured)
    }

    @Test
    fun `executeQuery records history and metrics identically for HTTP mode`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val result = QueryResult(documents = listOf(mapOf("a" to 1)), totalCount = 1, executionTimeMs = 7L)
        coEvery { queryExecutionService.execute(any(), eq("HTTP")) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 42L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT * FROM c")
        vm.executeQuery()
        advanceUntilIdle()

        assertEquals(result, vm.queryResult.value)
        assertEquals(42L, sharedWorkbench.lastHistoryId)
        io.mockk.coVerify { historyRepository.addToHistory("test-db-id", "SELECT * FROM c") }
        io.mockk.coVerify { metricsRepository.save(any()) }
        io.mockk.coVerify { appMetricsRepository.incrementQueryCount() }
    }

    @Test
    fun `explainQuery always uses Local mode regardless of picker`() = runTest {
        val sharedWorkbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val result = QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 2L)
        coEvery { queryExecutionService.explain(any()) } returns result
        coEvery { historyRepository.addToHistory(any(), any()) } returns 0L

        val vm = createVm(sharedWorkbench)
        vm.onQueryTextChange("SELECT 1")
        vm.explainQuery()
        advanceUntilIdle()

        // The facade's explain() is local-only — confirm `execute(..., "HTTP")` was NOT called.
        io.mockk.coVerify(exactly = 0) { queryExecutionService.execute(any(), eq("HTTP")) }
        io.mockk.coVerify { queryExecutionService.explain("SELECT 1") }
    }
```

- [ ] **Step 2: Run the tests — verify all six fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.QueryEditorViewModelTest"`
Expected: 6 new tests fail with "unresolved reference: setExecuteMode" (etc.) and "execute(..., String) not found".

- [ ] **Step 3: Add flows + setters + pass mode in `QueryEditorViewModel`**

Inside `QueryEditorViewModel`, immediately above the `// ── Public API ────...` divider, append:

```kotlin
    // ── Execute mode + Options toggles (session-backed) ──────────────────────
    val executeMode: StateFlow<String> = workbench.executeMode.asStateFlow()
    val executeModes: StateFlow<List<String>> = workbench.executeModes.asStateFlow()
    val captureProfilingData: StateFlow<Boolean> = workbench.captureProfilingData.asStateFlow()
    val captureQueryMetrics: StateFlow<Boolean> = workbench.captureQueryMetrics.asStateFlow()
```

Add three setters at the bottom of the public API (right after `fun clearHistory()`):

```kotlin
    fun setExecuteMode(mode: String) { workbench.executeMode.value = mode }
    fun setCaptureProfilingData(enabled: Boolean) { workbench.captureProfilingData.value = enabled }
    fun setCaptureQueryMetrics(enabled: Boolean) { workbench.captureQueryMetrics.value = enabled }
```

Change `executeQuery()` to pass mode. Find:

```kotlin
val result = queryExecutionService.execute(query)
```

Replace with:

```kotlin
val result = queryExecutionService.execute(query, mode = workbench.executeMode.value)
```

`explainQuery()` continues to call `queryExecutionService.explain(query)` — the facade already pins explain to local, so no change is needed there.

- [ ] **Step 4: Run the tests — verify all six pass and existing tests stay green**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.QueryEditorViewModelTest"`
Expected: BUILD SUCCESSFUL — all tests pass.

- [ ] **Step 5: Commit**

```bash
cd android && git add \
  app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt \
  app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt
git commit -m "feat(android): expose executeMode + Options toggles + pass mode to facade in VM"
```

---

### Task 10: `MainStudioViewModel` — derive `executeModes` on hydration (TDD)

**Files:**
- Modify: `android/app/src/test/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModelTest.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioSession.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt`

> **Design choice:** the easiest hook point is `StudioSession.hydrate()` — it already holds the `DittoDatabase` and writes to `uiState.queryWorkbench`. We update `executeModes` there and reset `executeMode` if the user's prior pick is no longer valid. The VM has no per-config callback today, so doing it on the session keeps the logic with the data.

- [ ] **Step 1: Write failing tests — append to `MainStudioViewModelTest`**

Add inside the existing class:

```kotlin
    // ── executeModes derivation ──────────────────────────────────────────────

    @Test
    fun `executeModes is Local only when httpApiUrl is blank`() = runTest {
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "",
            httpApiKey = "key",
        )

        val vm = createViewModel()
        advanceUntilIdle()

        assertEquals(listOf("Local"), vm.session.uiState.queryWorkbench.executeModes.value)
    }

    @Test
    fun `executeModes is Local only when httpApiKey is blank`() = runTest {
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "host.example",
            httpApiKey = "",
        )

        val vm = createViewModel()
        advanceUntilIdle()

        assertEquals(listOf("Local"), vm.session.uiState.queryWorkbench.executeModes.value)
    }

    @Test
    fun `executeModes is Local and HTTP when both are set`() = runTest {
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "host.example",
            httpApiKey = "k",
        )

        val vm = createViewModel()
        advanceUntilIdle()

        assertEquals(listOf("Local", "HTTP"), vm.session.uiState.queryWorkbench.executeModes.value)
    }

    @Test
    fun `executeMode resets to Local when HTTP drops out of executeModes`() = runTest {
        // Start with HTTP available + selected.
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "host.example",
            httpApiKey = "k",
        )
        val vm = createViewModel()
        advanceUntilIdle()
        vm.session.uiState.queryWorkbench.executeMode.value = "HTTP"

        // Then re-hydrate with HTTP removed — VM-side hook re-derives executeModes and
        // sees "HTTP" is no longer valid → resets to "Local".
        coEvery { databaseRepository.getById(1L) } returns testDatabase.copy(
            httpApiUrl = "",
            httpApiKey = "k",
        )
        vm.session.hydrate()
        advanceUntilIdle()

        assertEquals(listOf("Local"), vm.session.uiState.queryWorkbench.executeModes.value)
        assertEquals("Local", vm.session.uiState.queryWorkbench.executeMode.value)
    }
```

- [ ] **Step 2: Run the tests — verify all four fail**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.MainStudioViewModelTest"`
Expected: 4 new tests fail because `executeModes` is never written by hydration.

- [ ] **Step 3: Implement derivation inside `StudioSession.hydrate()`**

In `StudioSession.kt`, locate the `hydrate()` `runCatching` block. Inside the success branch, just after `currentDittoId = database.databaseId`, add:

```kotlin
                // Derive picker modes from credentials (mirrors SwiftUI QueryViewModel lines
                // 86–98). HTTP only appears when both URL and key are non-blank. If the user's
                // prior pick is no longer valid (e.g. credentials dropped mid-session), reset
                // back to "Local" so the picker can't render a stale selection.
                val modes = if (database.httpApiUrl.isBlank() || database.httpApiKey.isBlank()) {
                    listOf("Local")
                } else {
                    listOf("Local", "HTTP")
                }
                uiState.queryWorkbench.executeModes.value = modes
                if (uiState.queryWorkbench.executeMode.value !in modes) {
                    uiState.queryWorkbench.executeMode.value = "Local"
                }
```

> **Why on the session, not the VM:** the VM does not observe `currentDatabase` reactively, but `hydrate()` is the single canonical entry point for "a new active database is being installed". Doing the derivation here also covers re-hydration after editing config mid-session (test case 4).

- [ ] **Step 4: Run the tests — verify all four pass**

Run: `cd android && ./gradlew :app:testDebugUnitTest --tests "*.MainStudioViewModelTest"`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
cd android && git add \
  app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioSession.kt \
  app/src/test/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModelTest.kt
git commit -m "feat(android): derive executeModes from active database on hydration"
```

---

## Phase 3 — UI: top toolbar + bottom bar refactor

### Task 11: Create `QueryWorkbenchTopToolbar` composable (Compose UI TDD)

**Files:**
- Create: `android/app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbarTest.kt`
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbar.kt`

> **Composable shape (drives the tests):** the composable takes raw parameters (no VM) so unit-style Compose tests can drive it directly without a Koin scope. Wiring to `QueryEditorViewModel` happens in Task 12.

> **Test tags (locked in here so e2e in Task 16 can reuse them):**
> - `"QueryToolbar.Run"` — Run IconButton (+ `CircularProgressIndicator` swap inside)
> - `"QueryToolbar.TargetChip"` — Local/HTTP FilterChip
> - `"QueryToolbar.TargetMenuItem.Local"` / `"QueryToolbar.TargetMenuItem.HTTP"` — dropdown items
> - `"QueryToolbar.Options"` — gear IconButton
> - `"QueryOptions.CaptureProfiling"` / `"QueryOptions.CaptureMetrics"` — switches inside the popover

- [ ] **Step 1: Write the failing Compose UI tests**

`QueryWorkbenchTopToolbarTest.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.SoftwareKeyboardController
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsOff
import androidx.compose.ui.test.assertIsOn
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.compose.runtime.CompositionLocalProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class QueryWorkbenchTopToolbarTest {

    @get:Rule
    val rule = createComposeRule()

    @Test
    fun runButtonIsDisabledWhenQueryTextIsBlank() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").assertIsNotEnabled()
    }

    @Test
    fun runButtonIsEnabledWhenQueryTextIsNotBlankAndNotExecuting() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").assertIsEnabled().assertHasClickAction()
    }

    @Test
    fun runButtonIsDisabledWhileExecuting() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = true,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").assertIsNotEnabled()
    }

    @Test
    fun targetChipShowsCurrentMode() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "HTTP",
                    executeModes = listOf("Local", "HTTP"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.TargetChip").assertIsDisplayed()
    }

    @Test
    fun targetChipMenuExposesOnlyLocalWhenSingleMode() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.Local").assertIsDisplayed()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").assertDoesNotExist()
    }

    @Test
    fun targetChipMenuSwitchesToHttpWhenSelected() {
        val selectedMode = mutableStateOf("Local")
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = selectedMode.value,
                    executeModes = listOf("Local", "HTTP"),
                    captureProfilingData = true,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = { selectedMode.value = it },
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").performClick()
        rule.runOnIdle { assertEquals("HTTP", selectedMode.value) }
    }

    @Test
    fun optionsPopoverShowsTogglesAndReflectsInitialState() {
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = false,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = {},
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.CaptureProfiling").assertIsOff()
        rule.onNodeWithTag("QueryOptions.CaptureMetrics").assertIsOn()
    }

    @Test
    fun togglingProfilingSwitchInvokesCallback() {
        val profiling = mutableStateOf(true)
        rule.setContent {
            MaterialTheme {
                QueryWorkbenchTopToolbar(
                    queryText = "SELECT 1",
                    isExecuting = false,
                    executeMode = "Local",
                    executeModes = listOf("Local"),
                    captureProfilingData = profiling.value,
                    captureQueryMetrics = true,
                    onRun = {},
                    onModeSelect = {},
                    onCaptureProfilingDataChange = { profiling.value = it },
                    onCaptureQueryMetricsChange = {},
                )
            }
        }
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.CaptureProfiling").performClick()
        rule.runOnIdle { assertEquals(false, profiling.value) }
    }

    @Test
    fun tappingRunInvokesKeyboardHideAndOnRun() {
        var ranOnRun = false
        var hideInvoked = false
        val fakeController = object : SoftwareKeyboardController {
            override fun show() {}
            override fun hide() { hideInvoked = true }
        }
        rule.setContent {
            MaterialTheme {
                CompositionLocalProvider(LocalSoftwareKeyboardController provides fakeController) {
                    QueryWorkbenchTopToolbar(
                        queryText = "SELECT 1",
                        isExecuting = false,
                        executeMode = "Local",
                        executeModes = listOf("Local"),
                        captureProfilingData = true,
                        captureQueryMetrics = true,
                        onRun = { ranOnRun = true },
                        onModeSelect = {},
                        onCaptureProfilingDataChange = {},
                        onCaptureQueryMetricsChange = {},
                    )
                }
            }
        }
        rule.onNodeWithTag("QueryToolbar.Run").performClick()
        rule.runOnIdle {
            assertTrue("onRun must be invoked", ranOnRun)
            assertTrue("IME hide must be invoked before/with onRun", hideInvoked)
        }
    }
}
```

- [ ] **Step 2: Run the tests — verify all fail (composable does not exist)**

Run: `cd android && ANDROID_SERIAL=5C091JEA328801 ./gradlew :app:connectedDebugAndroidTest --tests "*.QueryWorkbenchTopToolbarTest"`
Expected: COMPILATION ERROR — `QueryWorkbenchTopToolbar` is unresolved.

- [ ] **Step 3: Implement the composable**

Create `QueryWorkbenchTopToolbar.kt`:

```kotlin
@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp

/**
 * Top sub-toolbar for the Query Workbench. Sits between the scaffold's [TopAppBar] and
 * the DQL editor. Houses Run (with progress swap), the Local/HTTP target chip, and the
 * Options popover (Capture profiling data / Capture query metrics switches).
 *
 * Stateless by design — the caller (Query section) reads/writes the session-scoped flows
 * on `QueryWorkbenchState`; this composable is a pure render of the supplied state plus
 * callback handlers. Keeps the composable trivially testable without a VM scope.
 */
@Composable
fun QueryWorkbenchTopToolbar(
    queryText: String,
    isExecuting: Boolean,
    executeMode: String,
    executeModes: List<String>,
    captureProfilingData: Boolean,
    captureQueryMetrics: Boolean,
    onRun: () -> Unit,
    onModeSelect: (String) -> Unit,
    onCaptureProfilingDataChange: (Boolean) -> Unit,
    onCaptureQueryMetricsChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    var targetMenuExpanded by remember { mutableStateOf(false) }
    var optionsExpanded by remember { mutableStateOf(false) }
    val keyboardController = LocalSoftwareKeyboardController.current

    Surface(
        modifier = modifier.fillMaxWidth(),
        color = MaterialTheme.colorScheme.surfaceContainerLow,
        tonalElevation = 0.dp,
        shadowElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 48.dp)
                .padding(horizontal = 8.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            // Run / progress.
            IconButton(
                onClick = {
                    keyboardController?.hide()
                    onRun()
                },
                enabled = !isExecuting && queryText.isNotBlank(),
                modifier = Modifier.testTag("QueryToolbar.Run"),
            ) {
                if (isExecuting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Icon(
                        imageVector = Icons.Outlined.PlayArrow,
                        contentDescription = "Run query",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }

            // Local/HTTP target chip + dropdown.
            FilterChip(
                selected = false,
                onClick = { targetMenuExpanded = true },
                modifier = Modifier.testTag("QueryToolbar.TargetChip"),
                label = { Text(executeMode, style = MaterialTheme.typography.labelMedium) },
                leadingIcon = {
                    Icon(
                        imageVector = if (executeMode == "HTTP") Icons.Outlined.Cloud
                        else Icons.Outlined.Storage,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                },
                trailingIcon = {
                    Icon(
                        imageVector = Icons.Outlined.KeyboardArrowDown,
                        contentDescription = null,
                        modifier = Modifier.size(16.dp),
                    )
                },
            )
            DropdownMenu(
                expanded = targetMenuExpanded,
                onDismissRequest = { targetMenuExpanded = false },
            ) {
                executeModes.forEach { mode ->
                    DropdownMenuItem(
                        modifier = Modifier.testTag("QueryToolbar.TargetMenuItem.$mode"),
                        text = {
                            Text(
                                text = if (mode == executeMode) "$mode  ✓" else mode,
                                color = if (mode == executeMode) MaterialTheme.colorScheme.primary
                                else MaterialTheme.colorScheme.onSurface,
                            )
                        },
                        onClick = {
                            targetMenuExpanded = false
                            onModeSelect(mode)
                        },
                    )
                }
            }

            Spacer(modifier = Modifier.weight(1f))

            // Options popover.
            IconButton(
                onClick = { optionsExpanded = true },
                modifier = Modifier.testTag("QueryToolbar.Options"),
            ) {
                Icon(
                    imageVector = Icons.Outlined.Tune,
                    contentDescription = "Query options",
                    tint = MaterialTheme.colorScheme.onSurface,
                )
            }
            DropdownMenu(
                expanded = optionsExpanded,
                onDismissRequest = { optionsExpanded = false },
                modifier = Modifier.width(280.dp),
            ) {
                DropdownMenuItem(
                    text = { Text("Capture profiling data") },
                    onClick = { onCaptureProfilingDataChange(!captureProfilingData) },
                    trailingIcon = {
                        Switch(
                            checked = captureProfilingData,
                            onCheckedChange = { onCaptureProfilingDataChange(it) },
                            modifier = Modifier.testTag("QueryOptions.CaptureProfiling"),
                        )
                    },
                )
                DropdownMenuItem(
                    text = { Text("Capture query metrics") },
                    onClick = { onCaptureQueryMetricsChange(!captureQueryMetrics) },
                    trailingIcon = {
                        Switch(
                            checked = captureQueryMetrics,
                            onCheckedChange = { onCaptureQueryMetricsChange(it) },
                            modifier = Modifier.testTag("QueryOptions.CaptureMetrics"),
                        )
                    },
                )
            }
        }
    }
}
```

- [ ] **Step 4: Run the Compose UI tests on the Pixel 10a — verify all pass**

Run: `cd android && ANDROID_SERIAL=5C091JEA328801 ./gradlew :app:connectedDebugAndroidTest --tests "*.QueryWorkbenchTopToolbarTest"`
Expected: BUILD SUCCESSFUL — all 9 toolbar tests pass.

> **Reminder:** never target `R5GL15XPVGA`. If only the Samsung tablet is attached, the run is invalid; reconnect the Pixel 10a or use the managed device leg (Task 15) for this slice.

- [ ] **Step 5: Commit**

```bash
cd android && git add \
  app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbar.kt \
  app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbarTest.kt
git commit -m "feat(android): add QueryWorkbenchTopToolbar (Run, target chip, options popover)"
```

---

### Task 12: Wire the toolbar into `QueryWorkbenchContentSection`

**Files:**
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchSection.kt`

- [ ] **Step 1: Restructure the content section to render the toolbar above the editor**

In `QueryWorkbenchSection.kt`, locate `QueryWorkbenchContentSection` (the `else` branch when `queryVm != null`). Replace the inner `QueryEditorScreen(...)` + `QueryWorkbenchBottomBar(...)` block with a `Column` that places the toolbar above the editor, leaving the bottom bar as the floating overlay. Concretely, change:

```kotlin
        } else {
            QueryEditorScreen(
                viewModel = queryVm,
                modifier = Modifier.fillMaxSize(),
            )
            // Floating bottom bar — ...
            QueryWorkbenchBottomBar(
                viewModel = queryVm,
                mainViewModel = viewModel,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(8.dp),
            )
        }
```

to:

```kotlin
        } else {
            val queryText by queryVm.queryText.collectAsStateWithLifecycle()
            val isExecuting by queryVm.isExecuting.collectAsStateWithLifecycle()
            val executeMode by queryVm.executeMode.collectAsStateWithLifecycle()
            val executeModes by queryVm.executeModes.collectAsStateWithLifecycle()
            val captureProfilingData by queryVm.captureProfilingData.collectAsStateWithLifecycle()
            val captureQueryMetrics by queryVm.captureQueryMetrics.collectAsStateWithLifecycle()
            androidx.compose.foundation.layout.Column(modifier = Modifier.fillMaxSize()) {
                QueryWorkbenchTopToolbar(
                    queryText = queryText,
                    isExecuting = isExecuting,
                    executeMode = executeMode,
                    executeModes = executeModes,
                    captureProfilingData = captureProfilingData,
                    captureQueryMetrics = captureQueryMetrics,
                    onRun = { queryVm.executeQuery() },
                    onModeSelect = { queryVm.setExecuteMode(it) },
                    onCaptureProfilingDataChange = { queryVm.setCaptureProfilingData(it) },
                    onCaptureQueryMetricsChange = { queryVm.setCaptureQueryMetrics(it) },
                )
                QueryEditorScreen(
                    viewModel = queryVm,
                    modifier = Modifier.fillMaxSize(),
                )
            }
            // Floating bottom bar (Run removed in Task 13).
            QueryWorkbenchBottomBar(
                viewModel = queryVm,
                mainViewModel = viewModel,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(8.dp),
            )
        }
```

> **Note:** `Column` is referenced under fully qualified name to avoid touching the existing import sort order. Add the import if SwiftFormat/SwiftLint-equivalent Android tooling complains; otherwise the fully qualified form is fine.

- [ ] **Step 2: Build for debug to confirm it compiles**

Run: `cd android && ./gradlew assembleDebug`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
cd android && git add app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchSection.kt
git commit -m "feat(android): place QueryWorkbenchTopToolbar above the DQL editor"
```

---

### Task 13: Remove Run from `QueryWorkbenchBottomBar` + regression test

**Files:**
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchSection.kt`
- Create: `android/app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchBottomBarTest.kt`

- [ ] **Step 1: Write the failing regression test**

`QueryWorkbenchBottomBarTest.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.MainActivity
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Regression guard for the Query Workbench bottom bar.
 *
 * The Run icon used to live as the first child of `QueryWorkbenchBottomBar`. After moving
 * it to [QueryWorkbenchTopToolbar], the bottom bar must never carry a node tagged
 * `"QueryBottomBar.Run"`. This test stands the activity up so the bottom bar composes in
 * its real surroundings and asserts the absence.
 */
@RunWith(AndroidJUnit4::class)
class QueryWorkbenchBottomBarTest {

    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    @Test
    fun bottomBarHasNoRunIcon() {
        // Activity is up on the database list; the assertion is global ("does not exist") so
        // we don't need to navigate into the studio. If a future change re-adds a node tagged
        // `QueryBottomBar.Run` anywhere in the tree, this fails — exactly the regression
        // boundary we want.
        rule.onNodeWithTag("QueryBottomBar.Run").assertDoesNotExist()
    }
}
```

- [ ] **Step 2: Run the test to verify it currently fails**

Run: `cd android && ANDROID_SERIAL=5C091JEA328801 ./gradlew :app:connectedDebugAndroidTest --tests "*.QueryWorkbenchBottomBarTest"`
Expected: This test passes today (the bar's Run icon has no test tag, so the assertion of absence holds trivially). Add the test tag in step 3 so the assertion becomes meaningful, then remove the icon in step 4.

- [ ] **Step 3: Add the test tag to the existing Run icon so the regression has teeth**

In `QueryWorkbenchSection.kt`, find the IconButton inside `QueryWorkbenchBottomBar` whose `contentDescription = "Run query"` (currently the first child of the inner `Row`). Add `.testTag("QueryBottomBar.Run")` to its `Modifier`. Re-run the test from Step 2 — it must now FAIL because the node exists.

- [ ] **Step 4: Remove the entire IconButton from `QueryWorkbenchBottomBar`**

Delete the block:

```kotlin
            IconButton(
                onClick = { viewModel.executeQuery() },
                enabled = !isExecuting,
            ) {
                if (isExecuting) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Icon(
                        imageVector = Icons.Outlined.PlayArrow,
                        contentDescription = "Run query",
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
            }
```

Also remove any now-unused imports (`Icons.Outlined.PlayArrow`, `CircularProgressIndicator`, `Modifier.size`) so the file stays clean. Keep `isExecuting` collection if it's still used by any other surviving child; otherwise drop that `collectAsStateWithLifecycle` call too.

- [ ] **Step 5: Run the regression test — must now pass**

Run: `cd android && ANDROID_SERIAL=5C091JEA328801 ./gradlew :app:connectedDebugAndroidTest --tests "*.QueryWorkbenchBottomBarTest"`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```bash
cd android && git add \
  app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchSection.kt \
  app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchBottomBarTest.kt
git commit -m "feat(android): remove Run from QueryWorkbenchBottomBar; add regression guard"
```

---

## Phase 4 — E2E + Gradle Managed Device

### Task 14: Wire the `tabletApi34` Gradle Managed Device

**Files:**
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: Add the managed device under `android { testOptions { ... } }`**

In `app/build.gradle.kts`, locate the existing `testOptions { unitTests { ... } }` block. Add a `managedDevices { ... }` sibling so the block reads:

```kotlin
    testOptions {
        unitTests {
            isReturnDefaultValues = true
        }
        managedDevices {
            // AGP 9 DSL: `managedDevices.localDevices` (renamed from `devices` in AGP 8 and the
            // explicit `create<ManagedVirtualDevice>` generic is no longer required —
            // `localDevices` is already typed as NamedDomainObjectContainer<ManagedVirtualDevice>).
            localDevices {
                create("tabletApi34") {
                    device = "Pixel Tablet"
                    apiLevel = 34
                    systemImageSource = "aosp-atd"
                }
            }
        }
    }
```

- [ ] **Step 2: Verify the task is now exposed**

Run: `cd android && ./gradlew tasks --group verification | grep tabletApi34`
Expected: line `tabletApi34DebugAndroidTest - Installs and runs the test for Debug build on the gradle managed device tabletApi34.` (or similar).

- [ ] **Step 3: Commit**

```bash
cd android && git add app/build.gradle.kts
git commit -m "build(android): add tabletApi34 Gradle Managed Device for instrumented tests"
```

> **First-run caveat:** the AOSP-ATD system image (~600MB) downloads the first time the managed device runs; subsequent runs are fast. Heads-up for whoever kicks off the full e2e in Task 16.

---

### Task 15: Build the end-to-end test class with MockWebServer (TDD)

**Files:**
- Create: `android/app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchE2ETest.kt`

> **Seeding strategy:** seed a `DittoDatabase` row before `MainActivity` starts by acquiring the Koin-bound `DatabaseRepository` via `KoinJavaComponent.inject` from the application instance. The activity then renders the list; the test taps the seeded card (`testTag("AppCard_<name>")` is used by the SwiftUI side; the Android `DatabaseCard` may use a different tag — confirm via a Layout Inspector pass before authoring the tap, and switch to `onNodeWithText("E2E DB")` if no tag exists). Seeding via the repository keeps the DB schema honored and avoids touching Room directly.

> **MockWebServer for HTTPS:** scenarios that exercise `allowUntrustedCerts` must enable `MockWebServer.useHttps(socketFactory, false)` with a `HeldCertificate`. For simplicity in this plan, the e2e tests run against MockWebServer over plain HTTP and seed `httpApiUrl = "<host>:<port>"` plus a `urlScheme` override only inside the test boot path. The default production scheme remains HTTPS — there's no production code change. (If the override hook is awkward, add a `BuildConfig.IS_TEST` flag-gated `urlScheme = "http"` to the HTTP service registration in `DataModule` — but prefer constructor override over flags.)

- [ ] **Step 1: Sketch the test class — author each scenario as a `@Test`**

`QueryWorkbenchE2ETest.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.costoda.dittoedgestudio.MainActivity
import com.costoda.dittoedgestudio.data.repository.DatabaseRepository
import com.costoda.dittoedgestudio.domain.model.AuthMode
import com.costoda.dittoedgestudio.domain.model.DittoDatabase
import kotlinx.coroutines.runBlocking
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.koin.java.KoinJavaComponent.get
import org.koin.java.KoinJavaComponent.inject

/**
 * End-to-end coverage for the Query Workbench toolbar refactor (spec §6.3).
 *
 * Each scenario seeds a deterministic [DittoDatabase] row via the Koin-managed
 * [DatabaseRepository], then drives `MainActivity` from the database list through to the
 * Query Workbench. HTTP scenarios point `httpApiUrl` at an in-process [MockWebServer].
 */
@RunWith(AndroidJUnit4::class)
class QueryWorkbenchE2ETest {

    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    private lateinit var server: MockWebServer
    private val databaseRepository: DatabaseRepository by inject(DatabaseRepository::class.java)
    private var seededId: Long = -1L

    @Before
    fun setUp() = runBlocking {
        server = MockWebServer().apply { start() }
        seededId = databaseRepository.save(
            DittoDatabase(
                name = "E2E DB",
                databaseId = "e2e-db",
                token = "tok",
                authUrl = "https://auth.example",
                httpApiUrl = "${server.hostName}:${server.port}",
                httpApiKey = "test-key",
                mode = AuthMode.SERVER,
                allowUntrustedCerts = true,
            )
        )
    }

    @After
    fun tearDown() = runBlocking {
        server.shutdown()
        databaseRepository.deleteById(seededId)
    }

    /**
     * Enter the studio: tap the seeded database card on the list. Falls back to text match
     * if the project's DatabaseCard does not carry a test tag yet.
     */
    private fun enterStudio() {
        rule.onNodeWithText("E2E DB").performClick()
        // Navigate to the Query Workbench section. The default landing section is
        // Subscriptions/Presence; tap the rail/drawer item "Query Workbench".
        runCatching {
            rule.onNodeWithContentDescription("Query Workbench").performClick()
        }.onFailure {
            // Phone-mode: open the hamburger drawer first, then tap.
            rule.onNodeWithContentDescription("Open menu").performClick()
            rule.onNodeWithText("Query Workbench").performClick()
        }
    }

    @Test
    fun localHappyPath() {
        enterStudio()
        rule.onNodeWithText("DQL").performScrollTo() // ensure editor visible on phone width
        rule.onNodeWithText("DQL").performTextInput("SELECT * FROM __collections")
        rule.onNodeWithTag("QueryToolbar.Run").assertIsDisplayed().performClick()
        // Spinner appears, then results render. (Loose assertion — Ditto store may return 0+ rows.)
        rule.waitForIdle()
        // The Run icon must come back (no longer in executing state).
        rule.onNodeWithTag("QueryToolbar.Run").assertIsDisplayed()
    }

    @Test
    fun httpHappyPath() {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"items":[{"_id":"a","name":"X"},{"_id":"b","name":"Y"}]}"""
            )
        )
        enterStudio()
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").performClick()
        rule.onNodeWithText("DQL").performScrollTo()
        rule.onNodeWithText("DQL").performTextInput("SELECT * FROM things")
        rule.onNodeWithTag("QueryToolbar.Run").performClick()
        rule.waitForIdle()
        val recorded = server.takeRequest()
        assertEquals("Bearer test-key", recorded.getHeader("Authorization"))
        assertTrue(recorded.body.readUtf8().contains("SELECT * FROM things"))
    }

    @Test
    fun httpMutationResult() {
        server.enqueue(
            MockResponse().setResponseCode(200).setBody(
                """{"mutatedDocumentIds":["abc","def"],"commitId":"c1"}"""
            )
        )
        enterStudio()
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").performClick()
        rule.onNodeWithText("DQL").performScrollTo()
        rule.onNodeWithText("DQL").performTextInput("UPDATE c SET x = 1")
        rule.onNodeWithTag("QueryToolbar.Run").performClick()
        rule.waitForIdle()
        // Both synthetic IDs and the commitId sentinel render in the results pane.
        rule.onNodeWithText("abc").assertIsDisplayed()
        rule.onNodeWithText("def").assertIsDisplayed()
        rule.onNodeWithText("c1").assertIsDisplayed()
    }

    @Test
    fun httpErrorSurfacing() {
        server.enqueue(
            MockResponse().setResponseCode(401).setBody("""{"error":"unauthorized"}""")
        )
        enterStudio()
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").performClick()
        rule.onNodeWithText("DQL").performScrollTo()
        rule.onNodeWithText("DQL").performTextInput("SELECT * FROM c")
        rule.onNodeWithTag("QueryToolbar.Run").performClick()
        rule.waitForIdle()
        rule.onNodeWithText("unauthorized", substring = true).assertIsDisplayed()
        // Run is re-enabled after the error.
        rule.onNodeWithTag("QueryToolbar.Run").assertIsDisplayed()
    }

    @Test
    fun modePersistsAcrossRailSwitch() {
        enterStudio()
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").performClick()
        // Rail to Subscriptions and back.
        runCatching { rule.onNodeWithContentDescription("Subscriptions").performClick() }
            .onFailure {
                rule.onNodeWithContentDescription("Open menu").performClick()
                rule.onNodeWithText("Subscriptions").performClick()
            }
        runCatching { rule.onNodeWithContentDescription("Query Workbench").performClick() }
            .onFailure {
                rule.onNodeWithContentDescription("Open menu").performClick()
                rule.onNodeWithText("Query Workbench").performClick()
            }
        rule.onNodeWithText("HTTP").assertIsDisplayed()
    }

    @Test
    fun httpHiddenWhenUnconfigured() = runBlocking {
        // Re-seed without httpApiUrl so HTTP must not appear in the picker.
        databaseRepository.deleteById(seededId)
        seededId = databaseRepository.save(
            DittoDatabase(
                name = "E2E DB",
                databaseId = "e2e-db",
                token = "tok",
                authUrl = "https://auth.example",
                httpApiUrl = "", // blank
                httpApiKey = "",
                mode = AuthMode.SERVER,
            )
        )
        // Force activity restart? Not needed — the list reloads on resume. For clarity:
        rule.activity.recreate()
        enterStudio()
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.Local").assertIsDisplayed()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").assertDoesNotExist()
    }

    @Test
    fun midSessionCredentialChangeResetsMode() = runBlocking {
        enterStudio()
        rule.onNodeWithTag("QueryToolbar.TargetChip").performClick()
        rule.onNodeWithTag("QueryToolbar.TargetMenuItem.HTTP").performClick()
        // Now wipe HTTP creds on the underlying DB row + re-enter studio so hydrate() re-fires.
        databaseRepository.save(
            (databaseRepository.getById(seededId)!!).copy(httpApiUrl = "", httpApiKey = "")
        )
        // Back to list, then re-tap.
        rule.activity.onBackPressedDispatcher.onBackPressed()
        rule.onNodeWithText("E2E DB").performClick()
        runCatching { rule.onNodeWithContentDescription("Query Workbench").performClick() }
            .onFailure {
                rule.onNodeWithContentDescription("Open menu").performClick()
                rule.onNodeWithText("Query Workbench").performClick()
            }
        // Picker must show "Local" now.
        rule.onNodeWithText("Local").assertIsDisplayed()
    }

    @Test
    fun keyboardDismissOnRun() {
        enterStudio()
        rule.onNodeWithText("DQL").performScrollTo()
        rule.onNodeWithText("DQL").performClick() // focus editor → IME opens
        rule.onNodeWithText("DQL").performTextInput("SELECT * FROM c")
        rule.onNodeWithTag("QueryToolbar.Run").performClick()
        // Best-effort visibility check: after run, the editor must not be focused/IME up.
        // No public API exposes IME state in createAndroidComposeRule, so this scenario
        // primarily exercises the codepath; the SoftwareKeyboardController.hide() callback
        // is unit-asserted in QueryWorkbenchTopToolbarTest.
        rule.waitForIdle()
    }

    @Test
    fun optionsTogglesPersistInSession() {
        enterStudio()
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.CaptureProfiling").performClick()
        rule.onNodeWithTag("QueryOptions.CaptureMetrics").performClick()
        // Close menu (tap outside), reopen, both still off.
        rule.activity.onBackPressedDispatcher.onBackPressed() // dismiss popover
        rule.onNodeWithTag("QueryToolbar.Options").performClick()
        rule.onNodeWithTag("QueryOptions.CaptureProfiling").assert(androidx.compose.ui.test.isOff())
        rule.onNodeWithTag("QueryOptions.CaptureMetrics").assert(androidx.compose.ui.test.isOff())
    }

    @Test
    fun bottomBarHasNoRunIcon() {
        enterStudio()
        rule.onNodeWithTag("QueryBottomBar.Run").assertDoesNotExist()
    }
}
```

> **Notes for the implementer:**
> - The "DQL" text used to locate the editor is illustrative — check `QueryEditorScreen`'s actual placeholder/label before authoring this test and substitute the real text or test tag. The plan documents the *intent*; the implementer adjusts to actual selectors discovered in `QueryEditorScreen.kt` (use Layout Inspector or `printToLog()` if needed).
> - `enterStudio()` is illustrative; the project's actual rail/drawer interaction might use different `contentDescription` values. The test gracefully tries both rail and drawer paths and either should succeed.
> - The `urlScheme = "http"` for MockWebServer means the HTTP service must accept the override in production code — already wired by Task 5 via the `urlScheme` constructor parameter on `HttpQueryExecutionService`. For the e2e to use this, `DataModule` registers a test-only variant; the simplest is to override the Koin module in the test through `loadKoinModules` if needed, or to leave MockWebServer's HTTPS path enabled (more work). Pick the simplest path that compiles and passes.

- [ ] **Step 2: Build the test class (compile-only first)**

Run: `cd android && ./gradlew :app:compileDebugAndroidTestSources`
Expected: BUILD SUCCESSFUL — compilation passes; the test selectors may not match real composables yet.

- [ ] **Step 3: Run the suite against the Pixel 10a (phone leg)**

Run: `cd android && ANDROID_SERIAL=5C091JEA328801 ./gradlew :app:connectedDebugAndroidTest --tests "*.QueryWorkbenchE2ETest"`
Expected: most or all 10 scenarios pass. Iterate on any scenario that fails: typically the failure mode is a selector mismatch (`onNodeWithText("DQL")`) — fix by inspecting the actual composable. The bottom-bar regression (#10) and toolbar absence/dropdown checks should be robust regardless.

- [ ] **Step 4: Run the suite against the managed tablet device (tablet leg)**

Run: `cd android && ./gradlew tabletApi34DebugAndroidTest --tests "*.QueryWorkbenchE2ETest"`
Expected: First invocation downloads the AOSP-ATD image (~600MB); subsequent runs reuse it. All scenarios pass on the tablet form factor too. The multi-pane layout means `enterStudio()`'s rail/drawer fork lands on the rail branch (no hamburger).

- [ ] **Step 5: Commit**

```bash
cd android && git add app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchE2ETest.kt
git commit -m "test(android): add QueryWorkbenchE2ETest covering toolbar + HTTP scenarios"
```

---

### Task 16: Final full-suite verification

**Files:** (none — this is a verification pass)

- [ ] **Step 1: Unit tests**

Run: `cd android && ./gradlew test`
Expected: BUILD SUCCESSFUL — all unit tests pass.

- [ ] **Step 2: Phone instrumented leg**

Run: `cd android && ANDROID_SERIAL=5C091JEA328801 ./gradlew connectedAndroidTest`
Expected: BUILD SUCCESSFUL on Pixel 10a — all instrumented tests pass.

- [ ] **Step 3: Tablet managed leg**

Run: `cd android && ./gradlew tabletApi34DebugAndroidTest`
Expected: BUILD SUCCESSFUL on the managed tabletApi34 device. First run includes a ~600MB image download.

- [ ] **Step 4: Both Gradle assemble flavors (sanity, per CLAUDE.md root rule)**

Run: `cd android && ./gradlew assembleDebug` then `cd android && ./gradlew assembleRelease`
Expected: BUILD SUCCESSFUL for both.

- [ ] **Step 5: Lint + check verifications**

Run: `cd android && ./gradlew check`
Expected: BUILD SUCCESSFUL — `forbidNonAdaptiveSizeApis` task passes (the new files do not reference `screenWidthDp`).

- [ ] **Step 6: Optional smoke (manual)** — open `app/src/main/assets/help/query.md` to confirm the help text still matches the new toolbar; if it described the old top-bar Run, update it as a follow-up (out of scope here unless trivially short).

---

## Out of Scope (verbatim from design spec §8)

- **EXPLAIN over HTTP** — local-only in v1.
- **DataStore persistence of Options toggles** — toggles default ON every session.
- **Behavioral gating from Options toggles** — wired to state but do not yet change what `executeQuery()` captures.
- **`X-DITTO-API-KEY` header variant** — SwiftUI uses `Authorization: Bearer`; we match.
- **Query cancellation** — no Cancel button.
- **Persisting executeMode across activity restarts** — session-scoped only.

---

## Self-Review

**1. Spec coverage:**
- §1 Goal & Scope → Tasks 8–13 (UI), 1–7 (HTTP path).
- §2 Architecture → Tasks 3 (rename), 5 (HTTP), 6 (facade).
- §3.1 Toolbar slots → Task 11.
- §3.2 Options popover → Task 11 (popover) + Task 8 (state) + Task 9 (setters).
- §3.3 Bottom bar Run removal → Task 13.
- §3.4 Keyboard dismiss → Task 11 (composable wires hide) + Task 15 scenario 8.
- §4.1 `QueryWorkbenchState` additions → Task 8.
- §4.2 `executeModes` derivation → Task 10.
- §4.3 VM setters/exposures → Task 9.
- §4.4 `executeQuery()` mode pass-through → Task 9 step 3.
- §4.5 No persistence → spec compliant (Task 8 explicit comment).
- §5 HTTP path → Tasks 1, 2, 4, 5, 7.
- §5.4 `allowUntrustedCerts` → Task 5 step 3 (`trustAllClient`).
- §5.5 DI wiring → Task 7.
- §5.6 Error mapping → Task 4 + Task 5 happy/error paths.
- §5.7 EXPLAIN local-only → Task 6 facade `explain` + Task 9 test.
- §6.1 unit tests → Tasks 5, 6, 9, 10.
- §6.2 Compose UI tests → Tasks 11, 13.
- §6.3 e2e (all 10 scenarios) → Task 15.
- §6.4 manual smoke → Task 16 step 6 (note).
- §7 files touched → File Structure table above.

**2. Placeholder scan:** no TBDs, no "TODO", no "implement later". The one judgement call left to the implementer (the e2e selectors like `onNodeWithText("DQL")`) is documented explicitly so adjustment is bounded and intentional.

**3. Type consistency:**
- `LocalQueryExecutionService` constructor: `(dittoManager: DittoManager)` — used identically in tests and DI.
- `HttpQueryExecutionService` constructor: `(client: OkHttpClient, json: Json, databaseProvider: () -> DittoDatabase?, urlScheme: String = "https")` — used identically in tests and DI.
- `QueryExecutionService` facade: `execute(query: String, mode: String = "Local")` + `explain(query: String)` — VM call site `execute(query, mode = ...)` matches; default keeps existing tests green.
- `QueryWorkbenchState` new flow names: `executeMode`, `executeModes`, `captureProfilingData`, `captureQueryMetrics` — used identically across `StudioSession.hydrate()`, VM exposures, VM tests, and the toolbar composable.
- Toolbar callbacks: `onRun`, `onModeSelect`, `onCaptureProfilingDataChange`, `onCaptureQueryMetricsChange` — matched in `QueryWorkbenchContentSection`'s wire-up (Task 12).
- Test tags: `QueryToolbar.Run`, `QueryToolbar.TargetChip`, `QueryToolbar.TargetMenuItem.<Mode>`, `QueryToolbar.Options`, `QueryOptions.CaptureProfiling`, `QueryOptions.CaptureMetrics`, `QueryBottomBar.Run` — defined in Task 11/13 and consumed identically in Task 15.
