# Phase 4 Complete — Handoff for Phase 5

**Created**: 2026-05-08
**Branch**: `release-1.0b5`
**Last Phase 4 commit**: `6ce098e fix: ship-blocker UX/nav gaps (iOS back, hydration feedback, SQLCipher retry)`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md`
- Previous handoff: `plans/handoffs/phase-3-complete.md`
- This file is the entry point if Phase 5 starts in a fresh `/clear`'d session

## Project facts that don't change

- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Xcode workspace tab identifier for MCP: `windowtab1` (verify with `XcodeListWindows` if a fresh session)
- Apple Xcode MCP server **is registered for this project** — tools are namespaced `mcp__xcode__*`
- Xcode MCP project tree paths use `Edge Debug Helper/EdgeStudio/...` but **on-disk paths are `SwiftUI/EdgeStudio/...`** — `swiftlint` / `swiftformat` need the on-disk form, but `XcodeRead` / `XcodeUpdate` need the MCP form
- Test baseline is **396 tests** (254 unit + 142 integration) on macOS — Phase 4 added zero tests (UX changes; no new logic units to cover beyond manual verification per the plan). **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*` then `xcodebuild -resolvePackageDependencies` to fully resolve before testing) — incremental test runs intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- Use `mcp__xcode__BuildProject` for the active Xcode destination (typically macOS); use `xcodebuild` from Bash for the other platform.
- **Beware `XcodeUpdate` recursive `replaceAll` bug**: if `newString` contains `oldString` as a literal substring, replaceAll runs 1000 times. Either use a marker pattern OR include surrounding whitespace/context in `oldString` so the new content can't match again.

## What Phase 4 changed

### `fix: ship-blocker UX/nav gaps (iOS back, hydration feedback, SQLCipher retry)`

- **EDIT** `EdgeStudio/Views/MainStudioView.swift`:
  - **C7**: Line 74 — `UIDevice.current.userInterfaceIdiom == .phone` → `horizontalSizeClass == .compact`. The `horizontalSizeClass` was already wired (line 42). `grep -r "UIDevice.current.userInterfaceIdiom" EdgeStudio/` now returns zero hits.
  - **C1**: Added a sibling `#else .toolbar { ... } #endif` branch to the existing `#if os(macOS) .toolbar { ... } #endif` (around the original line 288). The iOS branch contains:
    - Conditional `if horizontalSizeClass == .compact { sidebarToggleButton() }` — only iPhone + iPad Slide Over get the explicit sidebar toggle; iPad regular keeps the system column toggle from `NavigationSplitView`. SwiftUI 6.2's `ToolbarContentBuilder` supports conditional `ToolbarContent`, so this compiles cleanly.
    - `syncToolbarButton()` (existing helper, `.primaryAction`, trailing on iOS)
    - `closeToolbarButton()` (existing helper) — this is what acts as "back to databases" since `closeButtonContent` already calls `viewModel.closeSelectedApp()` then flips `isMainStudioViewPresented = false`.
- **EDIT** `EdgeStudio/Views/ContentView.swift`:
  - **C2**: Added `var openingDatabaseId: String?` to `ContentView.ViewModel`. `showMainStudio(_:appState:)` now:
    - Returns early if `openingDatabaseId != nil` (double-tap guard)
    - Sets `openingDatabaseId = dittoApp._id` at start, clears in `defer`
    - On `didSetupDitto == false` (the previous silent abort): clears `selectedDittoConfigForDatabase` and calls `appState.setError(AppError.error(message: "Failed to initialize database '\(dittoApp.name)'…"))`
  - The iPad `compactPickerContent` card grid wraps each `DatabaseCard` with: an overlay spinner when its `_id == viewModel.openingDatabaseId`, dimming for sibling cards, and `.allowsHitTesting(viewModel.openingDatabaseId == nil)` to lock the grid during open.
  - **C3**: Added `var sqlCipherInitError: Error?` to `ContentView.ViewModel`. `loadApps(appState:)` now begins with `try await SQLCipherService.shared.initialize()` (idempotent — actor's `_isInitialized` short-circuit means it doesn't fight `AppState`'s eager warm-up Task). On throw, sets `sqlCipherInitError` and `return`s before touching repositories. The iOS picker renders `sqlCipherInitErrorView(_:)` (new `@ViewBuilder` helper at the bottom of the iOS `extension ContentView`) when `sqlCipherInitError != nil` — distinct from the empty-state branch — with an "arrow.clockwise" Retry button that re-runs `loadApps`.
- **EDIT** `EdgeStudio/Views/Database/DatabaseListPanel.swift`: macOS list got the same per-row spinner overlay + dimming + hit-test lockout, plus a `private @ViewBuilder func sqlCipherInitErrorView(_:)` rendering the same Retry state styled for the macOS panel.
- **EDIT** `EdgeStudio/AppState.swift`: The eager warm-up `Task` in `init()` no longer calls `self.setError(error)` on failure — it only logs. Reasoning: `loadApps` is now the canonical surfacing path with the Retry affordance; surfacing here too would produce duplicate alerts.

### Verification (Phase 4)
- ✅ macOS build SUCCEEDED (Xcode MCP `BuildProject`)
- ✅ iPadOS build SUCCEEDED (`xcodebuild` for iPad Pro 13-inch (M5))
- ✅ Zero compile warnings (`XcodeListNavigatorIssues` returns empty)
- ✅ 254 unit + 142 integration tests pass on clean DerivedData (matches baseline; no new tests added)
- ✅ SwiftFormat clean on changed files; SwiftLint clean (zero output) on changed files
- ✅ `grep -r "UIDevice.current.userInterfaceIdiom" EdgeStudio/` returns zero hits
- ✅ Aaron's manual smoke test on iPhone/iPad/macOS approved

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:
- **Phase 5** — Performance hot paths: `ForEach` identity in `ResultJsonViewer` (C9), `AttachmentInfo.detectTokens` from inline → `.task(id:)`, debounced `filteredEntries` cache in `LoggingDetailView`, drop `GeometryReader` wrap in `ResultTableViewer`, `Task.sleep` instead of `DispatchQueue.main.asyncAfter` for copy-feedback.
- **Phase 6** — HIGH concurrency cleanups (untracked Tasks in `MainStudioView.ViewModel.init`, parallelize loads, `DittoLogCaptureService` cancel checks, replace static+NSLock cache with instance state).
- Phases 7-11 cover remaining HIGH/MEDIUM/LOW items.

## How to start Phase 5 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-4-complete.md` then start Phase 5 per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` and verify the Xcode MCP tab via `XcodeListWindows`.
3. Phase 5 is single-agent work — all changes are localized perf fixes with similar patterns. Manual test gate involves running a 200+ document query, scrolling Table mode, and typing into the Logging tab search field with active sync.

## Open notes / risks for next phase

- The Phase 4 retry state in `ContentView.sqlCipherInitErrorView` calls `viewModel.loadApps(appState: appState)` — this is fine because `appState` is the `@Environment` value. Same for the macOS `DatabaseListPanel` (which already has `appState` as a let property). No special wiring needed in Phase 5.
- The `closeToolbarButton()` and `syncToolbarButton()` helpers are shared across macOS and iOS. If Phase 5 or later adds macOS-specific behavior to `closeButtonContent`, remember the iOS toolbar in `MainStudioView.swift` will share that change.
- The double-tap guard in `showMainStudio` (`guard openingDatabaseId == nil else { return }`) silently no-ops the second tap. If Phase 9 (UX cleanups) decides this should give explicit feedback ("Already opening…"), one place to change.
- `pendingObservedEvents` from Phase 3 is still intentionally a private buffer. Phase 5's hot-path work doesn't touch it.
- Phase 5 will edit `LoggingDetailView.swift:503` (`filteredEntries` debounce). Heads-up: `LoggingDetailView` was migrated to `@Environment(AppState.self)` in Phase 1 — it's already on the modern pattern. The debounce will involve adding a private `@State var cachedFilteredEntries` plus a private debounce-Task helper.
- Phase 5's `ForEach(items.indices, id: \.self)` swap uses `Array(items.enumerated())` per the plan, but if the underlying `items` already conforms to `Identifiable` (e.g., a doc with `_id`), prefer the simpler `ForEach(items, id: \.id)` — check at call sites before applying the canned fix.
