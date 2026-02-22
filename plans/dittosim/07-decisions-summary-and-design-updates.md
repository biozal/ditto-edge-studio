# DittoSim — Decisions Summary and Design Updates

**Status:** Complete — All design documents revised (2026-02-22)
**Created:** 2026-02-22
**Based on:** `05-questions-and-decisions.md` (all 20 questions answered)

This document summarizes every decision, identifies what changes in the existing design documents, and flags what research is still pending.

---

## 1. Complete Decision Summary

| # | Question | Decision |
|---|----------|----------|
| Q1 | Multiple simultaneous simulations? | **A** — One at a time. Simple simulator for demos and learning. |
| Q2 | Sample data `_id` handling in loops? | **C** — `{{uuid}}` template variable, auto-unique IDs per iteration. |
| Q3 | Unconfirmed bot at start time? | **C** — All bots must confirm. User runs this in a lab with phones on the desk — not a real problem. |
| Q4 | Running screen card colors? | **D** — Transport type. Cards show current primary transport. Colors change as transport changes. |
| Q5 | Maximum bot count? | **3×4 grid = 12 max.** Average test uses ~5 devices. |
| Q6 | iOS background execution? | **A** — Foreground only. Lab environment with always-on devices. No warning message needed (devs know). |
| Q7 | Bot recovery after going offline? | **C** — Resume from last logged step. Log the offline/resume event explicitly. |
| Q8 | Ditto identity type for bots? | **QR code driven** — same pattern already used in Edge Studio. Not a concern. |
| Q9 | Template variable complexity? | **A** — Simple path interpolation only. May never need more. n8n.io for complex stuff. |
| Q10 | Reactive scenario concurrency? | **B (backpressure)** — Kotlin Flows handle this natively via the SDK. No manual cap needed. |
| Q11 | Latency metrics? | **Everything we can log.** Primary metric: INSERT→observer receipt latency. Use `system:system_info` for snapshots. Needs more research. |
| Q12 | Export simulation results? | **A + C** — Raw JSON export + in-app results viewer with PDF export. |
| Q13 | Simulation list card contents? | Name, status, bot count, scheduled time, duration. |
| Q14 | Editing after creation? | **B** — Draft only. Immutable after "Create Simulation". |
| Q15 | "Save Progress" in wizard? | **Yes** — Must save as draft. Files take time to prepare. |
| Q16 | Steps embedded vs separate documents? | **Separate documents** — smaller docs sync better over any transport. New `__des_sim_steps` collection. |
| Q17 | How does bot know its peer key? | `ditto.presence.graph.localPeer.peerKey` — confirmed available in all SDKs. |
| Q18 | Simulation cleanup? | **Export-then-evict** — dump all docs to zipped JSON folder. Schema + Python script for offline reports. |
| Q19 | One file per bot vs bundled? | **One file per bot** — simpler to manage. |
| Q20 | Staggered bot start (`startOffsetSeconds`)? | **B** — Yes, per-bot offset in wizard Step 2. Default 0. |

**SDK Facts Confirmed:**
- Peer key is **stable** across sessions (only changes if DB directory deleted — won't happen in lab)
- `system:data_sync_info` is **NOT available on mobile** — use `system:system_info` instead
- `DittoTransportConfig` is **consistent across all SDKs** (Rust FFI)
- Max document size: **5 MB** — the simulator helps developers find their sweet spot for their use case
- Subscription count: **no hard limit**, customer apps typically have <8

---

## 2. Breaking Design Changes

Four decisions fundamentally change the existing design documents. These must be applied before implementation begins.

---

### Change 1: Steps Are Separate Documents (Q16)

**Affects:** `02-data-model-design.md`

The current design embeds steps as an array inside `__des_sim_scenarios`. This must change because **Ditto arrays are LWW registers** and large documents sync poorly over Bluetooth.

**New collection: `__des_sim_steps`**

Each step in a scenario file becomes its own document:

```json
{
  "_id": {
    "simId": "sim_abc123",
    "peerKey": "pk_device1",
    "scenarioIndex": 0,
    "stepIndex": 0
  },
  "type": "sleep",
  "description": "Customer wait",
  "params": {
    "minMs": 2000,
    "maxMs": 5000
  },
  "onError": "continue"
}
```

**Updated `__des_sim_scenarios` (no steps array):**

```json
{
  "_id": {
    "simId": "sim_abc123",
    "peerKey": "pk_device1",
    "scenarioIndex": 0
  },
  "name": "Order Insertion Loop",
  "type": "sequential",
  "stepCount": 4,
  "repeat": {
    "count": 50,
    "delayMs": 1000
  },
  "interScenarioDelayMs": 500
}
```

For reactive scenarios, the observer config moves into the scenario document:
```json
{
  "_id": { "simId": "...", "peerKey": "...", "scenarioIndex": 1 },
  "type": "reactive",
  "stepCount": 3,
  "observer": {
    "query": "SELECT * FROM orders WHERE status = 'pending'",
    "triggerOn": ["insert"]
  }
}
```

**Bot subscription now needs two queries:**
```
SELECT * FROM __des_sim_scenarios WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey
SELECT * FROM __des_sim_steps WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey
```

**Impact on scenario processing (orchestrator):**
- After parsing the uploaded JSON file, for each step: create one `__des_sim_steps` document
- Total document count = `sum(stepCount across all scenarios)` + `scenarioCount` + 1 (bot doc) + N (sample data)
- `processingProgress` on the simulation document should track step upload progress

---

### Change 2: Card Colors = Current Transport (Q4)

**Affects:** `04-system-workflow.md`, future running screen UI design

Bot cards in the running dashboard show the **current primary transport**, updated in real time.

**Color mapping:**

| Transport | Color | Hex (suggested) |
|-----------|-------|-----------------|
| P2P WiFi (AWDL) | Green | `#34C759` |
| LAN (local WiFi) | Teal | `#5AC8FA` |
| Bluetooth LE | Blue | `#007AFF` |
| WebSocket (Cloud) | Purple | `#AF52DE` |
| No transport / offline | Gray | `#8E8E93` |

**Primary transport = the fastest currently active transport** (priority: P2P WiFi > LAN > Cloud > Bluetooth).

**Implementation:** The bot's heartbeat already includes `activeTransports: [String]`. The orchestrator sorts this list by priority and picks the first entry as the card color. If `activeTransports` is empty or `lastHeartbeat` is stale (>30s), card turns gray.

**Card layout (updated):**
- Card background tint = primary transport color (subtle, 15-20% opacity)
- Top-right corner: small dots for ALL active transports (not just primary)
- Status dot (running/warning/error) moves to top-left corner
- The card color dynamically updates each time the heartbeat arrives with a different `activeTransports` value

---

### Change 3: Bot Recovery = Resume from Last Step (Q7)

**Affects:** `04-system-workflow.md`, `02-data-model-design.md`

This is required from Phase 1, not deferred to Phase 2. When a bot reconnects after going offline:

1. Bot re-initializes and observes its own `__des_sim_bots` doc
2. Bot queries its own logs for the highest `seq` where `eventType == "step_completed"` or `"step_started"`
3. Bot resumes from `lastCompletedStepIndex + 1` within the current scenario

**New log event type:** `"resumed_after_offline"` with fields:
```json
{
  "eventType": "resumed_after_offline",
  "resumedFromScenarioIndex": 0,
  "resumedFromStepIndex": 3,
  "offlineDurationMs": 45000
}
```

**`__des_sim_bots` needs two new fields:**
```json
{
  "offlineCount": 0,
  "lastOfflineAt": null
}
```

**Orchestrator response:** When a bot's heartbeat resumes after being marked "OFFLINE" in the UI, the card recovers to its previous color with a brief "reconnected" indicator.

---

### Change 4: `startOffsetSeconds` Per Bot (Q20)

**Affects:** `02-data-model-design.md`, wizard UI (Step 2)

Each bot gets its own start time offset. The orchestrator sets:
- `scheduledStartTime` = base simulation start time (on `__des_sim_simulations`)
- `startOffsetSeconds` = per-bot offset (stored on `__des_sim_bots`)
- Bot's effective start = `scheduledStartTime + startOffsetSeconds`

**`__des_sim_bots` gets a new field:**
```json
{
  "_id": { "simId": "...", "peerKey": "..." },
  "startOffsetSeconds": 10,
  "effectiveStartTime": "2026-02-22T14:00:10Z"
}
```

**Wizard Step 2 UX change:** Each bot row gets a numeric input: `Start offset: [0] seconds`. Default is 0. Range: 0 to 300 seconds (5 minutes).

---

## 3. Minor Design Updates

These are smaller changes that don't restructure the existing design but add or adjust specific behaviors.

---

### Update A: Reactive Backpressure (Q10)

Remove `maxConcurrentReactiveScenarios` from the scenario file format. The Ditto SDK's Kotlin Flows handle backpressure natively — the observer won't re-fire until the current execution completes. This simplifies the KMP implementation significantly.

**Remove from `03-scenario-file-format.md`:**
- `globalConfig.maxConcurrentReactiveScenarios` field
- Any documentation about dropping triggers beyond the cap

The reactive model is simply: observer fires → execute `steps[]` → observer is eligible to fire again.

---

### Update B: `system:system_info` Logging (Q11) — FINALIZED

Every 30 seconds during a simulation, each bot runs `SELECT * FROM system:system_info`, pivots the time-series rows into a flat snapshot (taking the most recent value per key), and INSERTs a consolidated log document:

```json
{
  "_id": { "simId": "...", "peerKey": "...", "seq": 42 },
  "eventType": "system_info_snapshot",
  "relativeMs": 30000,
  "data": {
    "connections_bluetooth": 2,
    "connections_p2pwifi": 1,
    "connections_accesspoint": 0,
    "connections_websocket": 0,
    "is_connected_to_ditto_cloud": true,
    "fs_usage_total": 38427256,
    "fs_usage_store": 3616808,
    "fs_usage_replication": 4445524,
    "transport_config": { "peer_to_peer": { "bluetooth_le": { "enabled": true }, "awdl": { "enabled": true } } },
    "recent_errors": [],
    "collection_num_docs": { "orders": 142 }
  }
}
```

The bot only stores entries from `system:system_info` with `timestamp >= simulationStartUnixSeconds` to avoid storing pre-simulation history.

**The `system:system_info` fields that matter most for DittoSim results:**
- `connections_bluetooth/p2pwifi/accesspoint/websocket` — peer count per transport over time
- `is_connected_to_ditto_cloud` — cloud connectivity timeline
- `transport_config` — detect when transport config changed (from `dittoTransportConfig` steps)
- `fs_usage_total` / `fs_usage_store` — storage growth during simulation
- `recent_errors` — connection failures with peer details
- `collection_num_docs[<user collection>]` — document accumulation in user collections

**Propagation latency:** Bot embeds `__des_sim_ts` (ms since simulation start) in user documents on INSERT. Receiving bot's observer computes `latencyMs = nowRelativeMs - doc.__des_sim_ts`. Opt-in via `"measurePropagationLatency": true` on reactive steps. See R2 resolution in Section 4 for full implementation.

---

### Update C: Export and Archive Flow (Q18)

The cleanup flow is user-initiated, not automatic:

1. User views completed simulation
2. User clicks "Export & Archive"
3. Orchestrator queries all `__des_sim_*` docs for this `simId`
4. Exports to a folder structure:
   ```
   sim_abc123_export/
   ├── simulation.json
   ├── bots/
   │   ├── bot_pk_device1.json
   │   └── bot_pk_device2.json
   ├── scenarios/
   │   ├── scenario_0_pk_device1.json
   │   └── ...
   ├── steps/
   │   ├── step_0_0_pk_device1.json
   │   └── ...
   ├── logs/
   │   ├── log_1_pk_device1.json
   │   └── ...
   └── README.md  (schema reference)
   ```
5. Zips the folder → user saves the ZIP
6. User optionally clicks "Delete Simulation" → orchestrator EVICTs all `__des_sim_*` docs for this `simId`

**Python analysis script:** A companion `analyze.py` script will be provided in the docs. It reads the exported ZIP and generates HTML reports with charts (propagation latency histograms, transport timelines, step duration distributions).

---

### Update D: Results Viewer (Q12)

The results view in Edge Studio needs to be a real visualization tool, not just raw data display:

**Results viewer panels (Phase 1 scope):**
1. **Summary header** — simulation name, total duration, bot count, total operations, error count
2. **Timeline** — horizontal chart, one row per bot, colored segments by transport, step events as dots
3. **Propagation latency chart** — histogram of INSERT→observer latency, filterable by transport
4. **System info timeline** — graph of `system:system_info` snapshots over time per bot
5. **Log stream** — scrollable timestamped log (same as running screen, but historical)

**PDF export:** Native macOS print dialog (`NSPrintOperation`) to PDF. The results viewer renders as a printable layout.

---

## 4. Research Resolved

### R1: `system:system_info` Schema — RESOLVED

**Sample data:** `plans/dittosim/system_info_example.json`

The collection returns a **time series of key-value entries**, each with `{ key, namespace, timestamp, value }`. Timestamps are **Unix seconds**.

**Namespaces and useful keys for DittoSim:**

| Namespace | Key | Useful For |
|-----------|-----|-----------|
| `presence` | `connections_bluetooth` | Active Bluetooth peer count over time |
| `presence` | `connections_p2pwifi` | Active P2P WiFi peer count over time |
| `presence` | `connections_accesspoint` | Active LAN/AP connections over time |
| `presence` | `connections_websocket` | Active cloud connections over time |
| `presence` | `is_connected_to_ditto_cloud` | Cloud connection state timeline |
| `core` | `transport_config` | Full transport config at each change point |
| `core` | `fs_usage_total` | Storage growth during simulation |
| `core` | `fs_usage_store` | Store (document) storage growth |
| `core` | `fs_usage_replication` | Replication data growth |
| `logs` | `recent_errors` | Connection errors (with remote peer details) |
| `replication` | `local_subscriptions[<query>]` | Which sync queries were active |
| `store` | `collection_num_docs[<name>]` | Document count growth per collection |

**What it does NOT expose:**
- No per-document sync timing or queue depth
- No bytes sent/received per peer
- No throughput rates
- No sync latency between specific peers

**DittoSim logging strategy:** Each bot periodically (every 30s) runs `SELECT * FROM system:system_info` and INSERTs a snapshot document into `__des_sim_bot_logs`. The orchestrator queries all snapshots after the simulation completes for the results viewer.

**For the results viewer, the time series enables:**
- Transport connection count chart (shows Bluetooth/WiFi/Cloud peer count over time)
- Transport config change timeline (derived from consecutive `transport_config` entries)
- Storage growth chart (total bytes over time)
- Error timeline (`recent_errors` entries during simulation period)
- Collection document growth chart (`collection_num_docs` per user collection)
- Bot connectivity status (from `is_connected_to_ditto_cloud`)

**DQL for snapshot:**
```dql
SELECT * FROM system:system_info
```
Returns an array of all time-series entries. The bot filters to entries with `timestamp >= simulationStartUnixSeconds` before storing (to avoid log bloat from pre-simulation history).

---

### R2: Propagation Latency Clock Sync — RESOLVED

**Decision:** Use **relative timestamps** (milliseconds since simulation start), not absolute wall-clock timestamps.

**Reason:** All bots use NTP but could have slight drift. Since we're measuring sync latency in the hundreds-of-milliseconds to seconds range, and NTP drift between LAN-connected devices is typically <10ms, relative timestamps give consistent results without clock coordination.

**Implementation:**

At simulation start, each bot records its local clock offset relative to the agreed `simulationStartTimeMs` from the simulation document:

```kotlin
val simStartMs = simulationDoc.scheduledStartTime  // from __des_sim_simulations
val myClockOffsetMs = System.currentTimeMillis() - simStartMs
// Store this as metadata — useful for debugging if latency seems off
```

All event timestamps in `__des_sim_bot_logs` are expressed as **milliseconds since `simulationStartTimeMs`**:

```kotlin
fun relativeNowMs(): Long = System.currentTimeMillis() - simStartMs
```

**Propagation latency measurement:**

When Bot A inserts a document into a user collection (e.g., `orders`), it adds a metadata field:
```json
{ "item": "Burger", "status": "pending", "__des_sim_ts": 45231 }
```
Where `45231` = milliseconds since simulation start.

When Bot B's reactive observer fires on that document:
```kotlin
val insertedAtRelativeMs = trigger.document["__des_sim_ts"] as Long
val receivedAtRelativeMs = relativeNowMs()
val latencyMs = receivedAtRelativeMs - insertedAtRelativeMs

// Log the latency event
insertLog(eventType = "propagation_latency", data = mapOf(
    "documentId" to trigger.document._id,
    "latencyMs" to latencyMs,
    "insertedAtMs" to insertedAtRelativeMs,
    "receivedAtMs" to receivedAtRelativeMs,
    "activeTransports" to currentActiveTransports()
))
```

**Bot scenario file opt-in:** The `reactive` step type gets a new optional field:
```json
{
  "type": "reactive",
  "observer": { "query": "SELECT * FROM orders WHERE status = 'pending'" },
  "measurePropagationLatency": true,
  "propagationLatencyField": "__des_sim_ts",
  "steps": [...]
}
```

When `measurePropagationLatency: true`, the bot automatically logs latency for every observed document that contains the timestamp field. This is opt-in because not all reactive scenarios are measuring sync performance — some are just responding to events.

---

## 5. Document Update Checklist

| Document | Changes Applied | Status |
|----------|----------------|--------|
| `02-data-model-design.md` | Added `__des_sim_steps` collection (7th collection); updated `__des_sim_scenarios` to remove steps array and add `stepCount`; added `startOffsetSeconds` + `effectiveStartTime` + `offlineCount` + `lastOfflineAt` to `__des_sim_bots`; updated subscriptions, ID table, DQL queries | ✅ Done |
| `03-scenario-file-format.md` | Removed `maxConcurrentReactiveScenarios`; added `measurePropagationLatency` + `propagationLatencyField` to reactive scenarios; updated KDS example | ✅ Done |
| `04-system-workflow.md` | Transport-colored cards (Q4 color mapping, primary transport logic); bot offline recovery flow (Q7 with full state machine); staggered starts via `effectiveStartTime`; `system:system_info` 30s poller; updated Document Ownership Matrix | ✅ Done |
| `05-questions-and-decisions.md` | Already updated with all answers | ✅ Done |
| `06-bot-app-kmp-design.md` | Removed `activeReactiveJobs` cap from reactive runner (Flow backpressure); added `ScenarioEngine` offline recovery class; added `startSystemInfoPoller()`; added propagation latency embedding pattern | ✅ Done |
| New: `09-results-viewer-design.md` | Design the results viewer UI, charts, PDF export, and Python analysis script | ⏳ Future |

---

## 6. Next Steps

In priority order:

1. **Research `system:system_info`** (R1 above) — determines the metrics design
2. **Research clock sync for propagation latency** (R2 above) — determines how reliable the primary metric is
3. **Update `02-data-model-design.md`** — apply the breaking changes from Q16, Q20, Q7
4. **Update `03-scenario-file-format.md`** — remove removed fields, add new parameters
5. **Update `04-system-workflow.md`** — transport-colored cards, recovery flow, staggered starts
6. **Update `06-bot-app-kmp-design.md`** — remove concurrency cap, add recovery logic
7. **Write Phase 1 implementation plan** — break the work into implementable tasks for Edge Studio (orchestrator side) and DittoBot (KMP)
