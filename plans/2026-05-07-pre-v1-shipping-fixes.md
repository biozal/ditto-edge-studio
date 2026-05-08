# Pre-v1 Shipping Fixes — Agent-Based Execution Plan

**Created**: 2026-05-07
**Owner**: aaron.labeau@ditto.com
**Scope**: All 54 findings from the SwiftUI pre-v1 audit (9 CRITICAL / 27 HIGH / 18 MEDIUM-LOW)
**Goal**: Ship v1 with zero ship-blocker issues remaining and a stable foundation for post-v1 work.

---

## How to use this plan

This plan is structured as **11 sequential phases**. Each phase:

1. Has a single, focused theme (e.g., "AppState foundation", "Performance hot paths").
2. Lists every file and line that will be touched.
3. Specifies which agent / approach to use.
4. Has a **Verification** block (build commands, automated checks) — must pass before moving on.
5. Has a **Manual Testing** checkpoint — Aaron exercises the app on macOS + iPadOS, confirms behavior, and signs off before the next phase starts.
6. Lists **Risks / Rollback** notes.

**Workflow per phase**:
1. Aaron says "start phase N"
2. Claude dispatches agent(s) for that phase, monitors output, applies edits
3. Claude runs build + tests; reports results
4. Aaron does manual testing using the test checklist; reports back
5. Aaron says "phase N approved" → Claude commits the phase as a single git commit with a clear message → moves to phase N+1
6. If issues found during manual testing → fix in-phase, do not advance

**Rules of engagement**:
- Per `CLAUDE.md`: all code edits via **Xcode MCP** for files in the Xcode project; standard tools for docs/scripts.
- Per `CLAUDE.md`: build for **both macOS and iPadOS** after every phase — non-negotiable.
- Per `docs/TESTING.md`: tests for new code use **Swift Testing**, not XCTest.
- Each phase must leave the app **buildable, runnable, and at least as functional** as before — no broken intermediate states.

---

## Build / Test Commands (used after every phase)

```bash
# macOS build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
           -scheme "Edge Studio" \
           -configuration Debug \
           -destination "platform=macOS,arch=arm64" build

# iPadOS build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
           -scheme "Edge Studio" \
           -configuration Debug \
           -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build

# Run all tests (macOS)
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64"

# Lint
swiftlint lint
swiftformat --verbose --dryrun .
```

---

## Phase 0 — Baseline & Safety Net

**Goal**: Establish a known-good starting point so we can detect regressions phase-over-phase.

**Estimated effort**: 30 min (no code changes — preparation only)

### Tasks
1. Confirm current branch is clean: `git status`
2. Working branch is `release-1.0b5` (all v1 fix work commits here, no separate feature branch)
3. Run baseline builds on both platforms (commands above) → confirm green
4. Run full test suite → record pass count and any pre-existing failures
5. Take screenshots of the macOS picker, MainStudioView (Subscriptions/Query/Observer/Logging), and iPad split-view layouts at full and 50% Split View → save in `screens/baseline-2026-05-07/`
6. Capture an `xclog` baseline of a clean app launch + open-database flow → save in `reports/pre-v1-baseline/`

### Verification
- Both builds green
- Test suite has a known pass count
- Baseline screenshots and logs captured

### Manual Testing — Aaron
None — this is a preparation phase.

### Approval gate
Aaron confirms: "baseline captured, start phase 1"

---

## Phase 1 — AppState Foundation (Concurrency C4 + cascading legacy migration)

**Goal**: Eliminate the single largest source of Swift 6 concurrency violations and `@EnvironmentObject` legacy. ~10 HIGH findings collapse into trivial migrations once `AppState` is `@MainActor @Observable`.

**Estimated effort**: 3-4 hours of agent work + 30 min manual testing

### Findings addressed
- **C4** — `AppState` not `@MainActor`, uses `@Published` + `DispatchQueue.main.async`
- **HIGH-Modernization** — `class AppState: ObservableObject` → `@Observable`
- **HIGH-Architecture** — `appConfig` is dead code (never read after init)
- **HIGH-Modernization** — 7 `@EnvironmentObject` consumers → `@Environment(AppState.self)`
- **HIGH-Modernization** — `@StateObject private var appState` → `@State private var appState`
- **HIGH-Concurrency** — `appState?.setError(error)` from actor contexts becomes safe `await`
- **MEDIUM-Architecture** — Unused `cancellables: Set<AnyCancellable>` in `ContentView.ViewModel`
- **MEDIUM-Architecture** — 3 unused `import Combine` statements

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/AppState.swift` | Rewrite as `@Observable @MainActor final class`, remove `appConfig`, simplify `setError` |
| `EdgeStudio/Ditto_Edge_StudioApp.swift` | `@StateObject` → `@State`; `.environmentObject(appState)` → `.environment(appState)` |
| `EdgeStudio/Views/ContentView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)`; remove unused `cancellables`; remove `import Combine` |
| `EdgeStudio/Views/MainStudioView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Views/Database/DatabaseEditorView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Views/Database/DatabaseList.swift` | Remove `import Combine` |
| `EdgeStudio/Views/Logging/LoggingDetailView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Views/StudioView/Details/TransportConfigView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Components/SubscriptionObserverEditor.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Components/ImportDataView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Components/ImportSubscriptionsView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Components/AddIndexView.swift` | `@EnvironmentObject` → `@Environment(AppState.self)` |
| `EdgeStudio/Components/DatabaseCard.swift` | Remove `import Combine` |
| `EdgeStudio/Data/DittoManager.swift` (and all extensions) | All `appState?.setError(error)` → `await appState?.setError(error)` (or restructure to avoid optional actor hops) |
| `EdgeStudio/Data/Repositories/HistoryRepository.swift` | `appState?.setError` → `await appState?.setError` |
| `EdgeStudio/Data/Repositories/FavoritesRepository.swift` | `appState?.setError` → `await appState?.setError` |
| `EdgeStudio/Data/Repositories/CollectionsRepository.swift` | Same |
| Any other repository file calling `appState.setError` | Same |

### Agent dispatch
Use **Xcode MCP** for all code edits. Single agent task — this is a tightly scoped refactor with cascading mechanical changes, best done by one agent in one pass.

Prompt: *"Migrate `AppState` to `@MainActor @Observable`, remove the `appConfig` dead property, drop the `DispatchQueue.main.async` workaround in `setError`. Then update all `@EnvironmentObject var appState` declarations across the app to `@Environment(AppState.self) private var appState`. In `Ditto_Edge_StudioApp.swift`, change `@StateObject` to `@State` and `.environmentObject(appState)` to `.environment(appState)`. Update all callers of `appState.setError(error)` from non-MainActor contexts to use `await appState?.setError(error)`. Remove the unused `cancellables: Set<AnyCancellable>` and `import Combine` from `ContentView.ViewModel`, `Components/DatabaseCard.swift`, and `Views/Database/DatabaseList.swift`. Build for both macOS and iPadOS — must succeed."*

### Verification
- ✅ Both builds green
- ✅ Existing tests still pass
- ✅ `grep -r "ObservableObject\|@Published\|@StateObject\|@ObservedObject\|@EnvironmentObject" --include="*.swift"` returns **zero hits**
- ✅ `grep -r "import Combine" --include="*.swift"` returns **zero hits in EdgeStudio/** (test/UI test targets may keep)
- ✅ `grep -r "DispatchQueue.main.async" --include="*.swift" EdgeStudio/AppState.swift` returns **zero hits**

### Manual Testing — Aaron
**macOS**:
1. Cold launch app — picker appears, no errors
2. Add a database — error states (e.g., bad token) still surface as alerts
3. Open a database — MainStudioView opens, sync starts
4. Trigger an error (e.g., temporarily break a config) — error alert appears, dismisses cleanly
5. Close database, reopen — no stale state

**iPad Pro 13-inch (M5)**:
1. Same as above — confirm no `EXC_BAD_ACCESS` or threading warnings in Console
2. Watch for any "Publishing changes from background threads is not allowed" warnings — should be **gone**

**Approval gate**: "phase 1 approved" → commit `feat: migrate AppState to @Observable @MainActor + cascading cleanup`

### Risks / Rollback
- **Risk**: `await appState?.setError(error)` in actor contexts may surface previously-hidden compile errors. Acceptable — they were latent races.
- **Risk**: Some sites may not be in async contexts. Wrap in `Task { @MainActor in await appState?.setError(error) }`.
- **Rollback**: `git revert` the phase commit; phase 2 should not start until phase 1 is solid.

---

## Phase 2 — Critical Concurrency Fixes

**Goal**: Close the remaining Swift 6 strict-concurrency holes that survived phase 1 — SDK callback boundaries, retain cycles in `ditto.auth.expirationHandler`, MainActor mutation from SDK threads, and `[weak self]` consistency across repository callbacks.

**Estimated effort**: 4-5 hours

### Findings addressed
- **C5** — `expirationHandler` strong self capture + cross-isolation `appState?.setError`
- **C6** — `registerStoreObserver` mutates `@MainActor` state directly from SDK thread
- **HIGH-Concurrency** — `SystemRepository` presence callback captures non-Sendable `Ditto`/`presenceGraph`
- **HIGH-Concurrency** — `SubscriptionsRepository.setOnSubscriptionsUpdate` callback missing `[weak self]`
- **HIGH-Concurrency** — `CollectionsRepository.setOnCollectionsUpdate` callback missing `[weak self]`
- **HIGH-Concurrency** — `CollectionsRepository.stopObserver()` uses `Task.detached` and returns before cleanup → race
- **HIGH-Concurrency** — `DatabaseRepository.onDittoDatabaseConfigUpdate` callback type not `@MainActor` (inconsistent)
- **HIGH-Concurrency** — `SystemRepository.processSyncStatusUpdate` completion not `@Sendable`/`@MainActor` typed

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Data/DittoManager.swift:131-144` | Capture `appState`/`databaseConfig` as locals; `[weak self]` on outer + inner closures; `Task { @MainActor in ... }` on inner |
| `EdgeStudio/Views/MainStudioView.swift:1054-1083` | Build event from results synchronously, then `Task { @MainActor [weak self] in self?.observableEvents.append(capturedEvent) }` |
| `EdgeStudio/Data/Repositories/SystemRepository.swift:217-382, 476-544` | Extract `presenceGraph` data synchronously before `Task`; only capture Sendable values across boundary |
| `EdgeStudio/Views/MainStudioView.swift:623,633` | Add `[weak self]` to subscriptions + collections callbacks |
| `EdgeStudio/Data/Repositories/CollectionsRepository.swift:245` | Make `stopObserver()` `async`; remove `Task.detached`; remove now-dead `deinit` |
| `EdgeStudio/Data/Repositories/DatabaseRepository.swift:32,207` | Type `onDittoDatabaseConfigUpdate` as `(@MainActor ([DittoConfigForDatabase]) -> Void)?` |
| `EdgeStudio/Views/ContentView.swift:595` | Simplify callsite (remove inner `Task`) now that callback type is `@MainActor` |
| `EdgeStudio/Data/Repositories/SystemRepository.swift:406-413` | Type `onSyncStatusUpdate` as `(@MainActor ([SyncStatusInfo], @escaping @Sendable () -> Void) -> Void)?` |
| `EdgeStudio/Views/MainStudioView.swift` (close path) | If `CollectionsRepository.stopObserver()` is now async, ensure `await` at all call sites |

### Agent dispatch
Two agents in parallel (independent work):

**Agent A (DittoManager + Observer):** Fix `expirationHandler` capture and `registerStoreObserver` MainActor dispatch.

**Agent B (Repositories):** Fix `SystemRepository` presence callback Sendable extraction; add `[weak self]` to subscriptions/collections callbacks; convert `CollectionsRepository.stopObserver` to async; type `DatabaseRepository` and `SystemRepository` callbacks as `@MainActor`; simplify ContentView callsite.

### Verification
- ✅ Both builds green
- ✅ Run with **Swift 6 strict concurrency** explicitly enabled — zero new warnings vs. baseline
- ✅ Existing tests pass
- ✅ `grep -n "Task.detached" CollectionsRepository.swift` returns zero
- ✅ All four affected callbacks now contain `[weak self]`

### Manual Testing — Aaron
**macOS + iPad**:
1. Open a database → confirm sync, presence, peers tab all populate (proves SDK callbacks still work)
2. Activate an Observer on a high-frequency collection → events stream in (proves `registerStoreObserver` MainActor dispatch works)
3. Close database, immediately re-open → confirm no missed-event ghost state (proves `CollectionsRepository.stopObserver` race is fixed)
4. Wait for an auth token to expire (or simulate) → confirm re-auth fires without crash
5. Watch Xcode runtime: zero "Sending 'self' risks data races" warnings, zero "main actor-isolated property mutated from a Sendable closure" warnings

**Approval gate**: "phase 2 approved" → commit `fix: close Swift 6 concurrency holes in SDK callback boundaries`

### Risks / Rollback
- **Risk**: SDK callback signatures may resist Sendable annotation if `DittoPresenceGraph` is not `Sendable` upstream. Workaround: extract primitive values (strings, counts) synchronously before the `Task`.
- **Risk**: Making `CollectionsRepository.stopObserver` async may cascade into `MainStudioView.performCleanupOperations` `TaskGroup` — needs `await` propagation.
- **Rollback**: revert phase commit; concurrency state returns to phase-1-end.

---

## Phase 3 — Memory Safety: Unbounded Collections

**Goal**: Cap unbounded collections that grow forever, and add observation-event batching to reduce the SwiftUI invalidation storm during high-frequency observer sessions.

**Estimated effort**: 1-2 hours

### Findings addressed
- **C8** — `observableEvents` array unbounded
- **HIGH-Memory** — `selectedObservableEvents` mirrors growth
- **HIGH-Performance** — `selectedEventObject` and `loadObservedEvents` do O(n) scan on every access

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Views/MainStudioView.swift:1075` | Cap at `maxObservableEvents = 500`; remove front when exceeded |
| `EdgeStudio/Views/MainStudioView.swift` (ViewModel) | Replace flat `observableEvents: [DittoObserveEvent]` with `observableEventsByObserverId: [String: [DittoObserveEvent]]` for O(1) lookup; update `selectedEventObject` and `loadObservedEvents` accessors |
| `EdgeStudio/Views/MainStudioView.swift` (ViewModel) | Add 100ms debounce/batch for `observableEvents` appends to coalesce SwiftUI updates under high-frequency sync |

### Agent dispatch
Single agent — focused refactor.

### Verification
- ✅ Both builds green
- ✅ Tests pass
- ✅ Add a unit test (Swift Testing) verifying the 500-event cap evicts oldest entries

### Manual Testing — Aaron
1. Open a database with an active high-frequency collection (or use `test_import.json` to seed data)
2. Activate an Observer; let it run 60 seconds
3. Observe Xcode Memory Report — `observableEvents` array stops growing at 500
4. UI remains responsive during burst events (no frame drops)
5. Selecting different observers still shows the correct event subset

**Approval gate**: "phase 3 approved" → commit `perf: cap observableEvents at 500 + dictionary-backed observer event lookup`

---

## Phase 4 — UX/Navigation Ship-Blockers

**Goal**: Fix the three "user gets stuck" issues that block iPhone/iPad and the cold-launch failure mode.

**Estimated effort**: 3-4 hours

### Findings addressed
- **C1** — iPhone has no toolbar back-to-databases button
- **C2** — `showMainStudio` silently aborts on non-throwing failure
- **C3** — SQLCipher init failure leaves picker spinning forever
- **C7** — `UIDevice.current.userInterfaceIdiom == .phone` breaks iPad Slide Over

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Views/MainStudioView.swift:74` | Replace `UIDevice.current.userInterfaceIdiom == .phone` with `horizontalSizeClass == .compact` |
| `EdgeStudio/Views/MainStudioView.swift:288` | Add `#if os(iOS)` toolbar branch with back button + sync button + close button (call existing `sidebarToggleButton()`) |
| `EdgeStudio/Views/ContentView.swift:650-666` | Add `isLoading` flag during hydration; if `didSetupDitto == false`, surface error via `appState.setError(.error(message: "Failed to initialize database '\(dittoApp.name)'..."))` |
| `EdgeStudio/Views/ContentView.swift:444-536` | Add tap-state visual feedback (disable card / show spinner overlay while loading) |
| `EdgeStudio/AppState.swift` | Add `sqlCipherReady: Bool` published flag; expose `waitForInitialization() async throws` API on `SQLCipherService` |
| `EdgeStudio/Views/ContentView.swift:583-612` | `loadApps` awaits `SQLCipherService.shared.waitForInitialization()` before calling repositories; on failure show distinct error state with **Retry** button (separate from "no databases" empty state) |

### Agent dispatch
Two agents in parallel:

**Agent A (Navigation):** iOS toolbar + horizontalSizeClass fix.

**Agent B (Loading/Error UX):** showMainStudio loading + error feedback; SQLCipher init gate + retry path.

### Verification
- ✅ Both builds green
- ✅ Tests pass
- ✅ `grep -r "UIDevice.current.userInterfaceIdiom" EdgeStudio/` returns zero hits

### Manual Testing — Aaron
**iPhone simulator (iPhone 15 Pro)**:
1. Open app → tap database → MainStudioView opens
2. Confirm back button visible in toolbar (top leading)
3. Tap back → returns to picker, sync stops cleanly

**iPad Pro 13-inch — Slide Over (~320pt window)**:
1. Open app, slide into Slide Over
2. Sidebar dismiss button must be visible (was gated by `.phone` before)
3. Tap dismiss → sidebar collapses

**iPad full-screen**:
1. Tap database → confirm spinner appears on tapped card while hydrating
2. Force a hydration failure (use a database with bad token / unreachable websocket)
3. Confirm error alert appears, picker remains usable

**Cold launch with broken SQLCipher**:
1. Manually corrupt `~/Library/Application Support/.../SQLCipher.db` (or simulate init failure)
2. Launch app → confirm error state with "Retry" button instead of indefinite spinner
3. Tap Retry → if fixed, picker loads; if still broken, error stays

**Approval gate**: "phase 4 approved" → commit `fix: ship-blocker UX/nav gaps (iOS back, hydration feedback, SQLCipher retry)`

---

## Phase 5 — Performance Hot Paths

**Goal**: Fix the four hottest view-body operations that cause measurable frame drops in everyday use.

**Estimated effort**: 2-3 hours

### Findings addressed
- **C9** — `ForEach(items.indices, id: \.self)` in `ResultJsonViewer`
- **HIGH-Perf** — `AttachmentInfo.detectTokens` called in `contextMenu` block of every result cell
- **CRITICAL-Perf** — `filteredEntries` computed in `LoggingDetailView` body (no caching, no debounce)
- **HIGH-Layout/Perf** — `GeometryReader` wrapping `ScrollView+LazyVStack` in `ResultTableViewer`

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Components/ResultJsonViewer.swift:178` | `ForEach(items.indices, id: \.self)` → `ForEach(Array(items.enumerated()), id: \.offset)` |
| `EdgeStudio/Components/ResultJsonViewer.swift:236` | Move `AttachmentInfo.detectTokens` from inline call to `@State var attachments` populated by `.task(id: jsonString)` |
| `EdgeStudio/Components/ResultTableViewer.swift:137,237` | Same — move `detectTokens` into `.task(id:)` per cell |
| `EdgeStudio/Components/ResultTableViewer.swift:80` | Remove outer `GeometryReader`; replace `.frame(minWidth: geometry.size.width)` per row with `.frame(maxWidth: .infinity)` |
| `EdgeStudio/Views/Logging/LoggingDetailView.swift:503` | Move `filteredEntries` from computed property → `@State var cachedFilteredEntries`; populate via debounced `.onChange` (150ms) on each filter input |
| `EdgeStudio/Components/ResultJsonViewer.swift:263` | Replace `DispatchQueue.main.asyncAfter` with `Task { @MainActor in try? await Task.sleep(for: .milliseconds(1500)); ... }` |

### Agent dispatch
Single agent — all changes are localized perf fixes with similar pattern.

### Verification
- ✅ Both builds green
- ✅ Tests pass
- ✅ Profile with Instruments SwiftUI template — confirm reduction in Long View Body Updates on `LoggingDetailView`, `ResultsList`, `ResultTableViewer`

### Manual Testing — Aaron
1. Run query that returns 200+ documents → scroll the result list. Expected: smooth scroll, no jitter
2. Same query in Table mode → smooth scroll
3. Open Logging tab during active sync (high log volume) → type in search field → no keystroke lag
4. Right-click a result row → context menu opens instantly (was previously blocked by JSON parsing)
5. Copy a result JSON → "Copied" indicator appears + clears smoothly with no stale state when scrolling during the 1.5s window

**Approval gate**: "phase 5 approved" → commit `perf: stable cell identity, .task-driven attachment detection, debounced log filter`

---

## Phase 6 — HIGH Concurrency Cleanups

**Goal**: Address the remaining HIGH concurrency findings that aren't ship-blockers but represent real risk.

**Estimated effort**: 3-4 hours

### Findings addressed
- **HIGH-Concurrency** — 5 untracked Tasks in `MainStudioView.ViewModel.init` with strong `self` capture and no cancellation
- **HIGH-Concurrency** — `MainStudioView.ViewModel.init` runs subscriptions/collections/history/favorites/observers loads sequentially on MainActor (parallelize)
- **MEDIUM-Concurrency** — `DittoLogCaptureService` flush tasks should add `Task.isCancelled` check
- **MEDIUM-Architecture** — `DittoManager.getCachedUntrustedSession` uses `static` + `NSLock` inside actor (incoherent isolation)

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Views/MainStudioView.swift:587-711` | Extract init Tasks into a single `func load() async` method called from view's `.task` modifier; store as `private var loadTask: Task<Void, Never>?`; cancel in `closeSelectedApp` and a `deinit`; use `[weak self]` on all captures |
| `EdgeStudio/Views/MainStudioView.swift:621-711` | Use `async let` to parallelize independent repository loads |
| `EdgeStudio/Data/DittoLogCaptureService.swift:73,...` | Add `guard !Task.isCancelled else { return }` before flush body |
| `EdgeStudio/Data/DittoManager.swift:292-313` | Replace static + NSLock with instance-level `cachedUntrustedSession: URLSession?`; remove NSLock |

### Agent dispatch
Single agent for ViewModel.init refactor (high cohesion); separate agent or same agent for the smaller fixes.

### Verification
- ✅ Both builds green
- ✅ Tests pass
- ✅ Verify deinit fires by adding a `Log.debug` in MainStudioView.ViewModel.deinit and watching console after close

### Manual Testing — Aaron
1. Open database → loading indicator appears, finishes faster than before (parallel loads)
2. Open database → immediately close before load completes → no lingering Task warnings; Log shows ViewModel deinit fired
3. Repeat 5 times — no memory growth in Memory Report; no zombie observers
4. Watch Console: if SQLCipher integrity check fires during flush cancellation, no crash

**Approval gate**: "phase 6 approved" → commit `refactor: structured concurrency for MainStudioView load + cleanup`

---

## Phase 7 — HIGH Navigation Cleanups

**Goal**: Replace string-keyed navigation, persist navigation state, and consolidate sheets.

**Estimated effort**: 4-5 hours

### Findings addressed
- **HIGH-Nav** — String-keyed sidebar switch with dead cases
- **HIGH-Nav** — No `@SceneStorage` (selected database, sidebar tab, sync tab all reset on relaunch)
- **HIGH-Nav** — 8 chained `.sheet` modifiers
- **MEDIUM-Nav** — `scenePhase` `onChange` reversed param order + empty bodies

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Views/MainStudioView.swift` | Define `enum SidebarDestination: String, CaseIterable, Identifiable` (subscriptions, query, observers, logging, appMetrics, queryMetrics) |
| `EdgeStudio/Views/MainStudioView.swift` (ViewModel) | Replace `selectedSidebarMenuItem.name: String` switch with `selectedDestination: SidebarDestination` exhaustive switch |
| `EdgeStudio/Views/ContentView.swift` | Add `@SceneStorage("selectedDatabaseId") private var storedDatabaseId: String?` and restore on launch |
| `EdgeStudio/Views/MainStudioView.swift` | `@AppStorage("selectedSyncTab")` + `@AppStorage("selectedSidebarTab")` |
| `EdgeStudio/Views/MainStudioView.swift:192-287` | Replace 8 chained `.sheet` modifiers with single `.sheet(item: $activeSheet)` driven by `enum ActiveSheet` |
| `EdgeStudio/Ditto_Edge_StudioApp.swift:129-138` | Fix `onChange(of: scenePhase) { _, newPhase in ... }` parameter order; either remove the empty bodies or wire actual save logic |

### Agent dispatch
Two agents in parallel:

**Agent A (Sidebar enum + scenePhase):** Sidebar destination enum + AppStorage + scenePhase fix.

**Agent B (Sheet consolidation + SceneStorage):** ActiveSheet enum + selected database persistence.

### Verification
- ✅ Both builds green
- ✅ Tests pass
- ✅ `grep -n "switch.*selectedSidebarMenuItem.name" --include="*.swift"` returns zero

### Manual Testing — Aaron
1. Open database, switch sidebar to Observers, kill app
2. Relaunch → app restores to the same database AND Observers tab
3. Switch sync tab to Presence, switch sidebar away and back → tab persists
4. Open import sheet, tap an action that opens another sheet → only one sheet at a time, transitions cleanly
5. Send app to background → no crash; bring back to foreground → state intact

**Approval gate**: "phase 7 approved" → commit `feat: enum-driven nav + SceneStorage + ActiveSheet consolidation`

### Risks
- **Risk**: SceneStorage on iOS 18+/macOS 26 has subtle Scene-vs-Window semantics on Mac. Test on macOS too.

---

## Phase 8 — HIGH Layout Cleanups

**Goal**: Remove the manual NSWindow choreography and tighten iPad layout.

**Estimated effort**: 2-3 hours

### Findings addressed
- **CRITICAL-Layout** — `NSWindow` manual sizing in `onChange` + `WindowAccessor` (replace with `windowResizability` / scene APIs)
- **HIGH-Layout** — iPad sidebar/inspector min widths break 50% Split View
- **HIGH-Layout** — `if/else` `compactLayout`/`tabLayout` destroys identity in `QueryResultsView`
- **MEDIUM-Layout** — `DatabaseEditorView` sheet `maxHeight: 860` clips Dynamic Type AX5

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Ditto_Edge_StudioApp.swift` | Add `.windowResizability(.contentMinSize)` and `.defaultSize(...)` on the main `WindowGroup` |
| `EdgeStudio/Views/ContentView.swift:53-66` | Remove the `onChange(of: viewModel.isMainStudioViewPresented)` NSWindow block; remove `WindowAccessor` overlay or repurpose for non-resize concerns |
| `EdgeStudio/Views/ContentView.swift` (root frame) | Replace dual-state frame manipulation with `.frame(minWidth:)` modifiers per branch |
| `EdgeStudio/Views/MainStudioView.swift:155-159` | Lower sidebar `min` to 200pt, ideal 260pt; lower inspector `min` to 220pt, ideal 320pt |
| `EdgeStudio/Components/QueryResultsView.swift:63-69` | Unify under shared `selectedTab` state with size-class-driven `pickerStyle` rather than `if/else` between layouts |
| `EdgeStudio/Views/ContentView.swift:271-278` | Remove `maxHeight: 860` constraint on `DatabaseEditorView` sheet; ensure inner content scrolls |

### Agent dispatch
Single agent — layout changes need to be tested as a whole.

### Verification
- ✅ Both builds green
- ✅ macOS window resizes freely (no longer locked to 800×540 on picker)
- ✅ iPad 50% Split View on iPad Pro 12.9 — sidebar + detail + inspector all visible OR gracefully collapse

### Manual Testing — Aaron
**macOS**:
1. Resize the picker window → resizes smoothly without snapping
2. Open database → window expands to studio size (or stays user-resized)
3. Resize during a query → no glitching

**iPad Pro 13-inch**:
1. Full-screen → sidebar/detail/inspector all visible at comfortable widths
2. 50% Split View → sidebar collapses or detail+inspector remain usable
3. 33% Slide Over → single-column fallback works
4. Rotate device → layout reflows correctly
5. Increase Dynamic Type to AX5 (Settings > Display & Brightness > Text Size) → DatabaseEditorView sheet scrolls instead of clipping

**Approval gate**: "phase 8 approved" → commit `fix: remove manual NSWindow sizing + iPad layout adaptivity`

---

## Phase 9 — HIGH UX Cleanups

**Goal**: Add missing loading/empty/error states and the unsaved-changes guard.

**Estimated effort**: 3-4 hours

### Findings addressed
- **HIGH-UX** — `MainStudioView` `isLoading` flag set but never consumed
- **HIGH-UX** — Subscriptions/Observers/Collections sidebar empty states missing
- **HIGH-UX** — `DatabaseEditorView` has no unsaved-changes guard
- **HIGH-UX** — QR scanner shows black screen on denied camera permission
- **HIGH-UX** — `QuickstartProgressWindow` dismiss locked on error
- **HIGH-UX** — `QRCodeScannerView` import errors aren't displayed in-context
- **HIGH-UX** — `ImportDataView` retry path
- **MEDIUM-UX** — `ContentView.ViewModel.loadApps` errors look identical to "no databases"
- **MEDIUM-UX** — `FontDebugWindow` close button uses `NSApplication.shared.keyWindow?.close()`
- **MEDIUM-UX** — `HelpDocumentationWindow` error has no fallback link
- **LOW-UX** — `DeleteAttachmentSheet` no confirmation dialog

### Files touched
| File | Change |
|------|--------|
| `EdgeStudio/Views/MainStudioView.swift` (detail area) | Wrap detail switch in `if viewModel.isLoading { ProgressView } else { ... }` |
| `EdgeStudio/Views/MainStudioView.swift` (sidebar lists) | Add `ContentUnavailableView` with CTA when subscriptions/observers/collections empty |
| `EdgeStudio/Views/Database/DatabaseEditorView.swift` | Track `hasUnsavedChanges`; add `.interactiveDismissDisabled(hasUnsavedChanges)` + `.confirmationDialog` |
| `EdgeStudio/Components/QRCodeScannerView.swift` | Check `AVCaptureDevice.authorizationStatus(for: .video)`; show `ContentUnavailableView` + Settings link when denied |
| `EdgeStudio/Components/QRCodeScannerView.swift` | Surface scan errors in-sheet before auto-dismiss |
| `EdgeStudio/Views/ContentView.swift` (Quickstart sheet) | `.interactiveDismissDisabled(quickstartService.isDownloading && quickstartService.errorMessage == nil)` and ensure error path resets `isDownloading` |
| `EdgeStudio/Views/ContentView.swift:583-612` | Distinguish loadApps error from empty list — show `ContentUnavailableView` with Retry button |
| `EdgeStudio/Views/Tools/FontDebugWindow.swift:421-433` | Use `@Environment(\.dismiss) var dismiss` instead of `NSApplication.shared.keyWindow?.close()` |
| `EdgeStudio/Views/Tools/HelpDocumentationWindow.swift:57-72` | Add "View Online Documentation" fallback link |
| `EdgeStudio/Components/DeleteAttachmentSheet.swift:47-58` | Add `.confirmationDialog` before destructive delete |

### Agent dispatch
Two agents in parallel:

**Agent A (MainStudioView UX):** loading state + empty states + DatabaseEditorView guard.

**Agent B (Modal correctness):** QR camera permission, Quickstart dismiss, FontDebugWindow, HelpDocumentation fallback, DeleteAttachment confirmation, ContentView load error state.

### Verification
- ✅ Both builds green
- ✅ Tests pass

### Manual Testing — Aaron
1. Open new database with zero subscriptions → ContentUnavailableView shown with "Add Subscription" CTA
2. Edit DatabaseEditorView, swipe to dismiss without saving → confirmation dialog appears
3. Revoke Camera permission for Edge Studio in iOS Settings → tap QR scan → see permission denial UI with Settings link
4. Trigger Quickstart download with offline network → progress sheet shows error, dismiss button enabled
5. macOS: Open Font Debug, click main app window, then click Close in Font Debug → only the Font Debug window closes
6. macOS: Open Help, ensure no `UserGuide.md` in dev bundle → see fallback "Open Online Documentation" link
7. Right-click a result row with attachments → "Delete Attachment..." → confirmation dialog appears
8. Force loadApps to fail (corrupt DatabaseRepository read) → see ContentUnavailableView with Retry button

**Approval gate**: "phase 9 approved" → commit `feat: missing loading/empty/error states + dismiss safety nets`

---

## Phase 10 — HIGH Architecture Cleanups (post-v1 ship-quality)

**Goal**: Decompose the god ViewModel and introduce protocol-based DI to unlock the unit-test target.

**Estimated effort**: 8-12 hours (largest phase — split into sub-phases if needed)

### Findings addressed
- **CRITICAL-Architecture** — Singleton-only access in ViewModels blocks unit tests (~80% coverage requirement)
- **HIGH-Architecture** — `MainStudioView.ViewModel` god ViewModel — 44+ properties, 4 unrelated domains
- **HIGH-Architecture** — `Binding(get:set:)` in body (8+ sites)
- **HIGH-Architecture** — Non-private `@State` properties throughout `MainStudioView`
- **HIGH-Architecture** — `MenuItem.image` returns `some View` (leaks SwiftUI into model)
- **HIGH-Architecture** — `ContentView` `NSOpenPanel` + multi-step download orchestration in view
- **MEDIUM-Architecture** — `SubscriptionsRepository.cancelAllSubscriptions` dead code

### Sub-phase breakdown
This phase is large enough to deserve sub-phases with manual testing in between:

#### 10a — Protocol-based DI for ViewModels (~3 hours)
Define protocols for `DittoManager`, `SubscriptionsRepository`, `SystemRepository`, `QueryService`, `DatabaseRepository`, `HistoryRepository`, `FavoritesRepository`, `ObservableRepository`, `CollectionsRepository`. ViewModels accept them via `init` with singleton defaults.

**Manual test**: app behavior identical (regression test only). Add at least one new Swift Testing unit test that constructs `MainStudioView.ViewModel` with mock repos.

#### 10b — Split `MainStudioView.ViewModel` (~5 hours)
Extract:
- `SyncStatusViewModel` — sync toggle, peer status, connectionsByTransport, local peer info
- `QueryViewModel` — selectedQuery, executeModes, jsonResults, isQueryExecuting
- `AttachmentViewModel` — attachment progress, picker state, delete picker, detected attachments, loaded images, errors
- `SubscriptionObserverViewModel` — subscriptions, observerables, observableEvents (now keyed dict), editor state

**Manual test**: full smoke test of every feature — query, observer, subscription, attachment, sync. No regressions.

#### 10c — View polish (~2 hours)
- Replace `Binding(get:set:)` with `@Bindable` projections where backing is `@Observable`
- Mark all non-private `@State` as `private`
- Move `MenuItem.image` to view-layer extension; keep `MenuItem` Foundation-pure
- Move `performDownload` and download orchestration from `ContentView` extension → `ContentView.ViewModel`
- Delete `SubscriptionsRepository.cancelAllSubscriptions`

**Manual test**: regression smoke test.

### Agent dispatch
Each sub-phase is its own agent invocation. **Do not parallelize across sub-phases — they are sequentially dependent.**

### Verification per sub-phase
- ✅ Both builds green
- ✅ All existing tests pass
- ✅ At least 5 new Swift Testing unit tests added (one per ViewModel) that construct with mock repositories

### Manual Testing — Aaron
After each sub-phase, do a full feature smoke test (query execution, observer activation, subscription mgmt, attachment add/delete, sync toggle, presence view, log viewer).

**Approval gate (per sub-phase)**: "phase 10a approved" / "phase 10b approved" / "phase 10c approved" → commit each as its own commit

---

## Phase 11 — MEDIUM/LOW Polish

**Goal**: Clear the long tail.

**Estimated effort**: 2-3 hours

### Findings addressed
- **MEDIUM-Architecture** — `HistoryRepository.saveQueryHistory` reloads full cache (N+1)
- **MEDIUM-Architecture** — `FavoritesRepository.saveFavorite` reloads full cache (N+1)
- **MEDIUM-UX** — `AttachmentPickerSheet` async dismiss timing (error not in-context)
- **MEDIUM-Layout** — `PaginationControls` doesn't adapt to compact width
- **MEDIUM-Layout** — Fixed 200pt column width in `ResultTableViewer` should be flexible
- **MEDIUM-Perf** — `AppMetricsDetailView.timeAgo()` computed in body
- **MEDIUM-Perf** — `pagedItems` array copy as `.task(id:)` — replace with `PageKey` struct
- **MEDIUM-Layout** — Fixed-size macOS picker panels (340x450, 436pt, 280pt) → use flexible frames
- **LOW-UX** — `SubscriptionQRScannerView` shows "Importing 0 of N" briefly
- **LOW-Layout** — Replace `GeometryReader` row anchoring with `containerRelativeFrame` (if not already done in Phase 5)
- **LOW-Architecture** — Update CLAUDE.md to reflect post-cleanup state (paths, repository list, AppState pattern)

### Agent dispatch
Single agent — independent small fixes.

### Verification
- ✅ Both builds green
- ✅ Tests pass
- ✅ CLAUDE.md reflects current state

### Manual Testing — Aaron
1. Type a new query and execute → confirm history list updates immediately, no perceptible delay (cache update vs. reload)
2. Run pagination on iPad in Slide Over → controls adapt cleanly
3. Wide table with many short-value columns → columns size to content, not 200pt fixed
4. macOS picker — resize window → picker columns adapt

**Approval gate**: "phase 11 approved" → commit `chore: medium/low polish + CLAUDE.md updates`

---

## Final Validation

After all 11 phases:

1. **Full regression sweep** — run all UI tests, all unit tests, all integration tests
2. **Health-check rerun** — invoke `/axiom:health-check` to confirm zero CRITICAL findings remain and HIGH count is < 5 (anything left should be intentional / post-v1 backlog)
3. **Periphery scan** — `periphery scan` to confirm no dead code introduced
4. **SwiftLint clean** — `swiftlint lint` no warnings
5. **Performance baseline** — Instruments SwiftUI template — confirm Long View Body Updates < 5 per scrolling session in `LoggingDetailView`, `ResultsList`, `ResultTableViewer`
6. **Memory baseline** — open/close 5 databases in sequence — `MainStudioView.ViewModel` deinit fires every time (verified via `Log.debug` markers)
7. **Manual smoke test** — Aaron exercises every feature on macOS + iPad Pro + iPhone simulator
8. **Final commit** + tag: `git tag v1.0.0`

---

## Summary Table

| Phase | Theme | Hours | Findings | Risk |
|-------|-------|-------|----------|------|
| 0  | Baseline                              | 0.5  | n/a      | none |
| 1  | AppState foundation                   | 4    | 8        | low  |
| 2  | Critical concurrency                  | 5    | 8        | medium |
| 3  | Memory: unbounded collections         | 2    | 3        | low |
| 4  | UX/Nav ship-blockers                  | 4    | 4        | low |
| 5  | Performance hot paths                 | 3    | 4        | low |
| 6  | HIGH concurrency cleanups             | 4    | 4        | medium |
| 7  | HIGH navigation cleanups              | 5    | 4        | low |
| 8  | HIGH layout cleanups                  | 3    | 4        | medium |
| 9  | HIGH UX cleanups                      | 4    | 11       | low |
| 10 | Architecture refactor (sub a/b/c)     | 10   | 7        | high |
| 11 | MEDIUM/LOW polish                     | 3    | 11       | low |
| **Total** | | **~47h** | **68** | |

**Total wall-clock with manual testing pauses**: roughly 6-8 working days of focused effort.

---

## Notes

- **Do not skip manual testing gates.** Each phase touches different surface area; regressions are easiest to catch at the phase boundary, not at the end.
- **Commit per phase** keeps `git bisect` useful if a regression is found later.
- **Rollback policy**: if a phase fails manual testing, fix in-phase. Do NOT advance with known regressions. If a fix is too large, revert the phase commit and re-plan.
- **Agent isolation**: prefer `worktree` isolation for multi-agent parallel work where listed (Phase 2, Phase 4, Phase 7, Phase 9). Sequential phases run on the main branch.
- Per `CLAUDE.md`: every phase ends with both macOS AND iPadOS builds — non-negotiable.
- Per `docs/TESTING.md`: any new tests use Swift Testing.
