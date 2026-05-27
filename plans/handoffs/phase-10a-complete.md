# Phase 10a Complete — Handoff for Phase 10b

**Created**: 2026-05-08
**Branch**: `release-1.0b5` (not yet pushed at handoff time)
**Phase 10a commit**: `0148939 refactor: protocol-based DI for ViewModels (Phase 10a)`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md` (Phase 10b is in the "Phase 10 — HIGH Architecture Cleanups" section, sub-section `10b — Split MainStudioView.ViewModel`)
- Previous handoff: `plans/handoffs/phase-9-complete.md`
- This file is the entry point if Phase 10b starts in a fresh `/clear`'d session

## Project facts that don't change
- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- **Apple Xcode MCP server is registered for this project AND was healthy through Phase 10a.** Use it (`mcp__xcode__BuildProject`, `mcp__xcode__GetBuildLog`, `mcp__xcode__XcodeListNavigatorIssues`) when the user has Xcode open — running CLI `xcodebuild` while Xcode is also building shares the same `Edge_Debug_Helper-frsispgnpllgkbhhbcfsrmkgehzx` DerivedData and locks `build.db`. The fallout from that lock is "Missing package product 'CocoaLumberjack'" / "DittoSwift" errors in Xcode that look like a code regression but are really SPM checkouts left in a half-resolved state. If you hit that, run `xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -resolvePackageDependencies` (sometimes twice) and then re-trigger the Xcode build via `mcp__xcode__BuildProject`.
- Xcode MCP project tree paths use `Edge Debug Helper/EdgeStudio/...` but **on-disk paths are `SwiftUI/EdgeStudio/...`** — `swiftlint` / `swiftformat` need the on-disk form, but `XcodeRead` / `XcodeUpdate` need the MCP form (when MCP is up).
- Test baseline is now **398 tests** (256 unit + 142 integration) on macOS; xcresult-summary reports `passedTests: 397, skippedTests: 1, failedTests: 0`. Phase 10a added 2 unit tests in `MainStudioViewModelTests` (`ViewModel constructs with mock repositories`, `addQueryToHistory routes through the injected HistoryRepository`). **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*`) when test runs intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle — the issue is reproducible and clearing DerivedData clears it.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- **Don't run macOS and iPadOS builds simultaneously** — they share `Edge_Debug_Helper-*` DerivedData and one will fail with `database is locked`.
- **`rtk` (Rust Token Killer) wraps `git`**: `git diff` returns a token-saving summary, not raw unified diff. Use `rtk proxy git diff --no-color --no-ext-diff > patch.diff` when you need a real patch (e.g. for `git apply`).

## What Phase 10a changed

### `refactor: protocol-based DI for ViewModels (Phase 10a)` (`0148939`)

13 files; +496 / -52 lines. Pure additive + mechanical replacements; no behavior change.

#### Protocols introduced

- **`SwiftUI/EdgeStudio/Data/Protocols.swift`** (new) — defines 9 protocols, all `: Sendable` with every requirement marked `async`:
  - `DittoManagerProtocol` — `dittoSelectedApp`, `dittoSelectedAppConfig` (read), `setAppState(_:)`, `hydrateDittoSelectedDatabase(_:)`, `closeDittoSelectedDatabase()`, `selectedDatabaseStartSync()`, `selectedDatabaseStopSync()`. Other DittoManager API (`applyTransportConfig`, `changeDittoLogLevel`, `getCachedUntrustedSession`) is intentionally NOT in the protocol — those are not used by ViewModels.
  - `QueryServiceProtocol` — `executeSelectedAppQuery(query:)`, `executeSelectedAppQueryHttp(query:)`. `fetchSmallPeerInfo` is not in the protocol (not VM-callable; called from MCP backend code).
  - `DatabaseRepositoryProtocol` — `setAppState`, `loadDatabaseConfigs`, `addDittoAppConfig`, `updateDittoAppConfig`, `deleteDittoAppConfig`, `setOnDittoDatabaseConfigUpdate`. (`getCachedDatabaseConfigs` is currently NOT in the protocol because no VM uses it; if a future VM needs it, it's a one-line add.)
  - `SubscriptionsRepositoryProtocol` — `setAppState`, `setOnSubscriptionsUpdate`, `loadSubscriptions(for:)`, `saveDittoSubscription`, `removeDittoSubscription`, `clearCache`, `getCachedSubscriptions`.
  - `SystemRepositoryProtocol` — `setAppState`, `setOnSyncStatusUpdate`, `setOnConnectionsUpdate`, `registerConnectionsPresenceObserver`, `invalidateSession`, `stopObserver`. (`stopSyncStatusObserver` and `fetchPeersOnce` are NOT in the protocol — `fetchPeersOnce` is MCP-only; `stopSyncStatusObserver` is wired from `syncTabsDetailView().onAppear`/`onDisappear` paths in the View extension, not the VM. If 10b moves that wiring into the new `SyncStatusViewModel`, `stopSyncStatusObserver` will need to be added to the protocol.)
  - `HistoryRepositoryProtocol` — `setAppState`, `setOnHistoryUpdate`, `loadHistory(for:)`, `saveQueryHistory`, `clearCache`. (`deleteQueryHistory` is NOT in the protocol — only used by the inspector view's swipe-to-delete, which calls `HistoryRepository.shared` directly. If you move that into `QueryViewModel.deleteQueryFromHistory(_:)` in 10b/10c, add the method to the protocol.)
  - `FavoritesRepositoryProtocol` — `setAppState`, `setOnFavoritesUpdate`, `loadFavorites(for:)`, `saveFavorite`, `clearCache`. (`deleteFavorite` is NOT in the protocol — same situation as `deleteQueryHistory`.)
  - `ObservableRepositoryProtocol` — `setAppState`, `setOnObservablesUpdate`, `loadObservers(for:)`, `saveDittoObservable`, `removeDittoObservable`, `clearCache`.
  - `CollectionsRepositoryProtocol` — `setAppState`, `setOnCollectionsUpdate`, `hydrateCollections`, `refreshCollections`, `stopObserver`. (`createIndex` is NOT in the protocol — only used by `AddIndexView` which calls `CollectionsRepository.shared` directly. Move to protocol when needed.)

  All protocol methods are async even when the underlying actor method is sync (e.g. `clearCache()` is sync on the actor but `func clearCache() async` in the protocol). This works because actor methods automatically satisfy `async` requirements — actors look async from outside.

  `setOnXxxUpdate` callbacks use `@escaping @MainActor (...) -> Void` to match the existing actor signatures. The `SystemRepository` sync-status callback also keeps its `@escaping @Sendable () -> Void` completion handler.

- **9 conformance extensions** — each existing actor file (`DittoManager.swift`, `QueryService.swift`, and the 7 `Repositories/*.swift`) gains a one-liner `extension Actor: ActorProtocol {}` at the bottom under a `// MARK: - Protocol Conformance` header. Empty-body conformance — Swift's automatic protocol satisfaction matches every requirement against the existing methods.

#### ViewModel refactor

- **`SwiftUI/EdgeStudio/Views/MainStudioView.swift`** — `MainStudioView.ViewModel` (still `@Observable @MainActor`) now stores 8 protocol existentials behind `@ObservationIgnored private let` (the observation graph would otherwise track them and trigger meaningless invalidations on any actor mutation). Stored deps: `dittoManager`, `queryService`, `subscriptionsRepository`, `systemRepository`, `historyRepository`, `favoritesRepository`, `observableRepository`, `collectionsRepository`. The init signature gained 8 parameters with `.shared` defaults so every existing call site (View struct's `viewModel: ViewModel = .init(selectedApp)`) compiles unchanged. ~20 internal `.shared` callsites in `performLoad`, `closeSelectedApp`, `performCleanupOperations`, `toggleSync`, `deleteObservable`, `deleteSubscription`, `executeQuery`, `formSaveSubscription`, `formSaveObserver`, `importSubscriptionsFromQR`, `registerStoreObserver`, `executeDeleteAttachment`, `addQueryToHistory`, `refreshCollectionCounts` were rewired to the stored properties.
  - **`performCleanupOperations`** captures all repository protocols into local `let` bindings before the `withTaskGroup`, then the child tasks reference the locals. Without this capture the child tasks would have to capture `self` (the @MainActor VM) which races with the in-progress cleanup.
  - **`formSaveSubscription` and `formSaveObserver`** explicitly capture the relevant repository in the trailing `Task { [subscriptionsRepository] in ... }` / `Task { [observableRepository] in ... }` because the closure runs detached.
  - **NOT moved through protocols** (deliberately out of scope for 10a):
    - `AttachmentService.shared` (3 callsites in `executeAddAttachment` + 2 in `fetchAttachmentForViewing`) — not on the Phase 10 protocol list.
    - `QueryMetricsRepository.shared` (1 callsite in `refreshLastQueryMetrics`) — not on the list either.
    - `presentNewSubscriptionEditor` / `presentNewObserverEditor` (View struct methods, not VM) — staged for 10c per the Phase 9 handoff note.

- **`SwiftUI/EdgeStudio/Views/ContentView.swift`** — `ContentView.ViewModel` now stores 8 protocol existentials behind `@ObservationIgnored private let` and the init takes them with `.shared` defaults. `loadApps`, `showQRCode`, `importFromQRCode`, `showMainStudio`, `deleteApp` rewired to use the stored deps. **Note**: `ContentView` (the View struct) extensions still call `DittoManager.shared.dittoSelectedApp` / `dittoSelectedAppConfig` directly at lines 107, 108, 116, 117, 320, 321, 367 inside the macOS quickstart flow. Those are out of the VM and therefore out of Phase 10a scope; if 10c moves quickstart orchestration onto the VM (the plan flags `performDownload` as a 10c target), those lines come along.

- **`viewModel.isLoading` is preserved** at line 286 of `MainStudioView.swift` (the Phase 9 detail-area `if viewModel.isLoading { ProgressView } else { ... }` wrap) and lines 707/708 of the VM (set true at `performLoad` start, reset via `defer`).

#### Test added

- **`SwiftUI/EdgeStudioUnitTests/ViewModels/MainStudioViewModelTests.swift`** (new) — Swift Testing suite, `.serialized`, `@MainActor`, two tests:
  1. `ViewModel constructs with mock repositories` — asserts `selectedApp === config`, all collections empty, `isLoading == false`, `executeModes == ["Local", "HTTP"]` (when both http* fields are populated).
  2. `addQueryToHistory routes through the injected HistoryRepository` — sets `viewModel.selectedQuery`, calls `await viewModel.addQueryToHistory(appState:)`, asserts the mock's `savedQueries` array has exactly one entry with the expected query string. This is the actual proof-of-life — it exercises the wiring not just construction.

  Mocks: 8 actors (`MockDittoManager`, `MockQueryService`, `MockSubscriptionsRepository`, `MockSystemRepository`, `MockHistoryRepository`, `MockFavoritesRepository`, `MockObservableRepository`, `MockCollectionsRepository`), all `private` to the file, all conforming to the corresponding protocol with empty/inert implementations except `MockHistoryRepository` which records `savedQueries`. A `@MainActor private struct MockSet` bundles them so the test's ARRANGE block stays compact.

  SwiftFormat applied `swiftTestingTestCaseNames` so the @Test functions use backtick-name syntax (`func \`ViewModel constructs with mock repositories\`()` etc.) instead of camelCase + description string. SwiftLint `sorted_imports` required `@testable import Ditto_Edge_Studio` to come first (before `import DittoSwift`).

### Verification (Phase 10a)

- ✅ macOS build SUCCEEDED (`xcodebuild ... platform=macOS,arch=arm64 build`)
- ✅ iPadOS build SUCCEEDED (`xcodebuild ... iPad Pro 13-inch (M5)`)
- ✅ Tests via `xcrun xcresulttool get test-results summary`: **397 passed / 1 skipped / 0 failed = +2 from baseline** (was 395 / 1 / 0)
- ✅ Xcode app build SUCCEEDED via `mcp__xcode__BuildProject` (after the SPM checkouts were re-resolved post DerivedData clears)
- ✅ SwiftFormat clean on the 13 changed files (1/13 was reformatted in flight; cached after)
- ✅ SwiftLint on the 13 changed files: 0 violations (1 `sorted_imports` violation was fixed in flight)
- ✅ Manual test gate signed off by Aaron

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:

- **Phase 10b — Split `MainStudioView.ViewModel` (~5h)**: extract four sub-ViewModels:
  - `SyncStatusViewModel` — sync toggle, peer status (`syncStatusItems`, `mergeStatusItems`), `connectionsByTransport`, local peer info (4 properties), `isSyncEnabled`, `toggleSync`. Owns the `SystemRepository` callbacks (`setOnSyncStatusUpdate`, `setOnConnectionsUpdate`, `registerConnectionsPresenceObserver`).
  - `QueryViewModel` — `selectedQuery`, `executeModes`, `selectedExecuteMode`, `jsonResults`, `isQueryExecuting`, `executeQuery`, `addQueryToHistory`, `lastQueryMetricsRecord`, `refreshLastQueryMetrics`, `selectedJsonForInspector`, `showJsonInInspector`, `showJsonInObserveInspector`, `selectedQueryInspectorMenuItem`, `queryInspectorMenuItems`, `buildQueryInspectorItems`. Owns `QueryService` + `HistoryRepository` + `FavoritesRepository`.
  - `AttachmentViewModel` — `attachmentProgress`, the four `attachment*` staging properties, `detectedAttachments`, `attachmentLoadedImages`, `attachmentLoadingIds`, `attachmentErrors`, `stageAddAttachment`, `stageDeleteAttachment`, `parseCollectionName`, `parseDocumentId`, `executeAddAttachment`, `executeDeleteAttachment`, `detectAttachmentsInSelectedJson`, `fetchAttachmentForViewing`. Owns `AttachmentService` (still a singleton — out of Phase 10a's protocol set; consider if 10b should also protocolize it).
  - `SubscriptionObserverViewModel` — `subscriptions`, `observerables`, `selectedObservable`, `selectedEventId`, `eventStore`, `pendingObservedEvents`, `observedEventFlushTask`, `editorSubscription`, `editorObservable`, `eventMode`, `selectedObserveInspectorMenuItem`, `observeInspectorMenuItems`, `enqueueObservedEvent`, `flushPendingObservedEvents`, `cancelObservedEventFlush`, `deleteObservable`, `deleteSubscription`, `formSaveSubscription`, `formSaveObserver`, `importSubscriptionsFromQR`, `registerStoreObserver`, `removeStoreObserver`, `selectedEventObject`, `stageSubscriptionEditor`, `stageObservableEditor`. Owns `SubscriptionsRepository` + `ObservableRepository`.
  - **What stays on the parent `MainStudioView.ViewModel`** (orchestration): `selectedApp`, `selectedSidebarDestination` + UserDefaults wiring, `collections` + `isRefreshingCollections` + `refreshCollectionCounts`, `metricsInspectorMenuItems` + `selectedMetricsInspectorMenuItem` + the four `metricsPrometheus*` form-state properties, `isLoading`, `loadTask`, `startLoad`, `performLoad`, `performCleanupOperations`, `closeSelectedApp`, `isolated deinit`. Per the Phase 9 handoff: **`isLoading` lives on the parent VM** because it gates the detail-area ProgressView and orchestrates load across all sub-VMs. The four sub-VMs become `@ObservationIgnored private let` (or `@State`) on the parent so SwiftUI sees `parent.queryVM.selectedQuery` as part of the same observation graph.

  **Manual test**: full smoke test of every feature — query, observer, subscription, attachment, sync. No regressions.

- **Phase 10c — View polish (~2 hours)**: replace `Binding(get:set:)` with `@Bindable` projections (8+ sites), mark all non-private `@State` as `private`, move `MenuItem.image` (which returns `some View`) to a view-layer extension, move `performDownload` and download orchestration from `ContentView` extension into `ContentView.ViewModel`, delete dead `SubscriptionsRepository.cancelAllSubscriptions`.
- **Phase 11** — MEDIUM/LOW polish + CLAUDE.md updates.

## How to start Phase 10b in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-10a-complete.md` then start Phase 10b per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` (architecture refactor is SwiftUI domain) and `axiom-testing` once new sub-VM unit tests are written.
3. Phase 10 sub-phases are **sequentially dependent** — do not skip to 10c. Manual test gate between 10b and 10c is mandatory.

## Open notes / risks for Phase 10b

- **`isLoading` MUST stay on the parent `MainStudioView.ViewModel`.** It gates the detail-area `ProgressView` (line 286 of `MainStudioView.swift`) and is set/reset by `performLoad` which orchestrates across all sub-VMs. Don't move it to any of the four extracted children.
- **The four sub-VMs need to be observable from the View.** Two viable patterns: (a) `@Observable` classes stored as `@ObservationIgnored private let queryVM = QueryViewModel(...)` on the parent — SwiftUI sees `viewModel.queryVM.selectedQuery` as part of the parent's observation graph because the inner `@Observable` propagates; (b) `@State private var queryVM = QueryViewModel(...)` on the View itself, dropping the parent reference. Option (a) keeps the parent-VM-as-orchestrator pattern and is the lower-friction migration for view code that already does `viewModel.x` everywhere — they become `viewModel.queryVM.x`. Option (b) is cleaner architecturally but requires every view that touches a sub-VM property to gain a new `@State` declaration.
- **`performLoad` must initialise the sub-VMs with the same protocol deps the parent received.** The parent's init signature stays the same (8 protocols), but it now passes them down to the four child VM inits. Each child VM init takes the subset of protocols it actually uses, with `.shared` defaults so a unit test can construct them in isolation.
- **`presentNewSubscriptionEditor()` and `presentNewObserverEditor()` are still View struct methods** (Phase 9 handoff). When `SubscriptionObserverViewModel` lands, move them onto that sub-VM so the empty-state CTAs and the FAB go through the same VM-owned path.
- **`registerStoreObserver(_:)` reads `await dittoManager.dittoSelectedApp`** to get the SDK handle for `ditto.store.registerObserver(...)`. When this method moves to `SubscriptionObserverViewModel`, the sub-VM needs `DittoManagerProtocol` injected (read-only access to `dittoSelectedApp` is enough).
- **`refreshCollectionCounts` reads `collections` then writes it back** via `collectionsRepository.refreshCollections()`. The plan keeps `collections` on the parent VM, so this method also stays on the parent. But `selectedQuery` (which `performLoad` sets to `"SELECT * FROM \(collections.first?.name ?? "")"`) lives on `QueryViewModel` — so `performLoad` will need to bridge: `parent.queryVM.selectedQuery = "..."`. That's fine, just be aware the cross-VM write happens during initial load.
- **`closeSelectedApp` and `performCleanupOperations`** clear state across all four domains. They stay on the parent (orchestration), but each domain's clearing logic could be hoisted into a `reset()` method on each sub-VM that the parent calls. The current TaskGroup pattern (caches cleared in parallel, observers stopped in parallel, DittoManager closed in parallel) is the right shape — preserve it.
- **`AttachmentService.shared` is still a direct singleton call** in the VM's attachment methods. Phase 10b's `AttachmentViewModel` could either keep them as direct calls (out of scope) or take a 10th `AttachmentServiceProtocol` and add a tenth `extension AttachmentService: AttachmentServiceProtocol {}`. The plan doesn't require it — but it would make `AttachmentViewModel` unit-testable, which is the Phase 10 spirit. Recommend doing it if the budget allows; otherwise note for 10c.
- **`QueryMetricsRepository.shared.allRecords()`** in `refreshLastQueryMetrics` — same situation as AttachmentService. Single callsite, easy to protocolize, but not on the Phase 10 list. Defer if tight.
- **The Phase 10a tests are positioned at `EdgeStudioUnitTests/ViewModels/MainStudioViewModelTests.swift`.** Phase 10b should add `EdgeStudioUnitTests/ViewModels/{SyncStatusViewModelTests,QueryViewModelTests,AttachmentViewModelTests,SubscriptionObserverViewModelTests}.swift` — one per sub-VM, each constructing its sub-VM with the relevant subset of mocks. The mocks themselves can be lifted out of `MainStudioViewModelTests.swift` into a shared `EdgeStudioUnitTests/ViewModels/ViewModelMocks.swift` (or kept inline if the sub-VM tests need different stubbing). The plan calls for "at least 5 new Swift Testing unit tests" total — Phase 10a delivered 2; Phase 10b should add at least 3 more (one per sub-VM excluding whichever already has coverage from 10a).
- **SwiftLint enforces `sorted_imports`.** Test files with both `@testable import` and regular imports need the `@testable` first if it sorts alphabetically before the others (Ditto_Edge_Studio < DittoSwift, so it goes first).
- **SwiftFormat will rewrite Swift Testing test names.** Don't fight `swiftTestingTestCaseNames` — accept the backtick-name pattern and write the @Test description as the function name directly.
- **Don't run CLI `xcodebuild` while the user has Xcode building.** Use `mcp__xcode__BuildProject` via the Xcode MCP tool when Xcode is open. The `build.db is locked` error will surface as confusing "Missing package product" errors in Xcode after the next DerivedData clear — don't be misled, the code is fine.
- **Worktree branch reuse can leak stale state** — both Phase 9 agents had to `git reset --hard release-1.0b5` because their assigned worktree branches were pointing at older commits. New agents starting from a worktree should always confirm `git rev-parse HEAD` matches the expected base before starting, and reset if it doesn't.
