# Phase 3 Complete — Handoff for Phase 4

**Created**: 2026-05-08
**Branch**: `release-1.0b5`
**Last commit on this branch**: see `git log --oneline -10`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md`
- Previous handoff: `plans/handoffs/phase-2-complete.md`
- This file is the entry point if Phase 4 starts in a fresh `/clear`'d session

## Project facts that don't change

- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Xcode workspace tab identifier for MCP: `windowtab1` (verify with `XcodeListWindows` if a fresh session)
- Apple Xcode MCP server **is registered for this project** — tools are namespaced `mcp__xcode__*`
- Test baseline is now **396 tests** (254 unit + 142 integration) on macOS — Phase 3 added 9 new tests in `ObservableEventStoreTests`. **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*`) — incremental builds intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle. Clean once and tests pass.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- Use `mcp__xcode__BuildProject` for the active Xcode destination (typically macOS); use `xcodebuild` from Bash for the other platform.
- **Beware `XcodeUpdate` recursive `replaceAll` bug**: if `newString` contains `oldString` as a literal substring, replaceAll runs 1000 times. Either use a marker pattern OR include surrounding whitespace/context in `oldString` so the new content can't match again.

## What Phase 3 changed

### `perf: cap observableEvents at 500 + dictionary-backed observer event lookup`

- **NEW** `EdgeStudio/Models/ObservableEventStore.swift` — bounded FIFO event store. `static let capacity = 500`. Maintains `events: [DittoObserveEvent]` (ordered) and `eventsById: [String: DittoObserveEvent]` (O(1) lookup index). Public API: `append(_:)`, `append(contentsOf:)`, `remove(observerId:)`, `removeAll()`, `event(id:)`, `count`, `isEmpty`. Pure value type — no actor isolation, mutations are ViewModel-driven on MainActor.
- **EDIT** `EdgeStudio/Views/MainStudioView.swift`:
  - Removed `observableEvents: [DittoObserveEvent]` and `selectedObservableEvents: [DittoObserveEvent]` from the ViewModel; replaced with `eventStore: ObservableEventStore` (the dead `selectedObservableEvents` had zero readers).
  - Added private batching: `pendingObservedEvents: [DittoObserveEvent]`, `observedEventFlushTask: Task<Void, Never>?`, `static let observedEventFlushInterval: Duration = .milliseconds(100)`.
  - `selectedEventObject` now resolves O(1) via `eventStore.event(id: selectedId)`.
  - SDK callback in `registerStoreObserver`: `Task { @MainActor [weak self] in self?.enqueueObservedEvent(capturedEvent) }`. The enqueue path appends to `pendingObservedEvents` and schedules a 100ms flush iff one isn't already pending.
  - `flushPendingObservedEvents` moves the batch into `eventStore` in one assignment (one SwiftUI invalidation per 100ms window instead of per event).
  - Added `cancelObservedEventFlush()` helper used in cleanup paths.
  - Cleanup paths updated: `closeSelectedApp` cancels flush task + `eventStore.removeAll()`; `deleteObservable` calls `eventStore.remove(observerId: observable.id)` and removes pending events for that observer; `removeStoreObserver` cancels flush + `eventStore.removeAll()` (preserves prior wipe-all behavior — flagged as a possible bug-or-feature for post-v1).
  - **Deleted** `loadObservedEvents()` — was populating dead `selectedObservableEvents`.
- **EDIT** `EdgeStudio/Views/StudioView/Details/DetailViews.swift` — 5 call sites: `viewModel.observableEvents.X` → `viewModel.eventStore.X`.
- **EDIT** `EdgeStudio/Views/StudioView/SidebarViews.swift` — removed 3 dead `await viewModel.loadObservedEvents()` calls.
- **NEW** `EdgeStudioUnitTests/Models/ObservableEventStoreTests.swift` — 9 Swift Testing tests covering: append below capacity, FIFO eviction at 500, bulk append + single-pass eviction, missing-id lookup, lookup/array consistency, scoped per-observer remove, no-op for unknown observer, removeAll, capacity-constant boundary.

### `fix: PaginationControls picker tag/selection mismatch warning`

- **EDIT** `EdgeStudio/Components/PaginationControls.swift` — Picker's `ForEach` now iterates `displayedPageSizes` instead of `pageSizes`. `displayedPageSizes` returns `pageSizes` unchanged when it contains the current `pageSize`, otherwise returns `pageSizes + [pageSize]` sorted. This eliminates the runtime warning `Picker: the selection "25" is invalid and does not have an associated tag` that fired during the one-render gap between a result-set shrinking and the parent's `.onChange` clamp. Self-healing: as soon as the parent clamps `pageSize`, the transient extra entry vanishes.

### Verification (Phase 3)
- ✅ macOS build SUCCEEDED (Xcode MCP `BuildProject`)
- ✅ iPadOS build SUCCEEDED (`xcodebuild` for iPad Pro 13-inch (M5))
- ✅ Zero compile warnings (`XcodeListNavigatorIssues` returns empty)
- ✅ 254 unit + 142 integration tests pass on clean DerivedData; 9 new tests included in 254 count
- ✅ SwiftFormat clean on changed files; SwiftLint warnings only match the existing baseline convention (`ModelTests.swift` pattern)
- ✅ Aaron's manual smoke test on macOS+iPad approved

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:
- **Phase 4** — UX/Nav ship-blockers: iOS toolbar back button (C1), `showMainStudio` loading + error feedback (C2), SQLCipher init gate + retry (C3), replace `UIDevice.current.userInterfaceIdiom == .phone` with `horizontalSizeClass` (C7).
- **Phase 5** — Performance hot paths: `ForEach` identity in `ResultJsonViewer` (C9), `AttachmentInfo.detectTokens` to `.task(id:)`, debounced `filteredEntries` cache in `LoggingDetailView`, drop `GeometryReader` wrap in `ResultTableViewer`, `Task.sleep` instead of `DispatchQueue.main.asyncAfter` for copy-feedback.
- Phases 6-11 cover remaining HIGH/MEDIUM/LOW items.

## How to start Phase 4 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-3-complete.md` then start Phase 4 per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` and verify the Xcode MCP tab via `XcodeListWindows`.
3. Phase 4 is iOS-heavy — manual test gate involves iPhone simulator (back button, hydration error states) and iPad Slide Over (sidebar dismiss).

## Open notes / risks for next phase

- The `removeStoreObserver` cleanup path **preserves the pre-existing wipe-all behavior** (clears events from ALL observers when stopping one). This may be intentional UX or a bug. Phase 4 doesn't touch this code, but if Aaron decides it should be per-observer, the change is one line: replace `eventStore.removeAll()` with `eventStore.remove(observerId: observable.id)` (the API already supports it and is unit-tested).
- `pendingObservedEvents` is intentionally kept as a private buffer (not `@Observable`-tracked) — it's an implementation detail of the batching layer. SwiftUI re-renders only when `eventStore` is mutated by `flushPendingObservedEvents`.
- Phase 4 will add iOS-only toolbar items and `horizontalSizeClass` reads. Watch for the existing `UIDevice.current.userInterfaceIdiom == .phone` site at `MainStudioView.swift:74` — that's the C7 swap target. There's also a related `compact` check pattern already in use elsewhere that should be the model.
- The `PaginationControls.displayedPageSizes` self-heal also benefits Phase 5's pagination work — no additional onChange clamping needed at call sites for new pickers.
