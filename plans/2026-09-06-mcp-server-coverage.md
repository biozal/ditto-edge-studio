# MCP Server Coverage Audit — what the embedded MCP server must do to expose Edge Studio to agents

**Date:** 2026-09-06
**Baseline:** `6334785` ("feat: presence viewer multicast transport + large-mesh modes (SwiftUI)", 2026-09-04) — the last commit that touched `SwiftUI/EdgeStudio/Data/MCPServer/` or `docs/MCP_SERVER.md` (`git log --oneline -- SwiftUI/EdgeStudio/Data/MCPServer/ docs/MCP_SERVER.md`).
**Head at audit time:** `4e4678b` on branch `pv-search` (unmerged).

> **Tooling note.** The repo's `CLAUDE.md` requires the Xcode MCP server (`XcodeRead`/`XcodeGrep`/`XcodeGlob`) for code discovery. This audit was performed with **shell tools** (`cat`, `grep`, `sed`, `git`, `ls`) plus the `Read` tool, because the session was running under a harness directive to prefer Bash for file reads. Every claim below carries a `file:line` citation so it can be re-checked with `XcodeRead`. No code was modified.

> **Scope correction on the brief.** The task brief listed 6 commits since the baseline. The real delta is **32 commits** (`git rev-list --count 6334785..HEAD`) — the baseline is an ancestor of several later merges (PRs #35/#36/#37/#39), so branches like the Log Analyzer parity work and the System Metrics screen also landed after the MCP server was last touched. Part A below covers the whole range.

---

## 1. Ground truth — the current tool surface

**15 tools**, defined in `MCPToolHandlers.allTools` (`SwiftUI/EdgeStudio/Data/MCPServer/MCPToolHandlers.swift:43-268`) and dispatched by `MCPToolHandlers.execute(toolName:arguments:)` (`:272-292`). Transport is HTTP/SSE on loopback, port from `UserDefaults` key `mcpServerPort` (default 65269), clamped rather than trapped (`MCPServerService.swift:331-338`). Enabled via `mcpServerEnabled`, default `false` (`Ditto_Edge_StudioApp.swift:85`, toggle at `Views/Settings/AppPreferencesView.swift:47`).

Protocol support is exactly three JSON-RPC methods — `initialize`, `tools/list`, `tools/call` (`MCPJSONRPCHandler.swift:63-76`); protocol version pinned to `2024-11-05` (`:86`). **There are no MCP resources, no prompts, no notifications, no progress, and no `tools/list_changed`.** Tool errors are returned as `isError: true` content, not JSON-RPC errors (`:128-136`), so an agent sees them as text.

| # | Tool | Params | What it actually does | Gaps / limits |
|---|---|---|---|---|
| 1 | `execute_dql` | `query` (req), `transport` (`local`\|`http`) | `QueryService.executeSelectedAppQuery` (`:327`) or `executeSelectedAppQueryHttp` (`:323`) | Returns `[String]` of **pretty-printed JSON text**, not structured rows (`QueryService.swift:69-87`). Mutations return the sentinel strings `"Document ID: …"` / `"Commit ID: …"` inside the array (`QueryService.swift:55-64`) rather than fields. **Never captures a PROFILE** — uses the non-profile overload. No result cap, no LIMIT injection, no timeout. HTTP path returns errors *as data* (`QueryService.swift:336-341`) and its empty sentinel is `"No items found"`, which `formatQueryResults` does not special-case (`MCPToolHandlers.swift:334`). Fully unguarded: any DQL, including `EVICT`, `DELETE`, `ALTER SYSTEM RESET ALL`. |
| 2 | `list_databases` | — | `DatabaseRepository.loadDatabaseConfigs()` (`:348`) | Returns `{id, name, databaseId, mode}` only — credentials correctly stripped (`:350-357`). No indication of which one is active. |
| 3 | `get_active_database` | — | reads `DittoManager.shared.dittoSelectedAppConfig` (`:370`) | Credentials stripped; `httpApiConfigured` is a bool (`:380`). **Omits** advanced config (sync scopes, startup settings), `collectSystemMetrics` state, and the persistence directory. |
| 4 | `list_collections` | — | `CollectionsRepository.refreshCollections()` (`:403`) | Index `fields` are flattened to `[String]` via `map(\.strippingBackticks)` (`:411`), **dropping ASC/DESC direction** that `IndexField.ascending` carries (`Models/DittoCollectionModel.swift:5-20`). |
| 5 | `create_index` | `collection`, `field` | `CollectionsRepository.createIndex(collection:fields:)` (`:455`) | **Single ascending field only** — hard-codes `[IndexField(name:, ascending: true)]` (`:442`) while the repository accepts `[IndexField]` with direction (`CollectionsRepository.swift:230, :317`). SDK 5.1 composite indexes are unreachable. |
| 6 | `drop_index` | `index_name`, `collection?` | resolves owner from `system:indexes`, then `DROP INDEX … ON …` via `QueryService` (`:513-515`) | Correct and careful (dot-safe prefix strip at `:535-543`). Detects the "error" substring in output (`:518`) — a fragile success test. |
| 7 | `get_query_metrics` | — | `QueryMetricsRepository.allRecords()` (`:563`) | Gated on `metricsEnabled` (`:558`). Cap is genuinely 200, FIFO (`QueryMetricsRepository.swift:6, :21-23`); in-memory only, lost on relaunch. Returns a **plain sentence**, not JSON, when disabled or empty (`:560, :565`) — an agent must string-match. |
| 8 | `get_sync_status` | — | `presence.graph.remotePeers.count` + config flags (`:598-611`) | **Counts the whole mesh, not direct peers** — see §2.2. **Omits `multicast`** from the transport block although `configure_transport` can set it. Does not use `ConnectionsByTransport` (`Models/ConnectionsByTransport.swift:5`), so per-transport connection counts are unavailable. |
| 9 | `configure_transport` | `bluetooth?`, `lan?`, `awdl?`, `multicast?`, `multicast_group_address?`, `multicast_port?`, `multicast_interface?` | stops sync → `applyTransportConfig` → persists → restarts sync (`:678-721`) | Mutating and heavyweight. Validates multicast group/port including the CFBoolean trap (`:627-629, :661-665`). **No `cloud` toggle.** Restart re-runs the whole `OpenSequence`, so it can fail-closed on sync scopes (`:711-721`). |
| 10 | `insert_documents_from_file` | `file_path`, `collection`, `mode?` | `ImportService.importData(documentData:to:insertType:)` (`:763`) | Batch size 50, failing batches retried per-document (`ImportService.swift:130, :173-205`). Collection-name validation permits a leading digit (`ImportService.swift:238`). Sandbox limits readable paths. |
| 11 | `set_sync` | `enabled` | `selectedDatabaseStartSync()` / `selectedDatabaseStopSync()` (`:795, :804`) | Start re-applies the full advanced config incl. fail-closed sync scopes (`docs/ADVANCED_DATABASE_CONFIG.md`, "Apply order"). |
| 12 | `get_peers` | — | `SystemRepository.fetchPeersOnce()` (`:822`) | **Wrong data — see §2.2.** Every peer is labelled `"connectionStatus": "Connected"` (`SystemRepository.swift:724`); `distanceMeters` is documented but can never appear (`SystemRepository.swift:170`). |
| 13 | `list_indexes` | — | flattens `refreshCollections()` (`:906-917`) | Same direction loss as `list_collections`. Returns `"[]"` rather than an error when no database is active (`:902-904`) — inconsistent with every other tool. |
| 14 | `get_app_logs` | `lines?`, `filter?` | reads CocoaLumberjack files via `LoggingService.getAllLogFiles()` (`:843`) | Returns raw text, not structured. Default 200 lines. Reads every file fully into memory each call (`:845-850`). |
| 15 | `get_ditto_logs` | `lines?`, `filter?`, `level?` | `LogFileParser.parseDirectory(persistenceDir)` (`:871`) | **Broken — returns `[]` on every current build. See §2.1.** |

### 1.1 Tests pin the count

`SwiftUI/EdgeStudioUnitTests/MCP/MCPToolManifestTests.swift:18` asserts `allTools.count == 15`, and `SwiftUI/EdgeStudioIntegrationTests/MCP/MCPToolExecutionTests.swift:28` is named "tools/list over HTTP returns 15 tools". **Every item in Part B must update both.**

---

## 2. Confirmed defects in tools that already ship

These are not gaps; they are wrong behaviour in shipped MCP tools. Per `docs/FIX_VERIFICATION_RULE.md` each is labelled with its confirmation basis.

### 2.1 `get_ditto_logs` returns nothing, always — **P0**

`getDittoLogs` calls `LogFileParser.parseDirectory(persistenceDir)` (`MCPToolHandlers.swift:871`) where `persistenceDir` is `DittoManager.activePersistenceDirectory`, assigned as `<app support>/ditto_edge_studio/<name-id>/database` (`DittoManager.swift:116-119, :159`). `LogFileParser.parseDirectory` uses `contentsOfDirectory` and is **not recursive** (`LogFileParser.swift:10-20`). The SDK writes its rotating logs into a `ditto_logs/` subdirectory.

**Confirmations (4, independent):**
1. Code reading, above.
2. On-disk verification during this audit: `…/ditto_edge_studio/quickstarts-…/database/` contains `ditto_logs/`, `ditto_store/`, `ditto_replication/`, … and **zero** files matching `*.log` at its top level.
3. The identical bug was found and fixed **in this very commit range** for the app's own log viewer — `DittoLogCaptureService.loadHistoricalLogs` now probes `["ditto_logs", "logs"]` and bails with a warning if neither exists (`DittoLogCaptureService.swift:118-131`, added by the diff `6334785..HEAD`). Its commit message states the old path "silently returned zero entries on every current build". **The MCP handler was never given the same fix.**
4. `docs/LOG_ANALYZER_SPEC.md:302-310` is normative and states the log directory is `<persistenceDir>/ditto_logs/` with a `logs/` fallback, and that reading `logs/` only returns zero entries on every current build.

Both other readers in the app do the probe correctly — `DittoLogCaptureService.swift:125-127` and `LoggingDetailView.swift:879-881`. The MCP handler is the only one that does not.

**Fix:** apply the same probe in `getDittoLogs`, or reuse `DittoLogCaptureService.loadHistoricalLogs`. Add an integration test that asserts a non-empty parse against a fixture directory laid out as `…/database/ditto_logs/x.log`.

### 2.2 `get_peers` and `get_sync_status` report the full mesh as if it were directly connected — **P0**

`docs/PRESENCE_GRAPH.md:5-8` is normative: "`presenceGraph.remotePeers` returns the **full mesh topology** … **Never use it unfiltered** for peer cards or transport-count aggregation."

- `SystemRepository.fetchPeersOnce()` reads `ditto.presence.graph.remotePeers` with no filter (`SystemRepository.swift:658-662`) and emits `"connectionStatus": "Connected"` as a **hard-coded literal** for every one of them (`:724`).
- It calls `extractPeerEnrichment(from: peer, filteredBy: appConfig)` (`:685`) — **omitting `localPeerKeyString`**, whose default is `nil` (`:87`). That short-circuits the local-endpoint filter at `:152-158`, whose own comment says filtering there "ensures only directly connected transports appear on the peer card". So for an indirect peer the `connections` array lists **that peer's links to third parties**, presented as if they were links to us.
- `getSyncStatus` independently makes the same mistake: `connectedPeers` is `ditto.presence.graph.remotePeers.count` (`MCPToolHandlers.swift:598-600`).
- The **live UI path does it correctly** — `registerSyncStatusObserver` applies the direct filter at `SystemRepository.swift:268-280`. So the GUI and the MCP tool disagree about how many peers are connected.

**Confirmations (2):** the normative doc rule, and the divergence between `fetchPeersOnce` and `registerSyncStatusObserver` in the same file.

**Also wrong in the same tool:** `distanceMeters` is documented (`docs/MCP_SERVER.md:233, :246`) and advertised in the tool description ("connection types, **distances**", `MCPToolHandlers.swift:215`), but `extractPeerEnrichment` hard-codes `approximateDistanceInMeters: nil` with the comment "removed in Ditto SDK v5" (`SystemRepository.swift:170`). The field can never be emitted. **Remove it from the description and the doc.**

**Fix:** add an `isDirectlyConnected` boolean per peer and a `directPeerCount` alongside `meshPeerCount`, and pass `localPeerKeyString` into `extractPeerEnrichment`. Do **not** silently drop indirect peers — a mesh-debugging agent wants them; it just needs them labelled.

### 2.3 `syncedUpToCommitId` is very likely always empty — **UNVERIFIED**

`fetchPeersOnce` reads the field as `as? String` (`SystemRepository.swift:729`); `SyncStatusInfo` reads the same `system:data_sync_info` column as `as? Int` (`Models/SyncStatus.swift:171`), and `PeerDetailCardView` renders it via `String.init` from an `Int` (`Components/PresenceViewer/PeerDetailCardView.swift:86`). One of the two casts is wrong. If the SDK returns a number, the MCP tool emits `""` for every peer. **This needs a runtime check against a live database — I could not settle it from code.**

### 2.4 Documentation drift in `docs/MCP_SERVER.md`

| Line | Claim | Reality |
|---|---|---|
| `:98`, `:183-190` | `configure_transport` takes "Bluetooth, LAN, or AWDL" | Also takes `multicast`, `multicast_group_address`, `multicast_port`, `multicast_interface` (`MCPToolHandlers.swift:157-172`). **Four undocumented parameters.** |
| `:141` | `get_active_database` transport block is `{bluetoothLE, lan, awdl, cloudSync}` | Also returns `multicast` (`MCPToolHandlers.swift:388`). |
| `:195` | `insert_documents_from_file` path "must be in ~/Downloads" | The tool description is weaker and more accurate: Downloads is "the reliable location; other paths may work if the sandbox permits" (`MCPToolHandlers.swift:178`). |
| `:233, :246` | `get_peers` returns `distanceMeters` | Impossible — see §2.2. |
| `:421` | "~1400 lines across four files" | 1621 (`118 + 171 + 405 + 927`). |
| `:180` | `get_sync_status` transport block | Omits `multicast`, matching the code — but the code itself is the bug (§2.2 / Part B B7). |

`:391` ("change the port via `defaults write` (future: Settings UI)") is **still accurate** — `AppPreferencesView` displays `mcpServerPort` but offers no editor (`Views/Settings/AppPreferencesView.swift:28, :53-56`).

---

## 3. Capability matrix — app surface vs MCP

| Capability | Status | Detail |
|---|---|---|
| DQL execution, local | **PARTIAL** | Text-only results; no PROFILE; no ADVISE parsing; unguarded destructive statements. |
| DQL execution, HTTP | **PARTIAL** | Works, but errors arrive as data strings and the `"No items found"` sentinel isn't handled. |
| Commit IDs on mutation | **PARTIAL** | Present only as magic strings inside the results array (`QueryService.swift:55-64`). |
| Execution profiles | **NOT EXPOSED** | `executeSelectedAppQueryWithProfile` exists (`QueryService.swift:121`) but MCP calls the plain overload. `QueryProfile` is a single-slot, in-memory, MainActor value on `QueryViewModel:50` — never persisted, no repository. |
| ADVISE (index advisor) | **NOT EXPOSED (reachable)** | An agent can type `ADVISE SELECT …` through `execute_dql`; only the structured extraction (`QueryAdviceExtractor`, `Models/QueryAdvice.swift:30-68`) is missing. |
| Query history | **NOT EXPOSED** | `HistoryRepository` (`LIMIT 1000`, `Data/Repositories/HistoryRepository.swift:47-51`). |
| Favorites | **NOT EXPOSED** | `FavoritesRepository.favorites(for:)` is a safe non-stamping read (`:68`). |
| Subscriptions | **NOT EXPOSED** | `SubscriptionsRepository.getCachedSubscriptions()` (`:223`), `saveDittoSubscription` (`:84`), `removeDittoSubscription` (`:173`). |
| Observables / observe events | **NOT EXPOSED** | `ObservableRepository` (`:49, :82, :150`); events only via `ObservableEventStore` (cap 500, `Models/ObservableEventStore.swift:17`) which lives on a **view model**, not a repository. |
| Collections + doc counts | **FULLY EXPOSED** | |
| Indexes | **PARTIAL** | Read loses ASC/DESC; create is single-field-ascending only. |
| App/process metrics | **NOT EXPOSED** | `MetricsRepository.processMetricSnapshot()` / `queryMetricSnapshot()` (`:30, :52`). |
| Query metrics | **FULLY EXPOSED** | |
| System metrics (`system:metrics`) | **NOT EXPOSED (reachable)** | `SystemMetricsService.query = "SELECT * FROM system:metrics"` (`:43`) — an agent can run it directly. Only the host-side delta accumulation (`Models/SystemMetrics.swift:42`) is app-specific. |
| Disk usage / storage | **NOT EXPOSED** | `StorageRepository.fetchStorageSnapshot()` (`:6`) — 7 directory categories plus per-collection CBOR bytes. |
| Presence peer list | **PARTIAL, INCORRECT** | §2.2. |
| Presence mesh topology (edges) | **NOT EXPOSED** | `PresenceEdgeAggregator.aggregate/directVisiblePeerKeys/meshVisiblePeerKeys` — pure, headless (`Components/PresenceViewer/PresenceProtocols.swift:177, :225, :251`). |
| Peer detail card data | **NOT EXPOSED** | `PresencePeerDetail` — pure Foundation, covers **indirect** peers (`Components/PresenceViewer/PresencePeerDetail.swift:16`). |
| Peer search (new, `pv-search`) | **N/A — GUI navigation** | `PresencePeerSearch.matches` filters on name+key (`:79-88`) over data `get_peers` already returns. |
| Local peer info | **NOT EXPOSED** | `SyncStatusViewModel.loadLocalPeerInfo()` (`:110`) — device name, SDK language/platform/version. |
| Network interfaces / WiFi diagnostics | **NOT EXPOSED** | `NetworkDiagnosticsService.fetchAllInterfaces()` (`:50`). |
| Sync start/stop | **FULLY EXPOSED** | |
| Transports | **PARTIAL** | Settable; `get_sync_status` under-reports (no multicast, no per-transport counts). |
| Advanced config (sync scopes, startup settings) | **NOT EXPOSED** | `Models/AdvancedDatabaseSettings.swift`, `AdvancedSettingsApplier.swift`; outcome in `DittoManager.lastAdvancedApplyResult` (`:19`). |
| Attachments | **NOT EXPOSED** | `AttachmentService.createAndLink/fetch` (`:85, :144`); delete is a DQL null-out (`AttachmentViewModel.deleteAttachmentStatement:173`). |
| Import | **FULLY EXPOSED** (file path only) | |
| Export | **NOT EXPOSED — and barely exists** | No export service; `.fileExporter` UI only (`Views/StudioView/Details/DetailViews.swift:360-365`). An agent has the data already. |
| Permissions health | **DOES NOT EXIST on macOS** | Only `NetworkDiagnosticsService.checkLocationPermission()` (private, `:348`). `CLAUDE.md`'s "Permissions health checking" feature claim and its "Views/Tools/ (presence, disk usage, peers, permissions)" list are both **stale** — `Views/Tools/` holds only Font Debug, Help, and Quickstart windows. |
| Log Analyzer (analytics, connection sessions, patterns) | **NOT EXPOSED** | `LogAnalytics.compute(entries:matches:)` (`:168`), `LogConnectionTracker.track(_:)` (`:268`) — both pure static `Sendable` functions over `[LogEntry]`. |
| Ditto SDK logs | **BROKEN** | §2.1. |
| App logs | **FULLY EXPOSED** | |
| SDK log level control | **NOT EXPOSED** | `DittoManager.changeDittoLogLevel(_:for:)` (`Data/DittoManager.swift:781`). Without it an agent can read logs but not make them more informative — B12b. |
| Log pattern catalog (user patterns) | **NOT EXPOSED** | `LogPatternStore` (`Data/LogPatternStore.swift:15`) — deliberately rejected, §4. |
| Database config CRUD | **READ-ONLY** | `DatabaseRepository.addDittoAppConfig/updateDittoAppConfig/deleteDittoAppConfig` (`:156, :202, :250`) unexposed — correctly, see §6. |
| Selecting / opening a database | **NOT EXPOSED** | The single biggest workflow blocker — Part B B1. |
| QR sharing | **NOT EXPOSED** | Correctly — the payload carries credentials (§6). |

---

## Part A — changes since `6334785` that affect MCP

### A1. `get_ditto_logs` is now provably dead, and the fix exists next door — **P0, S**
The `ditto_logs/` vs `logs/` discovery landed in this range (`DittoLogCaptureService.swift:118-131`). The MCP handler still uses the old assumption. **Action:** apply the same directory probe at `MCPToolHandlers.swift:871`. See §2.1.

### A2. A whole Log Analyzer analytics layer landed, entirely unexposed — **P0, M**
New in range: `LogAnalytics.swift` (+300), `LogConnectionTracker.swift` (+275), `LogEntryContext.swift` (+50), `LogScanResult.swift` (+19), plus `LogAnalyticsSection.swift`, `LogFilterTabs.swift` and a rewritten `LoggingDetailView.swift`. `docs/LOG_ANALYZER_SPEC.md` is now normative across SwiftUI/Android/VS Code. The computation is headless: `LogAnalytics.compute(entries:matches:) -> LogAnalytics` (`:168`) and `LogConnectionTracker.track([LogEntry]) -> LogConnectionTracker` (`:268`). **Action:** Part B B4.

### A3. System Metrics became its own screen — **P1, S**
`SystemMetricsDetailView.swift` (+927) replaced `SystemMetricsSectionView.swift` (deleted), backed by `SystemMetricsService` (`system:metrics`, 5 s poll, `:42-43`) and a new per-database `SystemMetricsPinStore` (+213). `SidebarDestination` gained `.systemMetrics` (`Views/MainStudioView.swift:641-649`).
**Action:** *not* a new tool (an agent can `execute_dql("SELECT * FROM system:metrics")`) — but `get_active_database` should report the `collectSystemMetrics` flag, because the exporter is **startup-gated** via a `setenv` before `Ditto.open` (`DittoManager.swift:162-169`) and an agent that reads zero metric rows currently has no way to learn why. `SystemMetricsService` also now exposes `refreshNow()` (`:72`) and a `hasZeroed` instance flag (`:40`) so totals survive screen revisits.

### A4. Presence gained peer detail cards and (unmerged) peer search — **P1 for detail, REJECT for search**
`PresencePeerDetail.swift` (+87), `PeerDetailCardView.swift` (+155), `PresenceProtocols.swift` (+112) and, on `pv-search`, `PresencePeerSearch.swift` (+99) with `PresencePeerSearchField`/`ResultsCard`.
- **`PresencePeerDetail` is a real gap**: it carries `isDirectlyConnected`, `isCompatible`, `isConnectedToDittoCloud`, metadata key counts, and works for **indirect** peers (`:25, :38`) — everything `get_peers` gets wrong or omits. Part B B7.
- **`PresencePeerSearch` should not become a tool.** It is `matches(in:query:)`, a case-insensitive substring over `name` and `key` (`:79-88`), over candidates the agent already receives from `get_peers`. An agent filters lists natively. Its only non-trivial output is the graph-dimming contract (`nil` vs empty set), which is purely visual (`docs/PRESENCE_GRAPH.md:98-104`).

### A5. `SystemRepository` refactor — no MCP behaviour change
OS mapping was extracted to `PeerOS(dittoPeerOS:)` and is now shared with the detail card (`SystemRepository.swift:90-92`). Output strings are unchanged, so `get_peers`'s `osType` is unaffected. **No action.**

### A6. `SyncStatusInfo.==` now compares every rendered field — no MCP behaviour change
`Models/SyncStatus.swift:231-255` widened equality because `SyncStatusViewModel` now gates assignment on inequality. MCP does not consume `SyncStatusInfo`. **No action** — but it is a reminder that `get_peers` and the peer cards are built from two different code paths that can drift.

### A7. The in-app DQL Console was added and then reverted — nothing lost
`DebugConsoleService.swift` (−93) and `DebugConsoleView.swift` (−136) were removed (commits `1dc5142` then `d1ccba4`); `ResultViewTab` is back to `raw|table|profile` (`Components/QueryResultsView.swift:4-8`). `DebugSocketClient.swift` is retained but unused, documented as reserved for a future *external*-process attach (`:7-15`). **No MCP action** — but note that if that attach feature ships, "run DQL against another process's Ditto" would be a genuinely new MCP capability that `execute_dql` cannot cover.

### A8. Repository writes now refuse across a database switch — **affects any future mutating tool**
`InvalidStateError.isStaleSessionRefusal` (`FavoritesRepository.swift:252`) is thrown by history/favorites/subscriptions/observables when `currentDatabaseId` changed mid-operation, and call sites now swallow it deliberately (`Components/QueryToolbarView.swift:74-77`, `ImportSubscriptionsView.swift:264-268`). **Action:** every tool in Part B that writes must capture `databaseId` up front and treat a stale-session refusal as an informational outcome, not a failure.

### A9. `MulticastConfig.interfaceName` default-nil style change — cosmetic
`Models/MulticastConfig.swift:18`. **No action.**

---

## Part B — prioritized work listing

Effort: **S** ≤ half a day, **M** 1–3 days, **L** > 3 days or needs a design decision.
Every item must also bump the two hard-coded tool counts (§1.1).

---

### P0

#### B1 — `select_database` (and `close_database`)
- **Purpose:** unblock every other tool. Today all 13 database-scoped tools fail with "No active database. Select a database in Edge Studio first." (`MCPToolHandlers.swift:30`) until a human clicks a card. An agent asked to "check the retail demo database" cannot get started.
- **Params:** `database_id` (matches `list_databases[].id`); `close_database` takes none.
- **Calls:** `DittoManager.hydrateDittoSelectedDatabase(_:)` (`Data/DittoManager.swift:102`) / `closeDittoSelectedDatabase()` (`:29`).
- **Effort:** **M–L.** The complication is not the actor call — it is that the *UI* selection lives on `ContentView.ViewModel.showMainStudio` (`Views/ContentView.swift:853-888`), a `@MainActor` view-model instance with no shared accessor. Calling `hydrate` directly opens the Ditto instance while the GUI still shows the picker. Needs either a small shared coordinator or a notification the view observes. **See §7 — this needs a human decision.**
- **Priority:** **P0.** Justification: it is the difference between an agent-usable server and a server that requires a human babysitter for every session.

#### B2 — Fix `get_ditto_logs` (§2.1 / A1)
- **Effort:** **S.** One directory probe plus a fixture-based integration test.
- **Priority:** **P0.** A shipped tool that silently returns an empty array is worse than no tool — the agent concludes "no SDK log entries", which is a wrong diagnosis, not a missing one.

#### B3 — Fix presence correctness in `get_peers` / `get_sync_status` (§2.2)
- **Purpose:** stop reporting the mesh as direct connections.
- **Changes:** pass `localPeerKeyString` into `extractPeerEnrichment` (`SystemRepository.swift:685`); add `isDirectlyConnected` per peer; replace the hard-coded `"Connected"` (`:724`) with a real status; in `get_sync_status` report `directPeerCount` **and** `meshPeerCount`; add `multicast` to the transport block; drop the phantom `distanceMeters` from the description and doc.
- **Calls:** `SystemRepository.fetchPeersOnce()`, `PresenceEdgeAggregator.directVisiblePeerKeys(localPeer:remotePeers:)` (`Components/PresenceViewer/PresenceProtocols.swift:225`).
- **Effort:** **M.** **Priority:** **P0** — wrong data actively misleads a debugging agent, and it contradicts the GUI.

#### B4 — `analyze_logs`
- **Purpose:** the single largest genuinely-new agent capability. Turns 700k raw log lines into: level counts, problem/critical counts, connection **sessions** with durations, reinit events, unmatched ends, SDK version, and the time range. This is exactly the reduction an agent cannot do cheaply itself — matching the tri-platform pattern rules is not something to reimplement in a prompt.
- **Params:** `source` (`ditto_sdk` | `app` | `both`), `max_entries?`, `level?`, `filter?`, `include_sessions?` (default true), `include_histograms?` (default **false** — bins are for charts, not agents).
- **Returns:** `{counts: {critical, errors, warnings, problems, problemEntries, criticalEntries, totalLines}, range: {start, end}, sdkVersion, sessions: [{start, end, durationSec, remotePeer, transport, role, connectionId}], reinits: [...], unmatchedEnds, topProblems: [{severity, patternKey, recommendation, count, example}]}`.
- **Calls:** `LogFileParser.parseDirectory(<persistenceDir>/ditto_logs)` → `LogPatternEngine(patterns:).scanAll(_:maxEntries:)` → `LogAnalytics.compute(entries:matches:)` (`Data/LogAnalytics.swift:168`) and `LogConnectionTracker.track(_:)` (`Data/LogConnectionTracker.swift:268`). All pure and `Sendable`.
- **Implementation note:** this is essentially a ~15-line re-creation of `Views/Logging/LoggingDetailView.swift:165-190`, which is the only place the full pass is currently assembled. The one MainActor dependency is `LogPatternStore` (`Data/LogPatternStore.swift:15`), which loads the bundled `problem_patterns.json` plus the user's `user_patterns.json`; hop for it, or load the bundled catalog directly.
- **Respect the existing caps:** `LogPatternEngine.maxScanEntries = 5000` (`:96`), `maxUserPatternLength = 512` (`:99`), `LogConnectionTracker.sessionHistoryCap = 1000` (`:176`). ⚠️ `NSRegularExpression` has **no timeout**; the only ReDoS protection is a nested-quantifier reject at `LogPatternEngine.swift:105-108`. Do not let an MCP parameter raise `maxEntries` without bound.
- **Effort:** **M.** **Priority:** **P0** — "why does sync keep dropping" is the archetypal Ditto debugging question, and connection-session durations answer it directly. Depends on B2 for the log path.

#### B5 — `list_subscriptions` / `add_subscription` / `remove_subscription`
- **Purpose:** in Ditto, "the data isn't there" is most often "it isn't subscribed". An agent currently cannot see or change what is subscribed, which puts the most common root cause out of reach.
- **Params:** list — none; add — `name`, `query`; remove — `id`.
- **Calls:** `SubscriptionsRepository.getCachedSubscriptions()` (`:223` — the non-stamping read; **do not** use `loadSubscriptions`, which re-registers every subscription with the sync engine as a side effect, `:65`), `saveDittoSubscription(_:databaseId:)` (`:84`, this is the register path), `removeDittoSubscription(_:)` (`:173`, the cancel path).
- **Effort:** **M.** Must handle `isStaleSessionRefusal` (A8) and must not displace the UI's single-slot `setOnSubscriptionsUpdate` callback (`:217`).
- **Priority:** **P0.**

---

### P1

#### B6 — Structured results and profile capture for `execute_dql`
- **Purpose:** the agent currently receives an array of pretty-printed JSON *strings* it must re-parse, and mutation results hide the commit ID inside a string like `"Commit ID: abc"` (`QueryService.swift:55-64`). Profiles — the richest query-tuning data the app has — are never captured over MCP.
- **Params:** add `format` (`text` default for compatibility | `structured`) and `profile` (bool, SELECT-only).
- **Returns (structured):** `{rows: [...], rowCount, mutatedDocumentIds: [...], commitId, profile?: {elapsedNs, parseNs, planNs, resultCount, plan: {...}}}`.
- **Calls:** `QueryService.executeSelectedAppQueryWithProfile(query:)` (`Data/QueryService.swift:121`) returning `QueryExecutionResult` (`:10-20`). Note `QueryProfile` is **not** `Codable` (`Models/QueryProfile.swift:17`) — needs a hand-written serializer, and `QueryProfileOperator.attributes` is a tuple array (`:61`).
- **Effort:** **M.** Profile is gated on `metricsEnabled` and SELECT-only (`QueryService.swift:128-131`); return an explicit reason when skipped rather than a silent `null`.
- **Priority:** **P1.**

#### B7 — `get_peer_detail`
- **Purpose:** the per-peer facts `get_peers` cannot give: `isDirectlyConnected`, `isCompatible`, `isConnectedToDittoCloud`, `syncedUpToLocalCommitId`, `lastUpdateReceivedTime`, metadata key counts — and it works for **indirect** peers, which is precisely where mesh debugging happens.
- **Params:** `peer_key`.
- **Calls:** `PresencePeerDetail(peer:isLocal:isDirectlyConnected:syncStatus:)` (`Components/PresenceViewer/PresencePeerDetail.swift:55`), with `isDirectlyConnected` from `PresenceEdgeAggregator.directVisiblePeerKeys` (`PresenceProtocols.swift:225`).
- **Effort:** **S–M** (the type is pure Foundation; the plumbing is fetching the peer and its `SyncStatusInfo`). **Priority:** **P1.**

#### B8 — `get_presence_graph`
- **Purpose:** mesh **topology**, which no current tool provides. Nodes plus deduplicated typed edges, so an agent can answer "is C reaching me through B?" — the exact question `docs/PRESENCE_GRAPH.md` exists to explain.
- **Params:** `direct_only?` (default false).
- **Returns:** `{localPeerKey, nodes: [{key, name, isLocal, isDirect}], edges: [{from, to, type}]}`.
- **Calls:** `PresenceEdgeAggregator.aggregate(localPeer:remotePeers:showDirectConnectedOnly:)` (`PresenceProtocols.swift:177`) plus `meshVisiblePeerKeys` (`:251`). Pure and headless. **Do not** touch `PresenceNetworkScene` / `NetworkLayoutEngine` — layout geometry is for pixels.
- **Effort:** **S–M.** **Priority:** **P1.**

#### B9 — `get_storage_usage`
- **Purpose:** "the database is 4 GB, what's in it" — answerable only through this repository. Gives seven directory categories plus per-collection CBOR payload bytes, which is how an agent decides what to `EVICT`.
- **Params:** `include_collections?` (default **false**).
- **Calls:** `StorageRepository.fetchStorageSnapshot()` (`Data/Repositories/StorageRepository.swift:6`).
- **Effort:** **S.** ⚠️ The collection breakdown is **O(total documents across all collections)** — it materializes every document to sum `cborData().count` (`:82-112`, and `docs/METRICS.md:227-231` warns it takes seconds on large databases). Hence the opt-in flag and a documented cost note in the tool description.
- **Priority:** **P1.**

#### B10 — `get_advanced_config` (read-only)
- **Purpose:** diagnose "my setting isn't taking effect". Returns the configured sync scopes and startup settings **plus** which ones actually applied and which were skipped and why.
- **Params:** none.
- **Calls:** `DittoManager.lastAdvancedApplyResult` (`Data/DittoManager.swift:19`) — an `AdvancedApplyResult` with `appliedSettings` / `skippedSettings` (`Models/AdvancedDatabaseSettings.swift:254-261`); config from `dittoSelectedAppConfig.collectionSyncScopes` / `.startupSettings`.
- **Effort:** **S.** **Priority:** **P1.** **Read-only — the write side is deliberately rejected, see §6.**

#### B11 — Extend `create_index` to composite / directional indexes
- **Purpose:** SDK 5.1 supports composite indexes and the repository already accepts them; MCP does not. An agent asked to optimise `WHERE a = ? ORDER BY b DESC` cannot create the index that fixes it.
- **Params:** accept `fields: [{name, ascending?}]` alongside the existing scalar `field` (keep it for compatibility).
- **Calls:** `CollectionsRepository.createIndex(collection:fields:)` (`:230`), already `[IndexField]`.
- **Also:** emit `{name, ascending}` from `list_indexes` / `list_collections` instead of flattening to strings (`MCPToolHandlers.swift:411, :914`).
- **Effort:** **S.** **Priority:** **P1.**

#### B12 — Enrich `get_sync_status`
- **Purpose:** make one call answer "is sync healthy". Add `multicast`, per-transport connection counts, `syncEnabled`, and whether the system-metrics exporter is on.
- **Calls:** `ConnectionsByTransport` (`Models/ConnectionsByTransport.swift:5` — already `Codable` with `totalConnections`, `activeTransports`) via `SystemRepository.registerConnectionsPresenceObserver` semantics, or a one-shot equivalent; `UserDefaults` `collectSystemMetrics`.
- **Effort:** **M** (needs a pull-style counterpart to the push-only connections observer at `SystemRepository.swift:528`). **Priority:** **P1.** Folds in the B3 fix.

#### B12b — `set_log_level`
- **Purpose:** the missing half of the log tools. The classic debugging loop is *raise the SDK log level → reproduce → read the logs*. An agent can do steps 2 and 3 (once B2 lands) but not step 1, so it is stuck with whatever verbosity the human last chose. `logLevel` is per-database config (`Models/DittoConfigForDatabase.swift`, values `error|warning|info|debug|verbose`).
- **Params:** `level`.
- **Calls:** `DittoManager.changeDittoLogLevel(_:for:)` (`Data/DittoManager.swift:781`) — persists the config **and** sets `DittoLogger.minimumLogLevel` when a database is open. ⚠️ Per its own contract the caller must set `config.logLevel` on the MainActor **first**; the method does not mutate the config object.
- **Effort:** **S.** **Priority:** **P1.** Two caveats belong in the tool description: the level is process-wide (`DittoLogger.minimumLogLevel` is global, set before `Ditto.open` at `DittoManager.swift:150-153`), and `verbose` on a busy mesh rolls the 7-file × 5 MB log window in minutes.

---

### P2

#### B13 — `list_observers` / `add_observer` / `remove_observer` / `get_observer_events`
- **Purpose:** watch live change streams — genuinely useful for "does writing X actually propagate", but strictly less common than subscriptions.
- **Calls:** `ObservableRepository.loadObservers/saveDittoObservable/removeDittoObservable` (`:49, :82, :150`).
- **Effort:** **L.** ⚠️ The blocker: **registration and the event store live on a view model, not a repository** — `SubscriptionObserverViewModel.registerStoreObserver` (`:310`) and `eventStore` (`:52`, cap 500). `ObservableRepository.loadObservers` explicitly does **not** restore the live observer (`:62`). Exposing this properly means lifting the store into a repository first. **Priority:** **P2**, and honestly this is a refactor task wearing a tool's clothes.

#### B14 — `get_query_advice`
- **Purpose:** structured SDK 5.1 index advice — `{outcome, suggestions: [{collection, reason, statement}]}` — instead of the raw ADVISE rows.
- **Calls:** `QueryService.executeSelectedAppQuery("ADVISE …")` + `QueryAdviceExtractor.extract(from:)` (`Models/QueryAdvice.swift:30-68`).
- **Effort:** **S.** **Priority:** **P2** — an agent can already run `ADVISE` through `execute_dql`; this only saves it from parsing. Pairs naturally with B11 (advice → composite index).

#### B15 — `get_app_metrics`
- **Purpose:** process health (resident/virtual memory, CPU time, open FDs, uptime) and aggregate query stats.
- **Calls:** `MetricsRepository.processMetricSnapshot()` (`:30`), `queryMetricSnapshot()` (`:52`).
- **Effort:** **S.** **Priority:** **P2** — an agent debugging a *database* rarely needs the host app's RSS, and when it does, `ps` is one shell call away. Cheap enough to be worth adding, not worth prioritising. Note `getOpenFDCount` only scans fds 0–1023 (`:108-114`).

#### B16 — `get_local_peer_info`
- **Purpose:** our own SDK language/platform/version and device name — the baseline for "are peers on compatible SDKs".
- **Calls:** currently only `SyncStatusViewModel.loadLocalPeerInfo()` (`:110`) — a view model; the underlying query is `SELECT ditto_sdk_language, ditto_sdk_platform, ditto_sdk_version FROM __small_peer_info`, reachable today via `execute_dql`.
- **Effort:** **S.** **Priority:** **P2** — borderline reject; fold the three fields into `get_active_database` rather than adding a tool.

#### B17 — `get_network_interfaces`
- **Purpose:** WiFi/Ethernet diagnostics — SSID, BSSID, RSSI, noise, SNR, channel/band/width, MTU, AWDL presence.
- **Calls:** `NetworkDiagnosticsService.fetchAllInterfaces()` (`Data/NetworkDiagnosticsService.swift:50`).
- **Effort:** **S.** **Priority:** **P2.** ⚠️ SSID/BSSID require **Location permission**, and `requestLocationPermissionIfNeeded()` (`:100`) puts a **system permission dialog** on screen. An MCP tool must never trigger that — report `locationPermissionGranted: false` and let the human grant it in the GUI.

#### B18 — `read_history` / `read_favorites`
- **Purpose:** "what has this user been running" — occasionally useful context.
- **Calls:** `FavoritesRepository.favorites(for:)` (`:68`, safe non-stamping read). ⚠️ `HistoryRepository` has **no** non-stamping equivalent — `loadHistory(for:)` re-stamps `currentDatabaseId` (`:47-51`) and would hijack the live UI session's write guard. Needs a new read method first.
- **Effort:** **M** because of that. **Priority:** **P2.**

#### B19 — Attachments (`list_attachments` / `fetch_attachment`)
- **Purpose:** inspect attachment tokens found in query results.
- **Calls:** `AttachmentInfo.detectTokens(in:)` (`Models/AttachmentInfo.swift:35`) is pure and could annotate `execute_dql` results at near-zero cost — **do that instead of a tool**. `AttachmentService.fetch(token:)` (`:144`) returns raw `Data`, which does not belong in an MCP text response.
- **Effort:** **S** for detection, **L** for transfer. **Priority:** **P2**, and only the detection half.

---

## 4. Considered and rejected

| Considered | Verdict | Reason |
|---|---|---|
| `search_peers` (from the new `pv-search` work) | **Reject** | `PresencePeerSearch.matches` is a case-insensitive substring over `name` and `key` (`PresencePeerSearch.swift:79-88`) across data `get_peers` already returns. Agents filter lists natively. Its real output is a set of keys to *dim in a SpriteKit scene* — a GUI affordance with no headless meaning. |
| `focus_peer` / presence viewer camera, zoom, Direct toggle, background effects | **Reject** | Pure canvas control. `PresenceNetworkScene`/`PeerNode`/`ConnectionLine`/`FloatingSquaresLayer` are SpriteKit-only. Expose the **graph** (B8), never the viewport. |
| `get_layout` / `NetworkLayoutEngine.calculateLayout` | **Reject** | Returns `CGPoint` positions and ring radii. Pixels. An agent that wants topology wants B8's edge list. |
| Pinned System Metrics (`SystemMetricsPinStore.read/write`) | **Reject** | A per-user, per-database UI preference persisted in `UserDefaults` (`SystemMetricsPinStore.swift:44-48`). Zero diagnostic content, and writing it silently rearranges the human's dashboard. |
| Drag-to-reorder math (`SystemMetricsPinOrdering`, `dropIndex`, `gapOffset`) | **Reject** | Gesture geometry. |
| `get_system_metrics` as a dedicated tool | **Reject (mostly)** | `SystemMetricsService.query` is literally `"SELECT * FROM system:metrics"` (`:43`) — reachable today via `execute_dql`. The app-specific part is host-side delta accumulation across 5 s polls (`Models/SystemMetrics.swift:42`), which an agent can reproduce with two reads. **Kept from it:** surface the `collectSystemMetrics` gate in `get_active_database` (A3), because that is the one thing an agent cannot discover. |
| `export_query_results` / `export_logs` | **Reject** | There is no export *service* — export is a SwiftUI `.fileExporter` over data the agent already holds (`Views/StudioView/Details/DetailViews.swift:360-365`, `Components/ResultJsonViewer.swift:123-128`). An agent that has the rows can write its own file. |
| QR generate/scan (`QRCodeGenerator`, `SubscriptionQRDisplayView`) | **Reject — and dangerous** | Requires a camera or a rendered image, neither of which exists over MCP. Worse, the `EDS2:` payload copies `developmentToken`, `httpApiKey` and `secretKey` (`Models/DittoConfigForDatabase.swift:256-280`); a `generate_qr` tool would be a credential-exfiltration primitive returning base64. See §6. |
| Font Debug window, Help documentation, Quickstart browser/download | **Reject** | Developer/UI utilities. `Views/Tools/` contains only these. |
| `create_database` / `update_database` / `delete_database` | **Reject** for now | `DatabaseRepository.addDittoAppConfig/updateDittoAppConfig/deleteDittoAppConfig` (`:156, :202, :250`) write credential-bearing config into a **plaintext** SQLite store (§6). Creating a database means an agent supplying an app ID and token over an unauthenticated localhost socket. Needs a human decision before any of it ships. |
| `set_advanced_config` (sync scopes / startup settings) | **Reject** for now | Sync scopes are a **data-containment** control that is fail-closed by design (`docs/ADVANCED_DATABASE_CONFIG.md`). Flipping a collection from `LocalPeerOnly` to `AllPeers` publishes device-local data to the mesh and the cloud. Startup settings include acknowledgement-gated parameters like `metrics_exporter_prometheus_http_listener_addr` (defaults to `0.0.0.0:9000`) and `additional_p2p_trusted_ca_certs` — an agent must not be able to open a listening socket or add a trusted CA. **Read-only (B10) only.** |
| `clear_query_metrics` / `clear_logs` / `clear_history` | **Reject** | Destroying the human's diagnostic record so the agent's own reads look tidy is a bad trade, and none of these unblock any analysis. |
| Observer/subscription/favorites **callback registration** over MCP | **Reject** | Every `setOn*Update` hook is **single-slot** — `SystemRepository.swift:506`, `HistoryRepository.swift:208`, `FavoritesRepository.swift:216`, `SubscriptionsRepository.swift:217`, `ObservableRepository.swift:194`. An MCP registration would silently displace the GUI's own callback and break the live UI. Poll instead. |
| `debug_socket` / `DebugSocketClient` | **Reject (today)** | Retained but unused; it opens a socket back to our *own* process to run DQL that `execute_dql` already runs directly (`Data/DebugSocketClient.swift:7-15`). Its `execute(_:)` (`:91`) runs arbitrary DQL against whatever socket path it is handed, with no validation. Exposing it means resurrecting a dead path. Revisit only if the external-process attach feature ships (A7). |
| Log-pattern CRUD (`add_log_pattern` / `delete_log_pattern`) | **Reject** | `LogPatternStore.add/update/delete` (`:122, :136, :144`) **write to disk** — `~/Library/…/ditto_edge_studio/log-analyzer/user_patterns.json` (`:45-52`). That is the human's saved configuration, and a user-supplied regex reaches an `NSRegularExpression` with no timeout. If an agent wants a one-off match it can filter `analyze_logs` output itself. Reading the pattern catalog would be harmless, but adds nothing. |
| `reset_system_settings` / `ALTER SYSTEM RESET ALL` | **Reject** | `DittoManager.resetSystemSettingsToDefaults(for:)` (`:342`) and `AdvancedSettingsApplier.resetAllToDefaults()` (`:324`) are indiscriminate — the applier's own comment (`:319-323`) says the caller **must** re-apply transports, `DQL_STRICT_MODE`, the mesh cap and sync scopes afterwards. It also deliberately leaves sync stopped on failure (`DittoManager.swift:428-433`). Too easy to leave the human's database in a worse state than the agent found it. |
| Quickstart download (`QuickstartDownloadService`) | **Reject — and dangerous** | Fetches a ~100 MB zip from GitHub (`:30`), shells out to `/usr/bin/unzip` via `Process` (`:137-148`), **writes the playground token in cleartext** into `.env` and YAML files in a user-chosen directory *outside* the sandbox container (`:190-194, :218`), and offers a recursive delete of a caller-supplied URL (`:306`). Every one of those is a capability an unauthenticated localhost tool should not have. |
| `SQLCipherService.executeRawForTesting` | **Reject** | Arbitrary SQL against the plaintext credential store. **Verified `#if DEBUG`-guarded** (`Data/SQLCipherService.swift:1112-1129`), so it is compiled out of Release — but the MCP server is only `#if os(macOS)`-guarded, not Debug-guarded, so in a Debug build the two coexist in one process. Nothing routes to it today; keep it that way. |
| Permissions health check | **Reject** | Does not exist on macOS. The only primitive is a private `checkLocationPermission()` (`NetworkDiagnosticsService.swift:348`). Building it for MCP would be net-new product work, not exposure. Update `CLAUDE.md`, which claims the feature exists. |

---

## 5. Cross-cutting engineering notes for whoever implements Part B

1. **Do not call `load*` repository methods from MCP.** `HistoryRepository.loadHistory`, `FavoritesRepository.loadFavorites`, `SubscriptionsRepository.loadSubscriptions` and `ObservableRepository.loadObservers` all **stamp `currentDatabaseId`**, which is the live UI session's write guard. `loadSubscriptions` additionally **re-registers every subscription with the sync engine** (`SubscriptionsRepository.swift:65`). Use `getCachedSubscriptions()` (`:223`) and `favorites(for:)` (`:68`); history and observables need new safe reads.
2. **Handle `isStaleSessionRefusal`** on every write (A8).
3. **Return JSON, always.** Four handlers currently return prose — `get_query_metrics` when disabled or empty (`MCPToolHandlers.swift:560, :565`), `execute_dql` sentinels (`:334`), `create_index` (`:458-460`), `drop_index` (`:519-521`). New tools should not add to that; consider migrating the old ones behind a `format` param.
4. **`list_indexes` returns `"[]"` instead of erroring with no active database** (`:902-904`), unlike its 12 siblings. Make it consistent.
5. Request bodies are capped at **4 MB** (`MCPServerService.swift:146`); responses are unbounded. A `SELECT *` over a large collection materializes every row as pretty-printed JSON in memory (`QueryService.swift:69-87`) — consider a `limit` parameter on `execute_dql` and a documented response ceiling.
6. Bump `MCPToolManifestTests.swift:18` and `MCPToolExecutionTests.swift:28`.
7. `MCPToolHandlers.swift` is 927 lines and every handler is a `private static func` in one enum. Adding ~10 tools warrants splitting it by domain before, not after.

---

## 6. Security considerations

The server binds loopback-only (`NWParameters.requiredInterfaceType = .loopback`, `MCPServerService.swift:355`) and is **off by default** (`Ditto_Edge_StudioApp.swift:85`) — both good. But **there is no authentication**: any process running as the user can drive every tool. That is the frame for everything below.

### Already dangerous, shipping today

- **`execute_dql` can destroy a data-containment control, permanently for the session.** `docs/ADVANCED_DATABASE_CONFIG.md` states plainly that `ALTER SYSTEM RESET ALL` against an already-syncing instance clears the sync scopes for the rest of the session, and that re-applying them to a live session is **not** a fix (the SDK requires scopes before `start_sync()`). A collection the human marked `LocalPeerOnly` then replicates to the mesh and the cloud, while the GUI still shows "Local Peer Only". `execute_dql` accepts arbitrary DQL with no statement filtering.
  **Guard:** classify statements. At minimum refuse `ALTER SYSTEM` (including `RESET`) unless an explicit `allow_system_statements: true` argument is passed, and mention sync scopes in the refusal.
- **`execute_dql` performs unbounded destructive writes** — `DELETE`, `EVICT`, `UPDATE` with no `WHERE` guard, no dry-run, no row-count preview. The doc acknowledges this (`docs/MCP_SERVER.md:376`) but nothing enforces it.
  **Guard:** a `read_only` server-level setting (default **on** would be a behaviour change — default off, but surfaced in Settings), and/or return an affected-row estimate for destructive statements before executing.
- **`configure_transport` and `set_sync` silently change the human's live network behaviour.** `set_sync(false)` halts all replication until re-enabled; `configure_transport` restarts sync and can fail-closed on sync scopes, leaving the database not syncing. Both are already exposed with no confirmation.
- **The credential store is plaintext.** `docs/CREDENTIAL_STORAGE.md` is explicit: `SQLCipherService` imports Apple's system `SQLite3`, the `PRAGMA key` calls are silent no-ops, the file has the `SQLite format 3` magic and mode `0644`, and a reviewer read the live `databaseConfigs` rows with the stock `sqlite3` CLI and no key. The **only** protection is the macOS app container. MCP does not currently expose this store — `list_databases` and `get_active_database` strip credentials correctly (`MCPToolHandlers.swift:350-357, :374-390`) — but it sets a hard rule for Part B: **no new tool may read, write, or echo `token`, `authToken`, `httpApiKey`, `secretKey`, or `developmentToken`, in any form, including error messages.**

### Rules for the proposed tools

- **B1 `select_database`** switches which database every subsequent tool targets — including destructive ones. Log every selection at `Log.info`, and have `get_active_database` report *when* and *by what* the selection last changed.
- **B4 `analyze_logs` and `get_ditto_logs` return log content, which is not sanitized.** SDK logs carry peer keys, IP addresses, interface names and connection metadata; `LogEntry.rawLine` is the raw JSON line. Treat log output as sensitive; do not add a "post this to a URL" convenience anywhere near it.
- **B9 `get_storage_usage`** with `include_collections: true` reads **every document in every collection** to sum CBOR bytes (`StorageRepository.swift:82-112`). It returns only sizes, but an agent can trivially DoS a large database with a loop. Keep it opt-in and consider rate-limiting.
- **B17 `get_network_interfaces`** must never call `requestLocationPermissionIfNeeded()` (`NetworkDiagnosticsService.swift:100`) — an MCP call that raises a macOS permission dialog trains the human to click through prompts they did not initiate.
- **`delete_database` would be an unrecoverable data-loss primitive.** `DatabaseRepository.deleteDittoAppConfig` (`:250-288`) closes the database if open, CASCADE-deletes its subscriptions, history, favorites and observables (`:256-261`), then `FileManager.removeItem`s the **entire on-disk database directory** (`:264-274`). No confirmation, no undo.
- **`update_database` erases advanced config by omission.** The write path overwrites every column, so an agent constructing a partial `DittoConfigForDatabase` silently wipes `collectionSyncScopes` and `startupSettings`. The model comment at `Models/DittoConfigForDatabase.swift:56-61` says exactly this, which is why those two init parameters have no defaults.
- **Rejected outright as exfiltration primitives:** QR generation (`sanitizedForSharing()` at `Models/DittoConfigForDatabase.swift:249` strips advanced settings but **not** `developmentToken`, `secretKey` or `httpApiKey`, and `QRCodeGenerator.encodePayload:103-116` base64s the lot); the Quickstart downloader (writes the playground token in cleartext outside the sandbox container, `QuickstartDownloadService.swift:190-194, :218`); database-config write tools; and any tool that returns the persistence directory path *plus* a file-read capability.

### Recommended baseline hardening (independent of Part B)

1. **A shared-secret header**, checked in `MCPHTTPConnectionHandler.handleRequest` before routing (`MCPServerService.swift:169-183`), with the token shown in Settings. Cheap, and it closes "any local process" down to "any local process the user told".
2. **An audit log of every `tools/call`** — tool name, arguments, active database — through `Log.info`. There is none today; a mutating tool leaves no trace.
3. **A visible indicator in the app while an MCP session is connected**, not just the Settings status dot.
4. Reconsider the default `default_tools_approval_mode = "writes"` in `.codex/config.toml` once destructive-statement classification exists.

---

## 7. Unverified / needs a human decision

1. **`syncedUpToCommitId` type mismatch (§2.3).** `as? String` in `SystemRepository.swift:729` vs `as? Int` in `Models/SyncStatus.swift:171`. Needs one run against a live synced database to settle. If Int is correct, `get_peers` has been emitting `""` for this field since it shipped.
2. **How `select_database` (B1) should interact with the GUI.** Three options, all product decisions: (a) MCP drives the UI too (agent selection navigates the human's window); (b) MCP opens the database headlessly and the UI is unaware — risks two owners of one Ditto instance; (c) MCP can only select when no database is open. My recommendation is (a) with a visible banner, but this is not mine to choose.
3. **Whether `execute_dql` should default to read-only.** Safer, and a breaking change for existing agent workflows.
4. **Whether a shared-secret is wanted at all**, or whether "loopback + off by default + it's my machine" is the accepted threat model. `docs/MCP_SERVER.md:379-381` currently answers this with "disable it when not in use", which is a process control, not a technical one.
5. **`ObservableEventStore` lives on a view model (B13).** Lifting it into a repository is a refactor with UI blast radius; whether that is worth doing *for MCP* is a judgement call.
6. **Protocol version `2024-11-05` is pinned** (`MCPJSONRPCHandler.swift:86`). Whether to move to a newer MCP revision — and thereby gain resources/prompts, which would suit read-only surfaces like `list_collections` and `get_active_database` better than tools do — is unexamined here.
7. **Whether `pv-search` (`4e4678b`) merges before this work starts.** Nothing in Part B depends on it; B7/B8 touch `PresenceProtocols.swift`, which that branch also modified, so ordering matters only for merge conflicts.
8. **Stale claims in `CLAUDE.md`** — three, all of which cost time in this audit and will cost the next one:
   - "Permissions health checking" is listed as a key feature. It does not exist on macOS (only a private `checkLocationPermission()` at `NetworkDiagnosticsService.swift:348`).
   - `Views/Tools/` is described as "(presence, disk usage, peers, permissions)". It actually contains `FontDebugWindow`, `HelpContentView`, `HelpDocumentationWindow`, `QuickstartBrowserWindow`, `QuickstartProgressWindow`.
   - The architecture section lists eight `DittoManager_*.swift` files (`_Lifecycle`, `_Query`, `_Subscription`, `_Observable`, `_LocalSubscription`, `_DittoAppConfig`, `_Import`). **None of them exist** — `DittoManager` is one 802-line file with three same-file `extension` blocks (`Data/DittoManager.swift:633, :680, :772`). `SwiftUI/CLAUDE.md` repeats the same list, and also still documents a `websocketUrl` plist key that the root `CLAUDE.md` says is no longer needed.
9. **`docs/METRICS.md` predates the System Metrics screen.** It documents only the App and Query metrics views and never mentions `system:metrics`, `SystemMetricsService`, or the pin store, all of which landed in this commit range (A3).
