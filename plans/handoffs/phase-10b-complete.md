# Phase 10b Complete — Handoff for Phase 10c

**Created**: 2026-05-08
**Branch**: `release-1.0b5`
**Phase 10b commit**: see `git log` (refactor + 4 new sub-VMs + tests)

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md` (Phase 10c is in the "Phase 10 — HIGH Architecture Cleanups" section, sub-section `10c — View polish`)
- Previous handoff: `plans/handoffs/phase-10a-complete.md`
- This file is the entry point if Phase 10c starts in a fresh `/clear`'d session

## Project facts that don't change
- Same as Phase 10a's handoff. Apple Xcode MCP server is registered and was healthy through 10b. Use `mcp__xcode__BuildProject`, `mcp__xcode__GetBuildLog`, `mcp__xcode__XcodeListNavigatorIssues` when the user has Xcode open.
- Don't run macOS and iPadOS xcodebuild simultaneously — they share `Edge_Debug_Helper-*` DerivedData.
- `rtk` wraps `git`. Use `rtk proxy git diff --no-color --no-ext-diff > patch.diff` for raw diffs.
- Test baseline is now **412 tests** (270 unit including the new sub-VM tests + 142 integration) on macOS; xcresult-summary reports `passedTests: 411, skippedTests: 1, failedTests: 0`. Phase 10b added 13 new tests.
- **Run with a clean DerivedData** when `Command CodeSign failed` surfaces on the EdgeStudioUITests bundle — reproducibly fixed by `rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*` then re-running.

## What Phase 10b changed

### `refactor: split MainStudioView.ViewModel into four sub-VMs (Phase 10b)` (commit hash: see git log)

Manual smoke test signed off by Aaron after build + test verification.

#### Files added (10 total)

**Sub-ViewModels** (`SwiftUI/EdgeStudio/Views/StudioView/ViewModels/`):
- `MainStudioViewModel.swift` — composition root (~390 lines). Holds the four sub-VMs as `var` (NOT `@ObservationIgnored let` — see "Critical observation pattern" below). Owns parent-only state: `selectedApp`, `collections`, `isRefreshingCollections`, `isLoading` (Phase 9 gate — DO NOT MOVE), `selectedSidebarDestination` + UserDefaults wiring, `metricsInspectorMenuItems` + `selectedMetricsInspectorMenuItem` + four `metricsPrometheus*` form-state properties, the `loadTask`. Orchestration: `startLoad`, `performLoad`, `closeSelectedApp`, `performCleanupOperations`, isolated `deinit`. Cross-VM helpers: `showJsonInInspector(_:)` (delegates to queryVM + attachmentVM) and `showJsonInObserveInspector(_:)` (queryVM.selectedJsonForInspector + subObsVM tab selection).
- `SyncStatusViewModel.swift` — sync toggle, peer status (`syncStatusItems`, `mergeStatusItems`), `connectionsByTransport`, four `localPeer*` properties, `isSyncEnabled`, `toggleSync()`, `installCallbacks()` (registers SystemRepository sync-status + connections callbacks), `registerPresenceObserver()`, `loadLocalPeerInfo()`, `reset()`. Init takes `DittoManagerProtocol` + `SystemRepositoryProtocol`.
- `QueryViewModel.swift` — `selectedQuery`, `executeModes`, `selectedExecuteMode`, `jsonResults`, `isQueryExecuting`, `history`, `favorites`, `selectedJsonForInspector`, `lastQueryMetricsRecord`, `selectedQueryInspectorMenuItem` + `queryInspectorMenuItems`, `executeQuery(appState:)`, `addQueryToHistory(appState:)`, `refreshLastQueryMetrics()`, `showJsonInInspector(_:)`, `selectInspectorTab(named:)`, `installCallbacks()` (history + favorites), `loadHistory(for:)`, `loadFavorites(for:)`, `reset()`, static `buildQueryInspectorItems(metricsEnabled:)`. Init takes `QueryServiceProtocol` + `HistoryRepositoryProtocol` + `FavoritesRepositoryProtocol`.
- `AttachmentViewModel.swift` — `attachmentProgress`, four `attachment*Target*` staging properties, `detectedAttachments`, `attachmentLoadedImages`, `attachmentLoadingIds`, `attachmentErrors`, parsers (`parseCollectionName`, `parseDocumentId`), staging (`stageAddAttachment`, `stageDeleteAttachment` — both now take `currentQuery: String` so they don't read sibling VM state), `executeAddAttachment` (now takes `executeMode: String`), `executeDeleteAttachment` (unchanged signature except VM relocation), `detectAttachments(in:)` (renamed from `detectAttachmentsInSelectedJson`, now takes the JSON as a parameter), `fetchAttachmentForViewing(_:json:executeMode:appState:)` (signature changed — also takes JSON + executeMode by parameter). Init takes `QueryServiceProtocol`. **`AttachmentService.shared` is still called directly** for upload/fetch — see "Deferred to 10c" below.
- `SubscriptionObserverViewModel.swift` — `subscriptions`, `observerables`, `selectedObservable`, `selectedEventId`, `eventStore` (note: `var`, not `let` — `ObservableEventStore` is a struct with `mutating` methods), `pendingObservedEvents`, `observedEventFlushTask`, `editorSubscription`, `editorObservable`, `eventMode`, `selectedObserveInspectorMenuItem` + `observeInspectorMenuItems`, the new `stageNewSubscription()` / `stageNewObservable()` helpers (FAB + empty-state CTAs both go through these), `stageSubscriptionEditor`, `stageObservableEditor`, `formCancel`, `formSaveSubscription`, `formSaveObserver`, `importSubscriptionsFromQR`, `enqueueObservedEvent`, `flushPendingObservedEvents`, `cancelObservedEventFlush`, `deleteObservable`, `deleteSubscription`, `registerStoreObserver`, `removeStoreObserver`, `selectedEventObject` (computed), `selectInspectorTab(named:)`, `installCallbacks()`, `loadSubscriptions(for:)`, `loadObservers(for:)`, `reset()`. Init takes `DittoManagerProtocol` + `SubscriptionsRepositoryProtocol` + `ObservableRepositoryProtocol`.

**Tests** (`SwiftUI/EdgeStudioUnitTests/ViewModels/`):
- `ViewModelMocks.swift` — module-internal versions of the eight protocol mocks lifted out of `MainStudioViewModelTests.swift`, plus a `MockSet` bundle. Mock classes are now `actor`s at file scope (no longer `private`). Some mocks now also record evidence (e.g. `MockDittoManager.startSyncCallCount` / `stopSyncCallCount`, `MockSubscriptionsRepository.savedSubscriptions`, `MockObservableRepository.savedObservables`, `MockQueryService.lastLocalQuery` / `lastHttpQuery`). `MockSystemRepository.presenceObserverRegistered` records calls too.
- `SyncStatusViewModelTests.swift` — 3 tests (default state, toggleSync routes through DittoManager including state flip + count assertions, reset clears state).
- `QueryViewModelTests.swift` — 3 tests (executeModes reflects HTTP availability, executeQuery in Local mode forwards selectedQuery + records history, selectInspectorTab finds named tab and is a no-op for unknown tabs).
- `AttachmentViewModelTests.swift` — 4 tests (parseCollectionName extracts table after FROM, parseDocumentId returns nil/value correctly, stageAddAttachment captures + parses, detectAttachments(nil:) clears).
- `SubscriptionObserverViewModelTests.swift` — 4 tests (default observe inspector tabs, stageNewSubscription seeds blank, formSaveSubscription forwards via repository (polls ≤ 1s for the unstructured Task to land), reset clears state).

**Modified to repoint at the new sub-VM types**:
- `SwiftUI/EdgeStudioUnitTests/ViewModels/MainStudioViewModelTests.swift` — inline mocks deleted (lifted to `ViewModelMocks.swift`); test bodies updated to `viewModel.subObsVM.subscriptions`, `viewModel.queryVM.history`, `viewModel.queryVM.executeModes`, `viewModel.queryVM.selectedQuery`, `viewModel.queryVM.addQueryToHistory(...)`. SwiftFormat reordered the imports per `--importgrouping testable-bottom` config.
- `SwiftUI/EdgeStudioUnitTests/Models/AttachmentTests.swift` — both `makeViewModel()` helpers now return `AttachmentViewModel` (parsers moved there). The two helper functions had identical bodies but my first `replace_all` only caught one because of header-comment differences; needed a second targeted Edit.

#### Files removed-from / modified

- `SwiftUI/EdgeStudio/Views/MainStudioView.swift` — old `// MARK: ViewModel` extension block (lines 510-1527, ~1018 lines) deleted. View struct stays in this file, plus the `// MARK: Helpers`/`// MARK: - Sheet Presentation Helpers` extension and the `ActiveSheet` / `SidebarDestination` / `MenuItem` types. View struct call sites updated to the new sub-VM paths (e.g. `viewModel.subObsVM.editorSubscription`, `viewModel.queryVM.selectedQuery`, `viewModel.attachmentVM.executeAddAttachment(... executeMode: viewModel.queryVM.selectedExecuteMode, ...)`, `viewModel.syncVM.toggleSync()`). FAB inline buttons now call `viewModel.subObsVM.stageNewSubscription()` / `stageNewObservable()` to share the same path as the empty-state CTAs (per the Phase 10 handoff intent).
- `SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift` — `viewModel.subscriptions`/`observerables`/`selectedObservable`/`registerStoreObserver`/`removeStoreObserver`/`deleteObservable`/`deleteSubscription` repointed to `subObsVM`; `selectedQuery` repointed to `queryVM`.
- `SwiftUI/EdgeStudio/Views/StudioView/InspectorViews.swift` — bindings (`$viewModel.queryVM.selectedQueryInspectorMenuItem`, `$viewModel.subObsVM.selectedObserveInspectorMenuItem`) work because the parent VM stores sub-VMs as `var` (not `@ObservationIgnored let`). The `fetchAttachmentForViewing` call site changed to pass `json:` and `executeMode:` explicitly. All inspector reads (`history`, `favorites`, `selectedJsonForInspector`, `detectedAttachments`, `attachmentLoadedImages`, `attachmentLoadingIds`, `attachmentErrors`, `lastQueryMetricsRecord`, `selectedQuery`) repointed.
- `SwiftUI/EdgeStudio/Views/StudioView/Details/DetailViews.swift` — many sub-VM repoints across the sync detail, query detail, and observe detail views; bindings (`$viewModel.queryVM.selectedExecuteMode`, `$viewModel.subObsVM.eventMode`, `$viewModel.subObsVM.selectedEventId`, `$viewModel.queryVM.jsonResults`, `$viewModel.queryVM.selectedQuery`) all chain through `var` sub-VMs.
- `SwiftUI/EdgeStudio/Views/StudioView/Details/ConnectedPeersView.swift` — `syncStatusItems` and the four `localPeer*` reads repointed to `viewModel.syncVM.*`.

### Critical observation pattern (READ THIS BEFORE TOUCHING SUB-VMs IN 10c)

The four sub-VMs are stored on the parent as `var` properties, **NOT** `@ObservationIgnored let`. This was a build-time forced choice in Phase 10b: the View needs SwiftUI bindings into the sub-VMs (e.g. `$viewModel.queryVM.selectedExecuteMode` for `Picker`), and `@ObservationIgnored` suppresses the macro's binding generation, breaking the chain with "Cannot assign to property: 'queryVM' is a 'let' constant". The `var` choice doesn't cause observation churn because the sub-VM references are never reassigned after init — the parent never invalidates from the sub-VM property. Each sub-VM's own `@Observable` macro drives the actual property-level invalidations the View depends on. Documented inline at `MainStudioViewModel.swift:27-36`.

If you need to swap a sub-VM at runtime in 10c (you almost certainly don't), reconsider the architecture rather than adding `@ObservationIgnored`.

### Verification (Phase 10b)

- ✅ macOS build SUCCEEDED via `mcp__xcode__BuildProject`
- ✅ iPadOS build SUCCEEDED via CLI `xcodebuild ... iPad Pro 13-inch (M5)`
- ✅ Tests via `xcrun xcresulttool get test-results summary`: **411 passed / 1 skipped / 0 failed = +14 from Phase 10a baseline** (was 397 / 1 / 0)
- ✅ SwiftFormat clean on the 17 changed files (7/17 reformatted in flight; cached after)
- ✅ SwiftLint clean on the 10 changed source files (test files are excluded from the project's `.swiftlint.yml` `included:` path; the existing pattern matches Phase 10a's verification scope — `MetricsBackendTests.swift` and similar emit `sorted_imports` warnings when explicitly linted but pass project-wide runs)
- ✅ Manual smoke test signed off by Aaron

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:

- **Phase 10c — View polish (~2 hours)**:
  - Replace `Binding(get:set:)` with `@Bindable` projections where backing is `@Observable` (the plan says "8+ sites" — re-survey now that 10b is done)
  - Mark all non-private `@State` as `private` in `MainStudioView`
  - Move `MenuItem.image` (which returns `some View`) to a view-layer extension; keep `MenuItem` Foundation-pure
  - Move `performDownload` and download orchestration from `ContentView` extension into `ContentView.ViewModel`
  - Delete dead `SubscriptionsRepository.cancelAllSubscriptions`
- **Phase 11** — MEDIUM/LOW polish + CLAUDE.md updates.

### 10c also-rans (deferred from 10b)

These were intentionally deferred from 10b to keep the budget. None block 10c, but if you have spare time at the end:
- **Protocolize `AttachmentService`** — `AttachmentServiceProtocol` with `createAndLink`, `createAndLinkViaHttp`, `fetch(token:id:)`, `fetchViaHttp(attachmentId:)`. The `[String: Any]` token argument complicates a `: Sendable` protocol — either drop `: Sendable`, wrap the dict in a Sendable struct, or use `sending` keyword. Once landed, `AttachmentViewModel.executeAddAttachment` and `fetchAttachmentForViewing` become unit-testable end-to-end.
- **Protocolize `QueryMetricsRepository`** — single method (`allRecords()`). Trivial to add. `QueryViewModel.refreshLastQueryMetrics` is the only consumer.
- **`closeSelectedApp` no longer cancels `observable.storeObserver?.cancel()` in a TaskGroup** — the original god-VM had this, but with a bug: by the time `performCleanupOperations` ran, `observerables` had already been emptied by the close path, so the cancellation loop iterated over `[]`. Phase 10b preserves the (broken-but-stable) behavior implicitly via SDK shutdown when `closeDittoSelectedDatabase` runs. If 10c (or beyond) wants explicit per-observer cancellation in cleanup, capture the observerables snapshot **before** `subObsVM.reset()` runs and pass it to `performCleanupOperations`. See `MainStudioViewModel.swift:299-305` for the documented current state.
- **`AttachmentViewModel.reset()` doesn't exist** — original god-VM never reset attachment state on close, so neither does the new sub-VM. `closeSelectedApp` documents this at `MainStudioViewModel.swift:283-285`. If you want clean-slate-on-close for attachment state, add `reset()` to `AttachmentViewModel` and call it from `closeSelectedApp`. Behavior change — flag in 10c manual test.

## Open notes / risks for Phase 10c

- **Don't add `@ObservationIgnored` to the four sub-VM properties.** Bindings break (see "Critical observation pattern" above).
- **`isLoading` MUST stay on the parent `MainStudioView.ViewModel`.** It gates the detail-area `ProgressView` (line 286 of `MainStudioView.swift`) and is set/reset by `performLoad` which orchestrates across all sub-VMs. Don't move it to any of the four extracted children.
- **`presentNewSubscriptionEditor()` and `presentNewObserverEditor()` already delegate to `subObsVM.stageNewSubscription/Observable()`** as part of 10b's "FAB + empty-state CTAs share one VM-owned path" goal. The `activeSheet` flip remains on the View struct (View state).
- **`MenuItem.image` returning `some View`** — when 10c moves it to a view-layer extension, the existing definition lives at `MainStudioView.swift` (search for `struct MenuItem`). `QueryViewModel.buildQueryInspectorItems`, `SubscriptionObserverViewModel`'s init, and `MainStudioViewModel`'s init all create `MenuItem` instances; none of them touch `.image`, so the move is purely view-side.
- **`Binding(get:set:)` audit** — re-grep after 10b changed many surrounding sites:
  ```bash
  grep -rnE "Binding\(\s*get:" SwiftUI/EdgeStudio/Views --include="*.swift"
  ```
- **`@State` privacy audit** for `MainStudioView`:
  ```bash
  grep -nE "@State\s+var\s+" SwiftUI/EdgeStudio/Views/MainStudioView.swift
  ```
  Flip every `@State var X` (without `private`) to `@State private var X` unless it's a `@Binding` consumer (in which case it's already `@Binding`).
- **Phase 10c manual test gate** — full smoke test of every feature. Some `Binding(get:set:)` → `@Bindable` migrations can subtly change identity behavior. Watch for sheet/picker re-render flicker.
- **Test baseline**: 411 passing / 1 skipped / 0 failed = 412 total. Expect 10c to keep this number flat (no new tests required by the plan).

## Side note: window-size regression fix (Phase 8 follow-up, not Phase 10b)

During Phase 10b smoke testing Aaron noticed the studio window opened too small — the sidebar's segmented picker (6 × 48pt icons = 288pt min) and the FAB at the bottom were getting clipped. Root cause traced to Phase 8 (`3e09eee`): the imperative `window.setContentSize(...)` was removed but `WindowFrameRestorer.minimumSize` was left at `960x680`, well below the studio's `MainStudioView.frame(minWidth: 1400, minHeight: 820)` content min. `.windowResizability(.contentMinSize)` doesn't auto-grow the window when the content's min increases; it only enforces lower bound on user-driven resizes. Fix: bump `WindowFrameRestorer.minimumSize` to `(1400, 820)` so `enforceMinimum(in:)` resizes the window when MainStudioView appears for the first time. One-line change in `SwiftUI/EdgeStudio/Utilities/WindowFramePersistence.swift`. Committed separately from the 10b refactor.

## How to start Phase 10c in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-10b-complete.md` then start Phase 10c per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` (architecture refactor is SwiftUI domain).
3. Phase 10c is the final sub-phase of Phase 10. Manual test gate after 10c, then move to Phase 11.
