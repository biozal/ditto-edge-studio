# System Metrics

The System Metrics screen is a live dashboard fed by Ditto SDK 5.1's `system:metrics` virtual collection: DSOQ network counters, SQLite metrics per database role, and replication recovery counters.

For point-in-time **storage** numbers (disk usage, per-collection payload sizes) use the **App Metrics** screen on macOS / iPadOS, or the **Database Metrics** screen on Android.

The screen polls every 5 seconds **while it is visible** — the footer shows the accumulation window and the last poll time. The refresh button forces one immediate poll ahead of that cadence.

---

## Reading a row

Every metric series the SDK reports renders as a row: the metric name (with the `ditto.` prefix dropped) and its labels on the left, the since-connect total and the last poll period's delta (`▲ +N`, or `—` when nothing happened) on the right.

## Filtering

The segment control filters rows by namespace:

- **Network** — DSOQ connection counters (`ditto.network.*`). Watch opened vs closed counts: divergence raises a banner about a possible connection leak or handshake instability; non-zero `tlv.unknown_type_*` counts indicate interop / version skew between peers.
- **Store** — SQLite metrics per database role (`ditto.backend.*`, `labels.db` = `main` / `replication_metadata` / `attachment` / `system_info`). Rising fsync / checkpoint durations mean disk pressure; a WAL that only grows means checkpoints aren't keeping up with writers.
- **Sync** — replication state (`ditto.sync.*`, `ditto.replication.*`). Non-zero recovery counts mean sync sessions were torn down — check the `cause` label and the Log Analyzer.
- **Other** — anything outside those namespaces.
- **All** — every reported series.

The **search field** narrows the list to series whose metric name or labels contain the term, case-insensitively — for example `ble` finds every `transport=ble` series and `dsoq` every dsoq metric. Search and the namespace filter compose (Store + `wal` → the WAL metrics of the Store namespace).

The **Pinned** section is not affected by either filter — it is your stable set.

## Details

The **ⓘ button** on a row expands the series' details: the metric's description from the SDK registry, its kind (counter / histogram) and unit, the full metric name, and — for histograms — the average and absolute maximum since connect.

## Pinning

When you're troubleshooting, pin the handful of series you care about with the **pin button** on any row. Pinned series collect in a collapsible **Pinned** accordion above the namespace filter, so 5–10 key metrics stay in view without hunting through the full list.

- Pinning does not remove the series from the main list, and both rows show the same live values.
- The pinned section ignores the namespace filter and the search field.
- A pinned series with no data yet this connection stays visible with a `—` placeholder, so you can always unpin it — either there or from its row in the main list.
- **Clear** empties the whole pinned set.

**Reordering.** Pinned series start in the order you pinned them. To change that order, tap **Reorder** in the Pinned header — the same Edit-then-drag pattern Apple Music uses:

1. **Reorder** reveals a ☰ handle on every pinned row and suspends the screen's scrolling.
2. Drag a row by its handle. Rows swap as you pass them, so the list reads as the final order the whole time.
3. **Done** puts the screen back to normal.

The mode exists because a bare press-and-drag does not work on a touch screen: the scrolling container claims that gesture first, so the page moves and the row never does. Suspending the scroll for the duration is what hands the drag to the row. It works with a mouse too.

While reordering, the pin and ⓘ buttons on each row are inactive so a mis-tap cannot unpin something mid-drag.

If you would rather not drag, each handle also offers **Move up** / **Move down** — as a right-click / long-press menu on macOS and iPadOS, and as accessibility actions on Android.

The order you set is the order they are remembered in.

Pins are remembered **per database**: they survive leaving the screen, closing and re-opening the database, and relaunching the app.

---

## Why totals are "since connect"

Every read of `system:metrics` **flushes** Ditto's metric registry — each row reports only what happened since the previous read. Edge Studio therefore accumulates those per-read deltas into running totals that start at zero when the database opens, and the footer tells you what window the numbers cover.

Because reads flush, polling pauses while the screen is hidden: an invisible poll would consume counters without showing them to anyone. Nothing is lost — the missed activity folds into the next poll's delta.

## If the screen says metrics are disabled

The `system:metrics` exporter is **startup-gated**: the SDK reads the parameter once when a database opens and ignores runtime changes. If this database was opened with metrics collection off:

1. Enable **Collect system metrics** in **Settings**.
2. Close and re-open the database.

## Reading the banner

When dsoq connections opened ≠ closed since connect, an amber banner calls it out: that divergence indicates a connection leak or handshake instability. Follow up in the **Log Analyzer** with transport filters.
