# Phase 6 Complete — Handoff for Phase 7

**Created**: 2026-05-08
**Branch**: `release-1.0b5`
**Last Phase 6 commit**: `14b2936 refactor: structured concurrency for MainStudioView load + cleanup`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md`
- Previous handoff: `plans/handoffs/phase-5-complete.md`
- This file is the entry point if Phase 7 starts in a fresh `/clear`'d session

## Project facts that don't change
- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Xcode workspace tab identifier for MCP: `windowtab1` (verify with `XcodeListWindows` if a fresh session)
- Apple Xcode MCP server **is registered for this project** — tools are namespaced `mcp__xcode__*`
- Xcode MCP project tree paths use `Edge Debug Helper/EdgeStudio/...` but **on-disk paths are `SwiftUI/EdgeStudio/...`** — `swiftlint` / `swiftformat` need the on-disk form, but `XcodeRead` / `XcodeUpdate` need the MCP form
- Test baseline is **396 tests** (254 unit + 142 integration) on macOS — Phase 6 added zero new tests (concurrency refactor; manual fast-close test gate per plan). Result bundle from Phase 6: 395 passed, 1 skipped, 0 failed = baseline. **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*` then `xcodebuild -resolvePackageDependencies`) when test runs intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- Use `mcp__xcode__BuildProject` for the active Xcode destination (typically macOS); use `xcodebuild` from Bash for the other platform. **Don't run both simultaneously** — they share `Edge_Debug_Helper-*` DerivedData and the BuildProject side will fail with `database is locked`. Wait for one to finish before starting the other.
- **Beware `XcodeUpdate` recursive `replaceAll` bug**: if `newString` contains `oldString` as a literal substring, replaceAll runs 1000 times. Either use a marker pattern OR include surrounding whitespace/context in `oldString`.

## What Phase 6 changed

### `refactor: structured concurrency for MainStudioView load + cleanup`

#### `EdgeStudio/Views/MainStudioView.swift`
- **HIGH-Concurrency — extract init Tasks → tracked `loadTask`**:
  - New `private var loadTask: Task<Void, Never>?` next to the existing `observedEventFlushTask`.
  - `init` no longer spawns the 4 untracked Tasks (lines were 602/618/627/635 in pre-Phase-6). It now does pure synchronous setup and ends right after `selectedMetricsInspectorMenuItem = metricsDocsItem`.
  - New `func startLoad()` — idempotent, sync method called from the view's `.task` modifier. Cancels any prior task and stores a fresh `Task { [weak self] in await self?.performLoad() }`.
  - New `private func performLoad() async` — does all the work the 4 init Tasks used to do, in this order:
    1. Sequential `await` to register all 7 repository update callbacks (SystemRepository sync-status / connections, ObservableRepository, Subscriptions/Collections/History/Favorites). All callbacks use `[weak self]`. The pre-Phase-6 inner `Task { @MainActor in self?.... }` blocks were preserved (Phase 2 already shipped `[weak self]` on inner closures, so no further capture changes needed).
    2. `async let` parallelizes 5 independent loads (`SubscriptionsRepository.loadSubscriptions`, `CollectionsRepository.hydrateCollections`, `HistoryRepository.loadHistory`, `FavoritesRepository.loadFavorites`, `ObservableRepository.loadObservers`). Each is wrapped in an immediately-invoked `() async -> [...]` closure that does its own `do/catch` so one failure doesn't starve the others (matches the pre-existing per-domain `do/catch` semantics — failures are logged via `Log.error`, results default to `[]`).
    3. `let (subs, cols, hist, favs, obsv) = await (loadedSubscriptions, ...)` then assign to the @MainActor properties on the ViewModel.
    4. `selectedQuery` derivation runs after all loads (uses `collections.first?.name` or `subscriptions.first?.query`).
    5. `try await SystemRepository.shared.registerConnectionsPresenceObserver()` (preserved). Same Log.error fallback.
    6. Local peer info `__small_peer_info` query (preserved).
    7. Three `guard !Task.isCancelled else { return }` checks at natural breakpoints (after callback registration, after the `async let` joinpoint, before the local peer info fetch). The closures inside `async let` themselves don't need explicit cancel checks — the structured-concurrency child tasks are cancelled by the parent's cancellation, and each repository's own load API surfaces via thrown errors that are caught and logged.
  - New `isolated deinit` (Swift 6.2 SE-0371) — cancels `loadTask` and emits `Log.debug("MainStudioView.ViewModel deinit")`. **Without `isolated`, the deinit can't read the actor-isolated `loadTask` property.** A regular `deinit` produces `Main actor-isolated property 'loadTask' can not be referenced from a nonisolated context`.
  - `closeSelectedApp` now starts with `loadTask?.cancel(); loadTask = nil` BEFORE invalidating the system session — ensures the cleanup pass doesn't race in-flight callback registrations.
  - View body's existing `.task { sidebar/inspector setup }` now also calls `viewModel.startLoad()` at the end. Single `.task` modifier, two responsibilities — UserDefaults sync (synchronous, fast) and load kickoff (fire-and-forget, the heavy work runs in the stored `loadTask`).

#### `EdgeStudio/Data/DittoLogCaptureService.swift`
- **MEDIUM-Concurrency — flush tasks bail on cancel**:
  - Three flush sites (live entries `:73`, transport conditions `:239`, connection requests `:286`) all have the same pattern: `Task { @MainActor [weak self] in try? await Task.sleep(for: .milliseconds(250)); self?.flush... }`. Added `guard !Task.isCancelled else { return }` after the sleep in all three. The `try?` already swallows `CancellationError`, so the explicit guard is what actually skips the flush call.

#### `EdgeStudio/Data/DittoManager.swift`
- **MEDIUM-Architecture — drop NSLock, instance state on actor**:
  - Removed `private static var cachedUntrustedSession: URLSession?` and `private static let untrustedSessionLock = NSLock()` from the URL Session extension.
  - Added `private var cachedUntrustedSession: URLSession?` to the main actor declaration (next to `activePersistenceDirectory`).
  - `getCachedUntrustedSession()` no longer locks/unlocks. Function signature unchanged. Callers (`AttachmentService.swift:254,297,338` and `QueryService.swift:131`) already use `await dittoManager.getCachedUntrustedSession()` so no callsite changes were needed — actor isolation now serializes access.

### Verification (Phase 6)
- ✅ macOS build SUCCEEDED (Xcode MCP `BuildProject`, ~6.4s)
- ✅ iPadOS build SUCCEEDED (`xcodebuild` for iPad Pro 13-inch (M5))
- ✅ Zero compile warnings (`XcodeListNavigatorIssues` empty at warning severity)
- ✅ 395 passed, 1 skipped, 0 failed on macOS test suite (matches baseline; no new tests added)
- ✅ SwiftFormat clean on changed files (0/3 files would have been formatted)
- ✅ SwiftLint clean on changed files (zero output)
- ✅ Manual fast-close test gate is on Aaron's plate

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:
- **Phase 7** — HIGH navigation cleanups: enum-keyed sidebar (replace string switch), `@SceneStorage` for selected database / sidebar tab / sync tab, consolidate 8 `.sheet` modifiers into one `.sheet(item:)`, fix `scenePhase` `onChange` reversed param order + empty bodies.
- Phases 8-11 cover layout / UX / architecture / polish.

## How to start Phase 7 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-6-complete.md` then start Phase 7 per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` (sidebar/sheet patterns + SceneStorage are SwiftUI domain) and verify the Xcode MCP tab via `XcodeListWindows`.
3. Phase 7 uses two parallel agents per the plan:
   - **Agent A** — sidebar destination enum + `@AppStorage` for sidebar/sync tab + scenePhase fix.
   - **Agent B** — `ActiveSheet` enum (single `.sheet(item:)`) + `@SceneStorage("selectedDatabaseId")` for database persistence.
4. Manual test gate: open database → switch sidebar to Observers → kill app → relaunch and confirm the same database AND the Observers tab restore. Also background → foreground a few times to validate scenePhase wiring.

## Open notes / risks for next phase

- **Phase 6's `loadTask` is started from the View's `.task` modifier**, not from `init`. If Phase 10 splits `MainStudioView.ViewModel` into smaller VMs, each split-out VM will need its own `startLoad()` + `loadTask` + `isolated deinit` pattern. Don't fold the load back into `init` — that would re-introduce the untracked-Task problem Phase 6 fixed.
- **`isolated deinit` is Swift 6.2-only**. The project uses Xcode 26.2 / Swift 6.2 (per CLAUDE.md), so this is fine. If anyone tries to backport to Swift 6.0/6.1, the syntax won't compile and they'll need a different cancellation strategy (e.g. ditch the deinit and rely solely on `closeSelectedApp` for cancellation).
- **The `async let` joinpoint in `performLoad`** awaits all 5 loads as a tuple. If Phase 10 changes any of those repository APIs to a different return type (e.g. `Result<[T], Error>` or `AsyncSequence`), the `async let` block must be revisited — currently each closure unwraps the throwing call into an array via local `do/catch`.
- **Fast-close-during-load behavior**: with Phase 6, `closeSelectedApp` cancels `loadTask` first, then invalidates the SystemRepository session, then resets UI state, then runs `performCleanupOperations` (TaskGroup of 3 background-priority cleanups). The cancelled `loadTask` may still be mid-`await` on a repository load when `closeSelectedApp` proceeds; that's fine because the repository load's actor hop will be a no-op once Task.isCancelled is true (or the repository will throw CancellationError, which is caught and logged). If Phase 8/9/10 changes any repository's cancellation behavior, this assumption needs to hold or Phase 6's fast-close gate will regress.
- **DittoManager actor reentrancy**: `getCachedUntrustedSession()` is a synchronous-from-the-actor function (it reads + writes the cached property in one step without `await`). Since it's on the actor, callers already `await` it from outside. There's no reentrancy hazard — the function doesn't suspend. If a future change adds an `await` inside `getCachedUntrustedSession` (e.g. lazy delegate construction needing async setup), revisit: another caller could create a duplicate `URLSession` between the suspension and the assignment.
- **DittoLogCaptureService cancel guards**: the `try? await Task.sleep` already returns silently on cancellation; the explicit `guard !Task.isCancelled` is what prevents the flush. If anyone later replaces the sleep with a different delay primitive that doesn't honor cancellation (e.g. `DispatchQueue.asyncAfter` — don't), the guard becomes a no-op. Keep the sleep using `Task.sleep`.
- **Phase 5's `cachedFilteredEntries` and Phase 6's `loadTask` are independent**. Phase 7 doesn't touch either. If Phase 9 (UX) revisits Logging tab states or Phase 10 (architecture) splits the ViewModel, both can be moved as-is into the new structures — they're already well-scoped.
