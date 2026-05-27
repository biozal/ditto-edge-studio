# DQL `PROFILE` — Engineering Reference

Edge Studio captures and displays the execution profile that Ditto
emits when a DQL statement is prefixed with the `PROFILE` keyword.
This document covers the on-the-wire envelope, the Swift data model,
where the code lives, and the design decisions that aren't obvious
from reading any one file.

For the user-facing description, see
**[Resources/Help/UserGuide.md](../SwiftUI/EdgeStudio/Resources/Help/UserGuide.md)**
→ "Collections & Query → Execution Profile".

For the original design discussion, see
**[plans/dql-profile-feature.md](../plans/dql-profile-feature.md)**.

For Ditto's own (sparse) docs, see
**<https://docs.ditto.live/dql/profile>**.

---

## What `PROFILE` does on the wire

Prepend `PROFILE` to any DQL `SELECT` and Ditto:

1. Executes the statement normally.
2. Appends one extra item to the result set with a single key,
   `~request_profile`, whose value is the profile envelope.
3. Returns the combined set to the SDK caller.

The `~` prefix on the key is Ditto's convention for "system row" —
the same convention used for the `_id` field. It's there so callers
can detect and strip the row without confusing it with a user
document.

`PROFILE` only supports `SELECT` today. Prefixing it onto `INSERT`,
`UPDATE`, `DELETE`, `EVICT`, or `ALTER SYSTEM` raises a syntax error.
Edge Studio detects this via `QueryService.isSelectStatement` and
won't inject the prefix on non-SELECT statements.

---

## Envelope shape

The worked example from the spec (real Ditto output, lightly
formatted):

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
    "times": {
      "elapsed": 1294166,
      "parse": 49834,
      "plan": 32167,
      "start": "2026-05-26T20:59:21.310-05:00"
    }
  }
}
```

### Top-level fields

| Field | Type | Notes |
|---|---|---|
| `_id` | UUID string | Profile-request identifier. Stable per execution. |
| `app_id` | UUID string | Ditto database ID. Maps to `DittoConfigForDatabase.databaseId`. |
| `featureFlags` | hex string | Server-side feature flags active at execution. Surfaced as-is in the UI summary strip. |
| `plan` | object | Root of the operator tree. Required. |
| `queryType` | string | `"select"` (the only supported query type today). |
| `requestType` | string | `"SDK"` for local execution, would be `"HTTP"` if profiling ever supports that path. |
| `resultCount` | int | Number of user-facing rows (does not include the `~request_profile` row itself). |
| `state` | string | `"completed"` on success. Anything else means partial / aborted. |
| `text` | string | The statement Ditto saw — includes the leading `PROFILE`. The Swift UI strips this prefix when re-displaying the query. |
| `times` | object | Top-level timings (see below). |

### `times` object

| Field | Unit | Description |
|---|---|---|
| `elapsed` | nanoseconds | Total wall-clock time end-to-end. |
| `parse` | nanoseconds | Time spent parsing the statement to an AST. |
| `plan` | nanoseconds | Time spent planning (operator selection, optimisation). |
| `start` | ISO 8601 string | Server-side instant the request started. Preserved as a raw string for round-trip fidelity. |

### Plan operator nodes

Every node in the `plan` tree has the same shape:

| Field | Required | Notes |
|---|---|---|
| `#operator` | yes | Operator type name (`scan`, `sequence`, `limit`, `finalProjection`, …). |
| `#stats` | no | Throughput + per-phase timings. Hidden on operators that don't produce stats. |
| `children` | no | Array of child operator nodes (recursive). Absent on leaves. |
| `<other keys>` | varies | Operator-specific attributes (`collection`, `alias`, `datasource`, `limit`, `descriptor`, …). |

The `#` prefix on `#operator` and `#stats` distinguishes the
control fields from operator-specific attributes, so callers can
strip them at parse time without needing to enumerate the operator
catalogue.

### `#stats` block

| Field | Unit | Description |
|---|---|---|
| `documentsIn` | int | Documents flowing into this operator from upstream. Omitted on data-source operators (e.g. `scan`). |
| `documentsOut` | int | Documents flowing out to downstream. Omitted on operators that don't materialise. |
| `phaseTimes.exec` | ns | CPU time inside the operator. |
| `phaseTimes.recv` | ns | Time waiting on upstream operators to feed input. |
| `phaseTimes.send` | ns | Time pushing output to downstream operators. |

Phases are **disjoint** on the operator's own execution thread —
summing `exec + recv + send` gives the total wall-time the operator
occupied without double-counting. The Plan view's "total time" per
box uses exactly this sum.

---

## Time-unit convention

**All times are nanoseconds at source.** Verified by reading the
Rust source:

- `ditto-v5/crates/ditto-dql/src/engine/caches/request.rs`
  - `set_parse_time(ns: u128)` → stores `ns as u64`
  - `set_plan_time(ns: u128)` → stores `ns as u64`
  - `elapsed()` → `self.mark.elapsed().as_nanos() as u64`
  - Per-operator phase times (`OpState::Exec` / `Recv` / `Send`)
    use `mark.elapsed().as_nanos() as u64` at line 105

So a `times.elapsed` value of `1_294_166` is 1.29 ms; an operator's
`exec` of `209` is 209 ns. Don't apply any further scaling at the
parse layer — the formatter is the only thing that does unit
conversion.

### Display tiers

`Utilities/ProfileTimeFormatter.swift` formats raw ns values via a
three-tier auto-scale, picked per-value:

| Raw value | Display | Example |
|---|---|---|
| ≥ 1,000,000 ns (≥ 1 ms) | `%.2f ms` | `432.43 ms` |
| 1,000 – 999,999 ns | `%.2f µs` | `55.56 µs` |
| < 1,000 ns | `%d ns` | `209 ns` |

The middle µs tier is the load-bearing one. Without it, sub-ms
values either collapse to `0.056 ms` (Postgres style — hides
precision behind decimals) or expand to `55560 ns` (a five-digit
run that's hard to scan). The µs tier matches MongoDB's profiler
and SQL Server Profiler conventions.

For the cross-platform research that drove the choice, see the
**"Time format research"** section at the bottom of
[plans/dql-profile-feature.md](../plans/dql-profile-feature.md).

---

## Operator catalog

These are the operators Edge Studio has seen in practice. The list
is open-ended — Ditto can introduce new operator types, and the
parser handles unknown names gracefully (the box just shows the
name and any attributes it returned).

| Operator | Common attributes | What it does |
|---|---|---|
| `sequence` | (none) | Parent that runs its children in order. Root of most plans. |
| `scan` | `collection`, `datasource`, `alias`, `descriptor` | Reads documents from a collection. Leaf node. |
| `limit` | `limit` | Caps the number of rows passed to the parent. |
| `projection` / `finalProjection` | `alias`, term list | Reshapes the output document — picks fields, computes expressions. |
| `filter` | predicate | Drops documents that don't satisfy a WHERE clause. |
| `sort` | sort spec | Orders documents before passing them upward. |
| `aggregate` | grouping keys, expressions | GROUP BY / aggregations. |
| `join` | join condition | Combines streams from multiple children. |

`scan` operators are typically the heaviest because they pay the
read cost. A `scan` whose `recv` is large is waiting on disk; a
`scan` whose `exec` is large is doing heavy in-process work
(decryption, deserialisation). The Plan view's orange hotspot
highlight (50% threshold) is most useful for spotting an outlier
`scan` in a multi-`scan` query.

---

## Where the code lives

```
SwiftUI/EdgeStudio/
├── Models/
│   └── QueryProfile.swift                       ← QueryProfile / QueryProfileTimes /
│                                                  QueryProfileOperator / QueryProfileStats
├── Data/
│   ├── QueryService.swift                       ← executeSelectedAppQueryWithProfile,
│   │                                              isSelectStatement, alreadyHasProfilePrefix
│   └── QueryProfileParser.swift                 ← [String: Any] → QueryProfile
├── Utilities/
│   └── ProfileTimeFormatter.swift               ← ns → ms/µs/ns + percentOfTotal
├── Components/
│   └── ProfileViewer/
│       ├── ProfileViewerView.swift              ← Profile tab orchestrator
│       │                                          (4 states + Card/Plan sub-picker)
│       ├── ProfileQueryHeaderCard.swift         ← Query text + captured-at timestamp
│       ├── ProfileSummaryStrip.swift            ← ELAPSED/PARSE/PLAN/RESULT/FLAGS/TYPE
│       ├── ProfileStatsBadges.swift             ← Coloured in/out/exec/recv/send pills
│       ├── ProfileOperatorCard.swift            ← Card-mode single operator card
│       ├── ProfileCardListView.swift            ← Card-mode recursive nesting
│       ├── PlanNodeBox.swift                    ← Plan-mode rounded box + hotspot
│       ├── ProfilePlanTreeView.swift            ← Plan-mode recursive tree
│       │                                          with T-junction connectors
│       └── ProfileFooterStrip.swift             ← profile UUID · db ID · state
└── Views/
    ├── Settings/AppPreferencesView.swift        ← Collect Metrics toggle (existing)
    └── StudioView/ViewModels/QueryViewModel.swift  ← latestProfile state
```

Test coverage lives in
`SwiftUI/EdgeStudioUnitTests/Models/QueryProfileParserTests.swift`
(parser) and the `ProfileInjectionTests` suite inside
`SwiftUI/EdgeStudioUnitTests/Services/QueryServiceTests.swift`
(SELECT detection, PROFILE-prefix detection).

---

## Parsing edge cases

`QueryProfileParser.parseItem(_:)` is intentionally forgiving:

- **Empty / missing envelope** → returns `nil`. Caller treats nil as
  "PROFILE didn't fire" rather than throwing.
- **User document where `~request_profile` is absent** → returns
  `nil`. This is what every non-trailing row looks like.
- **Bare profile dict without the `~request_profile` wrapper** →
  still parses. Defensive against future SDK changes that might
  strip the wrapper.
- **Missing `_id` or `plan`** → returns `nil`. These two fields are
  the hard requirements; without them there's nothing useful to
  show.
- **Missing `times`** → returns a profile with `elapsedNs = parseNs
  = planNs = 0` and `startISO = ""`. The summary strip renders
  `0 ns` rather than crashing.
- **Operator node without `#operator`** → that subtree is dropped.
  An incomplete plan still parses; the rest of the tree shows.
- **Unknown attribute types** (e.g. nested objects, arrays) →
  re-encoded as compact sorted-keys JSON via `JSONSerialization`.
  The card view displays them inline.

Attributes are sorted alphabetically inside each operator node so
the same query renders the same way every time — important for
snapshot-style visual regression testing and avoids cosmetic
churn when Ditto reorders dictionary keys internally.

---

## Capture gating

`executeSelectedAppQueryWithProfile` only injects the `PROFILE`
prefix when **all** of these hold:

1. `UserDefaults.standard.bool(forKey: "metricsEnabled") == true`
   (the existing **Collect Metrics** Settings toggle).
2. `QueryService.isSelectStatement(query) == true`
   (statement starts with `SELECT` after trimming whitespace; case-
   insensitive; word-boundary checked so `SELECTOR` doesn't match).
3. `QueryService.alreadyHasProfilePrefix(query) == false`
   (user hasn't typed `PROFILE` manually — running
   `PROFILE PROFILE SELECT …` is a syntax error).

If any condition fails, the query runs unmodified and `.profile`
returns `nil`. The `ProfileViewerView` then renders one of four
empty states (metrics off / non-SELECT / no query yet / populated)
based on the inputs the parent passes in.

---

## What's deliberately out of scope (v1)

- **HTTP transport.** Profile capture only fires on the local
  store execution path. `executeSelectedAppQueryHttp` doesn't get
  PROFILE injection because Ditto's HTTP API's PROFILE support is
  unverified.
- **Profile history.** Every new run overwrites the previous
  profile. Query Metrics already handles "history of query
  performance"; a profile history would duplicate that surface
  with much heavier per-row payloads.
- **Profile diff / comparison.** Useful for regression hunting but
  a separate, larger feature.
- **Plan-view zoom / pan controls.** v1 relies on the parent
  ScrollView. Add explicit zoom controls if user feedback asks
  for them.
- **CTE detection (`WITH … SELECT …`).** Plan skips this for v1
  because DQL CTE support is unclear and `isSelectStatement`
  errs on the side of "not a SELECT".
- **Per-operator-type colors.** Plan view uses a single
  "is-bottleneck" highlight; per-operator-type palettes are an
  aesthetic polish for later.
