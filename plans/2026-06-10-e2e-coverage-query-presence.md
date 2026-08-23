# E2E Coverage Review — Query & Presence (2026-06-10)

## Context
1.0 is **blocked** on a Ditto SDK patch (observer activation crash — see memory
`observer-sdk-crash-blocked`). Observers are out of scope until then. Meanwhile we
extend the macOS XCUITest suite to the two most-used features: the **Query** screen
and the **Presence/Sync** screen. Harness, seeding, signing, and the query
round-trip already work (see `2026-06-07-e2e-coverage-initiative.md`).

## Current e2e coverage (committed)
- `QueryExecutionUITests` — INSERT → SELECT(WHERE) → assert real value → DELETE.
- `NavigationLifecycleUITests` — sidebar nav, inspector open/close, close DB → list.
- (Observer e2e removed — blocked on SDK.)

## Reliability constraints to design around
- **Segmented `Picker`s aren't tappable per-segment** in XCUITest (docs Pattern 2).
  This blocks two switchers we'd want: `ResultsViewModeToggle` (Raw/Table/Profile)
  and `SyncTabPicker` (Peers/Presence/Settings). → add per-option tappable hooks
  (the proven `NavItem_<x>`/container-anchor pattern) before testing those flows.
- **Context menus / right-click are flaky on macOS** (caused a runner crash earlier).
  Avoid for assertions; prefer DQL or buttons. History/Favorite delete + attachment
  add/delete currently live in context menus (`QueryResultRowMenu`).
- **`DittoPresenceViewer` (PresenceViewerSK) is a 3rd-party graph view** — assert the
  container renders, not its internals.
- Prefer **DQL-driven data setup** (proven, deterministic, no cloud dependency).

---

## Query screen — candidate flows

| # | Flow | Existing IDs | Instrumentation to add | Notes / Priority |
|---|------|-------------|------------------------|------------------|
| Q1 | Results render in **Table** view + back to **Raw** | `ResultsViewModeToggle`, `QueryResultsView` | per-segment hooks for the view-mode toggle; `ResultTableViewer` row/cell ids | **P1.** Raw already asserted; Table is the gap. |
| Q2 | **Pagination** — INSERT > pageSize docs → SELECT → Next/Prev changes page | `PaginationNextButton`, `PaginationPrevButton`, `QueryResultsView` | a page indicator id (assert page number/contents change) | **P1.** Buttons already instrumented. |
| Q3 | **History** — run query → appears in history → re-run from history | `QueryInspectorView` (container) | history row ids (`HistoryRow_<n>`) + tap-to-load | **P1.** Inspector container exists; rows need ids. |
| Q4 | **Favorites** — favorite a query → appears in Favorites → load it | `QueryInspectorView`, `InspectorSegmentedPicker` | favorite affordance id + favorite row ids; inspector tab switch hook | **P2** (favorite action is in a context menu today). |
| Q5 | **Execute mode** Local vs HTTP | — | id on the execute-mode `Picker` (`selectedExecuteMode`) | **P2.** HTTP needs live creds/network — less deterministic. |
| Q6 | **Profile/Metrics** tab renders for a SELECT (metrics on) | `ResultsViewModeToggle`, `MetricsInspectorSegmentedPicker` | view-mode hook + a profile container id | **P2.** Gated on Collect Metrics setting. |
| Q7 | **Empty / error** — SELECT from missing collection shows empty state; bad DQL shows error | `QueryResultsView` | error/empty container ids | **P2.** Good robustness coverage. |

## Presence / Sync screen — candidate flows

| # | Flow | Existing IDs | Instrumentation to add | Notes / Priority |
|---|------|-------------|------------------------|------------------|
| P1 | **Tab navigation** Peers List ↔ Presence Viewer ↔ Settings | `SyncTabPicker` (segmented — not tappable) | per-tab tappable hooks (`SyncTab_peers` / `_presence` / `_settings`) + a content anchor per tab | **P1 prerequisite** — unblocks all presence tests. |
| P2 | **Peers List** shows the local peer (Edge Studio) | — | `LocalPeerInfoCard` id; `ConnectedPeersView` peer-row ids | **P1.** Local peer always present → deterministic. |
| P3 | **Toggle sync** on/off and assert status reflects it | `SyncButton` | a sync-status indicator id (value: on/off) | **P1.** Single-peer deterministic (status, not remote peers). |
| P4 | **Presence Viewer** tab renders its container | — | container id on `PresenceViewerSK` wrapper | **P2.** Assert presence/graph container exists only. |
| P5 | **Transport settings** sheet opens from the toolbar | `TransportSettingsButton` (exists) | ids on the settings sheet toggles | **P2.** |

> ⚠️ Remote-peer presence (a second device showing up) is NOT deterministically
> testable single-peer — assert local peer + sync status, not remote peers.

## Other features (lower priority, after Query/Presence)
- **DB lifecycle**: add / edit / delete a database config — form already instrumented
  (`NameTextField`, `DatabaseIdTextField`, `TokenTextField`, `UrlTextField`,
  `HttpApiUrlTextField`, `AuthModePicker`, `SaveButton`, `CancelButton`, `AppCard_`).
- **Attachments**: add (file picker) → view → delete on a result row — needs ids on
  `AttachmentPickerSheet` / `AttachmentViewerSection` / `DeleteAttachmentSheet`;
  file-picker + context-menu flakiness makes this P3.
- **Collections sidebar**: tap a collection → query prefilled → run.

## Recommended order
1. **Q1 + Q2** (Table view + pagination) — query is the #1 feature, mostly
   instrumented; only need view-mode hooks + table cell ids. Highest value/effort ratio.
2. **P1 + P2 + P3** (presence tab nav hook, local-peer assertion, sync toggle) —
   second-most-used; the tab-nav hook is the one real prerequisite.
3. **Q3** (history) — strong coverage of a daily-use path.
4. Everything else as P2/P3.

## Per-flow workflow (unchanged)
Two phases each: (1) add the accessibility hooks listed above to the SwiftUI views,
(2) write the test reusing `UITestBase` (`openStudio`, `runDQL`, `waitForRowCount`,
`waitForDisappearance`, screenshots), degrading gracefully with `XCTSkip`. Build
macOS + iOS, then you run it in Xcode to confirm green.
