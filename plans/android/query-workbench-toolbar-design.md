# Query Workbench Toolbar — Design Spec

Status: **Approved design — pre-implementation**
Platform: Android (`android/`)
Related: SwiftUI parity — `SwiftUI/EdgeStudio/Views/StudioView/ViewModels/QueryViewModel.swift`, `SwiftUI/EdgeStudio/Data/QueryService.swift`

## 1. Goal & Scope

Bring the Android Query Workbench to parity with the SwiftUI implementation by moving the **Run** affordance out of the floating bottom bar and onto a new sub-toolbar between the scaffold's top bar and the DQL editor. The new toolbar exposes three controls — Run, a Local/HTTP target picker, and an Options popover — and also serves as the surface that dismisses the soft keyboard when Run is tapped on phone-width.

This spec covers both the **UI refactor** and the **HTTP query execution path** that the target picker requires (no HTTP path exists on Android today). It does **not** wire the Options toggles to gate behavior — they persist state for the UI but capture-gating is out of scope (see §8).

## 2. Architecture

A new composable `QueryWorkbenchTopToolbar` slots between the scaffold's `TopAppBar` and the existing `QueryEditorView`. It is only rendered inside `QueryWorkbenchContentSection` — other sections (Subscriptions, Observers, etc.) are untouched. The scaffold's shared top bar stays section-agnostic.

Execution gets a strategy split:

- Today's `QueryExecutionService` is renamed to `LocalQueryExecutionService`
- A new `HttpQueryExecutionService` ports SwiftUI's HTTP path
- A thin facade keeps the name `QueryExecutionService` and dispatches between the two based on the current `executeMode` flow on `QueryWorkbenchState`

`QueryEditorViewModel.executeQuery()` continues to call the facade — its body changes only to pass the current mode. `StudioSession` already holds the active `DittoDatabase`, so `executeModes` is derived from `httpApiUrl`/`httpApiKey` exactly like SwiftUI's `QueryViewModel` does.

## 3. UI Components

### 3.1 `QueryWorkbenchTopToolbar`

New file: `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbar.kt`

A horizontal `Surface` row, ~48dp tall, color `surfaceContainerLow`, no elevation (visually an extension of the scaffold's top bar). Rendered into the `Column` inside `QueryWorkbenchContentSection` above the existing `QueryEditorScreen`.

Slot layout (left → right):

```
┌────────────────────────────────────────────────────────────┐
│ ▶ Run    ⌖ Local ▾                                    ⚙   │
└────────────────────────────────────────────────────────────┘
```

| Slot | Composable | Behavior |
|---|---|---|
| Run | `IconButton` → `Icons.Outlined.PlayArrow` (primary tint); swaps to `CircularProgressIndicator(size = 18.dp, strokeWidth = 2.dp)` while `isExecuting` | Tap: `LocalSoftwareKeyboardController.current?.hide()` then `vm.executeQuery()`. Disabled if `isExecuting || queryText.isBlank()` |
| Target | `FilterChip` with leading icon `Icons.Outlined.Storage` (Local) / `Icons.Outlined.Cloud` (HTTP), label = current mode, trailing `KeyboardArrowDown` | Tap opens `DropdownMenu` with one item per `executeModes` value, current item ticked. When `executeModes.size == 1`, chip is still tappable but the menu shows only "Local ✓" so the affordance is consistent and layout doesn't shift when HTTP becomes available |
| Spacer | `Modifier.weight(1f)` | Pushes Options to the trailing edge |
| Options | `IconButton` → `Icons.Outlined.Tune` | Tap opens an anchored `DropdownMenu` (~280dp wide) with two `DropdownMenuItem`s, each containing a label + trailing `Switch`. Toggles persist via VM setters |

### 3.2 Options popover

```
┌─────────────────────────────────┐
│ Capture profiling data    [●]   │  ← default ON, session-scoped
│ Capture query metrics     [●]   │  ← default ON, session-scoped
└─────────────────────────────────┘
```

Both switches default to ON every session. State persists across rail-section switches via `QueryWorkbenchState` but is **not** persisted to disk in this plan.

### 3.3 Bottom bar changes

`QueryWorkbenchBottomBar` loses its Run `IconButton` (the first child in the inner Row). Everything else — peers chip + dropdown, pagination, page-size submenu, Clear Results overflow — stays. The Surface visual treatment is unchanged.

Conceptual narrowing: with Run gone, the bottom bar's purpose becomes "result-time controls" (peers chip about the live mesh; pagination/page-size/clear about the result set). The new top toolbar becomes "execution-time controls" (Run, target, options).

### 3.4 Keyboard dismiss

Wired only on the new Run `IconButton`. Hardware-keyboard users running with Ctrl/Cmd+Enter in the editor are unaffected (no IME open to dismiss).

## 4. State & ViewModel

### 4.1 `QueryWorkbenchState` additions

In `app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt`:

```kotlin
val executeMode: MutableStateFlow<String> = MutableStateFlow("Local")
val executeModes: MutableStateFlow<List<String>> = MutableStateFlow(listOf("Local"))
val captureProfilingData: MutableStateFlow<Boolean> = MutableStateFlow(true)
val captureQueryMetrics: MutableStateFlow<Boolean> = MutableStateFlow(true)
```

Session-scoped so the user's mode pick and toggle states survive rail-section switches — same draft-survival pattern as `queryText` and `queryResult`.

### 4.2 Computing `executeModes`

Done once in `MainStudioViewModel` when the studio scope hydrates (it already knows the active `DittoDatabase`). Logic mirrors SwiftUI verbatim:

```kotlin
workbench.executeModes.value = if (db.httpApiUrl.isBlank() || db.httpApiKey.isBlank())
    listOf("Local") else listOf("Local", "HTTP")
if (workbench.executeMode.value !in workbench.executeModes.value) {
    workbench.executeMode.value = "Local"
}
```

The reset branch handles the case where the user edits a config mid-session and HTTP credentials disappear.

### 4.3 `QueryEditorViewModel` additions

Exposes the new flows verbatim using the existing `asStateFlow()` pattern and gains three setters:

```kotlin
fun setExecuteMode(mode: String) { workbench.executeMode.value = mode }
fun setCaptureProfilingData(enabled: Boolean) { workbench.captureProfilingData.value = enabled }
fun setCaptureQueryMetrics(enabled: Boolean) { workbench.captureQueryMetrics.value = enabled }
```

### 4.4 `executeQuery()` change

One-line diff: `queryExecutionService.execute(query)` becomes `queryExecutionService.execute(query, mode = workbench.executeMode.value)`. The facade dispatches; the VM stays oblivious to local-vs-HTTP. History save, metrics record, and error capture stay identical regardless of mode.

`explainQuery()` always uses the local service regardless of the picker (matches SwiftUI — "PROFILE is local-only for v1"). It calls the facade with a fixed `mode = "Local"` to future-proof.

### 4.5 Persistence

None. Toggles default ON every session. DataStore persistence is explicit follow-up work (see §8).

## 5. HTTP Execution Path

### 5.1 Dependencies

Added to `gradle/libs.versions.toml`:

- `okhttp = "4.12.0"` — single artifact, no companion modules required, compatible with AGP 9 / Kotlin 2.3.21
- `okhttp-mockwebserver` (testImplementation only, same version)
- `kotlinx-serialization-json` — already in the catalog at 1.8.0 from the QR-code feature

### 5.2 `HttpQueryExecutionService`

New file: `app/src/main/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionService.kt`

```kotlin
class HttpQueryExecutionService(
    private val client: OkHttpClient,
    private val json: Json,
    private val sessionProvider: () -> DittoDatabase?,
) {
    suspend fun execute(query: String): QueryResult = withContext(Dispatchers.IO) {
        val db = sessionProvider() ?: error("No active database")
        require(db.httpApiUrl.isNotBlank() && db.httpApiKey.isNotBlank()) {
            "HTTP execution requires httpApiUrl and httpApiKey"
        }
        val url = "https://${db.httpApiUrl}/api/v5/store/execute"
        val body = json.encodeToString(JsonObject(mapOf("statement" to JsonPrimitive(query))))
            .toRequestBody("application/json".toMediaType())
        val request = Request.Builder()
            .url(url)
            .post(body)
            .header("Authorization", "Bearer ${db.httpApiKey}")
            .build()
        val start = System.currentTimeMillis()
        client.newCall(request).execute().use { response ->
            val elapsed = System.currentTimeMillis() - start
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) throw QueryExecutionException(response.code, text)
            parseResponse(text, elapsed)
        }
    }
}
```

### 5.3 Response parsing

Mirrors SwiftUI's branching in `QueryService.executeSelectedAppQueryHttp`:

1. If `mutatedDocumentIds` is non-empty → return one synthetic doc per id (`{"_id": id}`) plus a sentinel `{"commitId": "..."}` doc when present. This keeps the results pane render-compatible across modes.
2. Else if `items` is a JSON array → parse each into `Map<String, Any?>` using the same `parseJsonToMap` helper that `LocalQueryExecutionService` uses today (moved to a top-level util `JsonToMap.kt` so both services share it).
3. Else → wrap the raw body as a single `{"_raw": "<text>"}` doc so the results pane still renders something.

### 5.4 `allowUntrustedCerts` handling

When `db.allowUntrustedCerts == true`, build a per-execute OkHttp client that installs a trust-all `X509TrustManager` and a permissive hostname verifier. OkHttp clients share connection pools when constructed via `client.newBuilder()`, so per-execute construction is cheap.

A file-level Kdoc note in `HttpQueryExecutionService.kt` flags this as dev/test-only.

### 5.5 Facade refactor

`QueryExecutionService` becomes a dispatcher:

```kotlin
class QueryExecutionService(
    private val localService: LocalQueryExecutionService,
    private val httpService: HttpQueryExecutionService,
) {
    suspend fun execute(query: String, mode: String): QueryResult =
        if (mode == "HTTP") httpService.execute(query) else localService.execute(query)

    suspend fun explain(query: String): QueryResult = localService.explain(query)
}
```

The Koin `DataModule` registers all three (`LocalQueryExecutionService`, `HttpQueryExecutionService`, the facade) and wires `sessionProvider` to read the active `DittoDatabase` from `StudioSession`.

### 5.6 Error mapping

Non-2xx body → throw `QueryExecutionException(httpStatus: Int, body: String) : RuntimeException("HTTP $httpStatus: $body")`. Lives next to the HTTP service. The existing `runCatching` block in `executeQuery()` catches it and surfaces `e.message` as the execution error — no new error UI needed.

### 5.7 EXPLAIN over HTTP

Out of scope for v1 (matches SwiftUI's "PROFILE is local-only for v1"). `QueryEditorViewModel.explainQuery()` always uses the local service regardless of the picker.

## 6. Testing

### 6.1 Unit tests (`app/src/test/...`)

**`QueryEditorViewModelTest`** (existing — extended):

- `setExecuteMode("HTTP") updates session state`
- `setCaptureProfilingData(false)` / `setCaptureQueryMetrics(false)` flip the session flows
- `executeQuery() passes current mode to the execution service` — uses a `FakeQueryExecutionService` that records the last `mode` arg
- `executeQuery() with HTTP mode still records history and metrics identically to Local`
- Existing tests stay green (no regression for the Local path)

**`MainStudioViewModelTest`** (existing — extended):

- `executeModes is ["Local"] when httpApiUrl is blank`
- `executeModes is ["Local","HTTP"] when both httpApiUrl and httpApiKey are set`
- `executeMode resets to "Local" if the active config drops HTTP credentials mid-session`

**`HttpQueryExecutionServiceTest`** (new) — uses `okhttp3.mockwebserver`:

- Sends `POST /api/v5/store/execute` with `Authorization: Bearer <key>` and body `{"statement":"<query>"}`
- Parses `items` response into the expected `QueryResult.documents` shape
- Parses `mutatedDocumentIds` + `commitId` into synthetic docs
- Non-2xx response surfaces as an exception with the response body in the message
- `allowUntrustedCerts = true` produces a client that accepts MockWebServer's self-signed cert

**`QueryExecutionServiceTest`** (new) — facade-level:

- `mode == "Local"` delegates to the local service; HTTP service is not invoked
- `mode == "HTTP"` delegates to the HTTP service; local service is not invoked
- `mode == "HTTP"` when HTTP credentials are missing throws immediately (defensive — the picker should have prevented this, but the facade enforces it)

### 6.2 Compose UI tests (`app/src/androidTest/...`)

**`QueryWorkbenchTopToolbarTest`** (new):

- Run button shows `PlayArrow` when idle, `CircularProgressIndicator` when `isExecuting`
- Run button is disabled when `queryText` is blank
- FilterChip label reflects current `executeMode`
- FilterChip with `executeModes = ["Local"]` opens menu showing one item
- FilterChip with `executeModes = ["Local","HTTP"]` opens menu showing both, selected one ticked
- Options icon opens a popover; the two switches reflect state and toggle on click
- On Run tap: keyboard controller's `hide()` is invoked (verified via a test-double `SoftwareKeyboardController` injected through `LocalSoftwareKeyboardController`)

**`QueryWorkbenchBottomBarTest`** (existing — touched lightly):

- Assert Run icon is **no longer** present in the bottom bar (regression guard)
- Existing pagination / peers / page-size / clear-results assertions stay green

### 6.3 End-to-end tests (instrumented)

New `QueryWorkbenchE2ETest` class in `androidTest/java/.../ui/mainstudio/`:

- Uses `createAndroidComposeRule<MainActivity>()` so the full studio scaffold + nav graph mount
- Seeds a deterministic `DittoDatabase` row into the test instance's Room DB before launch via a `@Before` block (avoids tapping through the database list)
- Boots an in-process `MockWebServer` for the HTTP scenarios; the seeded `httpApiUrl` points at `localhost:${mockWebServer.port}` with `allowUntrustedCerts = true`
- All new toolbar widgets are tagged with `Modifier.testTag(...)`: `"QueryToolbar.Run"`, `"QueryToolbar.TargetChip"`, `"QueryToolbar.Options"`, `"QueryOptions.CaptureProfiling"`, `"QueryOptions.CaptureMetrics"`

**Scenarios:**

1. **Local happy path** — type `SELECT * FROM __collections` → tap Run → assert spinner appears → assert results pane renders ≥1 row → assert Run icon returns
2. **HTTP happy path** — tap chip → pick "HTTP" → enqueue MockWebServer `{items:[…]}` → tap Run → assert MockWebServer's recorded request has `Authorization: Bearer <test-key>` and body `{"statement":"SELECT…"}` → assert results render
3. **HTTP mutation result** — enqueue `{"mutatedDocumentIds":["abc","def"],"commitId":"c1"}` → run an `UPDATE` → assert synthetic docs render
4. **HTTP error surfacing** — enqueue 401 with body `{"error":"unauthorized"}` → tap Run → assert error message in results pane, Run re-enabled
5. **Mode persistence across navigation** — pick HTTP → switch rail to Subscriptions → switch back → assert chip still says "HTTP"
6. **HTTP item hidden when unconfigured** — variant `@Before` seeds blank `httpApiUrl` → open chip → assert only "Local" in menu
7. **Mid-session credential change** — start with HTTP configured + selected, update the DB row to clear `httpApiUrl` → assert chip falls back to "Local"
8. **Keyboard dismiss on Run** — focus the editor → assert IME up via `KeyboardHelper.waitUntilShown()` → tap Run → assert IME hidden within 1s before results render
9. **Options toggles persist for session** — flip both off → close menu → reopen → assert still off → relaunch activity → assert both back to default ON (no DataStore)
10. **Bottom bar regression** — `onNodeWithTag("QueryBottomBar.Run").assertDoesNotExist()` guards against accidentally leaving the old Run icon

**Device matrix:**

| Form factor | Target | Layout exercised |
|---|---|---|
| Phone (drawer mode, <840dp) | **Pixel 10a — `ANDROID_SERIAL=58300DLCR0000L`** | Drawer + IME dismiss assertions are only meaningful here |
| Tablet (multi-pane, ≥840dp) | **Gradle Managed Device `tabletApi34`** — Pixel Tablet AVD, API 34, AOSP-ATD | Toolbar coexists with rail + inspector |

**Gradle Managed Device wiring** in `app/build.gradle.kts`:

```kotlin
android {
    testOptions {
        managedDevices {
            devices {
                create<com.android.build.api.dsl.ManagedVirtualDevice>("tabletApi34") {
                    device = "Pixel Tablet"
                    apiLevel = 34
                    systemImageSource = "aosp-atd"
                }
            }
        }
    }
}
```

**Run commands:**

```bash
# Phone leg — real device
ANDROID_SERIAL=58300DLCR0000L ./gradlew connectedAndroidTest

# Tablet leg — managed emulator (auto-creates, boots, tears down)
./gradlew tabletApi34DebugAndroidTest
```

The Samsung tablet (R5GL15XPVGA) is intentionally not targeted — it's reserved for other test runs. Gradle Managed Devices isolate the tablet leg with a dedicated serial so no collision can occur with whatever device set is attached.

**Caveat:** the AOSP-ATD system image is downloaded the first time (~600MB); subsequent runs are fast. The plan will note this in its setup step.

Both legs must pass before merge.

### 6.4 Manual smoke checklist

1. Phone-width with HTTP not configured: open editor, tap chip → menu shows only Local
2. Phone-width with HTTP configured: pick HTTP, run a SELECT, verify results
3. Tap into editor, type a query, tap Run while IME is open → IME dismisses before results render
4. Toggle profiling/metrics switches in Options → both persist for the session, reset on app restart
5. Tablet (≥840dp) with Inspector visible: the new toolbar does not push the inspector down

## 7. Files Touched

**New files:**

- `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbar.kt`
- `app/src/main/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionService.kt`
- `app/src/main/java/com/costoda/dittoedgestudio/data/repository/LocalQueryExecutionService.kt` (renamed from existing `QueryExecutionService.kt`; the facade keeps the old name)
- `app/src/main/java/com/costoda/dittoedgestudio/data/repository/JsonToMap.kt` (extracted helper, shared by both execution services)
- `app/src/test/java/com/costoda/dittoedgestudio/data/repository/HttpQueryExecutionServiceTest.kt`
- `app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionServiceTest.kt`
- `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbarTest.kt`
- `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchE2ETest.kt`

**Modified files:**

- `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchSection.kt` — inserts `QueryWorkbenchTopToolbar` in `QueryWorkbenchContentSection`; removes Run from `QueryWorkbenchBottomBar`
- `app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt` — adds the four new flows to `QueryWorkbenchState`
- `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt` — exposes flows + setters; one-line `executeQuery()` change
- `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt` — computes `executeModes` on hydration and on config change
- `app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryExecutionService.kt` — becomes the dispatcher facade
- `app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt` — registers OkHttp client, both execution services, and the facade
- `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt` — extends with mode + toggle coverage
- `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModelTest.kt` — extends with `executeModes` derivation coverage
- `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchBottomBarTest.kt` — adds Run-absence regression guard
- `gradle/libs.versions.toml` — adds OkHttp + MockWebServer entries
- `app/build.gradle.kts` — adds OkHttp dependencies + Gradle Managed Device wiring

## 8. Out of Scope (Explicit)

- **EXPLAIN over HTTP** — local-only in v1, matches SwiftUI
- **DataStore persistence of Options toggles** — toggles default ON every session
- **Behavioral gating from Options toggles** — `Capture profiling data` and `Capture query metrics` are wired to state but do not yet change what `executeQuery()` captures. A follow-up plan will route these through the metrics path
- **`X-DITTO-API-KEY` header variant** — SwiftUI uses `Authorization: Bearer`; we match that exactly
- **Query cancellation** — no Cancel button. Tapping Run while a query is executing is disabled (matches today's behavior in the bottom bar)
- **Persisting executeMode across activity restarts** — session-scoped only; resets to "Local" on app launch

## 9. References

- SwiftUI VM: `SwiftUI/EdgeStudio/Views/StudioView/ViewModels/QueryViewModel.swift` (lines 86–98 for `executeModes` derivation)
- SwiftUI HTTP path: `SwiftUI/EdgeStudio/Data/QueryService.swift` (`executeSelectedAppQueryHttp`, lines 268–347)
- Android UI terminology: `android/CLAUDE.md` § "UI Layout Terminology"
- Plan location convention: `android/CLAUDE.md` § "Plans"
- Device-targeting rules: `android/CLAUDE.md` § "Build Commands" (ANDROID_SERIAL requirement)
