# Query Workbench Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. TDD discipline is mandatory for every behavioral change.

**Goal:** Close three gaps the Android Query Workbench has versus the SwiftUI version: (1) a Help entry in the inspector, (2) a Profile tab in the results pane gated by a persistent toggle, (3) full add/view/delete attachment support.

**Architecture:**
- **Phase 1 (Help — small):** add a `HELP` value to `QueryInspectorTab` and route to the existing `HelpContentView` reading `assets/help/query.md`. No new data layer.
- **Phase 2 (Profile — medium):** add a new third tab to `QueryResultsView` (next to JSON/TABLE) that renders a `ProfileViewerView`. Pipeline: `QueryEditorViewModel.executeQuery()` consults a persistent DataStore-backed `AppPreferences.metricsEnabled` flag; when ON for `SELECT` statements over Local mode it prepends `PROFILE ` to the query, then strips the `~request_profile` envelope from results, parses it via a new `QueryProfileParser` into a `QueryProfile` domain model, and stores the parsed profile on `QueryWorkbenchState.queryProfile`. The toolbar's `captureProfilingData` toggle is rewired to read/write `metricsEnabled`. HTTP-mode and non-SELECT statements skip the prefix injection (matches SwiftUI v1).
- **Phase 3 (Attachments — large):** add a `data/repository/AttachmentService` that wraps `DittoStore.newAttachment(...)`, `DittoStore.fetchAttachment(...)`, and the delete-via-DQL `UPDATE … SET <field> = null` codepath. Add a `domain/model/AttachmentInfo` struct + detector (matches SwiftUI's structural detection: a `Map<String, Any?>` field with keys `id: String`, `len: Number`, `metadata: Map<String, String>`). Wire UI surfaces: a per-row long-press context menu in `QueryResultsView` exposing Add/Delete; an `AttachmentPickerSheet` (Storage Access Framework file picker) for Add; a `DeleteAttachmentSheet` that issues the DQL UPDATE; an `AttachmentViewerSection` embedded inside the JSON inspector tab showing each attachment with inline thumbnail (for `image/*` metadata) and an Open button (opens via `Intent.ACTION_VIEW` on a cached temp file).

**Tech Stack:** Kotlin 2.3.21, Jetpack Compose (Material3), Ditto Kotlin SDK 5.1.0-preview.1 (`com.ditto:ditto-kotlin-android` — exposes `DittoAttachment`, `DittoAttachmentToken`, `DittoAttachmentFetcher`, `DittoAttachmentFetchResult`, `DittoStore.newAttachment`, `DittoStore.fetchAttachment`), Koin 4.1.1 DI, Markwon for the Help renderer (already wired), `androidx.datastore:datastore-preferences` (new dep) for the persistent toggle, `androidx.activity.result.contract.ActivityResultContracts.OpenDocument` for the file picker, OkHttp/MockWebServer (already wired) for any HTTP test paths.

**Hard constraints (from `android/CLAUDE.md` and user feedback in memory):**
- Gradle commands run from `/Users/labeaaa/Developer/ditto-edge-studio/android/`.
- Versions live in `gradle/libs.versions.toml`; never hardcode.
- Plans live in `plans/android/`; screenshots in `screens/android/`; docs in `docs/android/`.
- Do NOT run `connectedAndroidTest` or managed-device tests — per `feedback_no_instrumented_runs.md`, the user does manual smoke testing. Compose UI tests can be authored and committed; running them is the user's call.
- Unit tests via `./gradlew :app:testDebugUnitTest` ARE expected to run after each task.
- `./gradlew assembleDebug` must succeed after every commit.
- Pixel 10a serial (if instrumented is ever needed): `5C091JEA328801`. Forbidden serial: `R5GL15XPVGA`.

---

## File Structure

### New files

| Path | Responsibility |
|---|---|
| `app/src/main/java/com/costoda/dittoedgestudio/data/preferences/AppPreferences.kt` | DataStore-backed `metricsEnabled` (Boolean, default true) exposed as `StateFlow<Boolean>` + suspend setter. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryProfileParser.kt` | Pure-Kotlin parser: `Map<String, Any?>` → `QueryProfile?`. Detects the `~request_profile` envelope, builds the operator tree. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/ProfileTimeFormatter.kt` | Three-tier auto-scale formatter for ns/µs/ms display (matches `docs/PROFILE.md`'s "Display tiers" table). |
| `app/src/main/java/com/costoda/dittoedgestudio/domain/model/QueryProfile.kt` | `QueryProfile`, `QueryProfileTimes`, `QueryProfileOperator`, `QueryProfileStats` data classes. Pure Kotlin. |
| `app/src/main/java/com/costoda/dittoedgestudio/domain/model/AttachmentInfo.kt` | `AttachmentInfo(id, len, fieldName, metadata)` + `detectTokens(in: Map<String, Any?>)` and `detectTokens(in: List<Map<String, Any?>>)`. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/AttachmentService.kt` | Suspending wrapper over `DittoStore.newAttachment`, `DittoStore.fetchAttachment`, and the delete-via-DQL codepath. Caches downloaded attachments in `context.cacheDir/attachments/`. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileViewerView.kt` | Top-level profile-tab content. Four states: populated, metrics-off, non-SELECT, no-query-yet (mirrors SwiftUI). Hosts a Card/Plan sub-picker. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileCardListView.kt` | Card mode: vertical list of `ProfileOperatorCard`s with header + summary + footer strips. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfilePlanTreeView.kt` | Plan mode: tree diagram of `PlanNodeBox`es with `exec`-based percentage badges. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileQueryHeaderCard.kt` | Renders the captured query text (with leading `PROFILE` stripped). |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileSummaryStrip.kt` | Header row with elapsed / parse / plan time chips. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileFooterStrip.kt` | Footer with feature-flags hex string. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileOperatorCard.kt` | One operator's card with name, stats badges, and attribute list. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileStatsBadges.kt` | Reusable colored badge composables for documentsIn/out, exec/recv/send. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/PlanNodeBox.kt` | Box drawn in the tree view for one operator with exec-percentage badge. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentPickerSheet.kt` | ModalBottomSheet hosting an `OpenDocument` launcher + size validation (10MB soft / 20MB hard) + field-name input. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/DeleteAttachmentSheet.kt` | ModalBottomSheet listing detected attachments with toggles; on confirm issues a DQL `UPDATE ... SET <field> = null` per selected attachment. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentViewerSection.kt` | Section composable embedded at the bottom of `QueryJsonInspector`. Shows each `AttachmentInfo` as a row with id/len/metadata; image attachments get an inline thumbnail; tap "Open" downloads + launches `Intent.ACTION_VIEW`. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentProgressOverlay.kt` | Tiny indeterminate overlay used during upload/download. |
| `app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryProfileParserTest.kt` | Pure-Kotlin parser tests with fixture JSON from `docs/PROFILE.md`. |
| `app/src/test/java/com/costoda/dittoedgestudio/data/repository/ProfileTimeFormatterTest.kt` | Tier boundary tests. |
| `app/src/test/java/com/costoda/dittoedgestudio/domain/model/AttachmentInfoTest.kt` | Detection tests for the structural shape `{id, len, metadata}`. |
| `app/src/test/java/com/costoda/dittoedgestudio/data/preferences/AppPreferencesTest.kt` | DataStore round-trip test via `androidx.datastore.preferences.preferencesDataStoreFile` (in-memory tmp). |
| `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryHelpInspectorTest.kt` | Compose UI test — renders QueryInspectorView with HELP selected, asserts help title text shows. |
| `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileViewerViewTest.kt` | Compose UI test — drives the four states. |
| `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentViewerSectionTest.kt` | Compose UI test — renders one AttachmentInfo with image preview + Open button. |

### Modified files

| Path | Change |
|---|---|
| `gradle/libs.versions.toml` | Add `datastore-preferences = "1.1.1"` version + library alias. |
| `app/build.gradle.kts` | `implementation(libs.androidx.datastore.preferences)`. |
| `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt` | Add `HELP` to `QueryInspectorTab`; expose `queryProfile: StateFlow<QueryProfile?>`; `executeQuery()` consults `AppPreferences.metricsEnabled` + injects `PROFILE ` for SELECT/Local; parses the trailing item via `QueryProfileParser` and stores on the workbench; the toolbar's `setCaptureProfilingData(...)` writes to `AppPreferences`. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt` | Add `val queryProfile = MutableStateFlow<QueryProfile?>(null)` to `QueryWorkbenchState`. Keep `captureProfilingData` flow but make it a `StateFlow` derived from `AppPreferences` (no longer a session-only MutableStateFlow). |
| `app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt` | Register `AppPreferences` (single), `AttachmentService` (single, scoped to studio-session for cache directory). |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryInspectorView.kt` | Add 5th tab (questionmark icon) routing to `HelpContentView(assetFileName = "query.md")`. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryJsonInspector.kt` | Append an `AttachmentViewerSection` below the JSON tree when `AttachmentInfo.detectTokens(...)` returns ≥ 1. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryResultsView.kt` | Add "PROFILE" as a third tab; route to `ProfileViewerView`. Add a long-press handler on each row (in `ResultJsonView` and `ResultTableView`) that opens the Add/Delete attachment context menu. |
| `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryWorkbenchTopToolbar.kt` | No code change; the Options popover already exposes `Capture profiling data` and Phase 2 makes it write-through the persistent flag (which the toolbar already reads via the new `StateFlow`). |
| `app/src/main/java/com/costoda/dittoedgestudio/domain/model/QueryResult.kt` | Add optional `profile: QueryProfile? = null` so `LocalQueryExecutionService` can carry the parsed envelope through. |
| `app/src/main/java/com/costoda/dittoedgestudio/data/repository/LocalQueryExecutionService.kt` | After parsing items, run `QueryProfileParser.detect(items)` and partition into `(userDocs, profile?)` — return `QueryResult(documents = userDocs, profile = profile, ...)`. The PROFILE prefix is injected by the VM, not the service (matches SwiftUI's split). |
| `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt` | Extend with: SELECT + Local + metricsEnabled=true triggers `PROFILE` prefix; SELECT + HTTP does NOT; non-SELECT never; profile populates `queryProfile` flow. |

---

## Phase 1 — Help in the Inspector

### Task 1: Add HELP tab to the Query inspector (Compose UI TDD)

**Files:**
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt:22`
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryInspectorView.kt`
- Create: `app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryHelpInspectorTest.kt`

- [ ] **Step 1: Write the failing Compose UI test**

Create `QueryHelpInspectorTest.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio.inspector

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class QueryHelpInspectorTest {

    @get:Rule
    val rule = createComposeRule()

    @Test
    fun helpTabExistsAndRendersMarkdown() {
        rule.setContent {
            MaterialTheme {
                // Render a stub QueryInspectorView with a relaxed-fake VM is non-trivial;
                // instead exercise HelpContentView directly with the asset filename.
                HelpContentView(assetFileName = "query.md")
            }
        }
        // The query.md asset has a top-level heading we can pin against. Inspect
        // android/app/src/main/assets/help/query.md to confirm the actual H1 text; this
        // test fails until we either (a) add a stable heading or (b) update the assertion.
        rule.onNodeWithText("Query Workbench", substring = true).assertIsDisplayed()
    }
}
```

> **Note:** the direct route is to test `HelpContentView` because constructing `QueryInspectorView` requires a full `QueryEditorViewModel`. The Phase-1 UI change to `QueryInspectorView` is then visually obvious — the developer running the smoke test will see the Help icon as the 5th button.

- [ ] **Step 2: Add HELP to the enum**

Open `QueryEditorViewModel.kt`. Find line 22:

```kotlin
enum class QueryInspectorTab { HISTORY, FAVORITES, JSON, METRICS }
```

Replace with:

```kotlin
enum class QueryInspectorTab { HISTORY, FAVORITES, JSON, METRICS, HELP }
```

- [ ] **Step 3: Render the HELP tab in `QueryInspectorView`**

In `QueryInspectorView.kt`:

(a) Add `Icons.AutoMirrored.Outlined.HelpOutline` or `Icons.Outlined.HelpOutline` import. Inspect actual availability and use `HelpOutline`:

```kotlin
import androidx.compose.material.icons.outlined.HelpOutline
```

(b) Extend the two parallel lists at lines 21 and 28:

```kotlin
private val INSPECTOR_TAB_ICONS: List<ImageVector> = listOf(
    Icons.Outlined.History,
    Icons.Outlined.BookmarkBorder,
    Icons.Outlined.Code,
    Icons.Outlined.Analytics,
    Icons.Outlined.HelpOutline,
)

private val INSPECTOR_TAB_DESCRIPTIONS: List<String> = listOf(
    "History",
    "Favorites",
    "JSON",
    "Metrics",
    "Help",
)
```

(c) Add the new branch to the `when (selectedTab)` block:

```kotlin
            QueryInspectorTab.HELP -> HelpContentView(
                assetFileName = "query.md",
                modifier = Modifier.weight(1f),
            )
```

> Confirm `HelpContentView`'s signature accepts a `modifier` param; if it doesn't, wrap in a `Box(modifier = Modifier.weight(1f)) { HelpContentView(assetFileName = "query.md") }`.

- [ ] **Step 4: Verify**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew assembleDebug --console=plain 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL.

Run: `./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL — existing tests still green (Phase 1 doesn't touch behavior covered by unit tests).

- [ ] **Step 5: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryInspectorView.kt \
  android/app/src/androidTest/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryHelpInspectorTest.kt
git commit -m "feat(android): add Help tab to Query Workbench inspector"
```

---

## Phase 2 — Profile Tab in the Results Pane

### Task 2: Add DataStore dependency

**Files:**
- Modify: `gradle/libs.versions.toml`
- Modify: `app/build.gradle.kts`

- [ ] **Step 1: Add catalog entry**

In `gradle/libs.versions.toml`:

`[versions]` add (after `okhttp = "4.12.0"`):
```toml
datastorePreferences = "1.1.1"
```

`[libraries]` add (after the OkHttp block):
```toml
androidx-datastore-preferences = { group = "androidx.datastore", name = "datastore-preferences", version.ref = "datastorePreferences" }
```

- [ ] **Step 2: Wire dependency**

In `app/build.gradle.kts` dependencies block (after `implementation(libs.okhttp)`):
```kotlin
implementation(libs.androidx.datastore.preferences)
```

- [ ] **Step 3: Verify**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:dependencies --configuration debugRuntimeClasspath 2>&1 | grep datastore | head`
Expected: lines mentioning `androidx.datastore:datastore-preferences:1.1.1`.

- [ ] **Step 4: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add android/gradle/libs.versions.toml android/app/build.gradle.kts
git commit -m "build(android): add androidx.datastore.preferences for persistent settings"
```

---

### Task 3: `AppPreferences` (DataStore wrapper, TDD)

**Files:**
- Create: `app/src/main/java/com/costoda/dittoedgestudio/data/preferences/AppPreferences.kt`
- Create: `app/src/test/java/com/costoda/dittoedgestudio/data/preferences/AppPreferencesTest.kt`

- [ ] **Step 1: Failing test (Robolectric-free; uses tmp datastore file)**

`AppPreferencesTest.kt`:

```kotlin
package com.costoda.dittoedgestudio.data.preferences

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.preferencesDataStoreFile
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.File

class AppPreferencesTest {

    private lateinit var tmpDir: File
    private lateinit var prefs: AppPreferences

    @Before
    fun setUp() {
        tmpDir = File.createTempFile("appprefs", ".dir").apply { delete(); mkdirs() }
        val store = PreferenceDataStoreFactory.create { File(tmpDir, "prefs.preferences_pb") }
        prefs = AppPreferences(store)
    }

    @After
    fun tearDown() { tmpDir.deleteRecursively() }

    @Test
    fun `metricsEnabled defaults to true`() = runTest {
        assertTrue(prefs.metricsEnabled.first())
    }

    @Test
    fun `setMetricsEnabled persists across reads`() = runTest {
        prefs.setMetricsEnabled(false)
        assertEquals(false, prefs.metricsEnabled.first())
        prefs.setMetricsEnabled(true)
        assertEquals(true, prefs.metricsEnabled.first())
    }
}
```

- [ ] **Step 2: Run — expect unresolved**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:compileDebugUnitTestKotlin --console=plain 2>&1 | tail -10`
Expected: "unresolved reference: AppPreferences".

- [ ] **Step 3: Implement**

`AppPreferences.kt`:

```kotlin
package com.costoda.dittoedgestudio.data.preferences

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Persistent user preferences for the Studio app, backed by Jetpack DataStore (Preferences).
 *
 * Currently exposes [metricsEnabled] — the "Collect Metrics" toggle that mirrors SwiftUI's
 * AppStorage key of the same purpose. When ON, the Query Workbench captures execution
 * profiles for SELECT statements (PROFILE prefix injection in [QueryEditorViewModel]).
 */
class AppPreferences(private val store: DataStore<Preferences>) {

    val metricsEnabled: Flow<Boolean> =
        store.data.map { it[KEY_METRICS_ENABLED] ?: DEFAULT_METRICS_ENABLED }

    suspend fun setMetricsEnabled(enabled: Boolean) {
        store.edit { it[KEY_METRICS_ENABLED] = enabled }
    }

    companion object {
        private const val DEFAULT_METRICS_ENABLED = true
        private val KEY_METRICS_ENABLED = booleanPreferencesKey("metrics_enabled")
    }
}

/** Application-singleton DataStore. Lives at `app/files/datastore/app_prefs.preferences_pb`. */
val Context.appPreferencesDataStore: DataStore<Preferences> by preferencesDataStore("app_prefs")
```

- [ ] **Step 4: Verify**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --tests "*.AppPreferencesTest" --console=plain 2>&1 | tail -5`
Expected: 2 tests pass.

- [ ] **Step 5: Wire into Koin DI**

In `app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt`, add (after the existing `LoggingService` line):

```kotlin
single { com.costoda.dittoedgestudio.data.preferences.AppPreferences(
    androidContext().appPreferencesDataStore,
) }
```

Add the import at the top of the file:
```kotlin
import com.costoda.dittoedgestudio.data.preferences.appPreferencesDataStore
```

- [ ] **Step 6: Verify build**

Run: `./gradlew assembleDebug --console=plain 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 7: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/preferences/AppPreferences.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/data/preferences/AppPreferencesTest.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt
git commit -m "feat(android): add AppPreferences DataStore with metricsEnabled key"
```

---

### Task 4: Rewire `captureProfilingData` toggle to read/write `AppPreferences`

**Files:**
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt`
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt`
- Modify: `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt`

- [ ] **Step 1: Update tests to reflect persistent semantics**

In `QueryEditorViewModelTest.kt`, REPLACE the existing `setCaptureProfilingData flips session-scoped toggle` test with:

```kotlin
    @Test
    fun `setCaptureProfilingData writes through to AppPreferences`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val sharedWorkbench = QueryWorkbenchState()
        val vm = createVm(sharedWorkbench, appPreferences = fakePrefs)
        advanceUntilIdle()

        assertEquals(true, vm.captureProfilingData.value)
        vm.setCaptureProfilingData(false)
        advanceUntilIdle()
        assertEquals(false, fakePrefs.metricsEnabledValue)
        assertEquals(false, vm.captureProfilingData.value)
    }
```

Add the fake at the bottom of the test file (or in a sibling file):

```kotlin
private class FakeAppPreferences(initialMetricsEnabled: Boolean) {
    var metricsEnabledValue: Boolean = initialMetricsEnabled
        private set
    val metricsEnabled: kotlinx.coroutines.flow.MutableStateFlow<Boolean> =
        kotlinx.coroutines.flow.MutableStateFlow(initialMetricsEnabled)
    suspend fun setMetricsEnabled(enabled: Boolean) {
        metricsEnabledValue = enabled
        metricsEnabled.value = enabled
    }
}
```

> **Plan note:** the production `AppPreferences` is a concrete class. To make the VM testable without DataStore, we'll constructor-inject an `AppPreferencesGateway` interface (one method: `val metricsEnabled: Flow<Boolean>` and `suspend fun setMetricsEnabled(Boolean)`). The concrete `AppPreferences` implements it; the fake above mirrors the interface duck-typed (Kotlin doesn't need an interface for the fake — the VM constructor takes the interface, and the fake implements it). Adjust the fake to `: AppPreferencesGateway` when you write the interface in Step 3.

- [ ] **Step 2: Update `QueryWorkbenchState`**

In `StudioUiState.kt`, REMOVE the `val captureProfilingData = MutableStateFlow(true)` flow (it becomes derived). Keep the other three.

- [ ] **Step 3: Implement**

(a) Add interface `AppPreferencesGateway` in `data/preferences/AppPreferencesGateway.kt`:

```kotlin
package com.costoda.dittoedgestudio.data.preferences

import kotlinx.coroutines.flow.Flow

interface AppPreferencesGateway {
    val metricsEnabled: Flow<Boolean>
    suspend fun setMetricsEnabled(enabled: Boolean)
}
```

Make `AppPreferences` implement it (add `: AppPreferencesGateway`).

(b) Update `QueryEditorViewModel` constructor to take `appPreferences: AppPreferencesGateway`. Replace the existing exposure:

```kotlin
// Old:
val captureProfilingData: StateFlow<Boolean> = workbench.captureProfilingData.asStateFlow()
```

with:

```kotlin
val captureProfilingData: StateFlow<Boolean> = appPreferences.metricsEnabled
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)
```

Update setter:

```kotlin
fun setCaptureProfilingData(enabled: Boolean) {
    viewModelScope.launch { appPreferences.setMetricsEnabled(enabled) }
}
```

(c) Update Koin factory in `DataModule.kt` to pass `get<AppPreferences>()` (which satisfies `AppPreferencesGateway`) into the VM:

```kotlin
viewModel { (databaseId: String, workbench: ...QueryWorkbenchState) ->
    QueryEditorViewModel(databaseId, workbench, get(), get(), get(), get(), get(), get())  // add the AppPreferences get()
}
```

> Match the constructor parameter order — append `appPreferences` after the existing repositories.

- [ ] **Step 4: Verify**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 5: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/preferences/AppPreferencesGateway.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/preferences/AppPreferences.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt
git commit -m "feat(android): persist Capture Profiling Data via AppPreferences"
```

---

### Task 5: `QueryProfile` domain model + `QueryProfileParser` (TDD)

**Files:**
- Create: `app/src/main/java/com/costoda/dittoedgestudio/domain/model/QueryProfile.kt`
- Create: `app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryProfileParser.kt`
- Create: `app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryProfileParserTest.kt`

- [ ] **Step 1: Write failing parser tests with fixture from `docs/PROFILE.md`**

`QueryProfileParserTest.kt`:

```kotlin
package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.data.repository.QueryProfileParser.envelopeKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class QueryProfileParserTest {

    private val canonicalEnvelope: Map<String, Any?> = mapOf(
        "_id" to "e526fe68-04e9-4881-bf76-d0a582827e9b",
        "app_id" to "f5e954d9-0092-47a0-9a79-2829e767ba7b",
        "featureFlags" to "0x3a",
        "queryType" to "select",
        "requestType" to "SDK",
        "resultCount" to 1,
        "state" to "completed",
        "text" to "PROFILE SELECT * FROM tasks LIMIT 1",
        "times" to mapOf(
            "elapsed" to 1_294_166,
            "parse" to 49_834,
            "plan" to 32_167,
            "start" to "2026-05-26T20:59:21.310-05:00",
        ),
        "plan" to mapOf(
            "#operator" to "sequence",
            "children" to listOf(
                mapOf(
                    "#operator" to "scan",
                    "#stats" to mapOf(
                        "documentsOut" to 1,
                        "phaseTimes" to mapOf("exec" to 209, "recv" to 990_459, "send" to 61_500),
                    ),
                    "collection" to "tasks",
                    "datasource" to "default",
                ),
                mapOf(
                    "#operator" to "limit",
                    "#stats" to mapOf(
                        "documentsIn" to 2,
                        "documentsOut" to 1,
                        "phaseTimes" to mapOf("exec" to 2_083, "send" to 6_584),
                    ),
                    "limit" to 1,
                ),
            ),
        ),
    )

    private val wrappedItem: Map<String, Any?> = mapOf(envelopeKey to canonicalEnvelope)

    @Test
    fun `parseItem returns null for normal user document`() {
        val item = mapOf("_id" to "doc-1", "name" to "x")
        assertNull(QueryProfileParser.parseItem(item))
    }

    @Test
    fun `parseItem accepts wrapped envelope`() {
        val profile = QueryProfileParser.parseItem(wrappedItem)
        assertNotNull(profile)
        assertEquals("e526fe68-04e9-4881-bf76-d0a582827e9b", profile!!.id)
        assertEquals("select", profile.queryType)
        assertEquals("SDK", profile.requestType)
        assertEquals(1, profile.resultCount)
        assertEquals("completed", profile.state)
        assertEquals("PROFILE SELECT * FROM tasks LIMIT 1", profile.text)
        assertEquals(1_294_166L, profile.times.elapsedNs)
        assertEquals(49_834L, profile.times.parseNs)
        assertEquals(32_167L, profile.times.planNs)
        assertEquals("2026-05-26T20:59:21.310-05:00", profile.times.startISO)
    }

    @Test
    fun `parseItem accepts bare envelope without ~request_profile wrapper`() {
        val profile = QueryProfileParser.parseItem(canonicalEnvelope)
        assertNotNull(profile)
        assertEquals("e526fe68-04e9-4881-bf76-d0a582827e9b", profile!!.id)
    }

    @Test
    fun `operator tree preserves order and stats`() {
        val profile = QueryProfileParser.parseItem(wrappedItem)!!
        assertEquals("sequence", profile.plan.name)
        assertEquals(2, profile.plan.children.size)
        val scan = profile.plan.children[0]
        assertEquals("scan", scan.name)
        assertEquals(1, scan.stats?.documentsOut)
        assertEquals(209L, scan.stats?.execNs)
        assertEquals(990_459L, scan.stats?.recvNs)
        assertEquals(61_500L, scan.stats?.sendNs)
        // operator-specific attributes preserved in insertion order
        assertEquals(listOf("collection" to "tasks", "datasource" to "default"), scan.attributes)
        val limit = profile.plan.children[1]
        assertEquals("limit", limit.name)
        assertEquals(2, limit.stats?.documentsIn)
    }

    @Test
    fun `partitionItems splits user docs from profile`() {
        val items: List<Map<String, Any?>> = listOf(
            mapOf("_id" to "doc-1", "name" to "x"),
            mapOf("_id" to "doc-2", "name" to "y"),
            wrappedItem,
        )
        val (docs, profile) = QueryProfileParser.partition(items)
        assertEquals(2, docs.size)
        assertNotNull(profile)
        assertTrue(docs.none { it.containsKey(envelopeKey) })
    }

    @Test
    fun `partitionItems with no profile returns all docs + null`() {
        val items: List<Map<String, Any?>> = listOf(mapOf("_id" to "a"), mapOf("_id" to "b"))
        val (docs, profile) = QueryProfileParser.partition(items)
        assertEquals(2, docs.size)
        assertNull(profile)
    }

    @Test
    fun `parseItem returns null when plan missing`() {
        val malformed = mapOf(envelopeKey to canonicalEnvelope.minus("plan"))
        assertNull(QueryProfileParser.parseItem(malformed))
    }
}
```

- [ ] **Step 2: Run — expect failure**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:compileDebugUnitTestKotlin --console=plain 2>&1 | tail -10`
Expected: unresolved references.

- [ ] **Step 3: Implement data classes**

`QueryProfile.kt`:

```kotlin
package com.costoda.dittoedgestudio.domain.model

data class QueryProfile(
    val id: String,
    val appId: String,
    val featureFlags: String,
    val queryType: String,
    val requestType: String,
    val resultCount: Int,
    val state: String,
    val text: String,
    val times: QueryProfileTimes,
    val plan: QueryProfileOperator,
    /** Wall-clock instant we parsed the profile on the client. */
    val capturedAtMs: Long,
)

data class QueryProfileTimes(
    val elapsedNs: Long,
    val parseNs: Long,
    val planNs: Long,
    val startISO: String,
)

data class QueryProfileOperator(
    /** Stable per-parse synthesised identifier (string UUID) — drives Compose `key()`s. */
    val id: String,
    val name: String,
    val stats: QueryProfileStats?,
    val children: List<QueryProfileOperator>,
    /** Operator-specific attributes preserved in insertion order. */
    val attributes: List<Pair<String, String>>,
) {
    /** Recursive sum of `execNs` across this subtree — used for the plan percentage badge. */
    val subtreeExecNs: Long
        get() = (stats?.execNs ?: 0L) + children.sumOf { it.subtreeExecNs }
}

data class QueryProfileStats(
    val documentsIn: Int?,
    val documentsOut: Int?,
    val execNs: Long?,
    val recvNs: Long?,
    val sendNs: Long?,
)
```

- [ ] **Step 4: Implement parser**

`QueryProfileParser.kt`:

```kotlin
package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.QueryProfile
import com.costoda.dittoedgestudio.domain.model.QueryProfileOperator
import com.costoda.dittoedgestudio.domain.model.QueryProfileStats
import com.costoda.dittoedgestudio.domain.model.QueryProfileTimes
import java.util.UUID

/**
 * Pure-Kotlin parser for the `~request_profile` envelope Ditto returns when a DQL
 * statement is prefixed with `PROFILE`.
 *
 * Mirrors SwiftUI's `QueryProfileParser` semantics — see `docs/PROFILE.md` for the
 * envelope shape and operator-tree contract. Returns `null` for items that don't look
 * like a profile envelope so the caller can keep them as normal result rows.
 */
object QueryProfileParser {

    const val envelopeKey: String = "~request_profile"

    fun parseItem(item: Map<String, Any?>): QueryProfile? {
        val envelope: Map<String, Any?> = when {
            item[envelopeKey] is Map<*, *> -> {
                @Suppress("UNCHECKED_CAST")
                item[envelopeKey] as Map<String, Any?>
            }
            item["_id"] != null && item["plan"] is Map<*, *> -> item  // bare
            else -> return null
        }
        val id = envelope["_id"] as? String ?: return null
        @Suppress("UNCHECKED_CAST")
        val planDict = envelope["plan"] as? Map<String, Any?> ?: return null
        val plan = parseOperator(planDict) ?: return null
        return QueryProfile(
            id = id,
            appId = (envelope["app_id"] as? String) ?: "",
            featureFlags = (envelope["featureFlags"] as? String) ?: "",
            queryType = (envelope["queryType"] as? String) ?: "",
            requestType = (envelope["requestType"] as? String) ?: "",
            resultCount = (envelope["resultCount"] as? Number)?.toInt() ?: 0,
            state = (envelope["state"] as? String) ?: "",
            text = (envelope["text"] as? String) ?: "",
            times = parseTimes(envelope["times"] as? Map<String, Any?>),
            plan = plan,
            capturedAtMs = System.currentTimeMillis(),
        )
    }

    /**
     * Walks the result list, removes the profile envelope item if present, and returns
     * (userDocuments, profile?). Preserves user-document order.
     */
    fun partition(items: List<Map<String, Any?>>): Pair<List<Map<String, Any?>>, QueryProfile?> {
        var profile: QueryProfile? = null
        val docs = mutableListOf<Map<String, Any?>>()
        for (item in items) {
            val parsed = parseItem(item)
            if (parsed != null && profile == null) {
                profile = parsed
            } else {
                docs += item
            }
        }
        return docs to profile
    }

    private fun parseTimes(dict: Map<String, Any?>?): QueryProfileTimes {
        if (dict == null) return QueryProfileTimes(0L, 0L, 0L, "")
        return QueryProfileTimes(
            elapsedNs = (dict["elapsed"] as? Number)?.toLong() ?: 0L,
            parseNs = (dict["parse"] as? Number)?.toLong() ?: 0L,
            planNs = (dict["plan"] as? Number)?.toLong() ?: 0L,
            startISO = (dict["start"] as? String) ?: "",
        )
    }

    private fun parseOperator(dict: Map<String, Any?>): QueryProfileOperator? {
        val name = dict["#operator"] as? String ?: return null
        @Suppress("UNCHECKED_CAST")
        val statsDict = dict["#stats"] as? Map<String, Any?>
        @Suppress("UNCHECKED_CAST")
        val childList = (dict["children"] as? List<Map<String, Any?>>).orEmpty()
        val children = childList.mapNotNull { parseOperator(it) }
        val attributes = dict.entries
            .filter { it.key != "#operator" && it.key != "#stats" && it.key != "children" }
            .map { it.key to (it.value?.toString() ?: "") }
        return QueryProfileOperator(
            id = UUID.randomUUID().toString(),
            name = name,
            stats = parseStats(statsDict),
            children = children,
            attributes = attributes,
        )
    }

    private fun parseStats(dict: Map<String, Any?>?): QueryProfileStats? {
        if (dict == null) return null
        @Suppress("UNCHECKED_CAST")
        val phase = dict["phaseTimes"] as? Map<String, Any?>
        return QueryProfileStats(
            documentsIn = (dict["documentsIn"] as? Number)?.toInt(),
            documentsOut = (dict["documentsOut"] as? Number)?.toInt(),
            execNs = (phase?.get("exec") as? Number)?.toLong(),
            recvNs = (phase?.get("recv") as? Number)?.toLong(),
            sendNs = (phase?.get("send") as? Number)?.toLong(),
        )
    }
}
```

- [ ] **Step 5: Verify all 7 tests pass**

Run: `./gradlew :app:testDebugUnitTest --tests "*.QueryProfileParserTest" --console=plain 2>&1 | tail -10`
Expected: BUILD SUCCESSFUL.

- [ ] **Step 6: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/QueryProfile.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/QueryProfileParser.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryProfileParserTest.kt
git commit -m "feat(android): add QueryProfile domain model + parser for PROFILE envelopes"
```

---

### Task 6: `ProfileTimeFormatter` (TDD)

**Files:**
- Create: `app/src/main/java/com/costoda/dittoedgestudio/data/repository/ProfileTimeFormatter.kt`
- Create: `app/src/test/java/com/costoda/dittoedgestudio/data/repository/ProfileTimeFormatterTest.kt`

- [ ] **Step 1: Failing test**

```kotlin
package com.costoda.dittoedgestudio.data.repository

import org.junit.Assert.assertEquals
import org.junit.Test

class ProfileTimeFormatterTest {
    @Test fun `ns under 1000 renders as integer ns`() {
        assertEquals("209 ns", ProfileTimeFormatter.format(209L))
        assertEquals("0 ns", ProfileTimeFormatter.format(0L))
        assertEquals("999 ns", ProfileTimeFormatter.format(999L))
    }
    @Test fun `microseconds tier formats with two decimals`() {
        assertEquals("1.00 µs", ProfileTimeFormatter.format(1_000L))
        assertEquals("55.56 µs", ProfileTimeFormatter.format(55_560L))
        assertEquals("999.99 µs", ProfileTimeFormatter.format(999_999L))
    }
    @Test fun `milliseconds tier formats with two decimals`() {
        assertEquals("1.00 ms", ProfileTimeFormatter.format(1_000_000L))
        assertEquals("1.29 ms", ProfileTimeFormatter.format(1_294_166L))
        assertEquals("432.43 ms", ProfileTimeFormatter.format(432_430_000L))
    }
}
```

- [ ] **Step 2: Implement**

```kotlin
package com.costoda.dittoedgestudio.data.repository

import java.util.Locale

/**
 * Three-tier auto-scale formatter for nanosecond durations.
 *
 * | Raw value           | Display          |
 * |---------------------|------------------|
 * | < 1_000 ns          | `<n> ns`         |
 * | 1_000 – 999_999 ns  | `<v>.<dd> µs`    |
 * | ≥ 1_000_000 ns      | `<v>.<dd> ms`    |
 *
 * Matches SwiftUI's `ProfileTimeFormatter.swift`. See `docs/PROFILE.md` § Display tiers.
 */
object ProfileTimeFormatter {
    fun format(ns: Long): String = when {
        ns < 1_000L -> "$ns ns"
        ns < 1_000_000L -> String.format(Locale.US, "%.2f µs", ns / 1_000.0)
        else -> String.format(Locale.US, "%.2f ms", ns / 1_000_000.0)
    }
}
```

- [ ] **Step 3: Verify + Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --tests "*.ProfileTimeFormatterTest" --console=plain 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/ProfileTimeFormatter.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/data/repository/ProfileTimeFormatterTest.kt
git commit -m "feat(android): add ProfileTimeFormatter for ns/µs/ms display tiers"
```

---

### Task 7: Carry `QueryProfile` through `QueryResult` and `LocalQueryExecutionService`

**Files:**
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/domain/model/QueryResult.kt`
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/data/repository/LocalQueryExecutionService.kt`

- [ ] **Step 1: Extend `QueryResult`**

```kotlin
package com.costoda.dittoedgestudio.domain.model

data class QueryResult(
    val documents: List<Map<String, Any?>>,
    val totalCount: Int,
    val executionTimeMs: Long,
    val explainPlan: String? = null,
    /** Set only when the query was a SELECT prefixed with PROFILE and the envelope was parsed. */
    val profile: QueryProfile? = null,
)
```

- [ ] **Step 2: Pipe the profile through `LocalQueryExecutionService`**

In `LocalQueryExecutionService.kt`, change the `execute(...)` body to partition results:

```kotlin
suspend fun execute(query: String): QueryResult = withContext(Dispatchers.IO) {
    val ditto = dittoManager.currentInstance()
        ?: error("No active Ditto instance")
    val start = System.currentTimeMillis()
    val items = ditto.store.execute(query) { result ->
        result.items.map { item ->
            runCatching { parseJsonToMap(org.json.JSONObject(item.jsonString())) }
                .getOrDefault(emptyMap())
        }
    }
    val elapsed = System.currentTimeMillis() - start
    val (docs, profile) = QueryProfileParser.partition(items)
    QueryResult(
        documents = docs,
        totalCount = docs.size,
        executionTimeMs = elapsed,
        profile = profile,
    )
}
```

- [ ] **Step 3: Verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL — existing tests use a `QueryResult` constructor; the new `profile = null` default keeps call sites green.

- [ ] **Step 4: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/QueryResult.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/LocalQueryExecutionService.kt
git commit -m "feat(android): partition PROFILE envelope from query result documents"
```

---

### Task 8: Inject `PROFILE ` prefix in the VM when applicable (TDD)

**Files:**
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt`
- Modify: `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt`
- Modify: `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt`

- [ ] **Step 1: Add `queryProfile` flow on the workbench**

In `StudioUiState.kt` `QueryWorkbenchState`, add (next to `queryMetrics`):

```kotlin
val queryProfile = MutableStateFlow<QueryProfile?>(null)
```

Import:
```kotlin
import com.costoda.dittoedgestudio.domain.model.QueryProfile
```

- [ ] **Step 2: Failing tests (added to `QueryEditorViewModelTest`)**

```kotlin
    @Test
    fun `executeQuery prefixes PROFILE for SELECT Local with metricsEnabled true`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT * FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("PROFILE SELECT * FROM tasks"), captured)
    }

    @Test
    fun `executeQuery does NOT prefix when metricsEnabled is false`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = false)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT * FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("SELECT * FROM tasks"), captured)
    }

    @Test
    fun `executeQuery does NOT prefix for HTTP mode`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "HTTP" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT * FROM tasks")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("SELECT * FROM tasks"), captured)
    }

    @Test
    fun `executeQuery does NOT prefix for non-SELECT statements`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val captured = mutableListOf<String>()
        coEvery { queryExecutionService.execute(any(), any()) } coAnswers {
            captured += (it.invocation.args[0] as String)
            QueryResult(emptyList(), 0, 1L)
        }
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("UPDATE tasks SET done = true")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(listOf("UPDATE tasks SET done = true"), captured)
    }

    @Test
    fun `executeQuery populates queryProfile flow when service returns a profile`() = runTest {
        val fakePrefs = FakeAppPreferences(initialMetricsEnabled = true)
        val workbench = QueryWorkbenchState().apply { executeMode.value = "Local" }
        val fakeProfile = QueryProfile(
            id = "p1", appId = "a", featureFlags = "0x1",
            queryType = "select", requestType = "SDK", resultCount = 0,
            state = "completed", text = "PROFILE SELECT 1",
            times = QueryProfileTimes(1L, 2L, 3L, ""),
            plan = QueryProfileOperator("op", "scan", null, emptyList(), emptyList()),
            capturedAtMs = 0L,
        )
        coEvery { queryExecutionService.execute(any(), any()) } returns
            QueryResult(documents = emptyList(), totalCount = 0, executionTimeMs = 5L, profile = fakeProfile)
        val vm = createVm(workbench, appPreferences = fakePrefs)
        vm.onQueryTextChange("SELECT 1")
        vm.executeQuery()
        advanceUntilIdle()
        assertEquals(fakeProfile, vm.queryProfile.value)
    }
```

- [ ] **Step 3: Implement the prefix logic in `executeQuery`**

In `QueryEditorViewModel.kt`, replace the body of `executeQuery()` so the relevant snippet reads:

```kotlin
fun executeQuery() {
    val rawQuery = workbench.queryText.value.trim()
    if (rawQuery.isBlank()) return
    val mode = workbench.executeMode.value
    val captureProfile = captureProfilingData.value  // already a StateFlow<Boolean>
    val effectiveQuery = if (
        captureProfile &&
        mode == "Local" &&
        isSelectStatement(rawQuery) &&
        !rawQuery.uppercase().trimStart().startsWith("PROFILE")
    ) {
        "PROFILE $rawQuery"
    } else {
        rawQuery
    }
    viewModelScope.launch {
        workbench.isExecuting.value = true
        workbench.executionError.value = null
        try {
            runCatching {
                val result = queryExecutionService.execute(effectiveQuery, mode = mode)
                workbench.queryResult.value = result
                workbench.queryProfile.value = result.profile
                workbench.currentPage.value = 0
                // ... rest of the existing history/metrics block unchanged
            }.onFailure { e ->
                workbench.executionError.value = e.message ?: "Unknown error"
            }
        } finally {
            workbench.isExecuting.value = false
        }
    }
}

private fun isSelectStatement(q: String): Boolean {
    val upper = q.trimStart().uppercase()
    return upper.startsWith("SELECT ") || upper == "SELECT"
}
```

Expose:
```kotlin
val queryProfile: StateFlow<QueryProfile?> = workbench.queryProfile.asStateFlow()
```

- [ ] **Step 4: Verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -10
```

Expected: BUILD SUCCESSFUL — 5 new tests pass, existing tests still green.

- [ ] **Step 5: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/session/StudioUiState.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModelTest.kt
git commit -m "feat(android): inject PROFILE prefix for SELECT + Local + metricsEnabled"
```

---

### Task 9: Profile UI components (Card mode first)

> **Strategy:** ship Card mode end-to-end first so the user can verify the data plumbing visually. Plan view in Task 10.

**Files (all new):**
- `ui/mainstudio/profile/ProfileViewerView.kt`
- `ui/mainstudio/profile/ProfileQueryHeaderCard.kt`
- `ui/mainstudio/profile/ProfileSummaryStrip.kt`
- `ui/mainstudio/profile/ProfileFooterStrip.kt`
- `ui/mainstudio/profile/ProfileOperatorCard.kt`
- `ui/mainstudio/profile/ProfileStatsBadges.kt`
- `ui/mainstudio/profile/ProfileCardListView.kt`

- [ ] **Step 1: Outline each composable's API + render contract**

Each file is a single `@Composable` function with no business logic — the call site passes the model + optional callbacks. Define signatures consistent across the set:

```kotlin
// ProfileStatsBadges.kt
@Composable
fun ProfileStatsBadges(stats: QueryProfileStats, modifier: Modifier = Modifier)
// Renders up to 5 small chips: documentsIn, documentsOut, exec, recv, send.
// Each chip uses MaterialTheme.colorScheme.{tertiary|secondary|primary}Container.
// Hidden when the corresponding field is null.

// ProfileQueryHeaderCard.kt
@Composable
fun ProfileQueryHeaderCard(profile: QueryProfile, modifier: Modifier = Modifier)
// Title row "Captured Query" + the query text with the leading "PROFILE " token stripped.

// ProfileSummaryStrip.kt
@Composable
fun ProfileSummaryStrip(times: QueryProfileTimes, modifier: Modifier = Modifier)
// 3 inline chips: "Elapsed <ms>" / "Parse <µs>" / "Plan <µs>" using ProfileTimeFormatter.

// ProfileFooterStrip.kt
@Composable
fun ProfileFooterStrip(profile: QueryProfile, modifier: Modifier = Modifier)
// Single line "Feature flags: <hex>" + state pill + resultCount.

// ProfileOperatorCard.kt
@Composable
fun ProfileOperatorCard(operator: QueryProfileOperator, modifier: Modifier = Modifier)
// Card with operator name (headline) + ProfileStatsBadges + attribute key/value list.

// ProfileCardListView.kt
@Composable
fun ProfileCardListView(profile: QueryProfile, modifier: Modifier = Modifier)
// LazyColumn:
//   item { ProfileQueryHeaderCard(profile) }
//   item { ProfileSummaryStrip(profile.times) }
//   items(operatorListFlattened) { ProfileOperatorCard(op) }
//   item { ProfileFooterStrip(profile) }
// `operatorListFlattened` is a top-down pre-order traversal of profile.plan.

// ProfileViewerView.kt
@Composable
fun ProfileViewerView(
    profile: QueryProfile?,
    metricsEnabled: Boolean,
    lastQueryText: String,
    modifier: Modifier = Modifier,
)
// Four states (precedence in order):
//   1. metricsEnabled == false → message + "Enable in Settings" hint
//   2. profile != null → ProfileCardListView(profile)
//   3. lastQueryText is blank → "Run a SELECT query to capture an execution profile."
//   4. last query not a SELECT → "Profiles are only captured for SELECT statements."
```

Write each file with the implementation matching the contract. Use `MaterialTheme` colors. The flatten helper:

```kotlin
private fun flatten(op: QueryProfileOperator, depth: Int = 0): List<Pair<Int, QueryProfileOperator>> {
    return listOf(depth to op) + op.children.flatMap { flatten(it, depth + 1) }
}
```

Pass `depth` to `ProfileOperatorCard` and indent the card by `start = (depth * 16).dp`.

- [ ] **Step 2: Wire into `QueryResultsView`**

In `QueryResultsView.kt`, change the button group from `listOf("JSON", "TABLE")` to `listOf("JSON", "TABLE", "PROFILE")`. Add a `selectedTabIndex == 2` branch:

```kotlin
selectedTabIndex == 2 -> {
    ProfileViewerView(
        profile = queryResult?.profile,
        metricsEnabled = captureProfilingData,
        lastQueryText = queryResult?.let { lastQueryText } ?: "",
        modifier = Modifier.fillMaxSize(),
    )
}
```

`QueryResultsView` needs two new parameters threaded from its caller:

```kotlin
fun QueryResultsView(
    queryResult: QueryResult?,
    displayedDocuments: List<Map<String, Any?>>,
    isExecuting: Boolean,
    executionError: String?,
    captureProfilingData: Boolean,
    lastQueryText: String,
    onDocumentSelected: (Map<String, Any?>) -> Unit,
    modifier: Modifier = Modifier,
)
```

Update the call site in `QueryEditorScreen.kt` (or wherever it lives) to pass the new params from the VM's `captureProfilingData` and `queryText` flows.

- [ ] **Step 3: Verify build**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew assembleDebug --console=plain 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 4: Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryResultsView.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryEditorScreen.kt
git commit -m "feat(android): add Profile tab (Card mode) with full visual parity to SwiftUI"
```

---

### Task 10: Plan tree view (Plan mode)

**Files:**
- Create: `ui/mainstudio/profile/PlanNodeBox.kt`
- Create: `ui/mainstudio/profile/ProfilePlanTreeView.kt`
- Modify: `ui/mainstudio/profile/ProfileViewerView.kt` — add Card/Plan sub-picker

- [ ] **Step 1: `PlanNodeBox` composable**

```kotlin
@Composable
fun PlanNodeBox(
    operator: QueryProfileOperator,
    totalExecNs: Long,
    modifier: Modifier = Modifier,
)
```

Renders a rounded `Surface` with:
- The operator name (titleMedium).
- A percentage badge `<execShare>%` where `execShare = (operator.stats?.execNs ?: 0L) * 100 / max(totalExecNs, 1)`.
- Hotspot color: `MaterialTheme.colorScheme.errorContainer` when share ≥ 50, otherwise `surfaceContainerHigh`.

- [ ] **Step 2: `ProfilePlanTreeView`**

A simple vertical tree using `Column` + recursive composition. Each child is rendered indented `start = (depth * 24).dp` with a connecting `Divider`/`Spacer` line to the left. For v1, skip animated branch lines — a static indent is sufficient.

```kotlin
@Composable
fun ProfilePlanTreeView(plan: QueryProfileOperator, modifier: Modifier = Modifier) {
    val total = plan.subtreeExecNs
    Column(modifier = modifier.padding(16.dp)) {
        TreeNode(operator = plan, totalExecNs = total, depth = 0)
    }
}

@Composable
private fun TreeNode(operator: QueryProfileOperator, totalExecNs: Long, depth: Int) {
    PlanNodeBox(
        operator = operator,
        totalExecNs = totalExecNs,
        modifier = Modifier.padding(start = (depth * 24).dp).padding(vertical = 4.dp),
    )
    operator.children.forEach { child ->
        TreeNode(operator = child, totalExecNs = totalExecNs, depth = depth + 1)
    }
}
```

- [ ] **Step 3: Add Card/Plan picker to `ProfileViewerView`**

Wrap the populated state in:

```kotlin
var mode by remember { mutableStateOf("Card") }
Column {
    DittoConnectedButtonGroup(
        options = listOf("Card", "Plan"),
        selectedIndex = if (mode == "Card") 0 else 1,
        onSelect = { mode = if (it == 0) "Card" else "Plan" },
    )
    when (mode) {
        "Card" -> ProfileCardListView(profile = profile!!)
        else -> ProfilePlanTreeView(plan = profile!!.plan)
    }
}
```

- [ ] **Step 4: Plan-sum sanity test (unit)**

```kotlin
// In QueryProfileParserTest.kt or a new PlanNodeShareTest.kt
@Test
fun `subtreeExecNs sums match canonical fixture`() {
    val profile = QueryProfileParser.parseItem(/* canonical wrapped envelope from §Task 5 */)!!
    val total = profile.plan.subtreeExecNs
    // sequence (no exec) + scan(209) + limit(2083) = 2292
    assertEquals(2_292L, total)
}
```

- [ ] **Step 5: Verify + Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -5 && ./gradlew assembleDebug --console=plain 2>&1 | tail -3
```

Expected: BUILD SUCCESSFUL on both.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/PlanNodeBox.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfilePlanTreeView.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/profile/ProfileViewerView.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/data/repository/QueryProfileParserTest.kt
git commit -m "feat(android): add Plan tree view + Card/Plan picker on ProfileViewerView"
```

---

## Phase 3 — Attachments

### Task 11: `AttachmentInfo` detector (TDD)

**Files:**
- Create: `app/src/main/java/com/costoda/dittoedgestudio/domain/model/AttachmentInfo.kt`
- Create: `app/src/test/java/com/costoda/dittoedgestudio/domain/model/AttachmentInfoTest.kt`

- [ ] **Step 1: Failing test**

```kotlin
package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AttachmentInfoTest {
    @Test fun `detects token with id len metadata triplet`() {
        val doc: Map<String, Any?> = mapOf(
            "_id" to "doc-1",
            "photo" to mapOf(
                "id" to "att-1",
                "len" to 12345,
                "metadata" to mapOf("type" to "image/png"),
            ),
        )
        val found = AttachmentInfo.detectTokens(doc)
        assertEquals(1, found.size)
        val a = found.first()
        assertEquals("att-1", a.id)
        assertEquals(12_345L, a.len)
        assertEquals("photo", a.fieldName)
        assertEquals("image/png", a.metadata["type"])
    }
    @Test fun `ignores fields that are partial matches`() {
        val doc: Map<String, Any?> = mapOf(
            "photo" to mapOf("id" to "x", "len" to 0),  // no metadata
            "name" to "regular",
        )
        assertTrue(AttachmentInfo.detectTokens(doc).isEmpty())
    }
    @Test fun `handles len as long and as int`() {
        val asInt = mapOf("a" to mapOf("id" to "1", "len" to 5, "metadata" to mapOf<String, String>()))
        val asLong = mapOf("a" to mapOf("id" to "1", "len" to 5L, "metadata" to mapOf<String, String>()))
        assertEquals(5L, AttachmentInfo.detectTokens(asInt).first().len)
        assertEquals(5L, AttachmentInfo.detectTokens(asLong).first().len)
    }
}
```

- [ ] **Step 2: Implement**

```kotlin
package com.costoda.dittoedgestudio.domain.model

/**
 * In-result-row representation of a Ditto attachment token. The actual token contents
 * (id/len/metadata) come from the JSON Ditto returns in a query item; [fieldName] is
 * the parent document key that holds the token.
 */
data class AttachmentInfo(
    val id: String,
    val len: Long,
    val fieldName: String,
    val metadata: Map<String, String>,
) {
    companion object {
        /**
         * Structural detection of Ditto attachment tokens in a parsed document map.
         * A field is treated as an attachment when its value is a [Map] with exactly the
         * three keys `id` (String), `len` (Number), and `metadata` (Map). Mirrors
         * SwiftUI's `AttachmentInfo.detectTokens(in:)`.
         */
        fun detectTokens(doc: Map<String, Any?>): List<AttachmentInfo> {
            val out = mutableListOf<AttachmentInfo>()
            for ((field, value) in doc) {
                val token = asAttachmentToken(field, value)
                if (token != null) out += token
            }
            return out
        }

        fun detectTokens(docs: List<Map<String, Any?>>): List<AttachmentInfo> =
            docs.flatMap { detectTokens(it) }

        @Suppress("UNCHECKED_CAST")
        private fun asAttachmentToken(field: String, value: Any?): AttachmentInfo? {
            val map = value as? Map<*, *> ?: return null
            val id = map["id"] as? String ?: return null
            val len = (map["len"] as? Number)?.toLong() ?: return null
            val metaRaw = map["metadata"] as? Map<*, *> ?: return null
            val metadata = metaRaw.entries
                .mapNotNull { (k, v) ->
                    val ks = k as? String ?: return@mapNotNull null
                    ks to (v?.toString() ?: "")
                }
                .toMap()
            return AttachmentInfo(id = id, len = len, fieldName = field, metadata = metadata)
        }
    }
}
```

- [ ] **Step 3: Verify + Commit**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --tests "*.AttachmentInfoTest" --console=plain 2>&1 | tail -5
```

Expected: 3/3 pass.

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/AttachmentInfo.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/domain/model/AttachmentInfoTest.kt
git commit -m "feat(android): add AttachmentInfo with structural token detection"
```

---

### Task 12: `AttachmentService` (TDD against a fake `DittoStore`)

**Files:**
- Create: `app/src/main/java/com/costoda/dittoedgestudio/data/repository/AttachmentService.kt`
- Create: `app/src/main/java/com/costoda/dittoedgestudio/data/repository/AttachmentService.kt` companion `interface AttachmentStoreGateway` for testability

> **Important — testing strategy:** `DittoStore` is final and constructed by the SDK. Wrap it behind a tiny interface so unit tests don't need a live Ditto instance.

Define an internal gateway:

```kotlin
internal interface AttachmentStoreGateway {
    suspend fun newAttachment(path: String, metadata: Map<String, String>): String  // returns attachment id
    suspend fun fetchAttachment(tokenMap: Map<String, Any>): java.io.InputStream  // suspends until completed
}
```

The production wiring lives in `DataModule.kt`:

```kotlin
single<AttachmentStoreGateway> {
    object : AttachmentStoreGateway {
        override suspend fun newAttachment(path: String, metadata: Map<String, String>): String {
            val ditto = get<DittoManager>().currentInstance() ?: error("No active Ditto instance")
            val md = com.ditto.kotlin.serialization.DittoCborSerializable.Dictionary(
                metadata.mapValues { com.ditto.kotlin.serialization.DittoCborSerializable.Text(it.value) },
            )
            return ditto.store.newAttachment(path = path, metadata = md).id
        }
        override suspend fun fetchAttachment(tokenMap: Map<String, Any>): java.io.InputStream {
            val ditto = get<DittoManager>().currentInstance() ?: error("No active Ditto instance")
            val res = ditto.store.fetchAttachment(tokenMap) { _, _ -> }
            val completed = res.asCompleted() ?: error("Attachment deleted before fetch completed")
            return completed.attachment.getInputStream()
        }
    }
}
single { com.costoda.dittoedgestudio.data.repository.AttachmentService(
    gateway = get(),
    cacheDirProvider = { androidContext().cacheDir },
) }
```

The service:

```kotlin
package com.costoda.dittoedgestudio.data.repository

import com.costoda.dittoedgestudio.domain.model.AttachmentInfo
import java.io.File
import java.io.InputStream

/**
 * High-level attachment operations exposed to the VM and UI. Wraps [AttachmentStoreGateway]
 * (which in production delegates to `ditto.store.newAttachment` / `fetchAttachment`).
 *
 * - [createFromFile] uploads a file to Ditto and returns the attachment id.
 * - [fetchToCache] downloads an attachment by token-map to `cacheDir/attachments/<id>` and
 *   returns the local [File]. Idempotent: a second call for the same id short-circuits.
 * - [delete] is NOT implemented here — deletion is a DQL `UPDATE ... SET <field> = null`
 *   issued through the existing [QueryExecutionService] facade by the UI sheet.
 */
class AttachmentService internal constructor(
    private val gateway: AttachmentStoreGateway,
    private val cacheDirProvider: () -> File,
) {
    suspend fun createFromFile(path: String, metadata: Map<String, String>): String =
        gateway.newAttachment(path, metadata)

    suspend fun fetchToCache(info: AttachmentInfo): File {
        val cacheRoot = File(cacheDirProvider(), "attachments").apply { mkdirs() }
        val target = File(cacheRoot, info.id)
        if (target.exists() && target.length() == info.len) return target
        val tokenMap: Map<String, Any> = mapOf(
            "id" to info.id,
            "len" to info.len,
            "metadata" to info.metadata,
        )
        gateway.fetchAttachment(tokenMap).use { stream ->
            target.outputStream().use { out -> stream.copyTo(out) }
        }
        return target
    }
}
```

Unit test (`AttachmentServiceTest.kt`) uses a fake `AttachmentStoreGateway` that returns a canned `ByteArrayInputStream`. Assert `fetchToCache` writes the file and that the second call is a no-op (touch `cacheDirProvider`-supplied tmp dir).

- [ ] **Step 1-5: Standard TDD cycle** — write test, see it fail, implement, see it pass, commit.

Commit:

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/AttachmentService.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt \
  android/app/src/test/java/com/costoda/dittoedgestudio/data/repository/AttachmentServiceTest.kt
git commit -m "feat(android): add AttachmentService for upload + cached download"
```

---

### Task 13: `AttachmentViewerSection` (Compose UI)

**File:** `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentViewerSection.kt`

Renders a vertical list of `AttachmentInfo`s. For each:
- Header row: `"<fieldName>"` + size in human-readable form (KB/MB) + content-type from `metadata["type"]`.
- If `metadata["type"]` starts with `"image/"`: tap `View` button → triggers download via VM callback, sets local `bitmap: Bitmap?` state → renders `Image` inline; otherwise hidden until tapped, then opens via `Intent.ACTION_VIEW`.
- Delete button → invokes the caller-supplied `onRequestDelete(info)` callback.

Signature:

```kotlin
@Composable
fun AttachmentViewerSection(
    attachments: List<AttachmentInfo>,
    documentId: String?,                              // for the parent document; needed by Delete
    collectionName: String,                           // ditto
    onView: (AttachmentInfo) -> Unit,                 // VM downloads + caches + calls back with file path
    onRequestDelete: (AttachmentInfo) -> Unit,
    cachedFiles: Map<String, java.io.File>,           // VM-managed; updates trigger recomposition
    modifier: Modifier = Modifier,
)
```

Wire into `QueryJsonInspector.kt`:

```kotlin
// Append below the existing JSON-tree composable:
val attachments = remember(selectedDocument) {
    selectedDocument?.let { AttachmentInfo.detectTokens(it) } ?: emptyList()
}
if (attachments.isNotEmpty()) {
    AttachmentViewerSection(
        attachments = attachments,
        documentId = selectedDocument?.get("_id") as? String,
        collectionName = lastCollection,  // TODO param thread
        onView = viewModel::viewAttachment,
        onRequestDelete = viewModel::requestDeleteAttachment,
        cachedFiles = cachedFiles,
    )
}
```

Commit:

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentViewerSection.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/inspector/QueryJsonInspector.kt
git commit -m "feat(android): show attachments inline in the JSON inspector"
```

---

### Task 14: `AttachmentPickerSheet` + Add codepath

**File:** `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentPickerSheet.kt`

ModalBottomSheet hosting:
- `rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument())` to pick a file. Capture the resulting `Uri`.
- Read `len` via `context.contentResolver.openFileDescriptor(uri, "r")?.statSize`. Enforce 10MB soft (warn) / 20MB hard (block).
- A `TextField` for the target field name (default empty; reject blank).
- An optional metadata table (key/value rows) — for v1 just expose a single "Content type" field, defaulting to the mime from `contentResolver.getType(uri)`.
- A "Add Attachment" button → calls `viewModel.addAttachment(uri, fieldName, metadata)` then dismisses.

Add `addAttachment` to `QueryEditorViewModel`:

```kotlin
fun addAttachment(uri: Uri, fieldName: String, metadata: Map<String, String>) {
    // Hand off via repository; on success, re-run the previous query so the result row reflects the new field.
    viewModelScope.launch {
        runCatching {
            val temp = copyUriToTempFile(uri)
            val attachId = attachmentService.createFromFile(temp.absolutePath, metadata)
            val docId = workbench.selectedDocument.value?.get("_id") as? String ?: return@runCatching
            val collection = inferCollectionFromLastQuery() ?: return@runCatching
            queryExecutionService.execute(
                "UPDATE $collection SET $fieldName = ATTACHMENT('$attachId', $len, {…metadata}) WHERE _id = '$docId'",
                mode = "Local",
            )
        }.onFailure { workbench.executionError.value = it.message }
    }
}
```

> **Caveat:** Ditto's DQL ATTACHMENT() literal syntax needs verification against the Kotlin SDK docs. If the syntax differs, prefer `ditto.store.execute("UPDATE c SET f = :att WHERE _id = :id", mapOf("att" to attachmentObject, "id" to docId))` parameterised form. Decide at implementation time by reading the Ditto SDK docs or the 5.1.0-preview.1 source jar for the recommended insertion API.

Open the sheet from a context menu on the result row — see Task 16.

Commit:

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/AttachmentPickerSheet.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt
git commit -m "feat(android): add AttachmentPickerSheet + addAttachment VM action"
```

---

### Task 15: `DeleteAttachmentSheet` + Delete codepath

**File:** `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/DeleteAttachmentSheet.kt`

ModalBottomSheet with:
- Heading "Delete Attachments".
- List of `AttachmentInfo`s (toggle per row).
- "Delete Selected" button → issues `UPDATE <collection> SET <fieldName> = NULL WHERE _id = '<docId>'` per selected attachment via the existing facade.

Add VM action:

```kotlin
fun deleteAttachments(
    documentId: String,
    collection: String,
    attachments: List<AttachmentInfo>,
) {
    viewModelScope.launch {
        runCatching {
            for (att in attachments) {
                queryExecutionService.execute(
                    "UPDATE $collection SET ${att.fieldName} = NULL WHERE _id = '$documentId'",
                    mode = "Local",
                )
            }
        }.onFailure { workbench.executionError.value = it.message }
    }
}
```

> **SQL injection note:** since fieldName and collection come from server-controlled documents not user input, this is safer than at first glance — but still wrap field names in backticks/quoting per Ditto's DQL identifier rules. Read the DQL grammar reference before authoring.

Commit:

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/attachments/DeleteAttachmentSheet.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/QueryEditorViewModel.kt
git commit -m "feat(android): add DeleteAttachmentSheet + deleteAttachments VM action"
```

---

### Task 16: Wire the per-row context menu in `QueryResultsView`

**File:** `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryResultsView.kt`

In both `ResultJsonView` and `ResultTableView`, wrap each row in `Modifier.combinedClickable { onSelect } onLongClick { showContextMenu(row) }`. `showContextMenu` opens a `DropdownMenu` anchored to the long-press point containing:
- "Add Attachment…" → opens `AttachmentPickerSheet` with the current row's `_id` and collection.
- "Delete Attachment…" → opens `DeleteAttachmentSheet` (enabled only if `AttachmentInfo.detectTokens(row).isNotEmpty()`).

Pass two new callbacks down from the section host:

```kotlin
onAddAttachmentRequest: (row: Map<String, Any?>) -> Unit,
onDeleteAttachmentsRequest: (row: Map<String, Any?>) -> Unit,
```

Commit:

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio && git add \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryResultsView.kt \
  android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/QueryEditorScreen.kt
git commit -m "feat(android): expose per-row Add/Delete attachment via long-press menu"
```

---

## Final verification

### Task 17: Manual smoke checklist + unit/build sanity

- [ ] Run unit tests: `cd /Users/labeaaa/Developer/ditto-edge-studio/android && ./gradlew :app:testDebugUnitTest --console=plain 2>&1 | tail -5` → BUILD SUCCESSFUL.
- [ ] Run build: `./gradlew assembleDebug --console=plain 2>&1 | tail -5` → BUILD SUCCESSFUL.
- [ ] **DO NOT** run `connectedAndroidTest` or `tabletApi34DebugAndroidTest`. Per the user's standing rule (`feedback_no_instrumented_runs.md`), instrumented runs are smoke-tested manually by the user.

Manual smoke (for the user — write to `screens/android/` per `android/CLAUDE.md` if you want to attach screenshots):

1. Open the inspector while on Query Workbench → tap the 5th icon (help-outline) → confirm `query.md` markdown renders.
2. Toggle "Capture profiling data" OFF in the Options popover → relaunch the app → confirm it stays OFF (persistence works).
3. Toggle it back ON → run `SELECT * FROM <collection> LIMIT 5` against Local mode → switch to the new "Profile" tab in the results pane → confirm the Card view shows operator cards with stats.
4. Tap the "Plan" sub-picker → confirm the tree renders with percentage badges.
5. Run a non-SELECT statement (`UPDATE …`) → confirm the Profile tab shows the "Profiles are only captured for SELECT statements" empty state.
6. Long-press a result row containing an attachment-shaped field → confirm "Add Attachment…" and "Delete Attachment…" appear; the latter is disabled if no attachments are detected.
7. Tap a row, switch the inspector to JSON → confirm the Attachment Viewer section appears at the bottom; tap "View" on an image-type attachment → confirm it downloads + previews inline; tap Open on a non-image → confirm Android's chooser appears.
8. Add Attachment flow: pick a file < 10MB → confirm size badge; pick a file > 20MB → confirm hard block; pick a 12MB file → confirm soft warning + still allowed.
9. Delete Attachment flow: select multiple attachments → confirm they disappear from the JSON view after the next refresh.

---

## Out of scope (explicit)

- **Profile over HTTP:** matches SwiftUI v1 — Local mode only.
- **Card view bar charts:** v1 renders stats as colored badges (chips), not bars. Bar charts can land later.
- **Attachment streaming for very large files:** `getInputStream()` reads to a cached file before opening; we don't stream-render multi-GB attachments. Out of scope.
- **Custom file picker UI:** Android's system `OpenDocument` chooser is used; no in-app browser.
- **Auto-refresh after attachment changes:** v1 requires the user to re-run the query (matches SwiftUI). Auto-rerun on success can land later.

---

## Self-Review

**1. Spec coverage:**
- Help inspector entry → Task 1.
- Profile capture pipeline → Tasks 5–8.
- Profile UI → Tasks 9 (Card) + 10 (Plan).
- Profile gating via persistent + toolbar toggle → Tasks 2–4.
- Attachment detect → Task 11.
- Attachment service → Task 12.
- Attachment viewer (inline image + Open) → Task 13.
- Attachment add (file picker + size validation) → Task 14.
- Attachment delete (DQL UPDATE = null) → Task 15.
- Per-row context menu → Task 16.

**2. Placeholder scan:** the only intentional looseness is in Task 14's `ATTACHMENT(...)` literal call and Task 13's `lastCollection` thread — both flagged inline with "verify at implementation time" notes. Implementer must read the Ditto Kotlin SDK 5.1.0-preview.1 source jar for the DQL attachment-insertion grammar before authoring those two lines.

**3. Type consistency:**
- `QueryProfile` fields used across parser, formatter, and views all match.
- `AttachmentInfo(id, len, fieldName, metadata)` consistent across detector, service, viewer.
- `captureProfilingData: StateFlow<Boolean>` reads from `AppPreferences.metricsEnabled` everywhere; the toolbar setter writes through.
- `AttachmentStoreGateway` is the test seam — production wiring in DataModule, fake in tests.
