# Log Analyzer — cross-platform specification

**Normative for:** SwiftUI (`ditto-edge-studio/SwiftUI`), Android
(`ditto-edge-studio/android`), VS Code extension (`~/Developer/ditto-vsc-es`).

This document is the single source of truth for the Log Analyzer's *numeric and
semantic* behaviour. Three independent implementations produce these values;
this file is what keeps them from drifting. Change a value here and in all three
implementations in the same change, or not at all.

Implementation status: SwiftUI ✅ · Android ⬜ · VS Code ✅ (source of the values).

---

## 1. The SDK emits the same event in two encodings

This is the single most important fact in this document, and it is not obvious
from any one platform's code.

**Live callback** — `DittoLogger.setCustomLogCallback` (Swift / Kotlin) and the
JS `Logger.setCustomLogCallback` deliver a **flattened text** line whose body
carries `key=value` pairs:

```
physical connection started remote=pkAocCgkMCE7bZkwH9tXQR0uyd3Mg_GvIWqKfsdJ9RdWb0otzL2_8 role=Client transport_type=Awdl connection_id=9
```

**Rotating log files** — `<persistence>/ditto_logs/*.log(.gz)` are **JSON
Lines**. The message field holds only the bare verb; the interesting fields are
its siblings:

```json
{"timestamp":"2026-09-05T20:44:02.068216Z","level":"INFO","message":"physical connection started","remote":"pkAocCgkMCE7bZkwH…","role":"Client","transport_type":"Awdl","connection_id":"9","target":"ditto_multiplexer::connection"}
```

A `remote=([^\s]+)`-style regex therefore matches **nothing** in the file
encoding. Verified on a real capture: a 3 531-line `ditto-logs-*.log` containing
4 `physical connection started` records has **zero** occurrences of
`transport_type=`, `remote=`, or `role=`.

Any platform that reads both sources — SwiftUI and Android both do — must try
the structured form first and fall back to the flattened one. SwiftUI implements
this in `LogConnectionEvent.extract(from:)`; the JSON text is available verbatim
on `LogEntry.rawLine`.

The VS Code extension only ever sees the flattened encoding (its analyzer reads
the extension's own `Logger` stream), which is why `ConnectionTracker.ts` gets
away with regex alone.

### Records that must not be double counted

| Message | Level | Treatment |
|---|---|---|
| `physical connection started` | INFO | session open |
| `physical connection ended` | INFO | session close |
| `physical connection ended (extended info)` | DEBUG | **ignore** — duplicates the INFO close |
| `Physical connection shutting down` | DEBUG | **ignore** — not a lifecycle edge |

### The re-init marker is `starting Ditto`, not `ditto_init` — **verified**

`ConnectionTracker.ts` matches `/ditto_init/` against the whole line to detect a
Ditto restart. That token is the wrong signal. Measured over **all 31** real
captures under
`~/Library/Containers/com.costoda.dittoedgestudio/…/ditto_logs/*.log(.gz)`
(663 807 JSON Lines records, rotated `.gz` files decompressed and included):

| Signal | Occurrences |
|---|---|
| `ditto_init` anywhere on the raw line | **399** — all inside `span` / `spans` / `path` values |
| `ditto_init` in the **`message`** field | **0** |
| a record with **no `message` key** that mentions `ditto_init` | **11** |
| `"starting Ditto"` in the **`message`** field | **14** |

So a whole-line `/ditto_init/` match would close every open session 399 times
over, and scoping that same token to the message field makes it fire **never**.
The marker in the file encoding is the SDK's own init record:

```json
{"timestamp":"…","level":"INFO","message":"starting Ditto...","app_id":"…","sdk.version":"5.1.0",…}
```

Present in **both** encodings — the live callback emits
`ditto_init: starting Ditto... sdk.version=…` — so one message-scoped
`starting Ditto` probe covers both.

**Re-init detection is verified.** These are genuine init markers, not noise:

- Each `starting Ditto` is one real init; there are **14** across the captures
  and none in a non-init context.
- Where the SDK also emits the `{"span":{"name":"ditto_init"},…}` DEBUG record,
  it precedes `starting Ditto` by **5.3–24.4 ms** — the same event.
- The gap between the previous log line and the init is **≤ 7 ms at all 14**
  inits (0.0 minutes). `ditto_init` fires when the user *switches databases*, not
  when the app dies: the process keeps running and keeps logging, so a connection
  still open at that instant genuinely lasted right up to it, and closing it
  there records an **accurate** duration.

**A `ditto_init` re-init therefore closes every open session at that instant**
(§5). Measured impact of doing so, over the same captures:

| | closed sessions | `0–1s` | `1–5s` | `5–30s` | `30s–5m` | `5m+` |
|---|---|---|---|---|---|---|
| not closing on re-init | 386 | 144 | 146 | 48 | 48 | **0** |
| closing on re-init | **414** | 144 | 146 | 48 | 54 | **22** |

28 sessions that previously stayed open forever — never given a duration, never
binned — now appear, and the entire `5m+` bucket is among them. The longest is a
**22.9-hour** connection, which is exactly the thing a user opens that chart to
confirm.

### Fractional seconds are a *fraction*, not milliseconds

Both rows above bin on correctly parsed timestamps. That is worth stating,
because Android's `LogFileParser` did not produce them. It parsed the SDK's
`.log(.gz)` timestamps with `SimpleDateFormat`, whose `S` pattern letter means
**milliseconds**, not fraction-of-second. The pattern
`yyyy-MM-dd'T'HH:mm:ss.SSSSSS'Z'` — tried first, and matching every `ditto_logs`
record, all of which carry 6 fractional digits — therefore read
`2026-09-05T20:43:51.784135Z` as `20:43:51` **plus 784 135 ms**, i.e. `20:56:55`,
13 m 04 s late. Every duration, the analysis time range, both histograms and the
date filter were built on that.

Measured over the same 32 captures, all four combinations:

| re-init closing | timestamps | closed | `0–1s` | `1–5s` | `5–30s` | `30s–5m` | `5m+` |
|---|---|---|---|---|---|---|---|
| off | broken | 386 | 164 | 4 | 20 | 133 | 65 |
| off | correct | 386 | 144 | 146 | 48 | 48 | 0 |
| on | broken | 414 | 164 | 4 | 21 | 135 | 90 |
| **on** | **correct** | **414** | **144** | **146** | **48** | **54** | **22** |

The two defects are independent: closing on re-init adds the same **+28**
sessions under either timestamp regime. The timestamp defect is the larger
distortion of the *shape* — it emptied the `1–5s` bucket (4 against a true 146)
and inflated `5m+` four-fold (90 against a true 22), because a sub-second
connection whose two edges each gain a different sub-second offset can land
anywhere.

**Do not parse these timestamps with `SimpleDateFormat`.** `java.time`
(`Instant.parse` / `OffsetDateTime.parse`) reads 0–9 fractional digits correctly;
SwiftUI's `ISO8601DateFormatter` with `.withFractionalSeconds` already did.

#### Do not key on the absence of a `message` field

A tempting alternative is the parser artefact: 22 records across the captures
carry no `message` key, `LogFileParser`/`LogEntry` then falls back to putting the
whole raw JSON line in `message`, and `ditto_init` shows up there. **It is not
1:1 with init** — it fires 11 times against 14 real inits. The three it misses
(`mongodb sample`, `mongodb-movies`, `quickstarts/…-21-31-02`) contain the
`starting Ditto...` INFO record but no `ditto_init` span record at all. Key on
`starting Ditto`, which is a strict superset and is semantically the init rather
than an artefact of a fallback.

---

## 2. Counting semantics

| Field | Definition |
|---|---|
| `totalLines` | entries in the analysis window |
| `errors` / `warnings` | entries whose **level** is error / warning |
| `problems` | pattern **matches** — a line matched by 3 patterns contributes 3 |
| `problemEntries` | **distinct entries** with ≥1 match |
| `critical` | matches whose pattern severity is 5 |
| `criticalEntries` | **distinct entries** with ≥1 severity-5 match |

**Filter-tab badges MUST use `problemEntries` / `criticalEntries`.** The
Problems tab can only list distinct entries, so a badge sourced from `problems`
promises rows the table cannot render. The Summary header shows `problems` and
`critical`, which are the honest "how much went wrong" totals.

VS Code names these `problemLines` / `criticalLines`; SwiftUI names them
`problemEntries` / `criticalEntries` because its unit is a `LogEntry`. Same
meaning.

### Analysis window

Analytics must be computed over **exactly** the window the pattern scan covered.
Computing counts over the full buffer while scanning only its tail reports a line
total the problem counts were never measured against.

| Platform | Window |
|---|---|
| SwiftUI | `LogPatternEngine.maxScanEntries` = 5 000 (newest) |
| Android | `LogPatternEngine.MAX_SCAN_ENTRIES` = 5 000 (newest) |
| VS Code | `LINE_BUFFER_CAP` = 50 000 (newest), maintained incrementally |

---

## 3. Filter tabs

| Tab | Predicate | Badge |
|---|---|---|
| All | everything | `totalLines` |
| Critical | entry has a severity-5 match | `criticalEntries` |
| Errors | `level == error` | `errors` |
| Warnings | `level == warning` | `warnings` |
| Problems | entry has ≥1 match | `problemEntries` |

Every tab except **All** already constrains the level, so the per-level filter
chips must be suppressed while one is active. Leaving both live lets a stale chip
selection silently subtract rows from the tab the user just picked, which reads
as a broken filter rather than as two filters disagreeing.

---

## 4. Histogram binning

### Time-bin width

Pick the **finest** candidate whose width keeps the bucket count at or below the
target across the full time range.

```
candidatesMs = [1000, 5000, 30000, 60000, 300000, 600000, 1800000]
targetBuckets = 40
want = max(rangeMs, 1) / targetBuckets
width = first candidate >= want, else last candidate
```

| Range | Width |
|---|---|
| 1 s | 1 s |
| 40 s | 1 s |
| 200 s | 5 s |
| 20 m | 30 s |
| 40 m | 60 s |
| 13.7 h | 30 m |
| beyond the ladder | 30 m (clamped) |

A bin's start is `floor(epochMs / width) * width`. Bins are emitted in ascending
time order — they are accumulated in a hash map on every platform, whose
iteration order is not stable.

### Log Volume by Level

One stacked bar per time bin, one segment per level. Segment order must be fixed
(`verbose, debug, info, warning, error`, bottom to top) so the stack does not
reshuffle between refreshes.

### Problems over Time

One bar per time bin. Height is the match count in that bin; color is the bin's
**maximum** severity.

### Connection Durations

Half-open buckets — a duration exactly on a boundary belongs to the **next**
bucket up.

| Label | Range |
|---|---|
| `0–1s` | `d < 1` |
| `1–5s` | `1 ≤ d < 5` |
| `5–30s` | `5 ≤ d < 30` |
| `30s–5m` | `30 ≤ d < 300` |
| `5m+` | `d ≥ 300` |

Only **closed** sessions are bucketed; an open session has no duration. Empty
buckets are still rendered so the axis does not reflow as data arrives.

---

## 5. Connection session pairing

- Key on **`connection_id`** when both the open and close carry one; fall back to
  `remote::role` otherwise (what VS Code keys on).
- Match the **most recently opened** session with that key, not the oldest. The
  SDK reuses `connection_id` values, so first-match pairing closes the wrong
  session and reports a wrong duration for both.
- A `ditto_init` re-init closes every open session at that instant. Detect it
  with a **message-scoped** `starting Ditto` probe, never a whole-line
  `ditto_init` match — see §1 for the measurement.
- An `ended` with no matching open is counted as `unmatchedEnds`, not dropped.

### Bounds (all of these were bugs before they were bounds)

`closed`, `open`, **and** the re-init timestamp list are each capped at 1 000
entries, trimmed in chunks so the per-event cost stays amortized O(1). The
`open` cap matters most: a `started` whose `ended` never arrives — killed
process, truncated log, a phrasing the close regex misses — otherwise leaks for
the life of the view.

`reset()` must clear **every** array. Clearing only some makes "Clear" appear to
work until the next connection event resurrects the pre-Clear sessions, because
the session list is rebuilt from these arrays rather than from what the view last
displayed.

---

## 6. Palette

| Level | Hex | | Severity | Hex |
|---|---|---|---|---|
| error | `#ff5252` | | 5 critical | `#ff5252` |
| warn | `#d4a017` | | 4 high | `#ff8a52` |
| info | `#4ea1ff` | | 3 medium | `#d4a017` |
| debug | `#888888` | | 2 low | `#4ea1ff` |
| trace/verbose | `#555555` | | 1 info | `#888888` |

User-tag chip: `#b08fff`.

---

## 7. Other pinned values

- **SDK version** — the first line containing `sdk.version=`; the value is the
  non-whitespace run after the `=`. Latched: later lines do not overwrite it, and
  the probe is skipped once a version is found.
- **Tags** — the distinct component/tag labels in the window, sorted.
- **Range** — `HH:mm:ss → HH:mm:ss (Nh)`, with the duration rendered as `<1s`,
  `45s`, `1.5m`, `1.5h`, or `1.5d`.
- **Pause** — freezes the *display* only. Ingestion continues into the capture
  buffers (which are capped), so nothing is lost and resuming shows the full
  picture rather than a gap.
- **Row context** — expanding a row shows the 5 entries either side of it,
  sliced from the **unfiltered** source buffer. Slicing the filtered list
  instead makes the feature useless: expanding an error in the Errors tab would
  show five other errors rather than the lines that explain it. Expansion state
  belongs to the list's owner, not the row — a row cannot reach the unfiltered
  buffer, and per-row state does not survive a re-parse (which mints new entry
  ids). One row open at a time.

---

## 8. Log file locations

| Platform | SDK log directory |
|---|---|
| macOS / iOS | `<persistenceDir>/ditto_logs/` — with a `logs/` fallback for older SDK layouts |
| Android | `<cacheDir>/ditto_logs/` |

Reading only `logs/` returns zero entries on every current build. Verified: all
five persistence directories under
`~/Library/Containers/com.costoda.dittoedgestudio/…/ditto_edge_studio/` contain
`ditto_logs/` and none contain `logs/`.

---

## 9. Pattern catalog

`problem_patterns.json` is already byte-identical across the three repos (13
bundled keys) and is the existing precedent for cross-platform sharing:

| Platform | Path |
|---|---|
| VS Code | `src/logAnalyzer/patterns/problem_patterns.json` |
| SwiftUI | `SwiftUI/EdgeStudio/Resources/problem_patterns.json` |
| Android | `android/app/src/main/assets/problem_patterns.json` |

Adding a pattern means adding it to all three in the same change.

Engine semantics (already at parity): the regex matches the **message body**
case-insensitively; `level_filter` is **exact** equality, not "at least", so
tiered patterns stay mutually exclusive; `tag_filter` is a case-sensitive regex
against the entry's tag/component; user patterns are capped at 512 characters and
rejected if they nest a quantifier inside a quantified group.

---

## 10. Component classification

The entry's component is both a filter and the `tag_filter` input for §9, so a
divergence here changes row counts *and* which patterns fire.

Transcribed from SwiftUI (`Models/LogEntry.swift`) and verified against Android
(`domain/model/LogEntry.kt`). **The VS Code extension's classifier was not
audited for this section** — check it before relying on this as tri-platform.

**The substring list and its order are normative.** Match the first branch that
hits, top to bottom; the value is lowercased first.

### From the `target` field (file encoding)

`sync` → Sync · `replication` → Sync · `subscription` → Sync · `store` → Store ·
`service=blob` → Store · `query` → Query · `sqlparser` | `sql_parser` → Query ·
`observer` → Observer · `transport` · `discovery` · `presence` · `multihop` ·
`network` · `ble` · `tcp` · `awdl` · `virtual_connection` · `router` → Transport ·
`auth` → Auth · otherwise **Other**.

Order is load-bearing: `ditto_sync::query_planner` is Sync, not Query, and
`ditto_transport::auth_handshake` is Transport, not Auth.

Measured over the 33 real captures under
`~/Library/Containers/com.costoda.dittoedgestudio/…/ditto_logs/` — 746 282 JSON
Lines records, rotated `.gz` files decompressed and included — Android's older
6-substring list (`sync`, `store`, `query`, `observer`,
`transport`/`network`/`bluetooth`/`wifi`, `auth`) misfiled **866** records that
SwiftUI classified as Transport:

| `target` | records |
|---|---|
| `ditto_discovery_mdns` | 571 |
| `ditto_discovery_multicast::interface` | 157 |
| `ditto_discovery_multicast` | 119 |
| `ditto_presence::multihop::manager` | 18 |
| `ditto_discovery_mdns::platform::bonjour::browser` | 1 |

Transport totals across those captures: **4 233** with the full list, **3 367**
with the short one — 20% of the Transport rows lost their component.

**A blank `target` is `Other` on SwiftUI**, which calls `from(target:)`
unconditionally. Android falls back to the message heuristic below. Every one of
the 746 282 records carries a non-blank `target`, so the two cannot disagree on
SDK log files; Android keeps the fallback because it also serves its Timber
app-log parser, which has no SwiftUI counterpart.

### From the message body (live-callback encoding)

`sync` · `replication` · `subscription` → Sync · `store` | `insert` | `document`
→ Store · `service=blob` → Store · **prefix** `add_ble_transport` |
`start_tcp_server` | `add_awdl_transport` | `add_wifi_transport` → Transport ·
`tcp` → Transport · `awdl` → Transport · `query` | `select` → Query · **prefix**
`parsing sql` | `sql parser` → Query · `observer` → Observer ·
`transport` | `bluetooth` | `wifi` → Transport · `discovery` | `mdns` →
Transport · `presence` | `multihop` → Transport · `ble_` | <code>&nbsp;ble</code>
(space-prefixed, to avoid matching inside words) → Transport ·
`virtual_connection` → Transport · `router_` → Transport · `auth` | `token` →
Auth · otherwise **Other**.

The six transport probes **above** `query` are the reason the order is pinned:
the flattened callback line for an SDK transport operation routinely contains the
word "query" in its body, and without them those lines are filed under Query. The
generic `transport` branch is *below* `query`, so a message that merely mentions
both — `[transport::bluetooth] Discovered query endpoint` — is **Query** on every
platform.
