# Plan: Per-Collection Storage Breakdown + Filesystem-Based Categorization

## Summary

Two changes to the Storage section in App Metrics:

1. **Per-collection breakdown** — replace the single "Collection Payload" card with one `MetricCard` per collection showing its CBOR payload size (Ditto's native binary format, much more accurate than JSON).

2. **Filesystem-based categorization** — remove all `__small_peer_info` dependency (which is delayed). Every storage category maps directly to a `ditto_*` subdirectory in the Ditto data directory and is read from the `diskUsage` tree — immediate and accurate.

---

## Actual Ditto Directory Structure (Verified on Device)

```
{ditto-data-dir}/
├── ditto_store/          db.sql          ← document store
├── ditto_replication/    {peer}/{peer}/db.sql …  ← sync state per peer
├── ditto_attachments/    db.sql          ← binary attachments
├── ditto_auth/           *.cbor          ← identity / auth tokens
├── ditto_auth_tmp/                        ← transient auth scratch
├── ditto_logs/           *.log, *.log.gz ← rolling log files
├── ditto_metrics/                         ← telemetry
└── ditto_system_info/    db.sql          ← internal system metadata
```

All 8 cards in the Storage section can be derived purely from this tree — no `__small_peer_info` needed.

---

## Bugs Fixed by This Plan

| # | Bug | Impact |
|---|---|---|
| 1 | Log pattern `contains("/logs/")` never matches `ditto_logs/` | Logging card shows ~0 MB (misses almost all logs) |
| 2 | `.hasSuffix(".log")` misses `.log.gz` compressed archives | Rotated logs not counted |
| 3 | `__small_peer_info.items.first` may return a remote peer's stats | Attachments/Auth/Replication/Store/Total show wrong device's numbers |
| 4 | `__small_peer_info` data is delayed (not real-time) | Cards lag behind actual disk state |
| 5 | "Collection Payload" uses JSON size (2–4× inflated) | 52 MB shown for actual ~15 MB of data |

---

## Why cborData() for Per-Collection Sizes

`DittoQueryResultItem.cborData()` returns the document in Ditto's native CBOR binary format — the format actually stored in SQLite. `jsonData()` and `.value` are conversions *from* this. So `cborData().count` ≈ actual document payload bytes on disk.

Caveats (to be stated in help text): does not include per-row SQLite header, CRDT vector clock history, or index entries. These are tracked by the directory-based metrics instead.

---

## Model Changes

### `StorageModels.swift` — complete rewrite

Remove `DeviceDiskUsage` (no longer needed). Rename fields to match the actual `ditto_*` directories. Add `CollectionStats` for per-collection breakdown.

```swift
import Foundation

/// Per-collection CBOR payload estimate.
struct CollectionStats: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let documentCount: Int
    let cborPayloadBytes: Int
}

struct StorageSnapshot: Sendable {
    // From diskUsage tree — ditto_store/ directory
    var storeBytes: Int = 0

    // From diskUsage tree — ditto_replication/ directory
    var replicationBytes: Int = 0

    // From diskUsage tree — ditto_attachments/ directory
    var attachmentsBytes: Int = 0

    // From diskUsage tree — ditto_auth/ + ditto_auth_tmp/ directories
    var authBytes: Int = 0

    // From diskUsage tree — -wal / -shm file suffixes (across all directories)
    var walShmBytes: Int = 0

    // From diskUsage tree — ditto_logs/ directory + .log / .log.gz files
    var logsBytes: Int = 0

    // Residual: everything not matched above (ditto_metrics/, ditto_system_info/, lock files, etc.)
    var otherBytes: Int = 0

    // Per-collection CBOR payload breakdown
    var collectionBreakdown: [CollectionStats] = []

    /// Sum of all collection CBOR payload bytes — used for the summary card.
    var collectionPayloadBytes: Int {
        collectionBreakdown.reduce(0) { $0 + $1.cborPayloadBytes }
    }

    static func formatMB(_ bytes: Int) -> String {
        String(format: "%.2f MB", Double(bytes) / 1_048_576.0)
    }
}
```

---

## StorageRepository Changes

### Replace all file categorization with directory-path-based logic

The new `categorizeFiles` returns a `DiskBreakdown` value type (or we can use separate named outputs) instead of `(logs, walShm)`:

```swift
struct DiskBreakdown {
    var storeBytes: Int = 0
    var replicationBytes: Int = 0
    var attachmentsBytes: Int = 0
    var authBytes: Int = 0
    var walShmBytes: Int = 0
    var logsBytes: Int = 0
    var otherBytes: Int = 0
}
```

New `categorizeFiles` — public/internal for testability:

```swift
/// Pure function: categorizes flat file list by Ditto directory conventions.
/// Priority order: WAL/SHM suffix first (overrides directory), then directory component.
static func categorizeFiles(
    _ files: [(path: String, sizeInBytes: Int)]
) -> DiskBreakdown {
    var b = DiskBreakdown()
    for file in files {
        let p = file.path.lowercased()
        let bytes = file.sizeInBytes
        // WAL/SHM checked first — these suffixes appear inside any ditto_* directory
        if p.hasSuffix("-wal") || p.hasSuffix("-shm") {
            b.walShmBytes += bytes
        } else if p.contains("/ditto_logs/") || p.hasSuffix(".log") || p.hasSuffix(".log.gz") {
            b.logsBytes += bytes
        } else if p.contains("/ditto_store/") {
            b.storeBytes += bytes
        } else if p.contains("/ditto_attachments/") {
            b.attachmentsBytes += bytes
        } else if p.contains("/ditto_auth") {        // matches ditto_auth/ and ditto_auth_tmp/
            b.authBytes += bytes
        } else if p.contains("/ditto_replication/") {
            b.replicationBytes += bytes
        } else {
            b.otherBytes += bytes                    // ditto_metrics/, ditto_system_info/, lock files
        }
    }
    return b
}
```

### Replace `computeCollectionPayload` with `computeCollectionBreakdown`

```swift
/// Queries every user collection, sums cborData() byte counts per collection.
/// Uses cborData() — Ditto's native binary format — for accurate payload estimates.
/// Lower memory pressure than .value: CBOR Data is immediately counted and released,
/// no [String: Any?] dictionary materialized.
private static func computeCollectionBreakdown(
    ditto: Ditto
) async -> [CollectionStats] {
    guard let cols = try? await ditto.store.execute(
        query: "SELECT * FROM system:collections"
    ) else { return [] }

    let names = cols.items.compactMap { $0.value["name"] as? String }
    cols.items.forEach { $0.dematerialize() }

    var breakdown: [CollectionStats] = []
    for name in names {
        let escaped = name.replacingOccurrences(of: "`", with: "``")
        guard let result = try? await ditto.store.execute(
            query: "SELECT * FROM `\(escaped)`"
        ) else { continue }

        var cborBytes = 0
        var docCount = 0
        for doc in result.items {
            cborBytes += doc.cborData().count
            docCount += 1
            doc.dematerialize()
        }
        breakdown.append(CollectionStats(
            name: name,
            documentCount: docCount,
            cborPayloadBytes: cborBytes
        ))
    }

    return breakdown.sorted { $0.cborPayloadBytes > $1.cborPayloadBytes }
}
```

### Updated `computeDiskBreakdown`

```swift
private static func computeDiskBreakdown(ditto: Ditto) async -> StorageSnapshot {
    let root = await Task.detached(priority: .utility) {
        ditto.diskUsage.exec
    }.value

    let flatFiles = flattenTree(root)
    let b = categorizeFiles(flatFiles)
    let breakdown = await computeCollectionBreakdown(ditto: ditto)

    return StorageSnapshot(
        storeBytes: b.storeBytes,
        replicationBytes: b.replicationBytes,
        attachmentsBytes: b.attachmentsBytes,
        authBytes: b.authBytes,
        walShmBytes: b.walShmBytes,
        logsBytes: b.logsBytes,
        otherBytes: b.otherBytes,
        collectionBreakdown: breakdown
    )
}
```

### Remove `fetchDeviceDiskUsage` entirely

No longer needed — all data comes from the diskUsage tree.

### Update `fetchStorageSnapshot`

Remove the `async let device = fetchDeviceDiskUsage(ditto: ditto)` line. `fetchStorageSnapshot` now calls only `computeDiskBreakdown`.

---

## View Changes — `AppMetricsDetailView.swift`

### `storageSection` — one MetricCard per category + one per collection

Remove the `deviceUsage` conditional block entirely. Replace with a flat `LazyVGrid` containing:

**Fixed cards (always shown, from diskUsage tree):**

```swift
// 1. Store
MetricCard(
    title: "Store",
    systemImage: "cylinder.split.1x2",
    currentValue: StorageSnapshot.formatMB(snap.storeBytes),
    samples: [],
    helpText: "Size of Ditto's document store database files (ditto_store/ directory). Contains all collection documents, indexes, and CRDT state."
)

// 2. Replication
MetricCard(
    title: "Replication",
    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
    currentValue: StorageSnapshot.formatMB(snap.replicationBytes),
    samples: [],
    helpText: "Sync state stored per connected peer (ditto_replication/ directory). Grows with the number of peers synced with and the amount of data exchanged."
)

// 3. Attachments
MetricCard(
    title: "Attachments",
    systemImage: "paperclip",
    currentValue: StorageSnapshot.formatMB(snap.attachmentsBytes),
    samples: [],
    helpText: "Binary attachments stored by Ditto (ditto_attachments/ directory)."
)

// 4. Auth
MetricCard(
    title: "Auth",
    systemImage: "lock",
    currentValue: StorageSnapshot.formatMB(snap.authBytes),
    samples: [],
    helpText: "Authentication and identity credential files (ditto_auth/ directory). Includes certificate and token CBOR files."
)

// 5. SQLite WAL/SHM
MetricCard(
    title: "SQLite WAL/SHM",
    systemImage: "cylinder",
    currentValue: StorageSnapshot.formatMB(snap.walShmBytes),
    samples: [],
    helpText: "Write-Ahead Log and Shared Memory files used by SQLite for transaction journaling. Present across all ditto_* directories. Shrinks after a checkpoint."
)

// 6. Logging
MetricCard(
    title: "Logging",
    systemImage: "doc.plaintext",
    currentValue: StorageSnapshot.formatMB(snap.logsBytes),
    samples: [],
    helpText: "Ditto SDK log files (ditto_logs/ directory). Includes active .log and rotated .log.gz archives."
)

// 7. Other
MetricCard(
    title: "Other",
    systemImage: "archivebox",
    currentValue: StorageSnapshot.formatMB(snap.otherBytes),
    samples: [],
    helpText: "Remaining Ditto files: metrics, system info, lock files, and other internal data not covered by the categories above."
)
```

**Per-collection cards (one per collection, from CBOR scan):**

```swift
// Section header for the collection breakdown
Label("Collections (\(snap.collectionBreakdown.count))", systemImage: "tablecells")
    .font(.subheadline)
    .foregroundStyle(.secondary)
    .gridCellColumns(...)   // span full grid width — use padding trick below

// One card per collection, sorted largest-first (already sorted in repository)
ForEach(snap.collectionBreakdown) { col in
    MetricCard(
        title: col.name,
        systemImage: "doc.text",
        currentValue: StorageSnapshot.formatMB(col.cborPayloadBytes),
        samples: [],
        helpText: "\(col.documentCount) documents. Size is the sum of each document's CBOR payload — Ditto's native binary format, read via cborData(). Does not include SQLite row headers, CRDT history, or index entries."
    )
}
```

The label between the fixed cards and the collection cards needs to span the full grid. Use a `VStack` structure:

```swift
private var storageSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        Label("Storage", systemImage: "internaldrive")
            .font(.headline)
        if let snap = storageSnapshot {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                // 7 fixed cards
                storeCard(snap)
                replicationCard(snap)
                attachmentsCard(snap)
                authCard(snap)
                walShmCard(snap)
                loggingCard(snap)
                otherCard(snap)
            }
            if !snap.collectionBreakdown.isEmpty {
                Label("Collections (\(snap.collectionBreakdown.count))", systemImage: "tablecells")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                    ForEach(snap.collectionBreakdown) { col in
                        MetricCard(
                            title: col.name,
                            systemImage: "doc.text",
                            currentValue: StorageSnapshot.formatMB(col.cborPayloadBytes),
                            samples: [],
                            helpText: "\(col.documentCount) documents. Size estimated from CBOR payload (cborData()) — Ditto's native binary format. Does not include SQLite row overhead, CRDT history, or index entries."
                        )
                    }
                }
            }
        } else {
            ProgressView("Computing storage…")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
```

---

## Files to Modify / Create

| File | Action | Change |
|---|---|---|
| `StorageModels.swift` | Modify | Remove `DeviceDiskUsage`; rewrite `StorageSnapshot` with `ditto_*` fields; add `CollectionStats`; add computed `collectionPayloadBytes` |
| `StorageRepository.swift` | Modify | Add `DiskBreakdown` struct; rewrite `categorizeFiles` with directory-based logic; replace `computeCollectionPayload` with `computeCollectionBreakdown` using `cborData()`; remove `fetchDeviceDiskUsage`; update `fetchStorageSnapshot` and `computeDiskBreakdown` |
| `AppMetricsDetailView.swift` | Modify | Replace entire `storageSection` — 7 fixed cards + per-collection cards, no `deviceUsage` conditional block |
| `EdgeStudioUnitTests/Storage/StorageSnapshotTests.swift` | Modify | Update property names; add `CollectionStats` tests; remove `DeviceDiskUsage` decode tests |
| `EdgeStudioUnitTests/Repositories/StorageRepositoryTests.swift` | Modify | Update `categorizeFiles` tests to use new `DiskBreakdown` return type; add tests for `ditto_logs/`, `ditto_store/`, `ditto_auth/`, `ditto_replication/`, `ditto_attachments/` path matching; add test for `.log.gz`; remove old `(logs, walShm)` tuple tests |

---

## Updated Test Cases for `categorizeFiles`

```swift
@Test("ditto_store/ files go to storeBytes", .tags(.storage))
func testStoreDirectory() {
    let files = [("/data/ditto_store/db.sql", 5_000_000)]
    let b = StorageRepository.categorizeFiles(files)
    #expect(b.storeBytes == 5_000_000)
    #expect(b.walShmBytes == 0)
}

@Test("ditto_replication/ files go to replicationBytes", .tags(.storage))
func testReplicationDirectory() {
    let files = [("/data/ditto_replication/peerA/peerB/db.sql", 1_000_000)]
    let b = StorageRepository.categorizeFiles(files)
    #expect(b.replicationBytes == 1_000_000)
}

@Test("ditto_attachments/ files go to attachmentsBytes", .tags(.storage))
func testAttachmentsDirectory() {
    let files = [("/data/ditto_attachments/db.sql", 2_000_000)]
    let b = StorageRepository.categorizeFiles(files)
    #expect(b.attachmentsBytes == 2_000_000)
}

@Test("ditto_auth/ and ditto_auth_tmp/ go to authBytes", .tags(.storage))
func testAuthDirectory() {
    let files = [
        ("/data/ditto_auth/site.cbor", 1_024),
        ("/data/ditto_auth_tmp/scratch", 512)
    ]
    let b = StorageRepository.categorizeFiles(files)
    #expect(b.authBytes == 1_536)
}

@Test("ditto_logs/ and .log.gz go to logsBytes", .tags(.storage))
func testLogsDirectory() {
    let files = [
        ("/data/ditto_logs/ditto-2026.log", 400_000),
        ("/data/ditto_logs/ditto-2025.log.gz", 200_000)
    ]
    let b = StorageRepository.categorizeFiles(files)
    #expect(b.logsBytes == 600_000)
}

@Test("-wal and -shm suffixes go to walShmBytes regardless of directory", .tags(.storage))
func testWalShmPriority() {
    // WAL/SHM should be counted even inside ditto_store/
    let files = [
        ("/data/ditto_store/db.sql-wal", 10_000_000),
        ("/data/ditto_replication/peer/db.sql-shm", 4_096)
    ]
    let b = StorageRepository.categorizeFiles(files)
    #expect(b.walShmBytes == 10_004_096)
    #expect(b.storeBytes == 0)       // not double-counted
}

@Test("unrecognised files go to otherBytes", .tags(.storage))
func testOtherFiles() {
    let files = [
        ("/data/ditto_system_info/db.sql", 50_000),
        ("/data/__ditto_lock_file", 0),
        ("/data/ditto_metrics/some.dat", 1_000)
    ]
    let b = StorageRepository.categorizeFiles(files)
    #expect(b.otherBytes == 51_000)
}

@Test("empty input returns all zeros", .tags(.storage))
func testEmpty() {
    let b = StorageRepository.categorizeFiles([])
    #expect(b.storeBytes == 0)
    #expect(b.replicationBytes == 0)
    #expect(b.walShmBytes == 0)
    #expect(b.logsBytes == 0)
    #expect(b.otherBytes == 0)
}
```

---

## Build Order

1. **Edit** `StorageModels.swift` — remove `DeviceDiskUsage`; rewrite `StorageSnapshot`; add `CollectionStats` and `DiskBreakdown`
2. **Edit** `StorageRepository.swift` — rewrite `categorizeFiles`, replace `computeCollectionPayload` → `computeCollectionBreakdown`, remove `fetchDeviceDiskUsage`, update `computeDiskBreakdown` and `fetchStorageSnapshot`
3. **Edit** `AppMetricsDetailView.swift` — replace `storageSection` entirely
4. **Edit** `StorageSnapshotTests.swift` — update property names, remove DeviceDiskUsage tests
5. **Edit** `StorageRepositoryTests.swift` — replace all `categorizeFiles` tests with directory-based versions
6. Build macOS + iOS, run unit tests

---

## Verification

After the change:

| Check | Expected |
|---|---|
| Store + Replication + Attachments + Auth + WAL/SHM + Logs + Other | Sum ≈ `ditto.diskUsage.exec.sizeInBytes` |
| Logging card | Now shows ~6 MB + compressed archives (previously missed `.log.gz`) |
| Collection cards | One per collection, CBOR bytes, sorted largest-first |
| Values update on ⟳ refresh | Immediate — no sync delay |
| Database with no collections | No collection cards shown; fixed 7 cards still render |
| No remote peers connected | Values unchanged (not from `__small_peer_info` anymore) |

Cross-check against the filesystem:
```bash
# Total Ditto data dir size — should match sum of all 7 fixed cards
du -sh ~/Library/Application\ Support/DittoEdgeStudio/{db-dir}/

# Individual category checks
du -sh ~/Library/Application\ Support/DittoEdgeStudio/{db-dir}/ditto_store/
du -sh ~/Library/Application\ Support/DittoEdgeStudio/{db-dir}/ditto_replication/
du -sh ~/Library/Application\ Support/DittoEdgeStudio/{db-dir}/ditto_logs/
```
