# Phase 10c Status — Pause Point (2026-05-08, end of day)

**Branch**: `release-1.0b5`
**Last commit**: `6208296 fix: restore studio window minimum size (Phase 8 follow-up)`
**State**: Phase 10c **implementation complete, NOT YET COMMITTED**. Waiting on manual smoke test sign-off.

---

## Where we are in the overall plan

`plans/2026-05-07-pre-v1-shipping-fixes.md`:

| Phase | Status |
|---|---|
| 0–9 | ✅ committed |
| 10a — protocol DI | ✅ committed (`0148939`), manual test signed off |
| 10b — sub-VM split | ✅ committed (`0b5ed00`), manual test signed off |
| Window-size fix (Phase 8 follow-up) | ✅ committed (`6208296`) |
| **10c — view polish** | **⏸️ implementation complete, awaiting smoke test → commit** |
| 11 — MEDIUM/LOW polish | pending |

---

## Uncommitted changes (what's in the working tree)

`rtk proxy git status` will show:

**Modified (5 files)**
- `SwiftUI/EdgeStudio/Data/Repositories/SubscriptionsRepository.swift` — deleted `cancelAllSubscriptions` + private helper `performSubscriptionCleanup` (dead code, no callers).
- `SwiftUI/EdgeStudio/Views/ContentView.swift` — three changes bundled:
  - `@Bindable var viewModel = viewModel` projection at the top of `body`, `macOSPickerView`, and `iPadPickerView`. 10 `Binding(get:set:)` long-forms replaced with `$viewModel.x` short-forms.
  - The macOS quickstart download flow (state + `startQuickstartDownload`/`openFolderPickerAndDownload`/`performDownload` + new helper methods `replaceExistingFolderAndDownload`, `chooseDifferentLocationAndDownload`, `continueDownloadWithoutConfig`) moved from a `ContentView` extension into `ContentView.ViewModel`. Body's alert/sheet bindings now point at `viewModel.X`.
  - The 7 quickstart-related `@State` properties on the View struct deleted (now live on the VM).
- `SwiftUI/EdgeStudio/Views/MainStudioView.swift` — three changes bundled:
  - `MenuItem` struct removed from this file (now in `Models/MenuItem.swift`).
  - `expandedCollectionIds` / `expandedSubscriptionIds` / `expandedObserverIds` privatized (`@State private var`).
  - New helpers `toggleSubscriptionExpansion(_:)` and `toggleObserverExpansion(_:)` so cross-file extensions don't reach into the now-private Sets.
- `SwiftUI/EdgeStudio/Views/StudioView/Details/PresenceViewerSK.swift` — single `Binding(get:set:)` for the "Direct Connected" toggle replaced with `$viewModel.showDirectConnectedOnly` via local `@Bindable` projection.
- `SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift` — two button taps now call the new `toggleSubscriptionExpansion(_:)` / `toggleObserverExpansion(_:)` helpers instead of mutating the (now-private) Sets directly.

**New untracked files (2)**
- `SwiftUI/EdgeStudio/Models/MenuItem.swift` — Foundation-pure `MenuItem` (id, name, systemIcon).
- `SwiftUI/EdgeStudio/Views/StudioView/ViewModels/MenuItem+Image.swift` — SwiftUI extension on `MenuItem` providing the `image` view (48pt SF Symbol). Kept in a separate file so `MenuItem` itself doesn't drag SwiftUI into the model layer.

**Pre-existing untracked (untouched, not part of 10c)** — visible in `git status` but ignore:
- `issues/*.png`
- `plans/handoffs/phase-{4,6,7,8,9,10a,10b}-complete.md`
- `reports/pre-v1-baseline/`

To see the actual 10c diff cleanly:
```bash
rtk proxy git diff --no-color --no-ext-diff > /tmp/phase-10c.diff
```

---

## Verification done before pausing

- ✅ macOS build (`mcp__xcode__BuildProject`): green
- ✅ iPadOS build (CLI `xcodebuild`): green
- ✅ Full test suite (Unit + Integration, macOS): **411 passed / 1 skipped / 0 failed = 412 total** — flat from 10b baseline, no regressions
- ✅ SwiftFormat: 0 of 7 changed files needed reformat (already conforming)
- ✅ SwiftLint: clean on all 7 changed source files

DerivedData was cleared during verification (SPM checkouts had to be re-resolved once via `xcodebuild -resolvePackageDependencies` after the clear conflicted with Xcode's open state). Test pass after that recovery is reliable.

---

## Smoke test in the morning — what specifically to exercise

10c moved logic and changed Binding plumbing in three places. Test each:

1. **macOS quickstart download flow** (the biggest move):
   - Help menu → "Download Quickstarts..." → confirm:
     - With no database open: "No Database Connection" alert appears. Tap "Continue Anyway" → folder picker opens. Pick a folder where no `quickstart-main` exists → progress sheet shows download → completes → quickstart browser window opens.
     - With a database open: folder picker opens directly (no alert). Same completion path.
     - With an existing `quickstart-main` folder at the picked location: "Quickstarts Folder Exists" alert. "Replace" → overwrites + downloads. "Choose Different Location" → folder picker re-opens. "Cancel" → no action.
   - Force a download error (e.g. disconnect network mid-download): progress sheet shows error, OK button dismisses (interactive dismiss should now be ENABLED on error per the existing logic).

2. **macOS picker bindings** (10 sites switched from `Binding(get:set:)` to `$viewModel.x`):
   - Tap "+" on the picker → DatabaseEditorView sheet opens.
   - Edit, save → sheet dismisses cleanly.
   - Edit, hit unsaved-changes guard → confirmation dialog still works.
   - QR code button → QR display sheet appears, dismisses cleanly.
   - QR scanner button → QR scanner sheet appears, dismisses cleanly.

3. **iPad picker bindings** (4 sites; iPad simulator):
   - Same as #2 but on the compact iPad picker.

4. **Sidebar expansion behavior** (privatized state + new toggle helpers):
   - Open a database, switch to Subscriptions sidebar tab.
   - Tap a subscription row → row expands (showing the query text). Tap again → collapses.
   - Same for Observers tab.
   - Same for Collections tab (already used the binding-based helper, no change there but verify no regression).

5. **PresenceViewerSK toggle** (1 binding switch):
   - Open a database, switch to Sync tab → Presence Viewer.
   - Toggle "Direct Connected" off/on → the network diagram filter should respond.

6. **Inspector pickers** (use `MenuItem.image` from the new extension file):
   - Open the inspector, switch tabs (History / Favorites / JSON / Metrics / Help) — segmented picker icons should render correctly.
   - Same for the Observe inspector (JSON / Help).

If everything passes, say **"phase 10c approved"** and I'll commit (single commit titled something like `refactor: ContentView VM-owned download flow + @Bindable migrations + MenuItem extraction (Phase 10c)`).

---

## After 10c approval

1. **Commit Phase 10c** as one commit (I'll write the message).
2. **Write `plans/handoffs/phase-10c-complete.md`** as the formal handoff (replacing this status doc).
3. **Optional 10b also-rans** that were deferred — pick any/all if budget allows before Phase 11:
   - Protocolize `AttachmentService` (`AttachmentServiceProtocol` with `createAndLink`/`createAndLinkViaHttp`/`fetch(token:id:)`/`fetchViaHttp(attachmentId:)`). The `[String: Any]` token parameter is the friction point — wrap it in a `Sendable` struct or use the `sending` keyword. Yields end-to-end unit tests for `AttachmentViewModel.executeAddAttachment` and `fetchAttachmentForViewing`.
   - Protocolize `QueryMetricsRepository` (single `allRecords()` method). Trivial.
   - Add `AttachmentViewModel.reset()` and call it from parent's `closeSelectedApp` if you want clean-slate-on-close behavior for attachment UI state. Behavior change — flag in manual test.
4. **Phase 11** — MEDIUM/LOW polish + CLAUDE.md updates per `plans/2026-05-07-pre-v1-shipping-fixes.md` Phase 11 section.

---

## Out-of-scope notes from 10c (carry to 10c handoff or Phase 11)

- **`@State` privacy across MainStudioView extensions**: 14 of the 17 `@State`/`@AppStorage` properties on `MainStudioView` are accessed by extensions in 4 separate files (`SidebarViews`/`DetailViews`/`InspectorViews`/`Details/ConnectedPeersView`). Swift `private` at struct-member level is file-scoped, so privatizing them would break those cross-file accesses. Phase 10c privatized only the 3 expansion Sets (introducing toggle helpers to bridge the access). The other 14 stay `internal` until/unless someone collapses the extensions back into a single file or extracts the consumers into proper sub-Views with their own state. Out of scope for the polish phase.
- The remaining `Binding(get:set:)` sites in the codebase (8 of them) are legitimate uses — cross-property bridges (`activeSheet == .case ↔ nil`, `appState.error != nil ↔ nil`), Set-membership toggles, and component-internal selection helpers. None are migration candidates.

---

## How to start in the morning (fresh session)

After `/clear`:

> "Continue v1 shipping work. Phase 10c implementation is sitting uncommitted in `plans/handoffs/phase-10c-status.md`. I'm about to smoke test."

Then run through the 6 smoke-test groups above. When good → say "phase 10c approved" → I commit + write the formal handoff and we move to Phase 11 (or optional 10b also-rans first).

If the smoke test surfaces an issue, fix in-phase and re-test before approving.
