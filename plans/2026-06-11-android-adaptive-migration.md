# Android Adaptive App Migration Plan — WindowManager 1.5 + Navigation 3 + Android 16 Connected Displays

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the Android app from a hardcoded 600dp phone/tablet fork to a fully adaptive architecture (androidx.window 1.5+, Navigation 3, Material 3 Adaptive scenes) so that resizing — including plugging a phone into a monitor on Android 16 — automatically produces the tablet-class studio UI.

**Architecture:** Single-activity Compose app keeps its Rail + Data Panel + Content Pane + Inspector model, but pane visibility becomes a function of `WindowSizeClass` (not device type), screen switching becomes a serializable Nav3 back stack (not a `when()` on an enum), and the studio's multi-pane layout is driven by Material 3 Adaptive scene strategies (`adaptive-navigation3`). The 439-line `MainStudioViewModel` splits into a Koin-scoped session ViewModel (Ditto lifecycle) plus per-section ViewModels scoped to Nav3 entries.

**Tech Stack:** Kotlin 2.1.20 · Compose BOM 2025.12.00 · androidx.window **1.5.1** · navigation3 **1.0.0** (replaces navigation-compose 2.8.9) · material3-adaptive **1.3.0-beta02** (incl. `adaptive-navigation3`) · lifecycle-viewmodel-navigation3 **2.10.0-rc01** · Koin 4.1.1 · targetSdk 36 / minSdk 28

---

## Current State (audited 2026-06-11)

| Area | Today | Problem |
|---|---|---|
| Adaptivity | `LocalConfiguration.current.screenWidthDp >= 600` at `MainStudioScreen.kt:131` (also `DatabaseListScreen.kt`, `QueryMetricsScreen.kt`) forks into separate `TabletLayout()`/`PhoneLayout()` trees | `Configuration.screenWidthDp` is wrong in multi-window/desktop windowing; duplicated layout code; one breakpoint |
| Navigation | Nav2 2.8.9 with 4 string routes in `ui/navigation/AppNavGraph.kt`; inside the studio, manual `selectedNavItem` enum + `when()` (`MainStudioScreen.kt:717–828`) | No back-stack semantics for sections, no predictive back, no per-screen ViewModel scoping |
| Panels | Data Panel fixed `200.dp` (`MainStudioScreen.kt:282`), Inspector fixed `300.dp` (`:344`), toggled by booleans in the ViewModel | Hardcoded geometry can't adapt to Large/XL windows or foldables |
| Manifest | `configChanges="orientation|screenSize"`, no explicit `resizeableActivity`, no density handling | Desktop-windowing resizes change density too; activity recreation path untested |
| State | No `rememberSaveable`, no `SavedStateHandle`, `collectAsState()` (not lifecycle-aware) | Pane-local state lost on layout switch; process death loses everything |
| ViewModels | `MainStudioViewModel` (439 lines) owns nav state, panel toggles, Ditto lifecycle, subscriptions, observers, transports; `onCleared()` closes the Ditto instance | Fights Nav3 entry scoping; section VMs (QueryEditor, AppMetrics…) never cleared when section hidden |

**Already in good shape:** single activity, no orientation locks, targetSdk 36, edge-to-edge enabled, kotlinx-serialization plugin applied.

## Android 16 context (why this works for the monitor scenario)

- Android 16 QPR3 (March 2026) made connected-display desktop windowing generally available on Pixel 8+. Apps appear as freeform resizable windows.
- On large screens (sw ≥ 600dp — external monitors qualify) with targetSdk 36, the system **ignores** orientation/resizability restrictions; with targetSdk 37 the opt-out disappears. We have no locks — good.
- The contract for "phone-on-monitor shows the tablet UI" is exactly: derive layout from **current window metrics** (`WindowSizeClass`), survive config changes (size + density + orientation simultaneously), never cache `Display` or read sizes at startup.

## Target pane policy (single source of truth)

| Window width | Breakpoint check | Rail | Data Panel | Content | Inspector |
|---|---|---|---|---|---|
| < 600dp (Compact) | — | Modal Nav Drawer | merged into drawer | full width | `ModalBottomSheet` |
| ≥ 600dp (Medium) | `isWidthAtLeastBreakpoint(WIDTH_DP_MEDIUM_LOWER_BOUND)` | visible | toggleable (off by default) | weight | toggleable overlay |
| ≥ 840dp (Expanded) | `…WIDTH_DP_EXPANDED_LOWER_BOUND` | visible | toggleable (on by default) | weight | toggleable |
| ≥ 1200dp (Large — monitor) | `…WIDTH_DP_LARGE_LOWER_BOUND` | visible | visible | weight | visible (on by default) |

Rail items that don't use a Data Panel (Logging, App Metrics, Disk Usage) render list-pane-less at every width — the scene strategy per-entry metadata controls this.

---

## Phase 0 — Window-resilience groundwork (shippable; no visual change)

### Task 0.1: Manifest hardening for desktop windowing

**Files:**
- Modify: `android/app/src/main/AndroidManifest.xml` (activity element, ~lines 48–57)

- [ ] **Step 1: Update the `<activity>` element**

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:resizeableActivity="true"
    android:windowSoftInputMode="adjustResize"
    android:configChanges="orientation|screenSize|smallestScreenSize|screenLayout|density">
```

(`smallestScreenSize|screenLayout|density` are the additions; monitor plug/unplug changes all three at once. We keep handling config changes ourselves — Compose recomposes via `LocalConfiguration`/`LocalDensity` — rather than allowing recreation, because no `rememberSaveable` exists yet. Phase 0.3 adds the recreation safety net anyway.)

- [ ] **Step 2: Build and smoke-test**

Run: `cd android && ./gradlew :app:assembleDebug`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/AndroidManifest.xml
git commit -m "feat(android): declare resizeable activity + full config-change handling for desktop windowing"
```

### Task 0.2: Lifecycle-aware flow collection

**Files:**
- Modify: `android/gradle/libs.versions.toml` (add `lifecycle-runtime-compose`)
- Modify: `android/app/build.gradle.kts`
- Modify: every screen using `collectAsState()` on a ViewModel flow (`MainStudioScreen.kt:113` et al — `grep -rn "collectAsState()" android/app/src/main`)

- [ ] **Step 1: Add dependency**

```toml
# libs.versions.toml [libraries]
androidx-lifecycle-runtime-compose = { group = "androidx.lifecycle", name = "lifecycle-runtime-compose", version.ref = "lifecycle" }
```

```kotlin
// app/build.gradle.kts dependencies
implementation(libs.androidx.lifecycle.runtime.compose)
```

- [ ] **Step 2: Mechanical replacement**

Replace `.collectAsState()` with `.collectAsStateWithLifecycle()` (import `androidx.lifecycle.compose.collectAsStateWithLifecycle`) at every ViewModel-flow collection site found by the grep.

- [ ] **Step 3: Build + run unit tests**

Run: `cd android && ./gradlew :app:assembleDebug :app:testDebugUnitTest`
Expected: BUILD SUCCESSFUL, tests pass

- [ ] **Step 4: Commit** — `git commit -m "refactor(android): lifecycle-aware flow collection"`

### Task 0.3: Save panel/tab state across recreation

**Files:**
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt` (`ContentPlaceholder` local state, line ~722)
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt` (panel booleans, `selectedNavItem` line 94)

- [ ] **Step 1:** Convert composition-local `remember { mutableStateOf(...) }` UI state (selected tab indices, expansion state) to `rememberSaveable`.
- [ ] **Step 2:** Give `MainStudioViewModel` a `SavedStateHandle` (Koin: `viewModel { params -> MainStudioViewModel(get(), params.get(), handle = get()) }` via `androidx.lifecycle.SavedStateHandle` injection) and back `selectedNavItem`, `dataPanelVisible`, `inspectorVisible` with `handle.saveable` or explicit `handle[KEY]` writes. *(This is interim — Phase 4 moves section selection into the Nav3 back stack and deletes most of it.)*
- [ ] **Step 3:** Verify on the **resizable emulator**: drag phone→tablet→desktop sizes; toggle panels; kill process (`adb shell am kill com.costoda.dittoedgestudio`) and relaunch — selections survive.
- [ ] **Step 4:** Commit — `git commit -m "feat(android): persist studio UI state across config change and process death"`

---

## Phase 1 — WindowSizeClass replaces the 600dp fork (shippable)

### Task 1.1: Dependencies

**Files:**
- Modify: `android/gradle/libs.versions.toml`
- Modify: `android/app/build.gradle.kts`

- [ ] **Step 1: Version catalog additions**

```toml
[versions]
androidx-window = "1.5.1"
material3Adaptive = "1.3.0-beta02"

[libraries]
androidx-window = { group = "androidx.window", name = "window", version.ref = "androidx-window" }
androidx-window-core = { group = "androidx.window", name = "window-core", version.ref = "androidx-window" }
material3-adaptive = { group = "androidx.compose.material3.adaptive", name = "adaptive", version.ref = "material3Adaptive" }
material3-adaptive-layout = { group = "androidx.compose.material3.adaptive", name = "adaptive-layout", version.ref = "material3Adaptive" }
```

- [ ] **Step 2:** Add the four `implementation(libs.…)` lines; build: `./gradlew :app:assembleDebug` → BUILD SUCCESSFUL.
- [ ] **Step 3:** Commit.

### Task 1.2: One adaptive-info source of truth

**Files:**
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/adaptive/WindowSize.kt`

- [ ] **Step 1: Create the helper** (the ONLY place window size is computed; L/XL opted in)

```kotlin
package com.costoda.dittoedgestudio.ui.adaptive

import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.runtime.Composable
import androidx.window.core.layout.WindowSizeClass
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_EXPANDED_LOWER_BOUND
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_LARGE_LOWER_BOUND
import androidx.window.core.layout.WindowSizeClass.Companion.WIDTH_DP_MEDIUM_LOWER_BOUND

@Composable
fun studioWindowSizeClass(): WindowSizeClass =
    currentWindowAdaptiveInfo(supportLargeAndXLargeWidth = true).windowSizeClass

val WindowSizeClass.showsRail: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_MEDIUM_LOWER_BOUND)
val WindowSizeClass.dataPanelDefaultVisible: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_EXPANDED_LOWER_BOUND)
val WindowSizeClass.inspectorDefaultVisible: Boolean
    get() = isWidthAtLeastBreakpoint(WIDTH_DP_LARGE_LOWER_BOUND)
```

*(Note: adaptive 1.3.0 alphas deprecate `currentWindowAdaptiveInfo()` in favor of a V2 overload — at implementation time check which symbol 1.3.0-beta02 exposes and use the non-deprecated one. This indirection file exists precisely to absorb that churn.)*

- [ ] **Step 2: Build** → BUILD SUCCESSFUL. Commit.

### Task 1.3: Replace the three hardcoded 600dp checks

**Files:**
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt:131`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/DatabaseListScreen.kt` (the `screenWidthDp >= 600` site)
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/metrics/QueryMetricsScreen.kt` (the `isTablet` site)

- [ ] **Step 1:** In each file replace `LocalConfiguration.current.screenWidthDp >= 600` with `studioWindowSizeClass().showsRail` (and rename locals from `isTablet` to `expandedLayout` — *no device-type booleans*).
- [ ] **Step 2:** `grep -rn "screenWidthDp" android/app/src/main` → expect **zero** hits outside `ui/adaptive/`.
- [ ] **Step 3:** Build both behaviors on the resizable emulator: drag across 600dp — layout flips live (this now also works in a desktop window, which `Configuration.screenWidthDp` did not guarantee).
- [ ] **Step 4:** Commit — `git commit -m "refactor(android): WindowSizeClass replaces hardcoded 600dp breakpoints"`

---

## Phase 2 — Navigation 3 swap at the app graph (shippable)

### Task 2.1: Dependencies

**Files:** `android/gradle/libs.versions.toml`, `android/app/build.gradle.kts`

- [ ] **Step 1:**

```toml
[versions]
nav3 = "1.0.0"
lifecycleNav3 = "2.10.0-rc01"

[libraries]
androidx-navigation3-runtime = { group = "androidx.navigation3", name = "navigation3-runtime", version.ref = "nav3" }
androidx-navigation3-ui = { group = "androidx.navigation3", name = "navigation3-ui", version.ref = "nav3" }
androidx-lifecycle-viewmodel-navigation3 = { group = "androidx.lifecycle", name = "lifecycle-viewmodel-navigation3", version.ref = "lifecycleNav3" }
```

- [ ] **Step 2:** Add `implementation` lines. Do **not** remove `navigationCompose` yet (removed in Task 2.3). Build. Commit.

### Task 2.2: NavKeys + NavDisplay replace AppNavGraph

**Files:**
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/navigation/NavKeys.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/navigation/AppNavGraph.kt` (rewrite)

- [ ] **Step 1: Define the keys**

```kotlin
package com.costoda.dittoedgestudio.ui.navigation

import androidx.navigation3.runtime.NavKey
import kotlinx.serialization.Serializable

@Serializable data object DatabaseListKey : NavKey
@Serializable data class DatabaseEditorKey(val id: String? = null) : NavKey
@Serializable data object QrScannerKey : NavKey
@Serializable data class StudioKey(val databaseId: String) : NavKey
```

*(Match the id types to what the current `database_editor?id={id}` / `main_studio/{databaseId}` routes actually pass — verify in `AppNavGraph.kt` before writing.)*

- [ ] **Step 2: Rewrite `AppNavGraph.kt`**

```kotlin
@Composable
fun AppNavGraph() {
    val backStack = rememberNavBackStack(DatabaseListKey)
    NavDisplay(
        backStack = backStack,
        onBack = { backStack.removeLastOrNull() },
        entryDecorators = listOf(
            rememberSaveableStateHolderNavEntryDecorator(),
            rememberViewModelStoreNavEntryDecorator(),
        ),
        entryProvider = entryProvider {
            entry<DatabaseListKey> {
                DatabaseListScreen(
                    onOpenStudio = { id -> backStack.add(StudioKey(id)) },
                    onEdit = { id -> backStack.add(DatabaseEditorKey(id)) },
                    onAdd = { backStack.add(DatabaseEditorKey()) },
                    onScanQr = { backStack.add(QrScannerKey) },
                )
            }
            entry<DatabaseEditorKey> { key ->
                DatabaseEditorScreen(id = key.id, onDone = { backStack.removeLastOrNull() })
            }
            entry<QrScannerKey> { QrScannerScreen(onDone = { backStack.removeLastOrNull() }) }
            entry<StudioKey> { key ->
                MainStudioScreen(databaseId = key.databaseId, onBack = { backStack.removeLastOrNull() })
            }
        },
    )
}
```

*(Exact screen parameter names must be read from the current `composable(...)` blocks and preserved — this rewrite is mechanical: 4 routes → 4 entries.)*

- [ ] **Step 3:** Build; manually walk all 4 flows on emulator (list → editor → back; list → studio → back; QR). Predictive-back gesture now animates.
- [ ] **Step 4:** Commit — `git commit -m "feat(android): Navigation 3 NavDisplay replaces Nav2 app graph"`

### Task 2.3: Remove Navigation 2

- [ ] **Step 1:** Delete `navigationCompose` from `libs.versions.toml` + `build.gradle.kts`; `grep -rn "androidx.navigation\b" android/app/src/main` → zero hits.
- [ ] **Step 2:** Build + unit tests. Commit — `git commit -m "chore(android): drop navigation-compose 2.x"`

---

## Phase 3 — Session ViewModel decomposition (shippable)

The Ditto instance must outlive section switches but die when the studio closes. Nav3 has no graph-scoped ViewModel, so the session lives in a **Koin scope keyed by databaseId**.

### Task 3.1: Extract `StudioSessionViewModel`

**Files:**
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/StudioSessionViewModel.kt`
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt`
- Modify: Koin module file (locate via `grep -rn "viewModel {" android/app/src/main/java/com/costoda/dittoedgestudio/di/`)

- [ ] **Step 1:** Move from `MainStudioViewModel` into `StudioSessionViewModel`: Ditto instance creation/hydration, sync start/stop, subscription handles, observer registration handles, log-capture service wiring, and the `onCleared()` that closes Ditto. **This is the highest-risk move** — Ditto must close exactly once, when the studio exits, not on section switch.
- [ ] **Step 2:** Declare a Koin scope:

```kotlin
module {
    scope(named("studio")) {
        scoped { params -> StudioSessionViewModel(databaseId = params.get(), /* repos via get() */ ) }
    }
}
```

The `StudioKey` entry opens the scope (`koin.createScope("studio:$databaseId", named("studio"))`) and closes it when the entry leaves the back stack (`DisposableEffect(key) { onDispose { scope.close() } }`).
- [ ] **Step 3:** `MainStudioViewModel` shrinks to UI-coordination state only (panel toggles, selected items) and delegates all Ditto work to the session.
- [ ] **Step 4:** Tests: run existing unit tests; add a test asserting the session scope closes (and Ditto `close()` is invoked once) when the studio entry is popped. Manual: enter studio → switch all 7 sections → sync keeps running; back to database list → logcat shows single Ditto close.
- [ ] **Step 5:** Commit — `git commit -m "refactor(android): extract StudioSessionViewModel with Koin scope per database session"`

---

## Phase 4 — Section keys + Material adaptive scenes (the core payoff)

### Task 4.1: Add `adaptive-navigation3`

**Files:** `libs.versions.toml`, `app/build.gradle.kts`

- [ ] **Step 1:**

```toml
material3-adaptive-navigation3 = { group = "androidx.compose.material3.adaptive", name = "adaptive-navigation3", version.ref = "material3Adaptive" }
```

Build. Commit. *(Beta API — see Risks. `NavDisplay` takes `sceneStrategies: List<SceneStrategy>` as of adaptive 1.3.0-alpha09; do not use the deprecated `then`-chaining.)*

### Task 4.2: One NavKey per rail section

**Files:**
- Modify: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/navigation/NavKeys.kt`

- [ ] **Step 1:**

```kotlin
sealed interface StudioSectionKey : NavKey { val databaseId: String }
@Serializable data class SubscriptionsKey(override val databaseId: String) : StudioSectionKey  // Presence
@Serializable data class QueryKey(override val databaseId: String) : StudioSectionKey          // Query Workbench
@Serializable data class ObserversKey(override val databaseId: String) : StudioSectionKey      // Observation
@Serializable data class LoggingKey(override val databaseId: String) : StudioSectionKey        // Log Analyzer
@Serializable data class AppMetricsKey(override val databaseId: String) : StudioSectionKey
@Serializable data class QueryMetricsKey(override val databaseId: String) : StudioSectionKey
@Serializable data class DiskUsageKey(override val databaseId: String) : StudioSectionKey      // Database Metrics
// Compact-width drill-ins (pushed entries so system back works on phones):
@Serializable data class ObserverEventsKey(val databaseId: String, val observerId: String) : NavKey
```

`StudioKey(databaseId)` is replaced by `SubscriptionsKey(databaseId)` as the studio entry point. **Rail selection = replace top entry** (`backStack[backStack.lastIndex] = QueryKey(dbId)`): no per-section history, back from any section exits the studio — preserving today's behavior.

- [ ] **Step 2:** Build (keys unused yet). Commit.

### Task 4.3: Scene-driven studio layout

**Files:**
- Create: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/StudioScaffold.kt` (rail chrome + NavDisplay)
- Modify: `AppNavGraph.kt` (section entries with `ListDetailSceneStrategy` metadata)
- Modify (shrink): `MainStudioScreen.kt` — `TabletLayout`/`PhoneLayout`/`ContentPlaceholder` (lines 254–348, 717–828) are deleted as sections move out

- [ ] **Step 1: Rail as chrome.** `StudioScaffold` hosts the `NavigationRail` (Medium+) / `ModalNavigationDrawer` (Compact) driven by `studioWindowSizeClass()`, with selected item = `backStack.last()` type. The inner `NavDisplay` gets `sceneStrategies = listOf(ListDetailSceneStrategy())`.
- [ ] **Step 2: Per-section entries declare panes via metadata.** Sections with a Data Panel mark it as the **list pane**, content as **detail**, Inspector as **extraPane**:

```kotlin
entry<ObserversKey>(metadata = ListDetailSceneStrategy.listPane(detailPlaceholder = { ObserverEmptyState() })) { key ->
    ObserversDataPanel(key.databaseId)   // registered observers + active state
}
// detail + extra pane entries follow the adaptive-navigation3 recipe shape
```

Mapping per section (canonical names from `docs/android/RAIL_FEATURES.md`):
| Section | list pane (Data Panel) | detail (Content) | extraPane (Inspector) |
|---|---|---|---|
| Presence | Subscriptions | Connected Peers (+ future Presence Graph) | help |
| Query Workbench | Collections | Editor + Results | History/Favorites/JSON/Metrics/help |
| Observation | Observers | Events + detail | help |
| Log Analyzer | — (no list pane) | Log viewer full width | help |
| App Metrics | — | Metrics cards | help |
| **Query Metrics** | **Executed queries (moved here — fixes the RAIL_FEATURES gap)** | EXPLAIN detail | help |
| Database Metrics | — | Storage breakdown | help |

- [ ] **Step 3: Compact behavior.** At Compact width the strategy renders single-pane; Data Panel content lives in the drawer; `ObserverEventsKey`-style drill-ins are pushed entries (system back pops them). Inspector remains `ModalBottomSheet`.
- [ ] **Step 4: Panel toggles stay layout state** (`rememberSaveable` booleans wired to the top-bar buttons), NOT back-stack entries — back-press must never "close the Inspector."
- [ ] **Step 5: Delete** the manual `when()` (`ContentPlaceholder`), `TabletLayout`, `PhoneLayout`, and the duplicated `DataPanel`/`PhoneDrawerContent` trees as each section migrates. Migrate **one section at a time** (Observers first — it exercises list/detail/drill-in), committing per section; the `when()` shrinks until empty.
- [ ] **Step 6: Folded-in fix:** create `android/app/src/main/assets/help/diskusage.md` (content: storage metrics explained — DB file size, per-collection sizes, refresh cadence) so the Database Metrics Inspector renders help like every other section.
- [ ] **Step 7:** Per-section verification on resizable emulator at 4 widths (400 / 700 / 900 / 1300dp) + unit tests + commit per section.

---

## Phase 5 — Android 16 connected-display polish (shippable)

- [ ] **Task 5.1: Large/XL refinements.** At ≥1200dp let panes breathe: replace fixed `200.dp`/`300.dp` with `PaneScaffoldDirective`-derived widths or `Modifier.preferredWidth` on panes; verify the three-pane scene shows list+detail+extra simultaneously at Large.
- [ ] **Task 5.2: Pointer & keyboard basics.** Hover indications on rail/list items (Compose handles most via Material ripple); keyboard shortcuts: `Ctrl+Enter` run query, `Ctrl+1..7` rail sections (`Modifier.onPreviewKeyEvent` at `StudioScaffold` level); right-click context menu on query results rows (copy JSON) via `Modifier.pointerInput` secondary-button detection.
- [ ] **Task 5.3: Testing matrix.**
  - Resizable emulator (Display Mode toolbar): phone ↔ unfolded ↔ tablet ↔ desktop, all 7 sections, panel toggles, process-death restore.
  - Desktop AVD / tablet AVD (Android 15 QPR1+) for freeform windowing: drag-resize the window across all 4 breakpoints; no crashes, no state loss.
  - `adb shell am kill` + relaunch in a desktop window → back stack and section restore (Nav3 serializable keys).
  - Hardware (when available): Pixel 8+ on QPR3 + USB-C DP monitor — plug in mid-session: studio re-lays-out to Large without losing query text/results.
- [ ] **Task 5.4: Lock it in.** Add a CI/lint guard: forbid `Configuration.screenWidthDp` outside `ui/adaptive/` (custom lint rule or a grep-based Gradle verification task).

---

## Explicitly deferred (decisions from 2026-06-11)

- **Multi-instance windows** (`PROPERTY_SUPPORTS_MULTI_INSTANCE_SYSTEM_UI`, multi-session Ditto): deferred. The Koin session scope keyed by `databaseId` (Phase 3) keeps this door open.
- **Presence Graph**: separate feature plan after migration (`plans/` — depends on the Phase 4 Presence section landing first).
- **targetSdk 37**: bump when Android 17 stabilizes; we'll already comply with the resizability mandate.

## Risk Register

| Risk | Severity | Mitigation |
|---|---|---|
| `material3-adaptive 1.3.0-beta02` API churn (`currentWindowAdaptiveInfo` V2 deprecation, `NavDisplay` strategy-list signature changes) | Medium | All adaptive symbols funneled through `ui/adaptive/WindowSize.kt` and `StudioScaffold.kt`; pin the version; budget a half-day per beta bump |
| Ditto instance lifecycle during VM split (Phase 3) — double-close or leak kills sync | **High** | Single `onCleared`/scope-close owner; test asserting exactly-once close; manual section-switch soak test |
| `lifecycle-viewmodel-navigation3` is RC | Low | RC = API-frozen; stable expected before Phase 4 lands |
| Fixed-width panels vs Material proportional panes (user chose Material strategies) | Medium | Accept canonical pane sizing at Medium/Expanded; use directive customization at Large if the 200/300dp feel must be preserved — evaluate in Task 5.1 with the user |
| Phone drawer × pushed drill-in entries back-press interplay | Medium | UX-test on phone emulator in Task 4.3 Step 3 before deleting old PhoneLayout |
| Existing e2e tests (recent commits show e2e query/pagination tests) assume current layout/IDs | Medium | Run e2e suite per phase; keep accessibility identifiers stable when extracting composables |

## Sequencing & estimates

| Phase | Size | Shippable? |
|---|---|---|
| 0 — groundwork | S (1–2 days) | yes |
| 1 — WindowSizeClass | S (1–2 days) | yes |
| 2 — Nav3 app graph | M (2–3 days) | yes |
| 3 — Session VM split | M–L (3–5 days, highest risk) | yes |
| 4 — Scenes per section | L (1–2 weeks, 7 sections incremental) | per-section |
| 5 — Android 16 polish | M (3–4 days) | yes |

Phases 0–2 are independent of each other's internals and could interleave with small bug fixes; Phase 3 must precede 4; nothing else should land in `MainStudioScreen.kt` while Phase 4 is in flight.
