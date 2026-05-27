# Phase 8 Complete — Handoff for Phase 9

**Created**: 2026-05-08
**Branch**: `release-1.0b5` (pushed to origin)
**Last Phase 8 commit**: see `git log -1` after the merge — message is `fix: remove manual NSWindow sizing + iPad layout adaptivity`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md`
- Previous handoff: `plans/handoffs/phase-7-complete.md`
- This file is the entry point if Phase 9 starts in a fresh `/clear`'d session

## Project facts that don't change
- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Xcode workspace tab identifier for MCP: `windowtab1` (verify with `XcodeListWindows` if a fresh session)
- Apple Xcode MCP server **is registered for this project** — tools are namespaced `mcp__xcode__*`
- Xcode MCP project tree paths use `Edge Debug Helper/EdgeStudio/...` but **on-disk paths are `SwiftUI/EdgeStudio/...`** — `swiftlint` / `swiftformat` need the on-disk form, but `XcodeRead` / `XcodeUpdate` need the MCP form
- Test baseline is **396 tests** (254 unit + 142 integration) on macOS — Phase 8 added zero new tests (mechanical refactor; manual test gate per plan). Result bundle from Phase 8: 395 passed, 1 skipped, 0 failed = baseline. **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*`) when test runs intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle. Note: deleting DerivedData while Xcode is open with the workspace can wipe the SwiftPM artifacts cache and break `xcodebuild -resolvePackageDependencies`. If that happens, just use the Xcode MCP `BuildProject` and `RunAllTests` instead — those go through the live Xcode session, which auto-fetches missing artifacts.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- Use `mcp__xcode__BuildProject` for the active Xcode destination (typically macOS); use `xcodebuild` from Bash for the other platform. **Don't run both simultaneously** — they share `Edge_Debug_Helper-*` DerivedData and the BuildProject side will fail with `database is locked`. Wait for one to finish before starting the other.
- **Beware `XcodeUpdate` recursive `replaceAll` bug**: if `newString` contains `oldString` as a literal substring, replaceAll runs 1000 times. Either use a marker pattern OR include surrounding whitespace/context in `oldString`.

## What Phase 8 changed

### `fix: remove manual NSWindow sizing + iPad layout adaptivity`

This commit covers Phase 8 (CRITICAL/HIGH/MEDIUM layout findings) **plus** two iPad UX follow-ups discovered during manual testing of Phase 8 (inspector toggle missing on passive detail views; sidebar selection treatment too faint on iPad).

#### `EdgeStudio/Views/ContentView.swift`
- **CRITICAL-Layout — manual NSWindow choreography removed**:
  - Deleted the macOS-only `.onChange(of: viewModel.isMainStudioViewPresented)` block at the old line 58-73 that mutated `window.styleMask` / `setContentSize` / `minSize` / `maxSize` / `center()` based on whether the studio is presented.
  - Replaced the dual-state `.frame(...)` block at the old line 52-57 (which read `viewModel.isMainStudioViewPresented` for every frame value) with **per-branch** `.frame(minWidth:minHeight:)` modifiers inside the `Group` body — studio gets `1400×820`, picker gets `800×540`, no max constraints.
  - The Phase 7 SceneStorage `.onChange(of: viewModel.isMainStudioViewPresented)` block (cross-platform, sets `storedDatabaseId`) is **untouched** — it lives just below the deleted NSWindow block.
  - Removed the `.background(WindowAccessor { ... })` overlay on `macOSPickerView` — it was duplicating the new `.frame(minWidth: 800, minHeight: 540)` on the picker branch.
- **MEDIUM-Layout — drop `maxHeight: 860` on DatabaseEditorView sheet**: the inner `Form` already scrolls, so removing the cap lets Dynamic Type AX5 reflow vertically instead of clipping.

#### `EdgeStudio/Utilities/WindowAccessor.swift`
- **Deleted** (`mcp__xcode__XcodeRM ... deleteFiles=true`) — the only usage was the picker overlay above, which is gone. Project uses File System Synchronized groups, so no `.pbxproj` touch was needed.

#### `EdgeStudio/Ditto_Edge_StudioApp.swift`
- Untouched. `.windowResizability(.contentMinSize)` and `.defaultSize(800, 540)` were already on the main `WindowGroup` from prior work and serve as the SwiftUI source of truth for the macOS window sizing now that the NSWindow code is gone.

#### `EdgeStudio/Views/MainStudioView.swift`
- **HIGH-Layout — iPad NavigationSplitView column widths**:
  - Sidebar `navigationSplitViewColumnWidth` collapsed from the conditional `min: isIPadRegular ? 250 : 200, ideal: isIPadRegular ? 300 : 250, max: isIPadRegular ? 380 : 300` to a flat `min: 200, ideal: 260, max: 320`. The iPad-regular branch was the cause of 50% Split View on iPad Pro 12.9 not fitting all three columns; lowering the min unblocks it. `isIPadRegular` is still used for sidebar font sizing in `SidebarViews.swift`, so the helper stays.
  - Inspector `inspectorColumnWidth` lowered from `min: 250, ideal: 350, max: 500` to `min: 220, ideal: 320, max: 500` for the same reason.
- **iPad UX follow-up — inspector toggle on passive detail views**:
  - Added `passiveDetailToolbar()` helper using `@ToolbarContentBuilder` near `sidebarToggleButton()` (~line 438). Returns `sidebarToggleButton()` (compact only) + `syncToolbarButton()` + `closeToolbarButton()` + `inspectorToggleButton()`.
  - Applied `.toolbar { passiveDetailToolbar() }` (iOS-only) to the `.appMetrics`, `.queryMetrics`, and `.logging` cases inside the `.detail { Group { switch ... } }` block.
  - **Why it was missing**: `.toolbar` items declared on `NavigationSplitView` itself don't surface in the *detail column's* nav bar on iPad regular size class — only per-view `.toolbar` modifiers attached to the detail view do. `syncTabsDetailView()` / `queryDetailView()` / `observeDetailView()` each declare their own per-view toolbar (with their own inspector toggle), so they always rendered fine. The three passive views (`AppMetricsDetailView`, `QueryMetricsDetailView`, `LoggingDetailView`) didn't, so the inspector toggle never appeared on them. Compact size class hid the symptom because the parent's items propagate when NavigationSplitView collapses to a NavigationStack.
- **No change** to MainStudioView's existing top-level iOS `.toolbar` (sidebar in compact + sync + close). I briefly added `inspectorToggleButton()` there during exploration, then reverted — that toolbar binds to the sidebar's nav bar in regular size class, not the detail's, so it was a dead-end fix.

#### `EdgeStudio/Components/QueryResultsView.swift`
- **HIGH-Layout — unified `compactLayout`/`tabLayout`**:
  - Was an `if horizontalSizeClass == .compact { compactLayout } else { tabLayout }` outer switch. Each branch had a different SwiftUI structure (`VStack + Picker + switch` vs `TabView`), so a size class transition (rotate, split-view resize) destroyed the inner `ResultJsonViewer` / `ResultTableViewer` identity, losing their scroll position and selection state.
  - Now: a single `VStack(spacing: 0)` with one `Picker(.segmented)` at top and a `Group { switch selectedTab { case .raw: ResultJsonViewer; case .table: ResultTableViewer } }` body. `.controlSize(.large)` applies in regular size class, `.regular` in compact, so the Picker still feels appropriately sized in both modes. `.background(.regularMaterial)` on macOS is preserved (was on `tabLayout` only before).
  - Both `ResultViewTab` cases reuse the existing init signatures — no API change for callers.

#### `EdgeStudio/Views/StudioView/SidebarViews.swift`
- **iPad UX follow-up — sidebar selected-destination treatment**:
  - The Phase 7 selection treatment was `Label(...)` + `.listRowBackground(Color.accentColor.opacity(0.18))`. Two issues on iPad: (1) too faint against the white-ish sidebar background; (2) when I bumped the opacity and added `Color.accentColor` foreground, `dittoYellow` (the app's accent) on light yellow background made the text near-invisible in light mode.
  - Final state: rebuilt the row as `Label { Text } icon: { Image }` so I can style title and icon independently. Selected text is `Color.black` + `.fontWeight(.semibold)`; selected icon is `Color.black`. Unselected text uses `.primary`, unselected icon uses `.secondary`. Selection background is a `RoundedRectangle(cornerRadius: 10, style: .continuous)` filled with `Color.dittoYellow`, padded `.horizontal 8 / .vertical 2` so it reads as a pill instead of an edge-to-edge stripe. Always renders the RoundedRectangle (with `Color.clear` fill when not selected) so SwiftUI doesn't switch view types between selection states.
  - Locked black/yellow means the pill looks identical in light + dark, both on macOS and iPad. No more contrast issues.

### Verification (Phase 8)
- ✅ macOS build SUCCEEDED (Xcode MCP `BuildProject`)
- ✅ iPadOS build SUCCEEDED (`xcodebuild` for iPad Pro 13-inch (M5))
- ✅ Tests via `mcp__xcode__RunAllTests`: **395 passed / 1 skipped / 0 failed = 396 baseline match**
- ✅ SwiftFormat clean on changed files (0/N files would have been formatted)
- ✅ SwiftLint clean on changed files (0 violations across changed files)
- ✅ Manual test gate signed off by Aaron

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:
- **Phase 9** — HIGH UX cleanups: missing loading/empty/error states, `DatabaseEditorView` unsaved-changes guard with `interactiveDismissDisabled`, QR scanner camera-permission denied UI, Quickstart progress sheet dismiss-on-error, ContentView `loadApps` error vs empty differentiation, `FontDebugWindow` `@Environment(\.dismiss)` migration, `HelpDocumentationWindow` fallback link, `DeleteAttachmentSheet` confirmation dialog. Two parallel agents per the plan (Agent A — MainStudioView UX; Agent B — modal correctness).
- **Phase 10** — architecture refactor (sub a/b/c, ~10h), unblocks unit tests on ViewModels.
- **Phase 11** — MEDIUM/LOW polish + CLAUDE.md updates.

## How to start Phase 9 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-8-complete.md` then start Phase 9 per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` (loading/empty/error states + sheets are SwiftUI domain) — possibly also `axiom-accessibility` for the empty-state CTAs — and verify the Xcode MCP tab via `XcodeListWindows`.
3. Phase 9 splits into two parallel agents per the plan. Use `Agent` tool with the `general-purpose` subagent type (or specialised agents from the plugin marketplace if a better fit exists). Worktree isolation is recommended so the agents don't fight over the same files.
4. Manual test gate (per plan, lots of small UX flows): zero-subscriptions empty state, DatabaseEditorView swipe-dismiss with unsaved changes, revoked Camera permission UI on iOS, Quickstart download with offline network, FontDebugWindow close button on macOS, Help fallback link, attachment delete confirmation, loadApps failure (corrupt DatabaseRepository read).

## Open notes / risks for next phase

- **Phase 9 will touch DatabaseEditorView's sheet** in `ContentView.swift` (around line 283 in the macOS path, around line 440 in the iOS path). Phase 8 dropped its `maxHeight: 860` clamp; Phase 9's plan says to add `.interactiveDismissDisabled(hasUnsavedChanges)` + a `.confirmationDialog`. The sheet is presented from `ContentView`, so `hasUnsavedChanges` lives on `DatabaseEditorView` itself — pass it back via `@State` + `@Bindable` projection or a shared VM.
- **The `passiveDetailToolbar()` helper added in Phase 8 also returns `sidebarToggleButton()` in compact**. If Phase 9 changes how the iOS sidebar toggle works (e.g., adds a new `compactSidebar` state), make sure `sidebarToggleButton()` still does the right thing — it currently writes `preferredCompactColumn = .sidebar`.
- **`NavigationSplitView` parent `.toolbar` does not surface in the detail column on iPad regular**. This is the design — Phase 8 worked around it via per-view toolbars. If Phase 9 adds new sidebar destinations, those new destinations must declare their own per-view `.toolbar { passiveDetailToolbar() }` (or a domain-specific equivalent) on iPad, otherwise users will be stuck without sync/close/inspector buttons.
- **Sidebar selection styling is now hard-coded to `Color.dittoYellow` + `Color.black`** rather than `Color.accentColor`. If Phase 11 adds a theme picker, the sidebar selection should be revisited so it adapts to user-chosen accent colors. For v1 the locked brand colors are intentional.
- **`isIPadRegular` is still used for sidebar font sizing in `SidebarViews.swift`** even though Phase 8 removed its use in `navigationSplitViewColumnWidth`. Don't delete the helper without checking both call sites.
- **`WindowAccessor.swift` is gone** — if any post-Phase-8 work needs to call into `NSWindow` directly, prefer adding a fresh, narrowly-scoped `NSViewRepresentable` rather than restoring the whole helper. The Phase 8 deletion was deliberate.
- **`QueryResultsView`'s shared `selectedTab` is `@State` on the View, not on the VM**. If Phase 10 splits `MainStudioView.ViewModel`, `selectedTab` stays where it is — it's view-local UI state, not domain state.
