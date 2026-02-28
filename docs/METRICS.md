# Metrics Feature

**Last Updated:** 2026-02-27

This document describes the Metrics feature in Edge Studio: what is measured, how data is collected, how the two views differ, and how the optional Prometheus export works.

---

## Table of Contents

1. [Overview](#overview)
2. [What Is and Is Not Counted](#what-is-and-is-not-counted)
3. [Data Collection Architecture](#data-collection-architecture)
4. [App Metrics View](#app-metrics-view)
   - [Process Section](#process-section-macos-only)
   - [Queries Section](#queries-section)
   - [Storage Section](#storage-section)
5. [Query Metrics View](#query-metrics-view)
6. [Prometheus Export](#prometheus-export)
7. [Data Lifecycle](#data-lifecycle)
8. [Key Files](#key-files)

---

## Overview

The Metrics feature provides two complementary views accessible from the sidebar under **Metrics**:

| View | What it shows |
|------|--------------|
| **App** | Live process health (memory, CPU, uptime) and aggregate query statistics for the current session |
| **Query** | A per-query log of every DQL statement executed from the query editor, with latency and EXPLAIN output |

Both views display only in-session data. Nothing is persisted to disk and nothing carries over between app launches.

---

## What Is and Is Not Counted

**Only queries you explicitly run from the query editor are counted.** Specifically, only calls that go through `QueryService.executeSelectedAppQuery()` are recorded.

The following internal queries run automatically and are **intentionally invisible** to the metrics system — they call `ditto.store.execute()` directly, bypassing `QueryService`:

| Query | Trigger | Where |
|-------|---------|--------|
| `SELECT * FROM __collections` | Every database open | `CollectionsRepository.hydrateCollections()` |
| `SELECT COUNT(*) as numDocs FROM {collection}` | Every database open, once per collection | `CollectionsRepository.fetchDocumentCounts()` |
| `SELECT * FROM system:data_sync_info` | Every peer connect/disconnect event | `SystemRepository.registerSyncStatusObserver()` |
| `SELECT ditto_sdk_language, ... FROM __small_peer_info` | Once on database open | `MainStudioView` startup task |

This boundary is intentional: Query Metrics is a tool for understanding your DQL queries, not a log of internal app housekeeping.

**Also not counted:** HTTP-mode queries (`executeSelectedAppQueryHttp()`) are never recorded. Only local `ditto.store.execute()` calls routed through `QueryService` appear in the metrics.

---

## Data Collection Architecture

### InMemoryMetricsStore (actor)

The central store. Defined in `Data/MetricsBackend.swift`.

- Maintains two internal dictionaries: `counters` (running totals) and `samplesByLabel` (timestamped ring buffers)
- Each label's ring buffer holds at most **120 samples** (~2 minutes at 1 sample/second)
- Thread-safe via Swift actor isolation
- All writes are fire-and-forget via `Task.detached(priority: .utility)` to avoid blocking the query actor

**Labels in use:**

| Label | Type | Description |
|-------|------|-------------|
| `edge_studio.queries.total` | Counter | Incremented once per executed query |
| `edge_studio.query.latency_ms` | Timer | Records execution time in milliseconds per query |

### AppMetricsCounter / AppMetricsTimer

Thin structs that wrap a label name and dispatch writes to `InMemoryMetricsStore` on a background task. Created as stored properties of `QueryService`:

```swift
private let queryCounter = AppMetricsCounter(label: "edge_studio.queries.total")
private let queryTimer   = AppMetricsTimer(label: "edge_studio.query.latency_ms")
```

### Write path in QueryService

Every call to `executeSelectedAppQuery()` does the following around `ditto.store.execute()`:

```swift
let startDate = Date()
let results = try await ditto.store.execute(query: query)
let elapsedMs = Date().timeIntervalSince(startDate) * 1000.0

queryCounter.increment()                  // → edge_studio.queries.total + 1
queryTimer.recordMilliseconds(elapsedMs)  // → edge_studio.query.latency_ms sample
```

After recording to the aggregate store, `QueryService` also captures a full `QueryExplainRecord` in `QueryMetricsRepository` (see [Query Metrics View](#query-metrics-view)).

---

## App Metrics View

**File:** `Views/Metrics/AppMetricsDetailView.swift`

Displays a grid of `MetricCard` components, auto-refreshing every **15 seconds**. Each card shows the current value and a sparkline chart of recent samples where applicable.

### Process Section (macOS only)

These are read synchronously via Darwin kernel APIs in `MetricsRepository.processMetricSnapshot()`:

| Card | Source | API |
|------|--------|-----|
| **Resident Memory** | `mach_task_basic_info.resident_size` | `task_info(MACH_TASK_BASIC_INFO)` |
| **Virtual Memory** | `mach_task_basic_info.virtual_size` | `task_info(MACH_TASK_BASIC_INFO)` |
| **CPU Time** | User time + system time across all threads | `task_info(TASK_THREAD_TIMES_INFO)` |
| **Open File Desc.** | Count of valid file descriptors 0–1023 | `fcntl(F_GETFL)` |
| **Process Uptime** | `Date().timeIntervalSince(MetricsRepository.appStartDate)` | Captured at first access ≈ app launch |

> **Note on Process Uptime:** The static `appStartDate` property on `MetricsRepository` is initialised the first time the enum is accessed (effectively at app launch). It does **not** use `ProcessInfo.processInfo.systemUptime`, which would report how long the Mac has been running since its last boot, not how long Edge Studio has been running.

### Queries Section

These are read asynchronously from `InMemoryMetricsStore` via `MetricsRepository.queryMetricSnapshot()`:

| Card | Derivation |
|------|-----------|
| **Total Queries** | Latest value of `edge_studio.queries.total` counter |
| **Avg Latency** | Mean of all `edge_studio.query.latency_ms` samples in the ring buffer |
| **Last Latency** | Most recent `edge_studio.query.latency_ms` sample |

The **Avg Latency** card also renders a sparkline chart from the raw latency sample array, giving a visual history of query performance over the last ~2 minutes.

### Help Popovers

Every `MetricCard` optionally accepts `helpText` and `helpURL` parameters. When provided, a faint `?` button appears in the card header. Tapping it opens a popover with a plain-language explanation of the metric and, for memory and CPU cards, a link to the relevant Apple developer documentation.

### Storage Section

Displays disk usage for the currently selected Ditto database, broken down by directory category and by individual collection. All values are read from the local filesystem via `ditto.diskUsage.exec` — no network query, no sync delay.

**Data source:** `ditto.diskUsage` (from the `DittoDiskUsage` module). Returns a `DiskUsageItem` tree rooted at the Ditto data directory (e.g. `~/Library/Application Support/DittoEdgeStudio/`). The tree is flattened into `(path, sizeInBytes)` tuples and categorized by `StorageRepository.categorizeFiles(_:)`.

#### Directory Categories

The categorization is based on the Ditto SDK's actual on-disk directory layout. **WAL/SHM files are checked first** to prevent double-counting — e.g. `ditto_store/db.sql-wal` is a WAL file, not a store file.

| Card | Matched paths | What it contains |
|------|--------------|-----------------|
| **Store** | path contains `/ditto_store/` | SQLite document store (`db.sql` and its files) |
| **Replication** | path contains `/ditto_replication/` | Per-peer sync state: one SQLite DB per known remote peer under `ditto_replication/{localKey}/{peerKey}/db.sql` |
| **Attachments** | path contains `/ditto_attachments/` | Binary attachment blobs stored in `ditto_attachments/db.sql` |
| **Auth** | path contains `/ditto_auth` | Identity and capability token files in `ditto_auth/` and `ditto_auth_tmp/` (matched with substring, covers both directories) |
| **SQLite WAL/SHM** | suffix `-wal` or `-shm` | SQLite Write-Ahead Log and Shared Memory journal files for any SQLite database |
| **Logging** | path contains `/ditto_logs/` **or** suffix `.log` **or** suffix `.log.gz` | Ditto log files including gzip-compressed archives |
| **Other** | anything not matched above | `ditto_metrics/`, `ditto_system_info/`, lock files, etc. |

> **Log detection note:** The log condition uses `/ditto_logs/` (not `/logs/`) to match Ditto's actual directory name. Both `.log` and `.log.gz` suffixes are checked so compressed archives are included.

#### `DiskBreakdown` struct

`StorageRepository.categorizeFiles(_:)` returns a `DiskBreakdown` value:

```swift
struct DiskBreakdown: Sendable {
    var storeBytes: Int = 0
    var replicationBytes: Int = 0
    var attachmentsBytes: Int = 0
    var authBytes: Int = 0
    var walShmBytes: Int = 0
    var logsBytes: Int = 0
    var otherBytes: Int = 0
}
```

`StorageSnapshot` copies these seven values plus adds a `collectionBreakdown: [CollectionStats]` array.

#### Per-Collection Breakdown

After the seven fixed cards, the Storage section shows one `MetricCard` per collection, sorted largest-first.

**Algorithm (`StorageRepository.computeCollectionBreakdown`):**

1. Execute `SELECT * FROM system:collections` to list all user collection names.
2. For each collection, execute `SELECT * FROM \`{name}\`` to iterate all documents.
3. Call `doc.cborData()` on each result item and add `.count` to the collection's running total.
4. Call `doc.dematerialize()` immediately after to release memory.
5. Return `[CollectionStats]` sorted by `cborPayloadBytes` descending.

**`CollectionStats` struct:**

```swift
struct CollectionStats: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let documentCount: Int
    let cborPayloadBytes: Int
}
```

**Why `cborData()` instead of `JSONSerialization`:**

`cborData()` returns the document in Ditto's native CBOR binary format — the same encoding Ditto uses internally before writing to SQLite. JSON serialization (`JSONSerialization.data(withJSONObject: doc.value)`) inflates values by 2–4× because it produces UTF-8 text with verbose field names and no binary compression. Using CBOR gives a far more accurate estimate of the actual storage consumed per document.

**What `cborData()` does and does not include:**

| Included | Not included |
|----------|-------------|
| Document field values (in CBOR) | SQLite row overhead (B-tree page headers, rowid) |
| CRDT register metadata (current value markers) | CRDT vector clock history (past tombstones and versions) |
| Document `_id` field | SQLite index entries (for indexed fields) |
| | WAL journal entries for uncommitted writes |

The total of all `cborPayloadBytes` values is accessible via `StorageSnapshot.collectionPayloadBytes` (computed property: `collectionBreakdown.reduce(0) { $0 + $1.cborPayloadBytes }`).

#### Why `__small_peer_info` is not used

Earlier versions queried `__small_peer_info` for device-level disk totals. This was removed because:

1. `__small_peer_info` is populated by the sync engine and can be seconds-to-minutes out of date, especially on a fresh database open before any sync completes.
2. Taking `items.first` without filtering by local peer key returned whichever peer row the query optimizer chose — often a remote peer with a different (smaller) storage footprint.
3. `ditto.diskUsage.exec` reads directly from the filesystem and is always current.

#### Performance notes

- `ditto.diskUsage.exec` is dispatched in a `Task.detached(priority: .utility)` block to keep it off the main thread.
- The collection breakdown iterates all documents in all collections and is O(total document count). For very large databases this can take several seconds. The view shows the previous snapshot while a refresh is in progress.
- The entire storage computation runs as part of the 15-second auto-refresh cycle of `AppMetricsDetailView`.

---

## Query Metrics View

**File:** `Views/Metrics/QueryMetricsDetailView.swift`

Displays a master-detail list of `QueryExplainRecord` entries captured by `QueryMetricsRepository` (actor, `Data/Repositories/QueryMetricsRepository.swift`).

### What is captured per query

Every call to `QueryService.executeSelectedAppQuery()` captures:

| Field | Description |
|-------|-------------|
| `timestamp` | Wall-clock time when the query completed |
| `dql` | The exact DQL string that was executed |
| `executionTimeMs` | Time from just before `ditto.store.execute()` to when it returned |
| `resultCount` | Number of result items + mutated document IDs |
| `explainOutput` | Output of `EXPLAIN {query}` run immediately after, or an error string if EXPLAIN failed |

### EXPLAIN execution

After every successful query, `QueryService` runs `EXPLAIN {query}` silently. The output is stored in the record but never surfaced as an error to the user. If EXPLAIN fails (e.g. the query was itself an EXPLAIN, or the syntax is unsupported), the `explainOutput` field contains the error string.

Recursive EXPLAIN calls are guarded: if the original query already starts with `EXPLAIN`, the EXPLAIN step is skipped and `explainOutput` is stored as an empty string.

### Index usage indicator

Each row in the list shows a coloured dot:
- **Green** — the EXPLAIN output contains the word "index", indicating an index was used
- **Orange** — no index mention found; the query likely performed a full collection scan

This is a heuristic based on string matching in the EXPLAIN output. It is not a guarantee.

### Retention

`QueryMetricsRepository` retains at most **200 records**. When the limit is reached, the oldest record is evicted. Records are displayed in reverse chronological order (newest first).

The trash button in the header clears all records immediately.

### Timestamp format

Timestamps display as `MMM d, HH:mm:ss.SSS` (e.g. `Feb 22, 14:23:30.590`), including the date so records from earlier in a long session can be distinguished from recent ones.

---

## Prometheus Export

**File:** `Data/MetricsBackend.swift` — `PrometheusExportBackend` actor
**UI:** `Views/Metrics/MetricsInspectorView.swift`

This is an optional feature. When a Pushgateway URL is configured, Edge Studio periodically pushes the current counter snapshot to a [Prometheus Pushgateway](https://github.com/prometheus/pushgateway) in the standard text exposition format.

### How to configure

In the Metrics sidebar, select the **App** view. A settings panel (or inspector area depending on layout) contains:

- **Pushgateway URL** — e.g. `http://localhost:9091`. Leave blank to disable export.
- **Export interval** — how often to push, in seconds. Minimum 10 seconds. Default 60.

Press **Apply** to activate. The status indicator turns green after the first successful push.

### What is exported

Only counter values are exported. Timer samples (the ring buffer) are not included — only the cumulative totals stored in `counters`:

```
# HELP edge_studio_queries_total Edge Studio metric
# TYPE edge_studio_queries_total gauge
edge_studio_queries_total 42

# HELP edge_studio_query_latency_ms Edge Studio metric
# TYPE edge_studio_query_latency_ms gauge
edge_studio_query_latency_ms 3.7
```

Labels with `.` and `-` are converted to `_` to comply with Prometheus naming rules. All metrics are exported as `gauge` type (not `counter`) because the values are read directly from the in-memory store.

The job label is fixed as `edge-studio`:
```
PUT {pushgatewayURL}/metrics/job/edge-studio
```

### Push Now

The **Push Now** button triggers an immediate push outside the normal interval. Useful for verifying connectivity to the Pushgateway.

### Clear All Metrics

The **Clear All Metrics** button resets both `InMemoryMetricsStore` (counters + samples) and `QueryMetricsRepository` (per-query records). Export is not stopped; if a Pushgateway is configured, the next push will send zeroed counter values.

---

## Data Lifecycle

```
App launch
  │
  ├─ MetricsRepository.appStartDate = Date()       ← process uptime anchor
  │
  ├─ User opens a database
  │   └─ Internal startup queries run via ditto.store.execute()
  │      (invisible to metrics)
  │
  ├─ User executes a query from the editor
  │   ├─ QueryService.executeSelectedAppQuery()
  │   ├─ queryCounter.increment()                  → InMemoryMetricsStore
  │   ├─ queryTimer.recordMilliseconds(elapsedMs)  → InMemoryMetricsStore
  │   └─ QueryMetricsRepository.capture(...)       → per-query record list
  │
  ├─ AppMetricsDetailView polls every 15s
  │   └─ MetricsRepository.queryMetricSnapshot()   ← reads InMemoryMetricsStore
  │
  ├─ PrometheusExportBackend (if configured)
  │   └─ Pushes InMemoryMetricsStore.countersSnapshot() every N seconds
  │
App closed → all in-memory data discarded
```

---

## Key Files

| File | Role |
|------|------|
| `Data/MetricsBackend.swift` | `InMemoryMetricsStore`, `AppMetricsCounter`, `AppMetricsTimer`, `PrometheusExportBackend` |
| `Data/Repositories/MetricsRepository.swift` | Read-side: builds `ProcessMetricSnapshot` and `QueryMetricSnapshot` from Darwin APIs and `InMemoryMetricsStore` |
| `Data/Repositories/QueryMetricsRepository.swift` | Per-query record store (actor, capped at 200 records) |
| `Data/Repositories/StorageRepository.swift` | Storage read-side: `categorizeFiles(_:)` (filesystem categorization), `computeCollectionBreakdown` (per-collection CBOR sizing), `fetchStorageSnapshot()` (public entry point) |
| `Data/QueryService.swift` | The only write path into the metrics system; instruments `executeSelectedAppQuery()` |
| `Models/QueryExplainRecord.swift` | Data model for a single captured query record |
| `Models/StorageModels.swift` | `StorageSnapshot`, `DiskBreakdown`, `CollectionStats`, `StorageSnapshot.formatMB(_:)` |
| `Components/MetricCard.swift` | Reusable card component with optional help popover |
| `Views/Metrics/AppMetricsDetailView.swift` | Process + queries + storage aggregate view |
| `Views/Metrics/QueryMetricsDetailView.swift` | Per-query log view |
| `Views/Metrics/MetricsInspectorView.swift` | Prometheus export configuration panel |
