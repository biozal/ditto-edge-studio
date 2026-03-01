# Query Metrics

Query Metrics record per-query `EXPLAIN` analysis so you can understand how the Ditto query planner executes each statement.

---

## Enabling Metrics

Metrics are opt-in. Toggle **Enable Metrics** in **Settings** to show or hide the App Metrics and Query Metrics items in the sidebar. The sidebar updates dynamically — no restart required.

---

## How It Works

- Every DQL query you run is automatically analysed with `EXPLAIN`
- Results appear as a scrollable list, newest first
- Up to **200 records** are kept in memory; older records are dropped automatically

## Reading the List

- **Execution time** is colour-coded — green for fast queries, orange for moderate, red for slow
- **Index usage indicator** — a green badge means the query used an index; an orange badge means a full collection scan was performed

## Viewing Details

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

### Exported Metric Contents

Metrics are pushed under the job label `edge_studio` and include information such as:

- Process resource usage (e.g. resident and virtual memory, CPU time, open file descriptors)
- Application uptime
- Aggregate query statistics (e.g. total queries executed)
- Query latency statistics (e.g. average and most recent query latency)

The exact metric names and labels are determined by the exporter implementation and may evolve over time. Inspect the exported metrics (for example, via your Prometheus target or Pushgateway UI) to see the precise names available in your version.
