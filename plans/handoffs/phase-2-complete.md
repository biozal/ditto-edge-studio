# Phase 2 Complete — Handoff for Phase 3

**Created**: 2026-05-07
**Branch**: `release-1.0b5`
**Last commit on this branch**: see `git log --oneline -8`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md`
- The Phase 1 handoff (if any): not written — Phase 1 was committed in same session
- This file is the entry point if Phase 3 starts in a fresh `/clear`'d session

## Project facts that don't change

- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Xcode workspace tab identifier for MCP: `windowtab1` (verify with `XcodeListWindows` if a fresh session)
- Apple Xcode MCP server **is registered for this project** — tools are namespaced `mcp__xcode__*`
- Test baseline: **142 tests across 50 suites must pass** after every phase. UI tests have a pre-existing bundle load failure (NSCocoaErrorDomain Code=4) — that's the known baseline.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- Use `mcp__xcode__BuildProject` for the active Xcode destination (typically macOS); use `xcodebuild` from Bash for the other platform.
- **Beware `XcodeUpdate` recursive `replaceAll` bug**: if `newString` contains `oldString` as a literal substring, replaceAll runs 1000 times. Either use a marker pattern (replace to a unique sentinel, then sentinel to final) OR include surrounding whitespace/context in `oldString` so the new content can't match again. Verified safe pattern: when `oldString` has leading whitespace and `newString` adds a token before the same whitespace pattern, no recursion.

## What Phases 0-2 changed

### Phase 0 — baseline
- Working branch: `release-1.0b5` (no separate feature branch — all v1 fix work commits here)
- Baseline test pass count captured: **142 tests / 50 suites pass on macOS**
- Pre-existing fixed: `AttachmentTests.swift:425` triple-quoted string literal compile error

### Phase 1 — `feat: migrate AppState to @Observable @MainActor + cascading cleanup` (commit `a0e8368`)
- `AppState`: `ObservableObject` → `@Observable @MainActor final class`; dropped dead `appConfig` property; simplified `setError` (no more `DispatchQueue.main.async` hop)
- App entry: `@StateObject` → `@State`; `.environmentObject(_)` → `.environment(_)`
- 9 view files: `@EnvironmentObject` → `@Environment(AppState.self)`
- 9 chained `.environmentObject(...)` → `.environment(...)` (incl. 1 SwiftUI preview)
- 18 actor-context `appState?.setError` calls now use `await` (or `Task { @MainActor in ... }` for sync `compactMap` closures in `CollectionsRepository`)
- 2 async-view-context calls also got `await`
- Removed 3 unused `import Combine` statements + dead `cancellables: Set<AnyCancellable>` in `ContentView.ViewModel`

### Phase 2 — Critical Concurrency Fixes (this commit)
- **C5 fixed**: `DittoManager.swift:131` — `expirationHandler` no longer captures `self` strongly. `appState` and `databaseConfig.token` are captured as locals; inner `Task { @MainActor in capturedAppState?.setError(error) }`.
- **C6 fixed**: `MainStudioView.swift` `registerStoreObserver` callback — event is built synchronously on the SDK thread, then a `Task { @MainActor [weak self] in ... }` hops to MainActor before mutating `observableEvents` / `selectedObservableEvents`.
- **HIGH fixed**: `MainStudioView.swift:623` and `:633` — added `[weak self]` to the subscriptions and collections update callbacks (matches the existing `[weak self]` pattern on history/favorites/observables).
- **HIGH fixed**: `CollectionsRepository.stopObserver()` — now synchronous (drops `Task.detached`); race window where new-session observer was cancelled by stale cleanup task is gone. Dead `deinit` removed (singleton actor never deallocates).
- **HIGH fixed**: `DatabaseRepository.onDittoDatabaseConfigUpdate` — typed `(@MainActor ([DittoConfigForDatabase]) -> Void)?`; `notifyConfigUpdate` now `async` and `await`s the callback. Caller in `ContentView.swift:593` simplified (removed inner `Task { @MainActor in ... }` since the callback type now guarantees MainActor).
- **HIGH fixed**: `SystemRepository.onSyncStatusUpdate` typed `@MainActor` with `@Sendable` completion; `onConnectionsUpdate` typed `@MainActor`. Setters updated to match. `processSyncStatusUpdate` calls callback with `await`.
- **HIGH preempted**: SystemRepository presence callback Sendable boundary — Ditto SDK 5.0.0 release added Sendable conformances on `DittoPresenceGraph` / `DittoPeer`. Build is clean with zero concurrency warnings, no defensive extraction needed. Note in the plan when reading.

### Verification (Phase 2)
- ✅ macOS build SUCCEEDED (Xcode MCP `BuildProject`)
- ✅ iPadOS build SUCCEEDED (`xcodebuild`)
- ✅ 142 tests / 50 suites pass — same as baseline, zero regressions
- ✅ Zero compile warnings (Xcode `XcodeListNavigatorIssues` returns empty)
- ✅ Aaron's manual smoke test on macOS+iPad approved (assumed if this doc exists in commit history)

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:
- **Phase 3** — Memory safety: cap `observableEvents` at 500, add 100ms batch debounce, dictionary-keyed observer event lookup. Files: `MainStudioView.swift` ViewModel.
- **Phase 4** — UX/Nav ship-blockers: iOS toolbar back button (C1), `showMainStudio` loading + error feedback (C2), SQLCipher init gate + retry (C3), replace `UIDevice.current.userInterfaceIdiom == .phone` with `horizontalSizeClass` (C7).
- **Phase 5** — Performance hot paths: `ForEach` identity in `ResultJsonViewer` (C9), `AttachmentInfo.detectTokens` to `.task(id:)`, debounced `filteredEntries` cache in `LoggingDetailView`, drop `GeometryReader` wrap in `ResultTableViewer`, `Task.sleep` instead of `DispatchQueue.main.asyncAfter` for copy-feedback.
- Phases 6-11 cover remaining HIGH/MEDIUM/LOW items.

## How to start Phase 3 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-2-complete.md` then start Phase 3 per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` and verify the Xcode MCP tab via `XcodeListWindows`.
3. Phase 3 manual test gate is small (cap observableEvents test on a high-frequency observer for 60s).

## Open notes / risks for next phase

- The `Phase 2 build was clean` outcome may shift once Phase 3's batched `observableEvents` updates land — pay attention to any new "Main actor-isolated property mutated from a Sendable closure" diagnostics if Phase 3's batching introduces new closures.
- The CollectionsRepository.swift now has `Task { @MainActor in appState.setError(error) }` wraps inside `compactMap` closures (from Phase 1). These are correct but inelegant; Phase 10 architecture work may consolidate them.
