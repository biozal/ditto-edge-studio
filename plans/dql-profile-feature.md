# DQL `PROFILE` Capture + Execution-Plan Viewer

**Status:** Plan
**Date:** 2026-05-26
**Owner:** Aaron LaBeau
**Reference screenshots:** `screens/profile-viewer.png` (Edge Studio web app — card layout), `screens/couchbase-plan.png` (Couchbase — visual plan)
**Ditto docs:** <https://docs.ditto.live/dql/profile>

## Goal

Capture the execution-plan profile that Ditto produces when a DQL
statement is prefixed with `PROFILE`, strip it out of the user-facing
results, store it alongside the current query, and display it in a
new **Profile** tab next to **Raw** and **Table**. The Profile tab
has two display modes:

- **Card** — stacked operator cards with stats badges + KV
  attributes (modeled on `screens/profile-viewer.png`).
- **Plan** — visual tree of operator boxes connected by arrows
  (modeled on `screens/couchbase-plan.png`).

Capture is gated on the existing **Collect Metrics** Settings toggle
(`@AppStorage("metricsEnabled")`). No new user-facing toggle.

## What we're working with

The PROFILE keyword causes Ditto to append one extra item to the
result set with key `~request_profile`. The user's worked example:

```json
{
  "~request_profile": {
    "_id": "e526fe68-04e9-4881-bf76-d0a582827e9b",
    "app_id": "f5e954d9-0092-47a0-9a79-2829e767ba7b",
    "featureFlags": "0x3a",
    "plan": {
      "#operator": "sequence",
      "children": [
        {
          "#operator": "scan",
          "#stats": {
            "documentsOut": 1,
            "phaseTimes": { "exec": 209, "recv": 990459, "send": 61500 }
          },
          "collection": "tasks",
          "datasource": "default"
        },
        {
          "#operator": "limit",
          "#stats": {
            "documentsIn": 2,
            "documentsOut": 1,
            "phaseTimes": { "exec": 2083, "send": 6584 }
          },
          "limit": 1
        }
      ]
    },
    "queryType": "select",
    "requestType": "SDK",
    "resultCount": 1,
    "state": "completed",
    "text": "PROFILE SELECT * FROM tasks LIMIT 1",
    "times": { "elapsed": 1294166, "parse": 49834, "plan": 32167, "start": "2026-05-26T20:59:21.310-05:00" }
  }
}
```

Notes:
- All `times` values and `#stats.phaseTimes` values are nanoseconds
  at source (confirmed by the web-app screenshot — 432.43 ms ⇐
  432,430,000 ns; 55.56 µs ⇐ 55,560 ns).
- The `plan` is a recursive tree of operators. Each operator has
  `#operator` (string), `#stats` (optional), `children` (optional
  array), and zero or more operator-specific attribute keys
  (`collection`, `alias`, `datasource`, `limit`, `descriptor`, …).
- The `~request_profile` key has a `~` prefix that signals it's a
  system row, similar to `_id` being a system field.

## Scope guardrails

- **SELECT only.** `INSERT`, `UPDATE`, `DELETE`, `EVICT`,
  `ALTER SYSTEM`, etc. must not get the `PROFILE` prefix.
- **Local execution only for v1.** `executeSelectedAppQueryHttp` (the
  HTTP API path) does not get PROFILE injection. Same scoping as
  EXPLAIN, which is also local-only. Can extend in a follow-up if the
  Ditto HTTP API supports PROFILE.
- **Idempotent.** If the user typed `PROFILE` manually, don't
  double-prepend.
- **Backwards-compatible failure.** If Ditto changes the response
  shape, profile parsing fails silently and the regular query
  results still surface. The Profile tab shows a parse-error state.
- **Respect existing accessibility identifiers.** UI tests pass.

## Codebase landing points

- **`SwiftUI/EdgeStudio/Data/QueryService.swift`** — single owner of
  `executeSelectedAppQuery(query:)`. Already gates EXPLAIN capture
  on `metricsEnabled` via `UserDefaults.standard.bool(forKey:)`.
  This is where PROFILE injection + result splitting lives.
- **`SwiftUI/EdgeStudio/Views/StudioView/ViewModels/QueryViewModel.swift`**
  — owns `jsonResults: [String]`. Will own `latestProfile: QueryProfile?`
  too.
- **`SwiftUI/EdgeStudio/Components/QueryResultsView.swift`** — owns
  the Raw/Table segmented picker. Will own Raw/Table/Profile.
- **`SwiftUI/EdgeStudio/Views/Settings/AppPreferencesView.swift`** —
  already has the **Collect Metrics** toggle. No change.
- **`SwiftUI/EdgeStudio/Resources/Help/UserGuide.md`** — needs a
  Profile section under "Features → Collections & Query".
- **`SwiftUI/EdgeStudio/Resources/Help/query.md`**,
  **`querymetrics.md`** — in-app per-screen help docs. Profile
  needs cross-reference here.

## Architecture

### Phase 1 — Service: PROFILE injection + result splitting

`Data/QueryService.swift::executeSelectedAppQuery(query:)` changes
its return type from `[String]` to a small struct:

```swift
struct QueryExecutionResult: Sendable {
    let items: [String]            // existing — user-facing JSON rows
    let profile: QueryProfile?     // NEW — populated only on PROFILE'd SELECT
}
```

Updated execution flow:

```
1. Compute `shouldProfile = metricsEnabled && isSelectStatement(query) && !alreadyHasProfile(query)`
2. Send effectiveQuery = shouldProfile ? "PROFILE " + query : query
3. Get raw results from ditto.store.execute(...)
4. If shouldProfile:
     a. Find the last item where value["~request_profile"] is a dict
     b. Pop it from items, decode into QueryProfile
     c. Pass remaining items to existing string-render logic
5. Return QueryExecutionResult(items, profile)
```

**`isSelectStatement(_:)`** — trim leading whitespace, then
case-insensitive `hasPrefix("SELECT ")` or `hasPrefix("SELECT\n")`
or `hasPrefix("SELECT\t")`. (Avoid matching `SELECTED` etc.) Skip
detection of `WITH … SELECT` CTEs for v1 — the user didn't list it
and DQL CTE support is unclear; trivial follow-up if it's a thing.

**`alreadyHasProfile(_:)`** — same trim then
`hasPrefix("PROFILE")`. Prevents double-prepending if the user
types it manually.

**Why a struct instead of two return values:** keeps the call site
clean (`let result = try await queryService.execute(...)`) and
prevents accidentally dropping the profile in future refactors.

### Phase 2 — Data model

`Models/QueryProfile.swift` (new):

```swift
struct QueryProfile: Identifiable, Sendable {
    let id: String              // ~request_profile._id
    let appId: String
    let featureFlags: String
    let queryType: String       // "select"
    let requestType: String     // "SDK", "HTTP", etc.
    let resultCount: Int
    let state: String           // "completed", possibly others
    let text: String            // statement as Ditto saw it (with "PROFILE ")
    let times: QueryProfileTimes
    let plan: QueryProfileOperator
    let capturedAt: Date        // local Date() at parse time, for the header
}

struct QueryProfileTimes: Sendable {
    let elapsedNs: Int64        // total wall-clock
    let parseNs: Int64
    let planNs: Int64
    let startISO: String        // raw ISO string from "start"
}

struct QueryProfileOperator: Identifiable, Sendable {
    let id: UUID                // synthesized at parse time, stable per node
    let name: String            // "scan", "sequence", "limit", "finalProjection", …
    let stats: QueryProfileStats?
    let children: [QueryProfileOperator]
    /// Operator-specific keys (collection, alias, datasource, limit,
    /// descriptor, …). Stored as String so the card view can render
    /// them as KV pairs without knowing the full operator catalog.
    let attributes: [(key: String, value: String)]
}

struct QueryProfileStats: Sendable {
    let documentsIn: Int?
    let documentsOut: Int?
    let execNs: Int64?
    let recvNs: Int64?
    let sendNs: Int64?
}
```

**Why store attributes as `[(key, value)]` not `[String: String]`:**
preserves insertion order so the card view renders attributes in
the order Ditto returned them (matches the web app's behavior).

**Parsing** lives in `Data/QueryProfileParser.swift`:

```swift
enum QueryProfileParser {
    /// Returns nil if the dict doesn't look like a profile envelope.
    static func parse(_ raw: [String: Any]) -> QueryProfile?
    
    /// Recursive: parse one operator node from a plan dict.
    private static func parseOperator(_ raw: [String: Any]) -> QueryProfileOperator?
}
```

Parser conventions:
- Reads via `JSONSerialization`-style `[String: Any]` walk —
  matches how `QueryService` already shapes the SDK item values
  via `compactMapValues`.
- Unknown attributes become string-encoded via
  `String(describing:)` so the card view can render them without
  schema lock-in.
- Missing optional fields default to `nil` rather than failing.

### Phase 3 — ViewModel wiring

`QueryViewModel.swift`:

```swift
@Observable
final class QueryViewModel {
    var jsonResults: [String] = []         // existing
    var latestProfile: QueryProfile? = nil // NEW
    // …
    
    func runQuery() async {
        // existing branch by transport
        let result = try await queryService.executeSelectedAppQuery(query: selectedQuery)
        jsonResults = result.items
        latestProfile = result.profile      // nil clears the tab
        // …
    }
    
    func reset() {
        // existing reset of jsonResults, selectedQuery, etc.
        latestProfile = nil
    }
}
```

Profile is cleared on:
- New query run (overwritten with new profile or nil)
- Database close (`reset()` already wired)
- Switching the transport from local to HTTP — profile is local-only
  for v1; switching to HTTP nils it.

### Phase 4 — Profile tab in `QueryResultsView`

Extend the `ResultViewTab` enum (`QueryResultsView.swift:4-14`):

```swift
enum ResultViewTab: String, CaseIterable {
    case raw = "Raw"
    case table = "Table"
    case profile = "Profile"   // NEW

    var icon: String {
        switch self {
        case .raw: return "doc.plaintext"
        case .table: return "tablecells"
        case .profile: return "list.bullet.indent"   // SF Symbol — flat-tree feel
        }
    }
}
```

Wire a third branch in the switch inside the `Group { … }` body that
selects `ResultJsonViewer` / `ResultTableViewer` today.

The Profile tab is **always present** so it's discoverable.
It renders one of four states:

| State | Render |
|---|---|
| `latestProfile != nil` | The viewer described in Phase 5 |
| `metricsEnabled == false` (regardless of query type) | **Headline:** "Profiling is turned off." **Body:** "Profiles are captured automatically when Collect Metrics is enabled. Open the **Settings** window (⌘,) and toggle **Collect Metrics** on, then re-run your query to see the execution plan here." **Action button:** "Open Settings…" wired to the Settings scene |
| `metricsEnabled == true`, last query was non-SELECT | "Profiles are only captured for `SELECT` statements. Run a SELECT query to see the execution plan here." |
| `metricsEnabled == true`, no query run yet | "Run a `SELECT` query to capture an execution profile." |

The empty-state messaging uses the same `SidebarEmptyStateRow` /
`ContentUnavailableView` pattern other tabs use (whichever is closer
to the existing Raw empty state).

The metrics-off message is the most important of the four states —
it's how users discover the feature exists at all. Pin the
phrasing: **"Profiling is turned off. Open Settings (⌘,) and turn
on Collect Metrics."** with an inline "Open Settings…" button so the
user doesn't have to hunt for the menu.

### Phase 5 — Profile viewer (Card / Plan)

New directory `SwiftUI/EdgeStudio/Components/ProfileViewer/`:

```
ProfileViewerView.swift         // root: header + segmented Card/Plan picker
ProfileSummaryStrip.swift       // ELAPSED / PARSE / PLAN / RESULT COUNT / FEATUREFLAGS / QUERYTYPE
ProfileQueryHeaderCard.swift    // shows the query text in a monospaced rounded box
ProfileFooterStrip.swift        // profile UUID · db ID · state
ProfileCardListView.swift       // Card mode: recursive nested cards
ProfileOperatorCard.swift       // single operator card (shared by both modes)
ProfilePlanTreeView.swift       // Plan mode: horizontal tree with connectors
ProfileStatsBadges.swift        // colored pills: in / out / exec / recv / send
ProfileTimeFormatter.swift      // ns → "432.43 ms" / "55.56 µs" / "12.34 s"
```

`ProfileViewerView.swift` skeleton:

```swift
struct ProfileViewerView: View {
    let profile: QueryProfile
    @State private var mode: PlanMode = .card

    enum PlanMode: String, CaseIterable {
        case card = "Card"
        case plan = "Plan"
        var icon: String {
            switch self {
            case .card: return "list.bullet.rectangle"
            case .plan: return "rectangle.connected.to.line.below"
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            ProfileQueryHeaderCard(profile: profile)
            ProfileSummaryStrip(profile: profile)
            Picker("View", selection: $mode) {
                ForEach(PlanMode.allCases, id: \.self) { m in
                    Label(m.rawValue, systemImage: m.icon).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch mode {
            case .card: ProfileCardListView(root: profile.plan)
            case .plan: ProfilePlanTreeView(root: profile.plan)
            }
            ProfileFooterStrip(profile: profile)
        }
        .padding(16)
    }
}
```

#### Card mode — matches `screens/profile-viewer.png`

Recursive composition. Each operator gets a `ProfileOperatorCard`
that renders:
- **Header row**: operator name (bold, monospaced) + `ProfileStatsBadges`
  on the right (colored pills for `in: N`, `out: N`, `exec: 34.35 ms`,
  `recv: 82.78 ms`, `send: 296.95 ms`; pills hide when the stat is nil).
- **Attributes block**: two-column KV layout (`alias`/`movies`,
  `collection`/`movies`, `datasource`/`default`, `descriptor`/`{…}`).
  Long values truncate with full content on hover/tap.
- **Children**: if `children.isEmpty == false`, render a nested
  `VStack` of child cards indented inside the parent's bounds. The
  sequence operator in the screenshot shows this nesting clearly.

`ProfileStatsBadges` colors (from the screenshot):
- `in` (incoming docs) → blue
- `out` (outgoing docs) → green
- `exec` (CPU) → red/orange
- `recv` (upstream wait) → orange/yellow
- `send` (downstream push) → purple

`ProfileTimeFormatter` — three-tier auto-scaling, researched against
Postgres / MongoDB profiler / SQL Server Profiler / the existing
Edge Studio web app reference (see "Time format research" below):

| Raw value | Display | Example |
|---|---|---|
| ≥ 1,000,000 ns (≥ 1 ms) | `%.2f ms` | `432.43 ms` |
| 1,000 – 999,999 ns | `%.2f µs` | `55.56 µs` |
| < 1,000 ns | `%d ns` | `209 ns` |

Why three tiers rather than the user's initial "ms or ns" suggestion:
without the µs middle tier the display gets unreadable in the
common case — a parse time of 55,560 ns renders either as
`0.056 ms` (Postgres style — four trailing digits hide useful
precision) or `55560 ns` (a five-digit run that's hard to scan).
The µs middle tier matches the user's existing web-app reference
screenshot exactly (PARSE 55.56 µs / PLAN 52.79 µs) and aligns with
MongoDB's profiler conventions.

**Percent-of-total badge.** Cribbed from Couchbase — in the Plan
view, append the share of total `times.elapsed` to long-running
operators, e.g. `recv 82.78 ms (19.1%)`. Threshold: show the
percent badge only when the value is ≥ 5% of total (avoids visual
noise on small operators). Cheap to compute, hugely helpful for
spotting bottlenecks at a glance. This is also what powers the
"orange bottleneck" highlight described in Phase 5 — same
percentage, just visualized with color when it crosses 50%.

#### Plan mode — matches `screens/couchbase-plan.png`

Visual tree of operator boxes. SwiftUI choice:

```swift
struct ProfilePlanTreeView: View {
    let root: QueryProfileOperator

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            PlanNodeView(node: root)
                .padding(40)
        }
    }
}

private struct PlanNodeView: View {
    let node: QueryProfileOperator

    var body: some View {
        VStack(alignment: .center, spacing: 24) {
            OperatorBoxView(node: node)
            if !node.children.isEmpty {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(node.children) { child in
                        PlanNodeView(node: child)
                    }
                }
                .overlay(ConnectorOverlay(parentCount: node.children.count))
            }
        }
    }
}
```

`OperatorBoxView` — fixed-width (160pt) rounded rectangle:
- Operator name (semibold, centered)
- Key attribute (e.g. `airport` for a `scan` on `collection: airport`)
- Total time `exec + recv + send` formatted
- "N in / M out" line

**Color coding**: green by default; orange when a node's `execNs >
overallElapsedNs * 0.5` (a single operator burning more than half
the elapsed time — the "bottleneck" indicator). The threshold lives
in a constant so it's tunable.

**Arrows / connectors**: thin lines drawn via `Path` in an
`overlay`. Use `PreferenceKey`-based position propagation so the
overlay knows where children start.

**Direction**: top-down (root at top, data flows up through
children to the root). This is the more common Ditto/EXPLAIN
mental model, and the Couchbase example reads left-to-right but
they're equivalent — vertical is easier in SwiftUI.

**Zoom**: deferred to v1.1. The ScrollView handles overflow; pinch-
to-zoom on macOS isn't worth the layout math for the first cut.

### Phase 6 — Documentation

1. **`Resources/Help/UserGuide.md`** — add a new subsection under
   "Features → Collections & Query":
   ```
   ### Execution Profile
   - What it captures
   - When it's captured (Collect Metrics on + SELECT)
   - How to read the Card view (badges, attributes)
   - How to read the Plan view (nodes, arrows, orange = hotspot)
   - Link to Ditto's PROFILE docs
   ```
2. **`Resources/Help/query.md`** — append a "Profile tab" subsection
   describing the tab and pointing at the User Guide for depth.
3. **`Resources/Help/querymetrics.md`** — append a cross-reference
   "See also: Execution Profile" so users who land on metrics
   discover the new feature.
4. **`docs/PROFILE.md`** (new) — engineering-side reference:
   - JSON envelope structure
   - Time-unit conventions (nanoseconds)
   - Operator catalog (scan, sequence, limit, finalProjection,
     projection, filter, …) with what their attributes mean
   - Parsing edge cases
5. **`docs/METRICS.md`** — add a "Related: Execution Profile" link.
6. **`CLAUDE.md`** — under "Key Features", add "Execution profile
   capture and visualization for SELECT statements (Card and Plan
   views)".

## Testing

### Unit (`EdgeStudioUnitTests`)

- `QueryServiceTests` — extend with cases:
  - `metricsEnabled = false` → no PROFILE prepended, profile nil
  - `metricsEnabled = true`, SELECT → PROFILE prepended, profile non-nil
  - `metricsEnabled = true`, INSERT/UPDATE/DELETE/EVICT → no PROFILE,
    profile nil
  - User-typed "PROFILE SELECT …" → not double-prepended
  - Leading whitespace / newlines / tabs handled
- `QueryProfileParserTests` (new):
  - Happy path with the worked example from the user
  - Missing `times.parse` → profile decodes with nil for that field
  - Operator with no children → leaf
  - Deep tree (3+ levels of children) — parses bottom-up correctly
  - Operator with unknown attributes → still parses, attributes
    stored as strings
  - Profile envelope missing entirely → returns nil

### Integration (`EdgeStudioIntegrationTests`)

- Run a real `PROFILE SELECT * FROM tasks LIMIT 1` against a freshly
  seeded test database and assert:
  - Profile returned non-nil
  - `profile.plan.name == "sequence"` (or whatever the SDK actually
    returns for a basic SELECT)
  - `profile.text` contains the original query
  - `profile.resultCount == itemsReturned`

### UI (`EdgeStudioUITests`)

- Run a query with Collect Metrics on → Profile tab visible → switch
  to Profile → assert Card mode renders ≥ 1 operator card
- Run an INSERT with Collect Metrics on → Profile tab shows the
  "only SELECT" empty state
- Toggle off Collect Metrics, run SELECT → Profile tab shows the
  "enable Collect Metrics" empty state
- Switch Card → Plan picker → assert at least one plan box appears

## Build verification

Per CLAUDE.md, both targets:
- `xcodebuild -destination "platform=macOS,arch=arm64" build`
- `xcodebuild -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build`

## Order of operations

Land in vertical slices so each step is reviewable and gives the
user something to look at:

1. **Slice 1 — Service-only** (`QueryService.swift`,
   `QueryViewModel.swift`, new models + parser). PROFILE gets
   injected, results split, profile stored on the VM, but the UI
   still only shows Raw + Table. Verify via unit tests + a
   temporary `print` to confirm the profile is captured.
2. **Slice 2 — Card view + Profile tab.** Add the tab, render
   Card mode only. User can see and read profiles.
3. **Slice 3 — Plan view.** Add the Card/Plan sub-picker and the
   tree renderer.
4. **Slice 4 — Documentation.** UserGuide / query.md / querymetrics.md
   / new PROFILE.md.
5. **Slice 5 — Tests.** Unit + integration + UI.

## Out of scope (deliberately deferred)

- **HTTP transport.** PROFILE only fires on the local-store
  execution path for v1, matching the EXPLAIN scope.
- **Profile history.** Each new query overwrites the previous
  profile — no historical browsing. The Query Metrics screen
  already covers per-query timing history; profile history would
  duplicate that with much heavier data.
- **Profile diffing / "compare last two profiles".** Useful but a
  separate feature.
- **Plan mode zoom / pan controls.** v1 relies on the parent
  ScrollView. Add explicit zoom controls if user feedback asks
  for them.
- **CTEs (`WITH … SELECT …`).** Skip detection for v1.
- **Color-coding by node type** (e.g., scan = blue, projection =
  green). Use a single "is bottleneck" highlight color for v1;
  per-operator-type colors are an aesthetic polish for later.

## Resolved decisions

1. **Time units at source: nanoseconds.** Verified by reading the
   Ditto Rust source at
   `crates/ditto-dql/src/engine/caches/request.rs`:
   `set_parse_time(ns)` / `set_plan_time(ns)` / `elapsed()` all
   serialize `u64` nanoseconds via `.as_nanos()`. The per-operator
   `phaseTimes.exec`/`recv`/`send` (same file, line 105) also use
   `.as_nanos() as u64`.

   **Display strategy: three-tier auto-scale (ms / µs / ns).** See
   the `ProfileTimeFormatter` table in Phase 5, and the "Time format
   research" section at the bottom of this plan for the cross-
   platform comparison that drove the decision.
2. **Profile tab visibility.** Always shown. The metrics-off empty
   state is how users learn the feature exists — hiding the tab
   when there's no data would prevent discovery. See the State
   table in Phase 4 for the four empty-state messages.
3. **Plan direction.** Top-down (root at top, children below).
   Cleanest in SwiftUI with the recursive `VStack { card; HStack
   { children } }` shape sketched in Phase 5.
4. **Bottleneck threshold.** "Node `exec` > 50% of total
   `times.elapsed`" → orange. Threshold lives in a single
   constant so it's tunable once we have real-world data.

## Time format research

Recommendation in this plan was driven by checking what major
query profilers actually display, since the user flagged that
Edge Studio should match developer expectations from tools like
Postgres and Couchbase. Findings:

| Tool | Default unit | Sub-ms display | Notes |
|---|---|---|---|
| **Postgres** `EXPLAIN ANALYZE` | always ms | `0.026 ms` (3 decimals) | Single unit; sub-ms precision hides in decimals — frequent complaint in pgMustard/Supabase docs |
| **MongoDB** `explain` | ms (`executionTimeMillis`) | ms with decimals | Single unit, total-only |
| **MongoDB** profiler | mixed | µs for planning / locks / disk reads, ms for total | Two-unit hybrid by metric type |
| **SQL Server Profiler** | ms (UI default), µs (raw storage) | µs (user-toggleable) | Tools → Options → "Show in microseconds" |
| **Couchbase Workbench** | `mm:ss.SSS` for totals, ms per node + percentages | percent of total | Time + relative-weight badge |
| **Chrome DevTools Performance** | auto-scale | ns/µs/ms per event | Industry-standard for tracing UIs (not DB-specific) |
| **Edge Studio web-app reference** (this team) | µs / ms auto-scaled per value | µs | Already exists; matches what users have seen |

Industry consensus across DB tooling:
- **ms is the universally-recognized headline unit** for total query time
- **µs is the standard sub-ms unit** (MongoDB profiler, SQL Server Profiler) — both ship a user-toggleable "show in microseconds" option, suggesting users *want* this when looking at small values
- **ns is rare in DB profilers** but appropriate for sub-µs values that would otherwise collapse to `0.21 µs`
- **Percent-of-total** is a Couchbase signature feature that adds outsized signal-to-noise — adopting it costs ~3 lines of code

The three-tier auto-scale (ms / µs / ns, picked per value) +
percent-of-total badge for ≥ 5% nodes gets us the best of both
worlds: a familiar ms-first display that drops to µs/ns only when
the raw value is too small to read cleanly in ms, plus Couchbase's
proven bottleneck-spotting aid.

Sources:
- [PostgreSQL: Documentation: EXPLAIN](https://www.postgresql.org/docs/current/sql-explain.html)
- [Supabase: Understanding Postgres EXPLAIN Output](https://supabase.com/docs/guides/troubleshooting/understanding-postgresql-explain-output-Un9dqX)
- [pgMustard: Actual Total Time](https://www.pgmustard.com/docs/explain/actual-total-time)
- [Couchbase: Query Workbench](https://docs.couchbase.com/server/current/tools/query-workbench.html)
- [Couchbase: Monitor Queries](https://docs.couchbase.com/server/current/tools/query-monitoring.html)
- [DZone: New Profiling and Monitoring in Couchbase Server 5.0](https://dzone.com/articles/new-profiling-and-monitoring-in-couchbase-server-5)
- [MongoDB: Database Profiler Output](https://www.mongodb.com/docs/manual/reference/database-profiler/)
- [MongoDB: Explain Results](https://www.mongodb.com/docs/manual/reference/explain-results/)
- [Microsoft Learn: SQL Server Profiler — View and analyze traces](https://learn.microsoft.com/en-us/sql/tools/sql-server-profiler/view-and-analyze-traces-with-sql-server-profiler?view=sql-server-ver17)
- [Real World DBA: SQL Profiler — Duration in Milliseconds, or Microseconds…Which is it?](https://realworlddba.wordpress.com/2012/08/13/sql-profiler-duration-in-milliseconds-or-microseconds-which-is-it/)
