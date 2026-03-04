# DittoSim — System Workflow & State Machine

**Status:** Updated — All decisions applied (2026-02-22)
**Last Updated:** 2026-02-22

This document describes the full end-to-end workflow of a simulation from creation to results, including orchestrator behavior, bot behavior, sync patterns, and error handling.

---

## 1. System Roles

### Orchestrator (Ditto Edge Studio — macOS/iPadOS)
- Hosts the simulation wizard UI
- Parses uploaded scenario files and creates all Ditto documents
- Monitors bot confirmations and provides the Schedule button
- Provides the live running dashboard
- Subscribes to bot logs and problems
- Provides post-simulation results view

### Bot (DittoBot app — KMP/iOS/Android)
- Runs on physical mobile devices
- Scans QR code to connect to the Ditto database
- Observes for simulation assignments
- Acknowledges receipt of instructions
- Executes scenarios at the scheduled time
- Writes logs and heartbeats continuously
- Writes error reports to `__des_sim_problems`

---

## 2. Complete Simulation Lifecycle

### Phase 1: Setup (Orchestrator, in Edge Studio)

```
User opens Simulation section
  └─ Sees empty state (simulator-empty.png)
  └─ Taps + button to open wizard
```

**Wizard Step 1 — General Info (add-step1.png)**
- Enter simulation name + description
- Set scheduled start time and end time
- View available peers from the Ditto Presence Graph
- Select 1-12 peers to include as bots
- Each peer shown with: device name, peer key, OS icon

**Wizard Step 2 — Configure Bots (add-step2.png)**
- For each selected peer:
  - Editable Bot Name field (pre-filled with device name)
  - Role / Description text field
  - Start offset: `[0] seconds` numeric input (range 0–300). Default 0. Stored as `startOffsetSeconds` on the bot doc; `effectiveStartTime = scheduledStartTime + startOffsetSeconds`. (Q20)
  - Upload Scenario JSON button (or drag and drop)
  - When uploaded: shows filename + "N scenarios" count
  - Green checkmark when JSON is valid; red X with error details if invalid

**Wizard Step 3 — Summary (add-step3.png)**
- Total bots, total scenarios, simulation timeline
- Card for each bot showing: device name, role badge, scenario count, JSON status
- Important note: "Once created, bots must confirm before simulation can start"
- "Create Simulation" button (yellow, prominent)

```
User taps "Create Simulation"
  └─ Orchestrator begins processing
```

---

### Phase 2: Processing (Orchestrator Background Task)

After "Create Simulation" is tapped, Edge Studio performs these operations asynchronously while showing a progress indicator:

1. **Create simulation document** in `__des_sim_simulations` with `status: "processing"`

2. **For each bot** (loop):
   a. Parse the uploaded scenario JSON file
   b. Validate the schema
   c. Create `__des_sim_bots` document for this bot (status: `"pending"`, including `startOffsetSeconds` and `effectiveStartTime`)
   d. For each scenario in the file:
      - Create `__des_sim_scenarios` document (header + observer config only, no steps array)
      - For each step in that scenario:
        - Create one `__des_sim_steps` document with `_id.stepIndex = N`
   e. For each sample data set in the file:
      - Create `__des_sim_sample_data` document(s)
   f. Update `processingProgress` on the simulation document (progress = docs created / total docs)

   > **Total document count** = Σ(stepCount per scenario per bot) + scenarioCount + botCount + sampleDataDocCount + 1 (simulation)

3. **Update simulation status** to `"pending_confirmation"` after all documents created

The UI shows progress during processing and transitions to the confirmation view when done.

---

### Phase 3: Bot Confirmation

**Orchestrator shows** "Waiting for bot confirmations" with a list of bots and their current status (pending/acknowledged).

**Each bot** (running DittoBot app, already connected to the same Ditto database):
1. Observes `__des_sim_bots` filtered by own peer key
2. When a new `pending` bot document arrives via sync:
   - Bot automatically validates it can participate (no conflicting simulation, has capacity)
   - Bot updates its document: `status: "acknowledged"`, `acknowledgedAt: now`
3. Bot UI shows "Confirmed: [Simulation Name]" on the pending simulations list

**Orchestrator** observes `__des_sim_bots` and:
- Shows a real-time list of bot confirmation status
- When ALL bots are `acknowledged`:
  - Enables the "Schedule Simulation" button
  - Shows a summary screen with confirmation from all devices

**If a bot doesn't confirm within 5 minutes:**
- Show timeout warning in orchestrator UI
- Allow user to reschedule (update start time) or remove the unresponsive bot

---

### Phase 4: Scheduling

User clicks "Schedule Simulation" in Edge Studio:
1. Orchestrator updates `__des_sim_simulations` → `status: "confirmed"`
2. Orchestrator updates each `__des_sim_bots` document → `status: "ready"`, includes `scheduledStartTime`

**Each bot** observes its bot document for `status = "ready"`:
1. Reads `effectiveStartTime` from its bot document (`= scheduledStartTime + startOffsetSeconds`)
2. Calculates delay until `effectiveStartTime`
3. Registers a timer to begin execution at `effectiveStartTime`
4. Bot UI shows countdown: "Simulation starts in 00:04:32" (based on `effectiveStartTime`)

> Staggered starts allow scenarios where Bot A inserts data before Bot B starts reacting to it, enabling realistic producer→consumer test flows.

---

### Phase 5: Running

**At start time (each bot independently):**
1. Updates `__des_sim_bots` → `status: "running"`, `startedAt: now`
2. Starts executing scenarios

**Sequential Scenario Execution (bot):**
```
For each sequential scenario (in order):
  While (iteration < repeatCount || repeatCount == -1) AND simulation not ended:
    For each step in scenario.steps:
      1. Log "step_started"
      2. Execute step action
      3. Log "step_completed" (with durationMs)
      4. If error: log to __des_sim_problems
    Wait interScenarioDelayMs
    Wait scenario.repeat.delayMs
    iteration++
```

**Reactive Scenario Setup (bot, runs concurrently with sequential):**
```
For each reactive scenario:
  Register Ditto store observer with scenario.observer.query
  When observer fires AND trigger matches triggerOn:
    Collect via Kotlin Flow (natural backpressure — does not re-fire
    until current execution completes)
    Execute scenario steps sequentially
    If measurePropagationLatency = true AND doc contains propagationLatencyField:
      Compute latencyMs = relativeNowMs - doc[propagationLatencyField]
      Log propagation_latency event
```

> **No concurrency cap** (Q10): Kotlin Flows backpressure means the observer is naturally serialized per flow collector. Remove any `maxConcurrentReactiveScenarios` guard from the implementation — the SDK handles this.

**Orchestrator Live Dashboard (running-screen.png):**
- Grid of bot cards (one per bot)
- Each card shows:
  - Bot name + role
  - Active transport icons (BT, WiFi, Cloud)
  - Scenario progress bar
  - Current step description
  - Time remaining (based on simulation end time)
- Real-time activity log at bottom (scrolling, from `__des_sim_bot_logs`)
- Problems appear as alerts (from `__des_sim_problems`)
- TERMINATE button to stop all bots immediately
- Time remaining countdown (top right)

**Heartbeat (bot, every 5 seconds):**
```
UPDATE __des_sim_bots
SET lastHeartbeat = now,
    currentScenarioIndex = N,
    currentStepIndex = M,
    progressPercent = P,
    activeTransports = [...]
WHERE _id.simId = simId AND _id.peerKey = myPeerKey
```

**System info snapshot (bot, every 30 seconds — Q11):**
```
SELECT * FROM system:system_info
  → Filter entries where timestamp >= simulationStartUnixSeconds
  → Pivot: take most recent value per key
  → INSERT into __des_sim_bot_logs:
    {
      eventType: "system_info_snapshot",
      relativeMs: relativeNowMs(),
      data: {
        connections_bluetooth: N,
        connections_p2pwifi: N,
        connections_accesspoint: N,
        connections_websocket: N,
        is_connected_to_ditto_cloud: bool,
        fs_usage_total: bytes,
        fs_usage_store: bytes,
        fs_usage_replication: bytes,
        transport_config: { ... },
        recent_errors: [...],
        collection_num_docs: { "orders": N, ... }
      }
    }
```

---

### Phase 6: Completion

**A simulation completes when:**
- All sequential scenarios finish their runs AND no reactive scenarios are still running
- OR: the `scheduledEndTime` is reached (bots stop executing)
- OR: user clicks TERMINATE

**Bot completion:**
1. Finishes current step (doesn't interrupt mid-step)
2. Updates `__des_sim_bots` → `status: "completed"`, `completedAt: now`
3. Cancels all active observers
4. Bot UI shows "Simulation complete" screen

**Orchestrator completion detection:**
1. Observes all bot documents in the simulation
2. When ALL bots are `completed` (or endTime passed):
3. Updates `__des_sim_simulations` → `status: "completed"`, `actualEndTime: now`
4. Transitions UI to Results view

---

### Phase 7: Results

The results view shows post-simulation analysis from `__des_sim_bot_logs`:

**Summary Panel:**
- Total simulation duration
- Total operations executed per bot
- Total errors

**Timeline View:**
- Horizontal timeline showing each bot's events over time
- Color-coded by event type
- Click event to see details

**Latency Analysis (Key Value for Developers):**
- For documents written by one bot and read by another:
  - When Bot A wrote an INSERT at time T1
  - When Bot B received it via sync at time T2
  - Latency = T2 - T1
  - Show per-transport breakdown (WiFi vs Bluetooth vs Cloud)
- Helps developers understand: "My data model document is too large to sync over Bluetooth — 45-second sync latency vs 2-second over WiFi"

**Transport Performance:**
- Show when transport config changes occurred
- Correlate with sync latency spikes
- Example insight: "During the 2-minute WiFi outage, orders took 42 seconds longer to reach the KDS"

**Export:**
- Export raw log data as JSON
- Export summary as PDF or CSV

---

## 3. Error Handling

### Bot Step Errors

Per-step behavior is controlled by `globalConfig.onStepError`:
- `"continue"` — Log error, continue to next step
- `"stop_scenario"` — Log error, skip to next scenario
- `"stop_simulation"` — Write fatal problem, stop all scenarios

Individual steps can override with `"onError": "continue"` or `"stop_simulation"`.

### Fatal Bot Errors

If a bot encounters a fatal error:
1. Write to `__des_sim_problems` with `isFatal: true`
2. Update `__des_sim_bots` → `status: "failed"`, `errorMessage: "..."`
3. Cancel all observers and timers
4. Bot UI shows error screen

**Orchestrator response:**
- Show alert in running dashboard
- Show "1 bot failed" indicator on bot card
- Allow simulation to continue with remaining bots (or terminate all)

### Bot Offline Detection

**Heartbeat timeout (orchestrator-side):**
- If a bot's `lastHeartbeat` is > 30 seconds old during a running simulation:
  - Orchestrator marks that bot's card as "OFFLINE" in the UI (gray card, transport color removed)
  - Does NOT terminate the simulation
  - Bot may recover when connectivity resumes

**Bot-side recovery (Q7 — required from Phase 1):**

When the bot app restarts or reconnects after being offline:

1. Bot initializes Ditto and starts sync
2. Bot queries its own `__des_sim_bots` doc — sees `status = "running"` (set before going offline)
3. Bot queries its own logs for the highest `seq` with `eventType IN ('step_completed', 'step_started')`
4. Bot resumes from `lastCompletedStepIndex + 1` within the current scenario
5. Bot increments `offlineCount` and sets `lastOfflineAt` on its bot doc
6. Bot logs a `resumed_after_offline` event:

```json
{
  "eventType": "resumed_after_offline",
  "resumedFromScenarioIndex": 0,
  "resumedFromStepIndex": 3,
  "offlineDurationMs": 45000
}
```

**Orchestrator response on recovery:**
- When a bot's heartbeat resumes after being gray/offline, card recovers to its transport color
- Brief "reconnected" indicator shown on card (e.g., 3-second pulse animation)
- `offlineCount` visible in bot detail view for results analysis

### Orchestrator Crash Recovery

If Edge Studio crashes during a simulation:
- Simulation state is in Ditto — no data is lost
- On relaunch, Edge Studio checks for `running` simulations and reconnects
- Dashboard shows recovered live state

---

## 4. QR Code Configuration Flow

### Generating the QR Code (Edge Studio)

The QR code encodes the **minimum information a bot needs to connect**:

```json
{
  "type": "ditto_bot_config",
  "version": "1.0",
  "appId": "the-ditto-app-id",
  "token": "auth-token",
  "authUrl": "https://cloud.ditto.live",
  "websocketUrl": "wss://cloud.ditto.live",
  "httpApiUrl": "https://cloud.ditto.live",
  "httpApiKey": "api-key-here"
}
```

This is essentially the same as the existing `DittoConfigForDatabase` QR code feature. The bot uses the same QR scan flow already planned for database config import.

### Bot Scans QR Code

1. Bot scans QR code → receives Ditto config JSON
2. Bot initializes Ditto SDK with the config (online playground identity)
3. Bot starts sync
4. Bot subscribes to `__des_sim_bots WHERE _id.peerKey = myPeerKey` to watch for assignments
5. Bot UI shows "Connected — waiting for simulation assignments"
6. When a new simulation doc arrives, it appears in the bot's simulation list

---

## 5. Sync Architecture

### Document Ownership Matrix

| Collection | Created by | Updated by | Read by |
|-----------|-----------|-----------|---------|
| `__des_sim_simulations` | Orchestrator | Orchestrator | Both |
| `__des_sim_bots` | Orchestrator | **Bot** (status fields only) | Both |
| `__des_sim_scenarios` | Orchestrator | — | **Bot** only |
| `__des_sim_steps` | Orchestrator | — | **Bot** only |
| `__des_sim_sample_data` | Orchestrator | — | **Bot** only |
| `__des_sim_bot_logs` | **Bot** | — | Orchestrator only |
| `__des_sim_problems` | **Bot** | — | Orchestrator only |

### Data Flow Diagram

```
ORCHESTRATOR                    DITTO SYNC                    BOT
     │                              │                          │
     │── Creates simulation ────────►                          │
     │── Creates bot docs ──────────►                          │
     │── Creates scenario docs ─────►                          │
     │── Creates step docs ─────────►                          │
     │── Creates sample data ───────►                          │
     │                              │◄── Bot subscribes ───────│
     │                              │──── Scenarios sync ─────►│
     │                              │──── Bot doc sync ───────►│
     │◄── Bot acks (writes) ────────│                          │
     │                              │                          │
     │── Schedules simulation ──────►                          │
     │                              │──── Status: ready ──────►│
     │                              │                          │
     │                         [start time]                    │
     │                              │                          │
     │◄── Heartbeats ───────────────│◄── Bot writes ───────────│
     │◄── Log entries ──────────────│◄── Bot writes ───────────│
     │◄── Problems ─────────────────│◄── Bot writes ───────────│
     │                              │                          │
     │◄── Completion ───────────────│◄── Bot writes ───────────│
```

---

## 6. Collection Filtering in Edge Studio

The Collections sidebar must filter out `__des_sim_*` collections from the user-visible list. This should be done in `CollectionsRepository.swift`:

```swift
// Filter out internal DES simulation collections
let filteredCollections = collections.filter { collection in
    !collection.name.hasPrefix("__des_sim")
}
```

This joins the existing filter for Ditto system collections that start with `__`.

---

## 7. Running Screen Notes

Based on the `running-screen.png` mockup, the dashboard shows:

- **Header:** Simulation name + time remaining countdown + TERMINATE button
- **Bot grid:** 2×4 grid (8 bots in mockup, supports up to 3×4 = 12 max per Q5)
- **Each bot card:**
  - Bot name + role (top)
  - Status dot (top-left): green=running, orange=warning, red=error
  - Small transport indicator dots (top-right): one dot per active transport
  - **Card background tint = current primary transport** (subtle 15-20% opacity — Q4):
    - Green `#34C759` — P2P WiFi (AWDL)
    - Teal `#5AC8FA` — LAN (local WiFi)
    - Blue `#007AFF` — Bluetooth LE
    - Purple `#AF52DE` — WebSocket (Cloud)
    - Gray `#8E8E93` — Offline / no transport
  - Scenario progress bar (middle)
  - Real-time activity feed (bottom of card)
- **Activity log panel** at bottom: scrolling, timestamped, color-coded by level (WARNING in orange)

**Primary transport determination (orchestrator-side):**
Parse `activeTransports[]` from the bot's latest heartbeat. Sort by priority (P2P WiFi > LAN > Cloud > Bluetooth). First entry = card color. If `activeTransports` is empty OR `lastHeartbeat` is >30s stale → gray.

**Card color updates** happen in real time each time a heartbeat arrives with a different `activeTransports` value.

**>8 bots:** Grid scrolls vertically. Cards shrink slightly if needed to show all bots without scrolling (up to 12).

**Clicking a bot card:** Opens a detail view with full log stream, all system_info snapshot data, and transport history for that bot.
