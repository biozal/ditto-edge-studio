# Database Metrics

Database Metrics shows how much local disk space the currently selected Ditto database is consuming, broken down by subsystem and by collection.

---

## Why Storage Monitoring Matters on Edge Devices

Edge devices often have limited internal storage — a few GB on industrial handhelds or shared between multiple apps on Android tablets. A Ditto database can grow silently as documents accumulate, peers sync, and attachments are written. Monitoring storage proactively prevents "disk full" failures that would stop sync and corrupt in-flight writes.

---

## Filesystem Breakdown

The top section shows per-subsystem sizes for the entire Ditto data directory:

| Card | What it measures |
|------|-----------------|
| **Store** | The main document store (SQLite). Contains all document data — usually the largest category. |
| **Replication** | Sync-state databases, one per remote peer ever synced with. Grows as you connect to more peers over time. |
| **Attachments** | Binary attachments stored via the Ditto Attachments API. Zero if attachments are not in use. |
| **Auth** | Identity and capability tokens. Typically a few KB. |
| **SQLite WAL/SHM** | SQLite's Write-Ahead Log and Shared Memory journal — temporary write buffers, normally small. |
| **Logging** | Ditto log files, including compressed archives. |
| **Other** | Remaining files in the data directory (metrics databases, lock files, system info). |

All cards sum to the total Ditto data directory size shown at the top.

---

> **System Metrics moved.** Ditto's `system:metrics` counters (SDK 5.1) now have their own **System Metrics** item in the navigation menu, with per-metric details, pinning, and search. See its help page for details.

---

## Per-Collection Breakdown

One card appears per user collection, sorted largest-first by estimated document payload size. Each card shows the collection name, estimated size, and document count.

**How size is estimated:** Edge Studio reads each document's binary representation and sums the byte counts. This is more accurate than JSON serialization, which typically inflates sizes by 2–4×.

> For large databases the breakdown scan can take several seconds — a progress indicator appears while the calculation runs.

---

## Auto-Refresh

Database Metrics **auto-refreshes every 15 seconds**. You can also trigger an immediate refresh using the **⟳** button in the top bar. Storage values always reflect the filesystem at the moment of the last refresh — not real-time.

---

## Tips

- **Store vs. collection sum**: The Store card measures the full SQLite file (including indexes and CRDT history). Collection cards measure only current document payloads. A gap between the two is expected and normal.
- **Large Replication**: Each peer ever synced with leaves a sync-state database. This is managed automatically by Ditto and will compact over time.
- **Large WAL/SHM**: May indicate heavy write activity or a pending SQLite checkpoint. Usually resolves on its own after writes settle.
