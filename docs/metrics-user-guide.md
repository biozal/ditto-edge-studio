# App Metrics — User Guide

**Last Updated:** 2026-02-27

This guide explains every card and section visible in the **App Metrics** view of Edge Studio.

---

## Table of Contents

1. [How to open App Metrics](#how-to-open-app-metrics)
2. [Process section (macOS only)](#process-section-macos-only)
3. [Queries section](#queries-section)
4. [Storage section](#storage-section)
   - [Filesystem cards](#filesystem-cards)
   - [Collection breakdown cards](#collection-breakdown-cards)
   - [Understanding the numbers](#understanding-the-numbers)
5. [Refreshing data](#refreshing-data)

---

## How to open App Metrics

1. Select a database from the database list.
2. In the sidebar, tap or click **App Metrics**.
3. The view auto-refreshes every 15 seconds. Use the **⟳** button in the toolbar for an immediate refresh.

---

## Process section (macOS only)

These cards report on the Edge Studio process itself. They are only shown on macOS because the underlying Darwin APIs are not available on iPad.

| Card | What it shows |
|------|--------------|
| **Resident Memory** | How much RAM Edge Studio is currently using (physical memory mapped into the process). |
| **Virtual Memory** | Total virtual address space reserved by Edge Studio. Always larger than Resident Memory; includes memory-mapped files and frameworks. |
| **CPU Time** | Total CPU time consumed by all threads since app launch (user time + system time). |
| **Open File Desc.** | Number of open file descriptors (files, sockets, pipes). Useful for detecting descriptor leaks during long sessions. |
| **Process Uptime** | How long Edge Studio has been running in the current session. Resets each time the app is launched. |

---

## Queries section

These cards count queries you have run from the query editor in the current session. They reset when you close and relaunch the app. Internal queries run by the app itself (e.g. loading collections, checking sync status) are not counted.

| Card | What it shows |
|------|--------------|
| **Total Queries** | Running count of queries you have executed from the editor this session. |
| **Avg Latency** | Mean execution time across all queries, shown with a sparkline chart of the last ~2 minutes. |
| **Last Latency** | Execution time of the most recent query you ran. |

---

## Storage section

The Storage section shows how much disk space the currently selected Ditto database is using, broken down into two parts:

1. **Filesystem cards** — seven fixed cards based on Ditto's on-disk directory structure.
2. **Collection breakdown cards** — one card per collection, showing an estimated CBOR payload size.

All values are read directly from the local filesystem at the moment you open App Metrics (or refresh). There is no network request and no sync delay.

### Filesystem cards

Ditto organises its data into named directories inside its data folder. Each card corresponds to one directory group.

| Card | What it measures |
|------|-----------------|
| **Store** | The main document store. Contains all document data Ditto has written to its SQLite database. This is usually the largest category for databases with many documents. |
| **Replication** | Sync state with remote peers. Ditto maintains a separate database per peer it has synced with. This grows as you connect to more peers over time. |
| **Attachments** | Binary attachments stored via the Ditto Attachments API. Zero if you are not using attachments. |
| **Auth** | Identity and capability tokens used by Ditto's authentication system. Typically very small (a few KB). |
| **SQLite WAL/SHM** | SQLite's Write-Ahead Log and Shared Memory journal files. These are temporary transaction buffers created by SQLite during writes. Usually small, but can grow temporarily during heavy write operations. |
| **Logging** | Ditto log files, including compressed archives. Controlled by Ditto's log level setting. |
| **Other** | Everything else in the Ditto data directory that does not fall into the above categories — metrics databases, system info, lock files, etc. Usually very small. |

> **All seven cards sum to the total size of the Ditto data directory.** Adding them together equals the total bytes on disk for the selected database.

### Collection breakdown cards

Below the seven filesystem cards, one card appears per user collection in the database. Collections are sorted largest-first by estimated payload size.

Each card shows:
- The collection name as the card title
- The estimated payload size in MB
- The document count and a note about how the size is calculated in the **?** popover

**How the size is estimated:**

For each document in the collection, Edge Studio reads its CBOR representation using the Ditto SDK's `cborData()` call and sums the byte counts. CBOR (Concise Binary Object Representation) is the binary encoding Ditto uses internally — the same format it uses before writing to SQLite. This gives a far more accurate estimate than converting documents to JSON text, which inflates sizes by 2–4×.

**What the CBOR payload includes:**

- All document field values in binary CBOR encoding
- Current-value CRDT register markers
- The document `_id` field

**What the CBOR payload does not include:**

- SQLite row overhead (B-tree page headers, internal rowids)
- CRDT history (tombstones and old versions of fields from past syncs)
- SQLite index entries for indexed fields
- WAL journal entries for uncommitted writes

This means the per-collection card values will generally be **smaller** than the Store card, because the Store card measures the total SQLite file size, which includes all the overhead listed above. Use the collection cards for **comparing collections against each other**, not for predicting exactly how much space would be freed by deleting a collection.

> **System collections** (those starting with `__` or `system:`) are not shown in the breakdown. Only user-created collections appear.

### Understanding the numbers

**Why does Store not equal the sum of all collection cards?**

The Store card measures the full SQLite file on disk, including indexes, CRDT history, and SQLite internal structures. The collection cards measure only the current CBOR payload of live documents. The gap between the two is normal — it represents sync metadata, index overhead, and historical CRDT state.

**Why is Replication large?**

Each peer you have ever synced with has its own sync-state database. If you have synced with many peers over time, the Replication category can be significant. This data is managed automatically by the Ditto sync engine.

**Why is SQLite WAL/SHM non-zero?**

SQLite creates WAL files during write transactions. They are normally small and are merged back into the main database file periodically. Very large WAL/SHM values may indicate the database is under heavy write load or a checkpoint has been delayed.

**The collection breakdown is slow to appear.**

Estimating collection sizes requires iterating over every document in every collection. For databases with many documents (tens of thousands or more), this can take several seconds. The Storage section shows a "Computing storage…" spinner while the calculation runs in the background. The rest of App Metrics (process and query cards) appear immediately.

---

## Refreshing data

App Metrics auto-refreshes every **15 seconds**. The timestamp in the top-right corner of the view shows when the data was last fetched.

To force an immediate refresh, tap or click the **⟳** button in the toolbar. This re-reads all process, query, and storage data immediately.

Storage data reflects the state of the filesystem at the moment of the refresh. If you have just written a large batch of documents, tap Refresh to see the updated sizes.
