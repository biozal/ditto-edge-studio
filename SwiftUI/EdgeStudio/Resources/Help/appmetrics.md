# App Metrics

App Metrics show live resource usage for the currently running Edge Studio process.

---

## Enabling Metrics

Metrics are opt-in. Toggle **Enable Metrics** in **Settings** to show or hide the App Metrics and Query Metrics items in the sidebar. The sidebar updates dynamically — no restart required.

---

## Process Resources

**Available on macOS:**
- **Resident Memory** — physical RAM currently in use by the process
- **Virtual Memory** — total virtual address space allocated
- **CPU Time** — cumulative processor time used since launch
- **Open File Descriptors** — number of open file handles
- **Process Uptime** — time since the process started

**Available on iOS / iPadOS:**
- **Process Uptime** — time since the process started

**Query Performance (both platforms):**
- **Total Queries** — number of DQL queries executed in this session
- **Average Latency** — rolling average execution time across all queries, displayed with a sparkline chart showing recent trends
- **Last Latency** — execution time of the most recent query

App Metrics **auto-refresh every 15 seconds**. You can also trigger a manual refresh using the refresh button.

---

## Storage

The Storage section shows how much disk space the currently selected Ditto database is using. All values are read directly from the local filesystem — no network request, no sync delay.

### Filesystem Cards

| Card | What it measures |
|------|-----------------|
| **Store** | The main document store. Contains all document data written to Ditto's SQLite database. Usually the largest category. |
| **Replication** | Sync state with remote peers. Ditto keeps a separate database per peer synced with. Grows as you connect to more peers over time. |
| **Attachments** | Binary attachments stored via the Ditto Attachments API. Zero if attachments are not in use. |
| **Auth** | Identity and capability tokens. Typically a few KB. |
| **SQLite WAL/SHM** | SQLite's Write-Ahead Log and Shared Memory journal files. Temporary buffers during write operations — normally small. |
| **Logging** | Ditto log files, including compressed archives. |
| **Other** | Remaining files in the Ditto data directory (metrics databases, system info, lock files). |

All seven cards sum to the total size of the Ditto data directory.

### Collection Breakdown Cards

One card appears per user collection, sorted largest-first by estimated size. Each card shows the collection name, estimated size in MB, and document count.

**How size is estimated:** Edge Studio reads each document using `cborData()` — Ditto's native binary format — and sums the byte counts. This is significantly more accurate than JSON serialization, which inflates sizes by 2–4×.

Tap the **?** on any collection card to see what is and is not included in the estimate.

> The collection breakdown requires reading all documents across all collections. For large databases this can take several seconds — a spinner appears while the calculation runs.

### Tips

- **Store vs collection sum**: The Store card measures the full SQLite file (including indexes and CRDT history). Collection cards measure only current document payloads. The gap is normal.
- **Large Replication**: Each peer ever synced with leaves a sync-state database. This is managed automatically.
- **Large WAL/SHM**: May indicate heavy write activity or a delayed SQLite checkpoint. Usually resolves automatically.
- **Tap ⟳ to refresh**: Storage data reflects the filesystem at the moment of the last refresh.
