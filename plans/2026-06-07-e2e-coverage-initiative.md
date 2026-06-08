# E2E Coverage Initiative (2026-06-07)

Goal: lift the largely-untested UI surface (`Components` 0.5%, `Views` 9.7%) using
XCUITest e2e flows. XCUITest coverage counts toward the app target when run with
`-enableCodeCoverage YES`, so driving real user journeys covers the view code.

## Prerequisite: instrument views (approved)
The DB-management/entry surface is already instrumented; the high-value content
surfaces are not. Two-phase per flow: (1) add accessibility identifiers to the
SwiftUI views, (2) write the e2e test that drives them.

Sidebar nav is an SF-Symbol segmented `Picker` that XCUITest can't tap
(docs/TESTING.md Pattern 2). Make it automatable (e.g. accessible per-destination
hooks) so flows can reach Observer/Subscriptions.

## Flows (priority order, all approved)
1. **Query execution (Collections)** — biggest win. Instrument DQLCodeEditor input,
   QueryToolbarView (execute/mode), QueryResultsView, ResultTableViewer,
   ResultJsonViewer, PaginationControls. e2e: open DB → type DQL → run → assert
   results → toggle table/json → paginate.
2. **DB lifecycle + navigation** — add/edit/delete DB, open MainStudioView,
   sidebar nav across sections, inspector toggle. Mostly instrumented; add nav hooks.
3. **Observer + Subscriptions** — create subscription/observer, observer events
   table, sync/peer tabs. Instrument ObserverEventsTableView, SubscriptionCard/List,
   ConnectedPeersView.
4. **Attachments + Inspector** — add/view/delete attachment from a result row;
   History/Favorites inspector. Instrument attachment views, QueryResultRowMenu,
   InspectorViews.

## Constraints / division of labor
- e2e tests require credentials (testDatabaseConfig.plist — present) + macOS
  Accessibility permission (granted) + a real GUI session for reliable window
  activation. I can author + compile-verify; final pass/fail is confirmed by the
  user running in Xcode.
- Every test reuses UITestBase helpers; XCTSkip cleanly when preconditions absent.
- Keep accessibility identifiers stable + descriptive; add to docs/TESTING.md table.

## Verify each increment
Test build 0 warnings; unit (390) + integration (142) stay green; user runs the new
UI flow in Xcode and reports.
