# Phase 9 Complete — Handoff for Phase 10

**Created**: 2026-05-08
**Branch**: `release-1.0b5` (not yet pushed at handoff time — push before starting Phase 10 if you want a remote backup)
**Phase 9 commit**: `54a14bb feat: missing loading/empty/error states + dismiss safety nets`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md` (Phase 10 starts at the section titled "Phase 10 — HIGH Architecture Cleanups (post-v1 ship-quality)")
- Previous handoff: `plans/handoffs/phase-8-complete.md`
- This file is the entry point if Phase 10 starts in a fresh `/clear`'d session

## Project facts that don't change
- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Apple Xcode MCP server is registered for this project but **the MCP server disconnected mid-flight during Phase 9**. Both Phase 9 agents stalled on their initial `XcodeListWindows` probe, then the second-attempt agents finished cleanly using only standard `Read` / `Edit` / `Write` / `Bash` tools. **Do not assume Xcode MCP is available** — start with standard tools and only invoke `mcp__xcode__*` if you confirm the server is connected. The project uses File System Synchronized groups, so editing existing Swift files via standard tools is safe and does not require `.pbxproj` mutation. Adding new files would still benefit from Xcode MCP if it's available, but Phase 10 is mostly refactoring existing files.
- Xcode MCP project tree paths use `Edge Debug Helper/EdgeStudio/...` but **on-disk paths are `SwiftUI/EdgeStudio/...`** — `swiftlint` / `swiftformat` need the on-disk form, but `XcodeRead` / `XcodeUpdate` need the MCP form (when MCP is up).
- Test baseline is **396 tests** (254 unit + 142 integration) on macOS — Phase 9 added zero new tests (the plan calls for new tests in Phase 10a/b/c when ViewModels become unit-testable). Result bundle from Phase 9: 395 passed, 1 skipped, 0 failed = baseline. **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*`) when test runs intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- **Don't run macOS and iPadOS builds simultaneously** — they share `Edge_Debug_Helper-*` DerivedData and one will fail with `database is locked`. Wait for one to finish before starting the other.
- **`rtk` (Rust Token Killer) wraps `git`**: `git diff` returns a token-saving summary, not raw unified diff. Use `rtk proxy git diff --no-color --no-ext-diff > patch.diff` when you need a real patch (e.g., for `git apply`).

## What Phase 9 changed

### `feat: missing loading/empty/error states + dismiss safety nets` (`54a14bb`)

Two parallel worktree-isolated agents (Agent A — MainStudioView UX; Agent B — modal correctness) executed disjoint slices, then their diffs were merged into `release-1.0b5`. Both ContentView slices are non-overlapping so the merge was clean.

#### Loading + empty states

- **`SwiftUI/EdgeStudio/Views/MainStudioView.swift`** — wraps the detail-area `Group` with `if viewModel.isLoading { ProgressView("Loading…") } else { switch viewModel.selectedSidebarDestination { ... } }`. The `isLoading` flag was already set/unset in the existing `load()` lifecycle from Phase 6; Phase 9 just consumed it. Toolbar (sync/close/inspector toggles) remains functional during load because `.toolbar` is on the parent, not inside the wrapped `Group`. Also added `presentNewSubscriptionEditor()` and `presentNewObserverEditor()` helper methods on the View struct that mirror the FAB menu's existing inline editor-presentation logic — these are the targets of the new sidebar empty-state CTAs (so the CTA path and the FAB path both go through the same code).
- **`SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift`** — replaces three `Text("No Subscriptions" / "No Observers" / "No Collections")` footnotes with `ContentUnavailableView`:
  - Subscriptions → icon `arrow.trianglehead.2.clockwise.rotate.90`, CTA "Add Subscription" → `presentNewSubscriptionEditor()`. Accessibility ID: `EmptySubscriptionsAddButton`.
  - Observers → icon `eye`, CTA "Add Observer" → `presentNewObserverEditor()`. Accessibility ID: `EmptyObserversAddButton`.
  - Collections → icon `tray` (more idiomatic for empty state than the destination icon `macpro.gen2`), body text "Collections appear once data is synced or imported into this database.", CTA "Run a Query" → `viewModel.selectedSidebarDestination = .query`. Accessibility ID: `EmptyCollectionsQueryButton`.
  - All buttons use `.buttonStyle(.borderedProminent)` + `.tint(.dittoYellow)` + `.foregroundStyle(Color.black)` to stay consistent with the Phase 8 sidebar selection pill treatment.

#### Dismiss / unsaved-change safety

- **`SwiftUI/EdgeStudio/Views/Database/DatabaseEditorView.swift`** — added `@Binding var hasUnsavedChanges: Bool` (defaulted to `.constant(false)` so the existing `#Preview` keeps compiling without modification). New `OriginalSnapshot` struct captured in `init` via an `@ObservationIgnored private let original: OriginalSnapshot` (kept out of the observation graph to avoid feedback loops). New `viewModel.hasUnsavedChanges` computed property does cheap field-by-field equality vs. the snapshot. New `attemptCancel()` shows a `confirmationDialog("Discard changes?", titleVisibility: .visible)` with "Discard Changes" (destructive) / "Keep Editing" (cancel) when dirty, dismisses immediately when clean. The Cancel toolbar button on both platforms now calls `attemptCancel()`. An `.onChange(of: viewModel.hasUnsavedChanges)` pushes the dirty flag back up to the host binding.
- **`SwiftUI/EdgeStudio/Views/ContentView.swift` (Agent A's slice)** — added `@State private var databaseEditorHasUnsavedChanges = false`, passed it as a `Binding` to both the macOS and iOS `DatabaseEditorView` sheets, and put `.interactiveDismissDisabled(databaseEditorHasUnsavedChanges)` on each (no-op on macOS but valid syntax). `onDismiss:` resets the flag. Both sheet calls use the explicit `content:` argument label rather than a trailing closure to satisfy SwiftLint's `multiple_closures_with_trailing_closure` rule (the `onDismiss:` parameter forces this).
- **`SwiftUI/EdgeStudio/Views/ContentView.swift` (Agent B's slice — Quickstart)** — added `.interactiveDismissDisabled(quickstartService.isDownloading && !quickstartService.hasError)` on the Quickstart sheet (locks during download, releases on error so user can dismiss to recover).
- **`SwiftUI/EdgeStudio/Data/QuickstartDownloadService.swift`** — `setError(...)` now flips `isDownloading = false` synchronously *before* setting the error message. Previously a `defer { Task @MainActor in isDownloading = false }` ran asynchronously, so the gate state could lag the visible error by a tick. Success path is unchanged.
- **`SwiftUI/EdgeStudio/Components/DeleteAttachmentSheet.swift`** — destructive delete button now sets `showDeleteConfirmation = true` instead of firing immediately. New `.confirmationDialog("Delete Attachment?", titleVisibility: .visible)` with "Delete" (destructive) / "Cancel" (cancel) buttons. Message text is pluralised ("1 field" vs. "N fields").

#### Permission + recovery UX

- **`SwiftUI/EdgeStudio/Components/QRCodeScannerView.swift`** — gates the camera preview behind `AVCaptureDevice.authorizationStatus(for: .video)`:
  - `.notDetermined` → calls `AVCaptureDevice.requestAccess(for: .video)` and reacts to the result.
  - `.denied` / `.restricted` → renders `ContentUnavailableView` with `video.slash.fill`, title "Camera Access Denied" / "Camera Access Restricted", description, and an "Open Settings" Button (iOS uses `UIApplication.openSettingsURLString`; macOS uses `x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`).
  - `.authorized` → renders the existing scanner.
  - Re-checks status on `UIApplication.didBecomeActiveNotification` so returning from Settings refreshes the UI without a relaunch.
  - Scan errors now surface as an in-sheet banner overlay (anchored at the bottom over the camera preview, with a "Dismiss" button) instead of auto-dismissing — keeps the camera visible behind the error and lets the user retry. Both the iOS and macOS `QRCameraPreview` representables gained an `onError: (String) -> Void` parameter to push errors back to the parent.
- **`SwiftUI/EdgeStudio/Views/ContentView.swift` (Agent B's slice — `loadApps`)** — added `loadAppsError: Error?` to `ContentView.ViewModel`, set in `loadApps`'s catch block (alongside the existing `appState.setError`), cleared at the start of every `loadApps` invocation. New `loadAppsErrorView(_:)` helper renders a `ContentUnavailableView` with `exclamationmark.triangle.fill`, title "Couldn't Load Databases", body = `error.localizedDescription`, and a "Retry" Button (accessibility ID `RetryLoadAppsButton`) that calls `loadApps(appState:)` again. The iPad picker branch now reads: `if isLoading { … } else if let loadError = viewModel.loadAppsError { loadAppsErrorView(loadError) } else if viewModel.dittoApps.isEmpty { NoDatabaseConfigurationView } else { DatabaseList }`.
- **`SwiftUI/EdgeStudio/Views/Database/DatabaseListPanel.swift`** — same `loadAppsError` branch on the macOS picker side. This file backs the macOS picker UI and reads `viewModel.loadAppsError` directly, so the error rendering had to mirror across both files. (This was outside Agent B's original "ContentView only" framing but is on the same code path.)

#### Window / link correctness

- **`SwiftUI/EdgeStudio/Views/Tools/FontDebugWindow.swift`** — close button now calls `dismiss()` (the `@Environment(\.dismiss)` was already declared in the view) instead of `NSApplication.shared.keyWindow?.close()`. The old code closed whichever window had focus — wrong if the user clicked the main app window first then back to Font Debug.
- **`SwiftUI/EdgeStudio/Views/Tools/HelpDocumentationWindow.swift`** — when the bundled `UserGuide.md` is missing (e.g., in dev builds), a fallback `Link("Open Online Documentation", destination: URL(string: "https://docs.ditto.live")!)` is shown below the existing error UI. Wrapped in `if let onlineDocsURL = URL(string: …)` to avoid a force-unwrap. `Link` opens in the user's default browser on both macOS and iOS.

### Verification (Phase 9)

- ✅ macOS build SUCCEEDED (`xcodebuild ... platform=macOS,arch=arm64 build`)
- ✅ iPadOS build SUCCEEDED (`xcodebuild ... iPad Pro 13-inch (M5)`)
- ✅ Tests via `xcrun xcresulttool get test-results summary`: **395 passed / 1 skipped / 0 failed = 396 baseline match**
- ✅ SwiftFormat clean on the 10 changed files (0/10 would have been formatted — all `-- no changes (cached)`)
- ✅ SwiftLint on the 10 changed files: 0 violations introduced. One pre-existing warning at `QuickstartDownloadService.swift:29` (static URL force-unwrap) is unrelated to Phase 9 — it predates the branch.
- ✅ Manual test gate signed off by Aaron

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:

- **Phase 10** — architecture refactor (~10h, **largest phase in the plan**), split into three sequentially-dependent sub-phases:
  - **10a — Protocol-based DI for ViewModels (~3h)**: define protocols for `DittoManager`, `SubscriptionsRepository`, `SystemRepository`, `QueryService`, `DatabaseRepository`, `HistoryRepository`, `FavoritesRepository`, `ObservableRepository`, `CollectionsRepository`. ViewModels accept them via `init` with singleton defaults. Add at least one Swift Testing unit test that constructs `MainStudioView.ViewModel` with mock repos. Required by the 80% coverage rule for new code.
  - **10b — Split `MainStudioView.ViewModel` (~5h)**: extract `SyncStatusViewModel`, `QueryViewModel`, `AttachmentViewModel`, `SubscriptionObserverViewModel`. The current god-VM has 44+ properties spanning four unrelated domains and is the single biggest architecture finding.
  - **10c — View polish (~2h)**: replace `Binding(get:set:)` with `@Bindable` projections (8+ sites), mark all non-private `@State` as `private`, move `MenuItem.image` (which returns `some View`) out of the model into a view-layer extension, move `performDownload` and download orchestration from `ContentView` extension into `ContentView.ViewModel`, delete dead `SubscriptionsRepository.cancelAllSubscriptions`.
  - **Manual test gate** between every sub-phase — no skipping.
- **Phase 11** — MEDIUM/LOW polish + CLAUDE.md updates.

## How to start Phase 10 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-9-complete.md` then start Phase 10a per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` (architecture refactor + view polish are SwiftUI domain) and consider `axiom-testing` once unit tests start being written.
3. Phase 10 sub-phases are **sequentially dependent** — do not parallelize a/b/c. Each sub-phase is a single agent invocation, then a manual test gate, then the next.
4. Do not skip the manual test gates between sub-phases. The plan flags Phase 10 as "high risk" — regressions are easiest to catch at sub-phase boundaries.

## Open notes / risks for Phase 10

- **Phase 9 added a hard expectation that `viewModel.isLoading` exists on MainStudioView's ViewModel** (consumed by the new ProgressView wrap). Phase 10b splits the god-VM into four — the loading state must end up on whichever sub-VM owns the orchestration responsibility (probably the parent VM that coordinates the children, not any of the four extracted children). Don't drop `isLoading`.
- **Phase 9 added `presentNewSubscriptionEditor()` and `presentNewObserverEditor()` as View struct methods** (not VM methods) because they need to flip multiple `@State` flags + the existing FAB-menu inline editor presentation logic. When Phase 10c moves orchestration from views into VMs, these two helpers should probably move to the VM (or to whichever sub-VM `SubscriptionObserverViewModel` becomes).
- **`databaseEditorHasUnsavedChanges` is `@State` on `ContentView`** (not on `ContentView.ViewModel`). It's view-local UI plumbing for the sheet's `Binding`; it doesn't belong on the VM. Phase 10c's "non-private `@State` audit" should leave it as-is (and add `private` if it isn't already — it is).
- **`loadAppsError: Error?` lives on `ContentView.ViewModel`** (not on a separate error-state enum). Phase 10c could plausibly refactor this into a `LoadState` enum (`.loading`, `.loaded([…])`, `.empty`, `.failed(Error)`) for clarity, but it's not on the Phase 10 list — would be Phase 11 polish if anyone wants it.
- **`OriginalSnapshot` in `DatabaseEditorView`** uses `@ObservationIgnored` to keep the snapshot out of the observation graph. If Phase 10c standardises a `Bindable`-style projection pattern across the app, this snapshot pattern should be reviewed — but right now it's the cleanest way to avoid an observation feedback loop while keeping the dirty check synchronous and cheap.
- **`DatabaseListPanel.swift` was edited** for the macOS picker `loadAppsError` branch; this file wasn't in Phase 9's original spec but was on the same code path as the iPad picker. If Phase 10 reviews macOS-vs-iOS picker code-share opportunities, this is a candidate for further consolidation.
- **The pre-existing SwiftLint warning at `QuickstartDownloadService.swift:29`** (static URL force-unwrap) is now visible in any `swiftlint` run touching that file. Not Phase 9's regression — was already there. Trivial fix (`URL(string: "…") ?? URL(string: "https://…")!` is a wash, `if let url = URL(…)` is the right call) is appropriate for Phase 11 polish.
- **Xcode MCP server may be unstable in long sessions** — Phase 9 lost it mid-flight. Standard `Read` / `Edit` / `Write` / `Bash` are sufficient for File System Synchronized projects when only existing files are edited. If Phase 10 needs to add new Swift files (it shouldn't — refactoring is in-place), consider verifying Xcode MCP connectivity first via a small probe or restarting the MCP server.
- **`rtk proxy git diff …` is the way to get raw patch output** when applying patches across worktrees. The default `git diff` returns a summary that `git apply` rejects with `No valid patches in input`.
- **Worktree branch reuse can leak stale state** — both Phase 9 agents had to `git reset --hard release-1.0b5` because their assigned worktree branches were pointing at older commits (likely from the prior stalled attempts). New agents starting from a worktree should always confirm `git rev-parse HEAD` matches the expected base before starting, and reset if it doesn't.
