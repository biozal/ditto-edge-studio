# Phase 7 Complete — Handoff for Phase 8

**Created**: 2026-05-08
**Branch**: `release-1.0b5` (pushed to origin)
**Last Phase 7 commit**: `4bf322d feat: enum-driven nav + SceneStorage + ActiveSheet consolidation`

## Read first
- The execution plan: `plans/2026-05-07-pre-v1-shipping-fixes.md`
- Previous handoff: `plans/handoffs/phase-6-complete.md`
- This file is the entry point if Phase 8 starts in a fresh `/clear`'d session

## Project facts that don't change
- This is the SwiftUI Edge Studio at `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/`
- Xcode workspace tab identifier for MCP: `windowtab1` (verify with `XcodeListWindows` if a fresh session)
- Apple Xcode MCP server **is registered for this project** — tools are namespaced `mcp__xcode__*`
- Xcode MCP project tree paths use `Edge Debug Helper/EdgeStudio/...` but **on-disk paths are `SwiftUI/EdgeStudio/...`** — `swiftlint` / `swiftformat` need the on-disk form, but `XcodeRead` / `XcodeUpdate` need the MCP form
- Test baseline is **396 tests** (254 unit + 142 integration) on macOS — Phase 7 added zero new tests (mechanical refactor; manual test gate per plan). Result bundle from Phase 7: 395 passed, 1 skipped, 0 failed = baseline. **Run with a clean DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Edge_Debug_Helper-*` then `xcodebuild -resolvePackageDependencies`) when test runs intermittently fail with `Command CodeSign failed` on the EdgeStudioUITests bundle.
- Build commands: see top of `plans/2026-05-07-pre-v1-shipping-fixes.md`. Both macOS AND iPadOS must build green per CLAUDE.md.
- Use `mcp__xcode__BuildProject` for the active Xcode destination (typically macOS); use `xcodebuild` from Bash for the other platform. **Don't run both simultaneously** — they share `Edge_Debug_Helper-*` DerivedData and the BuildProject side will fail with `database is locked`. Wait for one to finish before starting the other.
- **Beware `XcodeUpdate` recursive `replaceAll` bug**: if `newString` contains `oldString` as a literal substring, replaceAll runs 1000 times. Either use a marker pattern OR include surrounding whitespace/context in `oldString`.

## What Phase 7 changed

### `feat: enum-driven nav + SceneStorage + ActiveSheet consolidation`

#### `EdgeStudio/Views/MainStudioView.swift`
- **HIGH-Nav — `SidebarDestination` enum replaces string switches**:
  - New `SidebarDestination: String, CaseIterable, Identifiable, Codable` at the bottom of the file (cases: `subscriptions`, `query`, `observers`, `appMetrics`, `queryMetrics`, `logging`). Each case has `displayName`, `systemIcon`, and `isMetricsDestination` helpers — display data lives on the enum, not on `MenuItem` instances.
  - ViewModel: removed `selectedSidebarMenuItem: MenuItem` and `sidebarMenuItems: [MenuItem]` and `static func buildSidebarItems(metricsEnabled:)`. Replaced with `selectedSidebarDestination: SidebarDestination` (default `.subscriptions`) backed by UserDefaults via `didSet` — the persistence is `@AppStorage`-equivalent without requiring the property to live on the View. Init reads `UserDefaults.standard.string(forKey: Self.sidebarDestinationKey).flatMap(SidebarDestination.init(rawValue:)) ?? .subscriptions`. Stored under key `"selectedSidebarDestination"`.
  - `MenuItem` struct kept (still used by inspector tabs: History/Favorites/JSON/Metrics/Help/Docs/Export — those aren't sidebar destinations).
  - View `availableDestinations: [SidebarDestination]` computed prop filters out `.appMetrics`/`.queryMetrics` when `metricsEnabled` is false. Replaces the conditional metrics-button block in SidebarViews.
  - `.detail` switch now exhaustive over `SidebarDestination` (no string fallthrough; the obsolete `case "Collections", "Query":` dead case is gone).
  - `.id(viewModel.selectedSidebarDestination)` and `.animation(value: ...)` use the enum.
  - `metricsEnabled` onChange auto-navigates away from metrics destinations using `viewModel.selectedSidebarDestination.isMetricsDestination`.
- **HIGH-Nav — `selectedSyncTab` → `@AppStorage`**:
  - Was `@State var selectedSyncTab = 0` on the View. Now `@AppStorage("selectedSyncTab") var selectedSyncTab = 0`. Bindings (`$selectedSyncTab` in `DetailViews.swift`) work unchanged because `@AppStorage` exposes a Binding the same way `@State` does.
- **HIGH-Nav — `ActiveSheet` enum + single `.sheet(item:)`**:
  - New `ActiveSheet: String, Identifiable` enum (9 cases: `editSubscription`, `editObserver`, `addIndex`, `importJSON`, `importSubscriptions`, `subscriptionQRDisplay`, `subscriptionQRScanner`, `attachmentPicker`, `deleteAttachmentPicker`).
  - Replaced 7 chained `.sheet(isPresented:)` modifiers (lines 192-287 pre-Phase-7) with a single `.sheet(item: $activeSheet) { sheet in sheetContent(for: sheet) }`. New `@ViewBuilder func sheetContent(for: ActiveSheet) -> some View` switches over the enum.
  - **Removed**: `ActionSheetMode` enum, VM `actionSheetMode` property, VM `showAttachmentPicker`/`showDeleteAttachmentPicker` flags, View `showingImportView`/`showingImportSubscriptionsView`/`showingSubscriptionQRDisplay`/`showingSubscriptionQRScanner` flags, the `isSheetPresented` computed Binding helper.
  - VM methods that used to flip those flags renamed to *stage* helpers (data-only): `stageSubscriptionEditor`, `stageObservableEditor`, `stageAddAttachment`, `stageDeleteAttachment`. Sheet activation moved to View extension methods `presentSubscriptionEditor`, `presentObservableEditor`, `presentAddAttachment`, `presentDeleteAttachment` — they call the VM stage method then set `activeSheet = .someCase`.
  - VM `formCancel`/`formSaveSubscription`/`formSaveObserver` no longer touch sheet state. The View's wrapper closures inside `sheetContent(for:)` clear `activeSheet = nil` after invoking the VM method. `formCancel` now also nils `editorObservable` (was implicit before via the `actionSheetMode = .none` fallthrough).
  - `ImportDataView` and `ImportSubscriptionsView` still want `Binding<Bool>` for their `isPresented` parameter — provided by `importJSONBinding` and `importSubscriptionsBinding` private computed Bindings on the View that read `activeSheet == .x` and clear it on `false`.

#### `EdgeStudio/Views/StudioView/SidebarViews.swift`
- Sidebar list collapsed: was 3 `Section`s with `ForEach(viewModel.sidebarMenuItems)` + 2 conditional metrics buttons + tree rows. Now a single `ForEach(availableDestinations)` for the top section (metrics filtering moved to the computed prop), then the existing tree-row sections (subscriptions/collections/observers) unchanged.
- All inline `viewModel.selectedSidebarMenuItem = MenuItem(...)` assignments replaced with direct enum assignments (e.g. `viewModel.selectedSidebarDestination = .observers`). Lookup-by-name patterns like `viewModel.sidebarMenuItems.first { $0.name == "Query" } ?? viewModel.sidebarMenuItems[0]` are gone.
- QR display button: `showingSubscriptionQRDisplay = true` → `activeSheet = .subscriptionQRDisplay`.
- Subscription context-menu Edit button: `viewModel.showSubscriptionEditor(sub)` → `presentSubscriptionEditor(sub)`.

#### `EdgeStudio/Views/StudioView/InspectorViews.swift`
- `inspectorView()` switch is now exhaustive over `SidebarDestination`. The `case "Collections", "Query"` legacy case is gone — `.query` is the only case for the QueryEditor inspector.
- `metricsDocsInspectorContent` resourceName picks `appmetrics` vs `querymetrics` via `viewModel.selectedSidebarDestination == .appMetrics`.
- `loadQueryFromInspector` simplified: `if viewModel.selectedSidebarDestination != .query { viewModel.selectedSidebarDestination = .query }`. The previous `viewModel.sidebarMenuItems.first(where: { $0.name == "Collections" })` lookup is gone.

#### `EdgeStudio/Views/StudioView/Details/DetailViews.swift`
- `selectedSyncTab` references unchanged (`$selectedSyncTab` still resolves to a `Binding<Int>`, just from `@AppStorage` now instead of `@State`).
- Attachment callbacks: `viewModel.requestAddAttachment(documentJson:)` → `presentAddAttachment(documentJson:)` (the new View extension method). Same for delete.

#### `EdgeStudio/Views/ContentView.swift`
- New `@SceneStorage("selectedDatabaseId") private var storedDatabaseId: String?` on `ContentView`.
- `.onAppear` now (after `loadApps`) attempts to restore: if `storedDatabaseId` matches a config's `_id` and `!isMainStudioViewPresented`, calls `viewModel.showMainStudio(config, appState: appState)` — auto-reopens last database.
- New `.onChange(of: viewModel.isMainStudioViewPresented)` (cross-platform, additive — the existing macOS-only NSWindow onChange is untouched): on present, sets `storedDatabaseId = viewModel.selectedDittoConfigForDatabase?._id`. On dismiss, clears it **only if `!viewModel.isClosingDatabase`** so transient dismiss states during cleanup don't lose the id.

#### `EdgeStudio/Ditto_Edge_StudioApp.swift`
- **MEDIUM-Nav — dead `scenePhase` `onChange` removed**:
  - Was `.onChange(of: scenePhase) { newPhase, _ in switch newPhase { case .background, .inactive: Task {} ... } }`. Reversed param order (`(newValue, oldValue)` instead of the `(oldValue, newValue)` Apple changed to in iOS 17+) and empty bodies (`Task {}` does nothing). Removed the entire onChange block — there's no save logic to wire yet, and Phase 4's hydration UX already handles foreground returns.
  - Also removed the now-unused `@Environment(\.scenePhase) private var scenePhase` declaration.

### Verification (Phase 7)
- ✅ macOS build SUCCEEDED (Xcode MCP `BuildProject`, ~4.3s)
- ✅ iPadOS build SUCCEEDED (`xcodebuild` for iPad Pro 13-inch (M5))
- ✅ Zero compile warnings (`XcodeListNavigatorIssues` only shows pre-existing DittoSwift SDK runtime warnings, unrelated to our changes)
- ✅ 395 passed, 1 skipped, 0 failed on macOS test suite (matches baseline; no new tests added)
- ✅ SwiftFormat clean on changed files (0/6 files would have been formatted)
- ✅ SwiftLint clean on changed files (zero violations)
- ✅ `grep -rn "switch.*selectedSidebarMenuItem.name" --include="*.swift" SwiftUI/` returns zero hits (the plan's required gate)
- ✅ Manual test gate signed off by Aaron

## What's left in the plan

Read `plans/2026-05-07-pre-v1-shipping-fixes.md` for full detail. Remaining phases:
- **Phase 8** — HIGH layout cleanups: replace manual `NSWindow` sizing with `windowResizability`/`defaultSize`, lower iPad sidebar/inspector min widths so 50% Split View works, fix `if/else` `compactLayout`/`tabLayout` identity loss in `QueryResultsView`, drop `maxHeight: 860` clip on `DatabaseEditorView` sheet for Dynamic Type AX5.
- Phases 9-11 cover UX / architecture / polish.

## How to start Phase 8 in a fresh session

After `/clear`:
1. Tell Claude: "Continue v1 shipping work. Read `plans/handoffs/phase-7-complete.md` then start Phase 8 per `plans/2026-05-07-pre-v1-shipping-fixes.md`."
2. Claude should invoke `axiom-swiftui` (layout patterns + adaptive size classes are SwiftUI domain) and verify the Xcode MCP tab via `XcodeListWindows`.
3. Phase 8 is a single agent (per the plan — "layout changes need to be tested as a whole"), no parallel split.
4. Manual test gate: macOS picker resizes freely after open/close; iPad Pro 13" full-screen + 50% Split View + 33% Slide Over all render usable layouts; rotation reflows; DatabaseEditorView sheet scrolls (not clips) at Dynamic Type AX5.

## Open notes / risks for next phase

- **Phase 8 will touch the existing macOS `.onChange(of: viewModel.isMainStudioViewPresented)` block in `ContentView.swift:51-66`** — the one that does `window.styleMask.insert(.resizable)` / `setContentSize` / `minSize` / `maxSize` / `center()`. This block is the target of the "remove manual NSWindow sizing" change. Phase 7 added a separate cross-platform `.onChange` of the same key (for SceneStorage) just below it. Both onChanges fire — that's fine, they don't conflict, but Phase 8 should leave the new SceneStorage onChange alone and only delete the NSWindow-sizing one (or repurpose the `WindowAccessor` overlay if Phase 8 needs to keep any per-window setup).
- **Phase 7 changed the source-of-truth for sheet presentation from VM flags to View `@State activeSheet`**. Phase 8 doesn't touch sheets, but if Phase 9 adds the `DatabaseEditorView` `interactiveDismissDisabled(hasUnsavedChanges)` + confirmation dialog, it operates on a sheet that's NOT in `MainStudioView` (it's in `ContentView`'s `dittoAppToEdit`/`isPresented` flow — separate code path). The Phase 7 `ActiveSheet` enum is scoped to `MainStudioView` only.
- **`@SceneStorage` on macOS is per-window**. If a user has multiple windows of the same scene open (rare for this app — `.commands { CommandGroup(replacing: .newItem) { } }` removes the New Window command in `Ditto_Edge_StudioApp`), each window gets its own `selectedDatabaseId`. On iOS this is per-scene as expected. No action needed; just don't be surprised if `defaults read com.costoda.dittoedgestudio` doesn't show the id directly — `@SceneStorage` writes to a different plist segment than `@AppStorage`.
- **The new SceneStorage restore logic runs inside the `.onAppear` Task**. If a user *also* taps a database card before the load finishes, the `viewModel.isMainStudioViewPresented` guard skips the auto-restore. Tested manually; if Phase 9 adds explicit tap-disable-during-load, ensure the guard still holds.
- **`selectedSidebarDestination` persistence uses UserDefaults directly via `didSet`, not `@AppStorage`**. Reason: `@AppStorage` lives on Views, not `@Observable` ViewModels. The `didSet` writes the rawValue under key `"selectedSidebarDestination"` — if you ever need to inspect/reset it, that's the key. Cross-launch behavior is identical to `@AppStorage`.
- **Phase 6's `loadTask` and Phase 7's `selectedSidebarDestination` are independent**. If Phase 10 splits `MainStudioView.ViewModel`, the destination stays on the parent VM (it's nav state, not domain state). The split-out child VMs shouldn't own destination state.
