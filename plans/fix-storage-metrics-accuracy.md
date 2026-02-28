# Fix: Storage Metrics Accuracy

## Problem Summary

The Storage section in App Metrics shows internally inconsistent numbers. In testing:
- **Collection Payload**: 52.14 MB
- **SQLite WAL/SHM**: 104.50 MB
- **Logging**: 5.99 MB
- **Metadata & Overheads**: 101.50 MB (residual)
- **Total (Ditto)** from `__small_peer_info`: **0.75 MB** ← impossibly small

The total of the diskUsage-based cards (52.14 + 104.50 + 5.99 + 101.50 = ~264 MB) cannot be reconciled with a "Total (Ditto)" of 0.75 MB. There are two independent bugs.

---

## Root Cause 1 — Collection Payload uses JSON in-memory size, not on-disk bytes

### Current code (`StorageRepository.computeCollectionPayload`)

```swift
for doc in result.items {
    if let data = try? JSONSerialization.data(withJSONObject: doc.value, options: []) {
        total += data.count
    }
}
```

**Problem**: `JSONSerialization.data(withJSONObject:)` produces a UTF-8 encoded JSON string of the document's in-memory dictionary. This is **not** how Ditto stores data on disk:

- Ditto stores documents as binary CRDT deltas inside SQLite blobs, which are far more compact than equivalent JSON text.
- 65,000 documents × ~800 bytes of JSON ≈ 52 MB, but the same data on disk may be 3–5× smaller.
- The metric is misleading: it inflates Collection Payload while simultaneously deflating Metadata & Overheads (which is a residual: `total − payload − WAL − logs`).

### Impact

When Collection Payload is inflated (52 MB), the residual Metadata & Overheads can appear unrealistically small, or even go negative if the JSON size exceeds the actual database size. None of the four diskUsage-based cards are trustworthy as a result.

### Fix

Remove `computeCollectionPayload` entirely. Instead, enumerate the diskUsage tree and categorize files directly by their file extension:

| Category | Files |
|---|---|
| **SQLite DB Files** | files ending `.db` (not WAL/SHM) |
| **SQLite WAL/SHM** | `.db-wal`, `.db-shm`, `-wal`, `-shm` (existing) |
| **Logs** | `/logs/` path component, `.log` suffix (existing) |
| **Other** | everything else in the Ditto directory |

This gives an accurate breakdown where all four categories sum to exactly `ditto.diskUsage.exec.sizeInBytes`.

**Rename "Collection Payload" → "SQLite DB Files"** and update the help text to explain it represents the total size of Ditto's SQLite `.db` database files on disk (includes document data, indexes, and CRDT metadata — all stored inside SQLite).

New `categorizeFiles` signature extension — add a `dbFiles` output:

```swift
static func categorizeFiles(
    _ files: [(path: String, sizeInBytes: Int)]
) -> (dbFiles: Int, logs: Int, walShm: Int) {
    var dbFiles = 0
    var logs = 0
    var walShm = 0
    for file in files {
        let p = file.path.lowercased()
        // WAL/SHM (check before .db so .db-wal is not double-counted)
        if p.hasSuffix(".db-wal") || p.hasSuffix(".db-shm") ||
           p.hasSuffix("-wal")    || p.hasSuffix("-shm") {
            walShm += file.sizeInBytes
        } else if p.contains("/logs/") || p.hasSuffix(".log") {
            logs += file.sizeInBytes
        } else if p.hasSuffix(".db") {
            dbFiles += file.sizeInBytes
        }
        // All other files fall through to "other" (residual)
    }
    return (dbFiles, logs, walShm)
}
```

Update `computeDiskBreakdown` to use the new return value:

```swift
private static func computeDiskBreakdown(ditto: Ditto) async -> StorageSnapshot {
    let root = await Task.detached(priority: .utility) { ditto.diskUsage.exec }.value

    let total = root.sizeInBytes
    let flatFiles = flattenTree(root)
    let (dbFiles, logs, walShm) = categorizeFiles(flatFiles)
    let other = max(0, total - (dbFiles + logs + walShm))

    return StorageSnapshot(
        dbFilesBytes: dbFiles,
        walShmBytes: walShm,
        logsBytes: logs,
        otherBytes: other
    )
}
```

Remove `computeCollectionPayload` entirely (no longer needed — no Ditto store queries for disk breakdown).

---

## Root Cause 2 — `fetchDeviceDiskUsage` returns a remote peer's data

### Current code

```swift
guard let result = try? await ditto.store.execute(
    query: "SELECT device_disk_usage FROM __small_peer_info"
), let first = result.items.first else { return nil }
```

**Problem**: `__small_peer_info` contains one row **per known peer** (local + all remote peers). Taking `.items.first` without filtering returns whichever row the query optimizer happens to return first — which may be a remote peer with a tiny storage footprint (0.75 MB).

### Fix

Filter by the local peer's key string, which is available from `ditto.presence.graph.localPeer.peerKeyString`:

```swift
private static func fetchDeviceDiskUsage(ditto: Ditto) async -> DeviceDiskUsage? {
    // Identify the local peer key so we query only the local device's row
    let localPeerKey = await Task.detached(priority: .utility) {
        ditto.presence.graph.localPeer.peerKeyString
    }.value

    guard let result = try? await ditto.store.execute(
        query: "SELECT device_disk_usage FROM __small_peer_info WHERE _id = :id",
        arguments: ["id": localPeerKey]
    ), let first = result.items.first else { return nil }

    let raw = first.value["device_disk_usage"]
    first.dematerialize()

    guard let outerRaw = raw,
          let dict = outerRaw,
          let jsonData = try? JSONSerialization.data(withJSONObject: dict),
          let usage = try? JSONDecoder().decode(DeviceDiskUsage.self, from: jsonData) else { return nil }
    return usage
}
```

**Why `ditto.presence.graph.localPeer`**: `SystemRepository.swift` already uses `ditto.presence.graph.remotePeers` for peer monitoring, confirming this API is available. The `localPeer.peerKeyString` matches the `_id` field in `__small_peer_info` for the local device row.

---

## Model Changes

### `StorageModels.swift` — rename `collectionPayloadBytes` → `dbFilesBytes`, `metadataOverheadsBytes` → `otherBytes`

```swift
struct StorageSnapshot: Sendable {
    var dbFilesBytes: Int = 0       // was: collectionPayloadBytes
    var walShmBytes: Int = 0
    var logsBytes: Int = 0
    var otherBytes: Int = 0         // was: metadataOverheadsBytes
    var deviceUsage: DeviceDiskUsage?

    static func formatMB(_ bytes: Int) -> String {
        String(format: "%.2f MB", Double(bytes) / 1_048_576.0)
    }
}
```

---

## View Changes

### `AppMetricsDetailView.swift` — update `storageSection`

Replace "Collection Payload" card:

```swift
// Before
MetricCard(
    title: "Collection Payload",
    systemImage: "doc.text",
    currentValue: StorageSnapshot.formatMB(snap.collectionPayloadBytes),
    samples: [],
    helpText: "Total JSON-serialized size of all documents across all collections."
)

// After
MetricCard(
    title: "SQLite DB Files",
    systemImage: "doc.text",
    currentValue: StorageSnapshot.formatMB(snap.dbFilesBytes),
    samples: [],
    helpText: "Total size of Ditto's SQLite database files on disk. Includes document data, CRDT metadata, and indexes — all stored inside SQLite .db files."
)
```

Replace "Metadata & Overheads" card:

```swift
// Before
MetricCard(
    title: "Metadata & Overheads",
    systemImage: "archivebox",
    currentValue: StorageSnapshot.formatMB(snap.metadataOverheadsBytes),
    samples: [],
    helpText: "Remaining storage: indexes, internal metadata, and other Ditto overhead. Calculated as Total − (Payload + WAL/SHM + Logs)."
)

// After
MetricCard(
    title: "Other Files",
    systemImage: "archivebox",
    currentValue: StorageSnapshot.formatMB(snap.otherBytes),
    samples: [],
    helpText: "Other files in the Ditto data directory that are not SQLite database files, WAL/SHM journals, or log files."
)
```

---

## Files to Modify

| File | Change |
|---|---|
| `StorageModels.swift` | Rename `collectionPayloadBytes` → `dbFilesBytes`, `metadataOverheadsBytes` → `otherBytes` |
| `StorageRepository.swift` | Update `categorizeFiles` return type; remove `computeCollectionPayload`; fix `fetchDeviceDiskUsage` to filter by local peer key |
| `AppMetricsDetailView.swift` | Update card titles, `currentValue` property references, and help text |
| `EdgeStudioUnitTests/Storage/StorageSnapshotTests.swift` | Update property names in default values test |
| `EdgeStudioUnitTests/Repositories/StorageRepositoryTests.swift` | Update `categorizeFiles` call sites to use new tuple labels |

---

## Test Changes

### `StorageRepositoryTests.swift` — update categorization tests

The `categorizeFiles` function now returns `(dbFiles:, logs:, walShm:)` instead of `(logs:, walShm:)`. All test call sites need to be updated. Also add tests for the new `.db` file category:

```swift
@Test("categorizeFiles classifies .db files as dbFiles", .tags(.storage))
func testDbFile() {
    let files = [("/var/data/ditto.db", 1000), ("/var/data/ditto.db-wal", 200)]
    let (dbFiles, logs, walShm) = StorageRepository.categorizeFiles(files)
    #expect(dbFiles == 1000)
    #expect(walShm == 200)
    #expect(logs == 0)
}

@Test("categorizeFiles does not classify .db-wal as a db file", .tags(.storage))
func testWalNotClassifiedAsDb() {
    let files = [("/var/data/ditto.db-wal", 500)]
    let (dbFiles, _, walShm) = StorageRepository.categorizeFiles(files)
    #expect(walShm == 500)
    #expect(dbFiles == 0)
}
```

### `StorageSnapshotTests.swift` — update property names

```swift
@Test("StorageSnapshot defaults to all zeros and nil deviceUsage", .tags(.storage))
func testDefaultValues() {
    let snap = StorageSnapshot()
    #expect(snap.dbFilesBytes == 0)         // was: collectionPayloadBytes
    #expect(snap.walShmBytes == 0)
    #expect(snap.logsBytes == 0)
    #expect(snap.otherBytes == 0)            // was: metadataOverheadsBytes
    #expect(snap.deviceUsage == nil)
}
```

---

## Build Order

1. **Edit** `StorageModels.swift` — rename properties
2. **Edit** `StorageRepository.swift` — update `categorizeFiles` signature, remove `computeCollectionPayload`, fix `fetchDeviceDiskUsage`
3. **Edit** `AppMetricsDetailView.swift` — update card references (2 title/helpText changes + 2 property name changes)
4. **Edit** `StorageSnapshotTests.swift` — update property names in default values test
5. **Edit** `StorageRepositoryTests.swift` — update categorizeFiles call sites + add 2 new `.db` tests

Build for macOS and iOS after each file change to catch compile errors early.

---

## Verification

After the fix, numbers should be consistent:

| Card | Source | Expected relationship |
|---|---|---|
| SQLite DB Files | diskUsage `.db` files | ≤ Total |
| SQLite WAL/SHM | diskUsage WAL/SHM files | ≤ Total |
| Logging | diskUsage log files | ≤ Total |
| Other Files | residual | ≈ 0 or small |
| **Sum** | DB + WAL + Logs + Other | = `ditto.diskUsage.exec.sizeInBytes` (within rounding) |
| Total (Ditto) from `__small_peer_info` | local peer's `device_disk_usage.ditto_total` | ≈ Sum above (same device) |

Manual checks:
1. Select a database with data → Storage section populates
2. DB Files + WAL/SHM + Logging + Other ≈ disk space used by Ditto (verify via `du -sh` on the Ditto data directory)
3. Total (Ditto) from `__small_peer_info` ≈ same order of magnitude as the sum above
4. Connect to a remote peer → Total (Ditto) still shows LOCAL device's data, not the remote peer's

---

## Edge Cases

| Condition | Behavior |
|---|---|
| No `.db` files (empty/new database) | SQLite DB Files = 0.00 MB |
| `__small_peer_info` has no local peer row yet | deviceUsage = nil → device cards not rendered |
| Local peer not yet in presence graph | Falls back to `items.first` for safety (see below) |
| `ditto.presence.graph.localPeer.peerKeyString` unavailable | Should always be available once Ditto is initialized; if query returns empty, `fetchDeviceDiskUsage` returns nil gracefully |

> **Fallback note**: `ditto.presence.graph.localPeer` is populated immediately when the Ditto instance is created (before sync starts), so there is no race condition. No fallback to `.items.first` is needed — if the WHERE-filtered query returns no rows, returning nil is the correct behavior (UI shows no device cards rather than a wrong value).
