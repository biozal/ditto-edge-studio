# Rail Features — Android Edge Studio

Canonical names and functions for the Navigation Rail items, top to bottom, and
what each one puts in the **Data Panel**, **Content Pane**, and **Inspector**
(region names defined in [`UI_TERMINOLOGY.md`](UI_TERMINOLOGY.md)).

![Rail Features — Android Edge Studio](images/rail-features.png)

*(Source: [`images/rail-features.svg`](images/rail-features.svg) — regenerate the PNG with `rsvg-convert -w 3840 --keep-aspect-ratio rail-features.svg -o rail-features.png`)*

---

## Quick Reference

The Rail is defined by `StudioNavItem` in
[`viewmodel/MainStudioViewModel.kt`](../../android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt)
(enum order = top-to-bottom rail order). Canonical names are the terms used in
docs, plans, and conversation; code names are what you'll grep for.

| # | Canonical Name | Code Enum | Code Label | Material Icon | Data Panel |
|---|---|---|---|---|---|
| 1 | **Presence** | `SUBSCRIPTIONS` | "Presence" | `Icons.Outlined.Sync` | Yes |
| 2 | **Query Workbench** | `QUERY` | "Query Workbench" | `Icons.Outlined.Storage` | Yes |
| 3 | **Observation** | `OBSERVERS` | "Observation" | `Icons.Outlined.Visibility` | Yes |
| 4 | **Log Analyzer** | `LOGGING` | "Log Analyzer" | `Icons.Outlined.Description` | No — full-width Content Pane |
| 5 | **App Metrics** | `APP_METRICS` | "App Metrics" | `Icons.Outlined.Memory` | No — full-width Content Pane |
| 6 | **Query Metrics** | `QUERY_METRICS` | "Query Metrics" | `Icons.AutoMirrored.Outlined.ManageSearch` | Yes — executed-query list |
| 7 | **Database Metrics** | `DISK_USAGE` | "Database Metrics" | `Icons.Outlined.DataUsage` | No — full-width Content Pane |

**App Metrics** and **Query Metrics** are gated by the **Collect Metrics** toggle
(Settings screen, opened from the Database List top bar; `AppPreferences.metricsEnabled`,
mirrors SwiftUI's `SidebarDestination.isMetricsDestination`). When disabled, both items
are hidden from the rail and drawer (`StudioNavItem.visibleEntries`), an active metrics
section auto-navigates to Presence, no metrics data is captured, and the Query
Workbench inspector hides its Metrics tab. Enabled by default.

Every rail item exposes feature documentation in the Inspector, rendered from a
Markdown file sourced from `docs/help/` (synced to `assets/help/` by
`scripts/sync-help-docs.sh`) via `StudioNavItem.helpFileName` →
`ui/mainstudio/inspector/HelpContentView.kt` (Markwon renderer).

> All code paths below are relative to
> `android/app/src/main/java/com/costoda/dittoedgestudio/` unless noted.

---

## 1. Presence

Everything about the mesh: what this peer is syncing and who it is connected to.

| Region | Contents |
|---|---|
| **Data Panel** | **Subscriptions** list — the DQL subscriptions registered on this peer, i.e. what data is being synced between peers. Add/edit/remove via FAB. |
| **Content Pane** | Two features: **Connected Peers** (local peer info, remote peers, transports, network interfaces) and the **Presence Graph** (visual mesh topology). |
| **Inspector** | Feature documentation. |

**Layout is user-configurable** via Settings → "Split Presence view" (default OFF).
Because the peers view / Presence Viewer is not selection-driven and needs the full
width, OFF keeps it full-width at every window size — the subscriptions list opens from
the modal Nav Drawer (drawer-mode widths) or the Presence toolbar's Subscriptions dialog
(rail-mode widths). ON restores list-beside-peers at ≥600dp.

| Part | Code |
|---|---|
| Rail item | `StudioNavItem.SUBSCRIPTIONS` → `SubscriptionsKey` |
| List pane (Data Panel) | `ui/mainstudio/SubscriptionsListPane.kt`; section entry-point `ui/mainstudio/PresenceSection.kt` → `PresenceListSection` |
| Content pane (Connected Peers) | `ui/mainstudio/PresenceSection.kt` → `PresenceContentSection`; tabs: "Peers List" (`ConnectedPeersScreen.kt`) + "Presence Viewer" (`PresenceGraphView.kt`). Not selection-driven: it is the default full-width view at every width (no compact drill-in key) |
| Presence Graph | `ui/mainstudio/presence/PresenceGraphView.kt` (+ `PresenceGraphState.kt`, `PresenceGraphLayout.kt`, `PresenceGraphRenderer.kt`), wired into the "Presence Viewer" tab of `PresenceContentSection` |
| Data layer | `data/repository/SubscriptionsRepositoryImpl.kt`, `data/repository/SystemRepositoryImpl.kt` (peers, sync status, transports) |
| Inspector docs | `assets/help/subscription.md` |

---

## 2. Query Workbench

The primary working surface: browse collections, write and run DQL, inspect results.

| Region | Contents |
|---|---|
| **Data Panel** | **Collections** list — each collection shows its document count and the indexes applied to it; the user can add and remove indexes from here. |
| **Content Pane** | **Query Editor** (write and run DQL against the collections) with **Query Results** shown below. |
| **Inspector** | **Query History**, **Favorite Queries**, **JSON Document Viewer**, **Query Metrics** (per-query EXPLAIN), and feature documentation. |

| Part | Code |
|---|---|
| Rail item | `StudioNavItem.QUERY` → `QueryKey` |
| List pane (Collections, Data Panel) | `ui/mainstudio/CollectionsListPane.kt`; section entry-point `ui/mainstudio/QueryWorkbenchSection.kt` → `QueryWorkbenchListSection`; data via `data/repository/CollectionsRepositoryImpl.kt` (doc counts, index add/remove) |
| Content pane (Query Editor + Results) | `ui/mainstudio/QueryWorkbenchSection.kt` → `QueryWorkbenchContentSection` hosting `QueryEditorScreen.kt`; Ctrl/Cmd+Enter runs query; state persists on session-scoped `QueryWorkbenchState`; on compact the editor is the default full-width view and the collections list lives in the Nav Drawer (no drill-in key) |
| Execution | `data/repository/QueryExecutionService.kt`; state in `viewmodel/QueryEditorViewModel.kt` |
| Inspector | Rich `ui/mainstudio/inspector/QueryInspectorView.kt` (History / Favorites / JSON viewer / Metrics tabs); threaded via scaffold's `inspectorContent` slot |
| Inspector — History | `ui/mainstudio/inspector/QueryHistoryInspector.kt`, `data/repository/HistoryRepositoryImpl.kt` |
| Inspector — Favorites | `ui/mainstudio/inspector/QueryFavoritesInspector.kt`, `data/repository/FavoritesRepositoryImpl.kt` |
| Inspector — JSON viewer | `ui/mainstudio/inspector/QueryJsonInspector.kt` |
| Inspector — Query metrics | `ui/mainstudio/inspector/QueryMetricsInspector.kt`, `data/repository/QueryMetricsRepositoryImpl.kt` |
| Inspector docs | `assets/help/query.md` |

---

## 3. Observation

Live-query observers: register them, activate them, and watch the change events they fire.

| Region | Contents |
|---|---|
| **Data Panel** | **Observers** list — every observer that has been registered, with an indicator showing whether it is currently activated. Add/edit/delete from here. |
| **Content Pane** | **Events list** — the events fired by the selected (activated) observer; selecting an event shows its results/detail below. The table is paginated (page-size selector + prev/next, SwiftUI `PaginationControls` parity). |
| **Inspector** | Feature documentation. |

Event capture (SwiftUI `ObservableEventStore` parity): events are in-memory only,
hard-capped at 500 with FIFO eviction (`domain/model/ObserveEventStore.kt`), and
coalesced — Ditto callbacks accumulate in a pending buffer that a single job flushes
to StateFlow every 100 ms so hot queries produce batched recompositions.

| Part | Code |
|---|---|
| Rail item | `StudioNavItem.OBSERVERS` → `ObserversKey` |
| List pane (Observers, Data Panel) | `ui/mainstudio/ObserversListPane.kt`; section entry-point `ui/mainstudio/ObserversSection.kt` → `ObserversListSection`; CRUD + activation in `viewmodel/MainStudioViewModel.kt` |
| Content pane (Events list + detail) | `ui/mainstudio/ObserversSection.kt` → `ObserverEventsSection` hosting `ObserverDetailScreen.kt` (pagination chrome); `ObserverEventsTable` (top) + `ObserverEventDetailView` (bottom, with insert/update/delete/move filters); pushed via `ObserverEventsKey` |
| Event buffer | `domain/model/ObserveEventStore.kt`; capture/flush lifecycle in `data/session/StudioSession.kt` (`activateObserver`, `enqueueObserverEvent`, flush job) |
| Data layer | `data/repository/ObservableRepositoryImpl.kt`; models `DittoObservable`, `DittoObserveEvent` |
| Inspector docs | `assets/help/observe.md` |

---

## 4. Log Analyzer

Ditto SDK log capture. No Data Panel — the Content Pane takes the full width so
there is maximum room for log lines.

| Region | Contents |
|---|---|
| **Data Panel** | Not used (hidden). |
| **Content Pane** | Log viewer with filtering — by level, by component, and free-text search (including pattern user tags); live capture plus historical log files. Pattern problem matching: user-defined regex patterns (severity 1–5, recommendation, exact level filter, component tag filter, user tag) scanned against the newest 5k entries at ≤1 scan/sec; matches surface in a collapsible problems strip above the list and as user-tag chips on rows. Pattern manager (bundled read-only catalog + user CRUD with live regex validation and a test-line field) opens from the toolbar tune icon. |
| **Inspector** | Feature documentation. |

| Part | Code |
|---|---|
| Rail item | `StudioNavItem.LOGGING` → `LoggingKey` |
| Content pane (single-pane, full-width) | `ui/mainstudio/SinglePaneSections.kt` → `LoggingSection` → `LoggingScreen.kt` |
| Problems strip | `ui/mainstudio/LogProblemsSection.kt` |
| Pattern manager | `ui/mainstudio/LogPatternManagerSheet.kt` (list + editor dialog) |
| Pattern engine/store | `data/logging/LogPatternEngine.kt` (validation + scan, ReDoS guards), `data/logging/LogPatternStore.kt` (bundled `assets/problem_patterns.json` + `<filesDir>/log-analyzer/user_patterns.json`); models in `domain/model/LogPattern.kt` |
| Data layer | `DittoLogCaptureService` (live capture), `LogFileParser`; models `LogEntry`, `LogComponent` |
| Inspector docs | `assets/help/logging.md` |

---

## 5. App Metrics

Process-level health of the running app. No Data Panel — full-width Content Pane.

| Region | Contents |
|---|---|
| **Data Panel** | Not used (hidden). |
| **Content Pane** | Card-based metrics about the running app: memory (resident/virtual), CPU time, file descriptors, uptime. Auto-refreshes every 15 seconds. |
| **Inspector** | Feature documentation. |

| Part | Code |
|---|---|
| Rail item | `StudioNavItem.APP_METRICS` → `AppMetricsKey` |
| Content pane (single-pane, full-width) | `ui/mainstudio/SinglePaneSections.kt` → `AppMetricsSection` → `ui/mainstudio/metrics/AppMetricsScreen.kt` |
| State / refresh | `viewmodel/AppMetricsViewModel.kt` |
| Data layer | `data/repository/AppMetricsRepositoryImpl.kt` |
| Inspector docs | `assets/help/appmetrics.md` |

---

## 6. Query Metrics

EXPLAIN-level analysis of every query run against the current database — records persist in Room across app restarts (200-record cap per database).

| Region | Contents |
|---|---|
| **Data Panel** | List of queries executed against the current database (statement, run count, duration) — persisted in Room across app restarts. |
| **Content Pane** | Detailed information for the query selected in the Data Panel — full EXPLAIN output. |
| **Inspector** | Feature documentation. |

**Width adaptation** follows the Material 3 list-detail pattern: at ≥600dp (Medium and
up — including flip phones when open, ~690dp) the `ListDetailSceneStrategy` renders the
executed-query list and EXPLAIN detail side-by-side. Below 600dp (Compact — cover
screens, narrow split-screen) the section body is the list alone; tapping a row pushes
`QueryMetricDetailKey` as a full-screen drill-in with an Up arrow in the top bar, and
system back returns to the list.

| Part | Code |
|---|---|
| Rail item | `StudioNavItem.QUERY_METRICS` → `QueryMetricsKey` |
| List pane (executed-query list, Data Panel) | `ui/mainstudio/metrics/QueryMetricsListPane.kt`; section entry-point `ui/mainstudio/QueryMetricsSection.kt` → `QueryMetricsListSection` |
| Content pane (EXPLAIN detail) | `ui/mainstudio/metrics/QueryMetricsDetailPane.kt`; section entry-point `ui/mainstudio/QueryMetricsSection.kt` → `QueryMetricsDetailSection`; pushed via `QueryMetricDetailKey` |
| Data layer | `data/repository/QueryMetricsRepositoryImpl.kt`; model `QueryMetrics` (auto-capture, 200-record cap — `QueryMetricsRepositoryImpl.MAX_RECORDS`). Capture is gated by Settings → "Collect Metrics" (`AppPreferences.metricsEnabled`) AND the Query Workbench toolbar's "Capture query metrics" toggle; records persist in Room (`query_metrics` table, including the DQL text in `query_text`). |
| Inspector docs | `assets/help/querymetrics.md` |

---

## 7. Database Metrics

What the Ditto database costs on disk. No Data Panel — full-width Content Pane.

| Region | Contents |
|---|---|
| **Data Panel** | Not used (hidden). |
| **Content Pane** | Storage metrics for the database: total database file size and the size of each collection, with size indicators. Auto-refreshes every 15 seconds. |
| **Inspector** | Feature documentation. |

| Part | Code |
|---|---|
| Rail item | `StudioNavItem.DISK_USAGE` → `DiskUsageKey` |
| Content pane (single-pane, full-width) | `ui/mainstudio/SinglePaneSections.kt` → `DiskUsageSection` → `ui/mainstudio/metrics/DiskUsageScreen.kt` |
| State / refresh | `viewmodel/DiskUsageViewModel.kt` |
| Data layer | `data/repository/DatabaseMetricsRepositoryImpl.kt` |
| Inspector docs | `assets/help/diskusage.md` |

---

## Known Gaps (canonical spec vs. current code)

| Item | Gap |
|---|---|
| Naming | UI labels now use the canonical names (`StudioNavItem.label`); only the code enum constants (`SUBSCRIPTIONS`, `DISK_USAGE`, `LOGGING`, `OBSERVERS`) retain legacy names — they are stable identifiers (persisted in SavedStateHandle) and intentionally unchanged. |

---

*Region terminology (Rail, Data Panel, Content Pane, Inspector, Nav Drawer): [`UI_TERMINOLOGY.md`](UI_TERMINOLOGY.md)*
*Layout source of truth: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/StudioScaffold.kt` + `android/app/src/main/java/com/costoda/dittoedgestudio/ui/navigation/AppNavGraph.kt`*
