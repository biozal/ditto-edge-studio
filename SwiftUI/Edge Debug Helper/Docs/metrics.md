# Metrics

The Metrics feature provides real-time visibility into your app's resource usage and query performance, plus optional export to a Prometheus Pushgateway for external monitoring.

---

## Enabling Metrics

Metrics are opt-in. Toggle **Enable Metrics** in **Settings** to show or hide the Metrics item in the sidebar. The sidebar updates dynamically — no restart required.

---

## App Metrics

App Metrics show live resource usage for the running process.

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

## Query Metrics

Query Metrics record per-query `EXPLAIN` analysis so you can understand how the Ditto query planner executes each statement.

**How it works:**
- Every DQL query you run is automatically analysed with `EXPLAIN`
- Results appear as a scrollable list, newest first
- Up to **200 records** are kept in memory; older records are dropped automatically

**Reading the list:**
- **Execution time** is colour-coded — green for fast queries, orange for moderate, red for slow
- **Index usage indicator** — a green badge means the query used an index; an orange badge means a full collection scan was performed

**Viewing details:**
Select any record in the list to see the full DQL statement and the complete `EXPLAIN` output in the detail panel on the right.

---

## Prometheus Export

Push metrics to a **Prometheus Pushgateway** for aggregation by Prometheus and visualisation in Grafana or any compatible dashboard.

### Configuration

| Field | Description |
|---|---|
| **Pushgateway URL** | Base URL of your Pushgateway, e.g. `http://localhost:9091`. Leave blank to disable export. |
| **Export Interval** | How often metrics are pushed automatically (minimum 10 s, default 60 s). |

Tap **Apply** to save changes. The export timer restarts immediately.

### Actions

- **Push Now** — Sends the current metrics snapshot immediately, regardless of the timer. Useful for testing your configuration.
- **Clear All Metrics** — Resets all in-memory metrics counters and clears the Query Metrics list. The export configuration is preserved.

### Status Indicator

| Colour | Meaning |
|---|---|
| Grey | Not configured — Pushgateway URL is empty |
| Green | Last successful push time |
| Red | Last push failed — error message shown |

### Exported Metric Names

Metrics are pushed under the job label `edge_studio`. Exported names include:

- `edge_studio_resident_memory_bytes`
- `edge_studio_virtual_memory_bytes`
- `edge_studio_cpu_time_seconds`
- `edge_studio_open_file_descriptors`
- `edge_studio_uptime_seconds`
- `edge_studio_total_queries`
- `edge_studio_average_query_latency_seconds`
- `edge_studio_last_query_latency_seconds`
