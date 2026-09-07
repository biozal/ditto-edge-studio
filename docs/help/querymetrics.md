# Query Metrics

Query Metrics record per-query `EXPLAIN` analysis so you can understand how the Ditto query planner executes each statement.

---

## Enabling Metrics

Metrics are on by default (opt-out). Toggle **Collect Metrics** in **Settings** to show or hide the App Metrics and Query Metrics items in the navigation menu (the sidebar on macOS / iPadOS, the navigation rail/drawer on Android). The navigation menu updates dynamically — no restart required.

---

## How It Works

- Every DQL query you run is automatically analysed with `EXPLAIN`
- Results appear as a scrollable list, newest first
- Up to **200 records** are kept; older records are dropped automatically. On Android the cap is **per database** (each configured database keeps its own 200); on macOS / iPadOS a single in-memory store holds records for the currently selected app. On macOS / iPadOS records are kept in memory for the current session; on Android they are persisted in a local on-device database.

## Reading the List

- **Execution time** is colour-coded — green for fast queries (under 10 ms), the default text colour for moderate, orange for slow (100 ms and above)
- **Index usage indicator** — a green badge means the query used an index; an orange badge means a full collection scan was performed

## Viewing Details

Select any record in the list to see the full DQL statement and the complete `EXPLAIN` output in the detail panel on the right.

---

## See also: Execution Profile

Query Metrics records a per-query `EXPLAIN` plus latency for **every** query you run. The **Profile tab** in the Query results pane is a complementary feature — it captures the deeper `PROFILE` envelope (operator tree, per-phase timing) for the **most recent SELECT** so you can see exactly where the time went.

Both features share the **Collect Metrics** Settings toggle as their on/off switch. With it enabled:

- **Query Metrics** (this screen) — historical view across many queries; great for spotting which queries are slow over time.
- **Execution Profile** (Query → Profile tab) — deep dive into one query; great for finding the bottleneck operator inside a slow plan.

On macOS / iPadOS, see the User Guide for the full Execution Profile reference (the User Guide is not shipped on Android), or jump straight to the Profile tab next to Raw and Table after running any `SELECT`.
