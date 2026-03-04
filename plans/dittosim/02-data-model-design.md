# DittoSim — Data Model Design

**Status:** Updated — All decisions applied (2026-02-22)
**Last Updated:** 2026-02-22

This document defines all Ditto collections and document schemas for the DittoSim feature. All collections use the `__des_sim` prefix to identify them as internal Edge Studio collections and to enable filtering them from the Collections UI sidebar.

---

## Collection Overview

| Collection | Primary Writer | Primary Readers | Purpose |
|-----------|---------------|-----------------|---------|
| `__des_sim_simulations` | Orchestrator | Orchestrator, Bots (read-only) | Master simulation record |
| `__des_sim_bots` | Orchestrator (creates), Bot (updates) | Both | Per-bot config and status |
| `__des_sim_scenarios` | Orchestrator | Bot (read-only) | Scenario header + observer config per bot |
| `__des_sim_steps` | Orchestrator | Bot (read-only) | Individual step documents (one per step) |
| `__des_sim_sample_data` | Orchestrator | Bot (read-only) | Sample data for DQL steps |
| `__des_sim_bot_logs` | Bot | Orchestrator (read-only) | Execution telemetry |
| `__des_sim_problems` | Bot | Orchestrator (read-only) | Error reports |

**Why these 7 collections?**
- `simulations` and `bots` are separate because the simulation has global state while bots have individual state
- `scenarios` and `steps` are separate because steps are individual documents (not embedded arrays) — smaller docs sync faster over Bluetooth and avoid Ditto array LWW conflicts (Q16)
- `sample_data` is separate because sample data sets can be large and may be reused across scenarios
- `bot_logs` and `problems` are separate so that the orchestrator can subscribe to problems-only for alerts without streaming all log data

---

## Collection 1: `__des_sim_simulations`

**Purpose:** One document per simulation. Stores configuration and lifecycle state.

**Writer:** Orchestrator only (no concurrent writes expected)

### Schema

```json
{
  "_id": "sim_<uuid>",

  // Core identity
  "name": "Fast Food Restaurant Stress Test",
  "description": "Testing order flow performance over P2P WiFi with 3 bots",
  "databaseId": "the-ditto-app-id-being-simulated",

  // Lifecycle
  "status": "draft",
  "createdAt": "2026-02-22T10:00:00Z",
  "updatedAt": "2026-02-22T10:00:00Z",

  // Scheduling
  "scheduledStartTime": "2026-02-22T14:00:00Z",
  "scheduledEndTime": "2026-02-22T15:00:00Z",
  "actualStartTime": null,
  "actualEndTime": null,

  // Configuration
  "botCount": 3,
  "totalScenarioCount": 65,

  // Processing state (set during wizard confirmation)
  "processingProgress": 0,
  "processingError": null,

  // Creator
  "createdByPeerKey": "pk_orchestrator_abc123"
}
```

### Status State Machine

```
draft
  ↓ (user completes wizard step 3 and clicks "Create Simulation")
processing
  ↓ (orchestrator finishes creating all scenario + sample_data docs)
pending_confirmation
  ↓ (all bots update their bot doc to status=acknowledged)
awaiting_schedule
  ↓ (user clicks "Schedule Simulation")
confirmed
  ↓ (all bots have set their status=ready, timer registered)
scheduled
  ↓ (start time reached, first bot updates status=running)
running
  ↓ (all bots complete, or simulationEndTime reached)
completed

  At any point:
  → failed       (unrecoverable error in processing or critical bot failure)
  → terminated   (user clicks "Terminate" during running)
```

### Field Notes

- `_id` uses `sim_` prefix followed by UUID for human readability in DQL queries
- `databaseId` is the Ditto App ID of the database being tested (used by bots to connect)
- `processingProgress` is 0-100 percentage for UI feedback during document creation
- `botCount` and `totalScenarioCount` are denormalized for summary display without additional queries

---

## Collection 2: `__des_sim_bots`

**Purpose:** One document per bot per simulation. Orchestrator creates it; bot updates its own status fields.

**Writers:** Orchestrator creates; Bot updates `status`, `currentScenarioIndex`, `currentStepIndex`, `progressPercent`, `lastHeartbeat`, `errorMessage`, `activeTransports`, `offlineCount`, `lastOfflineAt`

**CRDT Note:** The orchestrator writes read-only fields once. The bot writes status fields only to its own document. No concurrent writes to the same fields — LWW registers are safe here.

### Schema

```json
{
  "_id": { "simId": "sim_<uuid>", "peerKey": "pk_abc123def456" },

  // Identity (written by orchestrator, never changed)
  "simId": "sim_<uuid>",
  "peerKey": "pk_abc123def456",
  "deviceName": "iPad Air - Kitchen",

  // Bot configuration (written by orchestrator from wizard)
  "botName": "Kitchen Display 1",
  "role": "Kitchen Display Unit",
  "scenarioCount": 45,

  // Scheduling (written by orchestrator)
  "scheduledStartTime": "2026-02-22T14:00:00Z",
  "scheduledEndTime": "2026-02-22T15:00:00Z",
  "startOffsetSeconds": 0,
  "effectiveStartTime": "2026-02-22T14:00:00Z",

  // Lifecycle status (written by BOT)
  "status": "pending",
  "acknowledgedAt": null,
  "startedAt": null,
  "completedAt": null,

  // Progress (written by BOT continuously)
  "currentScenarioIndex": 0,
  "currentStepIndex": 0,
  "progressPercent": 0,
  "lastHeartbeat": null,

  // Error state (written by BOT on failure)
  "errorMessage": null,
  "errorScenarioIndex": null,
  "errorStepIndex": null,

  // Network state (written by BOT)
  "activeTransports": [],
  "deviceOs": "iPadOS 18.2",
  "appVersion": "1.0.0",

  // Recovery tracking (written by BOT — Q7)
  "offlineCount": 0,
  "lastOfflineAt": null
}
```

### Bot Status State Machine

```
pending           → acknowledged   (bot receives its bot doc and confirms)
acknowledged      → ready          (bot receives confirmed status from simulation)
ready             → running        (start time reached)
running           → completed      (all sequential scenarios done, no reactive scenarios active)
running           → failed         (unrecoverable step error, bot writes errorMessage)
running           → offline        (heartbeat timeout — RECOVERABLE, bot resumes on reconnect)
offline           → running        (bot reconnects and resumes)
```

### Composite _id Design Note

Using `{ "simId": "sim_uuid", "peerKey": "pk_abc123" }` as the composite key means:
- Subscription query: `SELECT * FROM __des_sim_bots WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey`
- Orchestrator query for all bots in sim: `SELECT * FROM __des_sim_bots WHERE _id.simId = :simId`
- No secondary indexes needed

---

## Collection 3: `__des_sim_scenarios`

**Purpose:** One document per scenario per bot. Orchestrator creates these during the `processing` phase by parsing the uploaded JSON files. Bots read these to know what to execute.

**Writer:** Orchestrator only (created once, never modified)

**CRDT Note:** Steps are stored as **separate documents** in `__des_sim_steps` (not embedded here). This ensures each step document is small and syncs quickly over Bluetooth. Ditto arrays are LWW registers — even though we're the only writer, breaking steps into individual documents keeps each sync packet small and makes the resume-from-step recovery logic simpler (Q16).

### Schema

```json
{
  "_id": { "simId": "sim_<uuid>", "peerKey": "pk_abc123", "scenarioIndex": 0 },

  // Identity
  "simId": "sim_<uuid>",
  "peerKey": "pk_abc123",
  "scenarioIndex": 0,

  // Scenario definition
  "scenarioId": "scenario_create_order",
  "name": "Create Order",
  "description": "Simulates a worker creating an order at the POS terminal",

  // Type: "sequential" | "reactive"
  "type": "sequential",

  // Step reference (steps are in __des_sim_steps, NOT embedded here)
  "stepCount": 5,

  // For sequential scenarios: repeat config
  "repeatCount": -1,
  "repeatDelayMs": 3000,
  "maxRuns": 50,

  // For reactive scenarios: the observer query (null for sequential)
  "observerQuery": null,
  "observerQueryArgs": null,
  "triggerOnInsert": true,
  "triggerOnUpdate": false,
  "measurePropagationLatency": false,
  "propagationLatencyField": "__des_sim_ts",

  "createdAt": "2026-02-22T10:00:05Z"
}
```

### Reactive Scenario Example

```json
{
  "_id": { "simId": "sim_<uuid>", "peerKey": "pk_kds", "scenarioIndex": 1 },
  "type": "reactive",
  "name": "Watch for New Orders",
  "stepCount": 3,
  "observerQuery": "SELECT * FROM orders WHERE status = 'pending' ORDER BY createdAt ASC",
  "observerQueryArgs": {},
  "triggerOnInsert": true,
  "triggerOnUpdate": false,
  "measurePropagationLatency": true,
  "propagationLatencyField": "__des_sim_ts",
  "createdAt": "2026-02-22T10:00:05Z"
}
```

Steps for this scenario live in `__des_sim_steps` with `_id.scenarioIndex = 1` and `_id.stepIndex = 0, 1, 2`.

---

## Collection 4: `__des_sim_steps`

**Purpose:** One document per step per scenario per bot. Created by the orchestrator during the `processing` phase by parsing the uploaded scenario JSON files. Bots read these to know what to execute.

**Writer:** Orchestrator only (created once, never modified)

**Why separate from scenarios?** Keeping steps as individual documents (rather than embedded arrays) means each sync packet carries one step, not a full scenario with all its steps. This is critical for Bluetooth sync where packet size is constrained. It also simplifies the bot's recovery logic: finding "the last completed step" is a single DQL query on sequential `_id.stepIndex` values (Q16).

### Schema

```json
{
  "_id": {
    "simId": "sim_<uuid>",
    "peerKey": "pk_abc123",
    "scenarioIndex": 0,
    "stepIndex": 2
  },

  // Identity (denormalized for query convenience)
  "simId": "sim_<uuid>",
  "peerKey": "pk_abc123",
  "scenarioIndex": 0,
  "stepIndex": 2,

  // Step definition (matches scenario file format exactly)
  "type": "dqlExecute",
  "id": "insert_order",
  "description": "Insert order into the database",
  "params": {
    "statement": "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE",
    "args": { "order": "{{current.item}}" },
    "expectMutations": true
  },
  "onError": "continue"
}
```

### Step Types

Valid `type` values match the scenario file format: `sleep`, `dqlExecute`, `httpRequest`, `dittoStartSync`, `dittoStopSync`, `dittoTransportConfig`, `loadData`, `setVar`, `log`, `updateScreen`, `alertOrchestrator`.

### Subscription Query (Bot)

```
SELECT * FROM __des_sim_steps WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey
```

The bot loads all its steps on startup, then uses them as a lookup table by `(scenarioIndex, stepIndex)` during execution.

### Recovery Query (Bot — Q7)

```dql
SELECT * FROM __des_sim_bot_logs
WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey
  AND eventType IN ('step_completed', 'step_started')
ORDER BY _id.seq DESC
LIMIT 1
```

This gives the bot the last known good step, from which it resumes.

---

## Collection 5: `__des_sim_sample_data`

**Purpose:** Sample data sets (arrays of JSON documents) that bots use for their DQL operations. The `loadData` step type references these by `dataSetKey`.

**Writer:** Orchestrator only (created once during processing)

**Why separate from scenarios?** Sample data sets can be large (hundreds of order objects) and may be referenced by multiple scenarios from the same bot. Keeping them separate avoids bloating scenario documents.

### Schema

```json
{
  "_id": { "simId": "sim_<uuid>", "peerKey": "pk_abc123", "dataSetKey": "orders" },

  "simId": "sim_<uuid>",
  "peerKey": "pk_abc123",
  "dataSetKey": "orders",
  "description": "Sample fast food orders for POS simulation",

  // The actual data items
  "items": [
    {
      "_id": "order_sim_001",
      "items": [
        { "sku": "burger_classic", "qty": 1, "price": 8.99 },
        { "sku": "fries_large", "qty": 1, "price": 3.49 }
      ],
      "total": 12.48,
      "customerName": "Alice",
      "orderType": "dine_in"
    },
    { "_id": "order_sim_002", "..." : "..." }
  ],

  "itemCount": 50,
  "createdAt": "2026-02-22T10:00:05Z"
}
```

### Large Data Sets

If a data set has hundreds of items, consider splitting into multiple documents:
```
{ "_id": { "simId": "...", "peerKey": "...", "dataSetKey": "orders", "page": 0 }, "items": [...] }
{ "_id": { "simId": "...", "peerKey": "...", "dataSetKey": "orders", "page": 1 }, "items": [...] }
```

The bot loads all pages and concatenates them on startup.

---

## Collection 6: `__des_sim_bot_logs`

**Purpose:** Execution telemetry written by bots during simulation. One document per significant event. The orchestrator subscribes to these to power the live dashboard and final results view.

**Writer:** Bot only
**CRDT Safety:** Each bot writes only its own logs. No concurrent writes to the same document. LWW registers are fine.

### Schema

```json
{
  "_id": { "simId": "sim_<uuid>", "peerKey": "pk_abc123", "seq": 1 },

  // Identity
  "simId": "sim_<uuid>",
  "peerKey": "pk_abc123",
  "seq": 1,

  // What was happening
  "scenarioIndex": 0,
  "scenarioId": "scenario_create_order",
  "stepIndex": 2,
  "stepId": "insert_order",

  // Classification
  "level": "info",
  "eventType": "step_completed",

  // Content
  "message": "INSERT INTO orders: 1 doc inserted in 23ms",
  "durationMs": 23,
  "timestamp": "2026-02-22T14:01:23.456Z",

  // Optional structured metadata
  "metadata": {
    "documentId": "order_sim_001",
    "rowsAffected": 1
  }
}
```

### Event Types

| eventType | Meaning |
|-----------|---------|
| `scenario_started` | Bot started a scenario |
| `scenario_completed` | Bot finished all steps of a scenario |
| `scenario_repeated` | Bot started next iteration of a repeating scenario |
| `step_started` | Bot started a step |
| `step_completed` | Bot finished a step successfully |
| `step_failed` | A step failed (non-fatal, may retry or continue) |
| `sync_event` | Bot observed a Ditto sync event (for reactive scenarios) |
| `transport_changed` | Bot's transport config changed |
| `heartbeat` | Periodic "I'm alive" event |
| `simulation_started` | Bot started the simulation |
| `simulation_completed` | Bot finished all scenarios |
| `resumed_after_offline` | Bot reconnected and resumed from last step (Q7) |
| `system_info_snapshot` | Periodic `system:system_info` snapshot (every 30s) |
| `propagation_latency` | INSERT→observer latency measurement (opt-in via `measurePropagationLatency`) |

### Log Sequence Number

Each bot maintains a monotonically increasing `seq` counter starting at 1. This allows:
- Ordering logs correctly regardless of sync timing
- Detecting missing logs (gaps in seq)
- Efficient new-log queries: `SELECT * FROM __des_sim_bot_logs WHERE simId = :simId AND peerKey = :peerKey AND seq > :lastSeenSeq`

---

## Collection 7: `__des_sim_problems`

**Purpose:** Error reports from bots. Separate from `bot_logs` so the orchestrator can subscribe specifically to this collection and show alerts without streaming all telemetry.

**Writer:** Bot only

### Schema

```json
{
  "_id": { "simId": "sim_<uuid>", "peerKey": "pk_abc123", "seq": 1 },

  // Identity
  "simId": "sim_<uuid>",
  "peerKey": "pk_abc123",
  "seq": 1,

  // Error details
  "errorType": "step_execution_failed",
  "errorMessage": "DQL execute failed: collection 'orders' does not exist",
  "stackTrace": null,

  // Context
  "scenarioIndex": 0,
  "scenarioId": "scenario_create_order",
  "stepIndex": 2,
  "stepId": "insert_order",

  // Severity
  "isFatal": true,
  "timestamp": "2026-02-22T14:15:00Z"
}
```

### Error Types

| errorType | Meaning | Fatal? |
|-----------|---------|--------|
| `step_execution_failed` | A DQL, HTTP, or other step threw an error | Configurable |
| `scenario_parse_error` | The scenario doc could not be parsed | Yes |
| `connection_lost` | Ditto sync connection lost for too long | No (bot may recover) |
| `timeout` | A step exceeded its configured timeout | Configurable |
| `sample_data_exhausted` | No more sample data items available | Configurable |
| `orchestrator_unreachable` | Orchestrator hasn't been seen in N minutes | No |

---

## Subscription Strategy

### Orchestrator Subscriptions (in Edge Studio)

```swift
// Subscribe to ALL simulation data for the active simulation
ditto.sync.registerSubscription("SELECT * FROM __des_sim_simulations WHERE _id = :simId", ["simId": activeSimId])
ditto.sync.registerSubscription("SELECT * FROM __des_sim_bots WHERE _id.simId = :simId", ["simId": activeSimId])
ditto.sync.registerSubscription("SELECT * FROM __des_sim_problems WHERE _id.simId = :simId", ["simId": activeSimId])
ditto.sync.registerSubscription("SELECT * FROM __des_sim_bot_logs WHERE _id.simId = :simId", ["simId": activeSimId])
```

### Bot Subscriptions (in DittoBot app)

```kotlin
// Bot subscribes only to ITS documents for the simulation
ditto.sync.registerSubscription(
    "SELECT * FROM __des_sim_bots WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey",
    mapOf("simId" to simId, "myPeerKey" to myPeerKey)
)
ditto.sync.registerSubscription(
    "SELECT * FROM __des_sim_scenarios WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey",
    mapOf("simId" to simId, "myPeerKey" to myPeerKey)
)
ditto.sync.registerSubscription(
    "SELECT * FROM __des_sim_steps WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey",
    mapOf("simId" to simId, "myPeerKey" to myPeerKey)
)
ditto.sync.registerSubscription(
    "SELECT * FROM __des_sim_sample_data WHERE _id.simId = :simId AND _id.peerKey = :myPeerKey",
    mapOf("simId" to simId, "myPeerKey" to myPeerKey)
)
// Bot writes its own logs and problems — these sync to orchestrator automatically
```

---

## ID Convention Summary

| Collection | _id Format | Example |
|-----------|-----------|---------|
| `__des_sim_simulations` | `"sim_<uuid>"` (string) | `"sim_a1b2c3d4"` |
| `__des_sim_bots` | `{ simId, peerKey }` | `{ "simId": "sim_a1b2c3d4", "peerKey": "pk_abc123" }` |
| `__des_sim_scenarios` | `{ simId, peerKey, scenarioIndex }` | `{ "simId": "sim_a1b2c3d4", "peerKey": "pk_abc123", "scenarioIndex": 0 }` |
| `__des_sim_steps` | `{ simId, peerKey, scenarioIndex, stepIndex }` | `{ "simId": "sim_a1b2c3d4", "peerKey": "pk_abc123", "scenarioIndex": 0, "stepIndex": 2 }` |
| `__des_sim_sample_data` | `{ simId, peerKey, dataSetKey }` | `{ "simId": "sim_a1b2c3d4", "peerKey": "pk_abc123", "dataSetKey": "orders" }` |
| `__des_sim_bot_logs` | `{ simId, peerKey, seq }` | `{ "simId": "sim_a1b2c3d4", "peerKey": "pk_abc123", "seq": 42 }` |
| `__des_sim_problems` | `{ simId, peerKey, seq }` | `{ "simId": "sim_a1b2c3d4", "peerKey": "pk_abc123", "seq": 1 }` |

---

## DQL Queries Reference

### Orchestrator: Check if all bots are acknowledged

```dql
SELECT COUNT(*) as total,
       SUM(CASE WHEN status = 'acknowledged' THEN 1 ELSE 0 END) as confirmed
FROM __des_sim_bots
WHERE _id.simId = 'sim_a1b2c3d4'
```

### Orchestrator: Get latest status per bot

```dql
SELECT * FROM __des_sim_bots WHERE _id.simId = 'sim_a1b2c3d4'
```

### Orchestrator: Get all problems for active simulation (sorted by time)

```dql
SELECT * FROM __des_sim_problems
WHERE _id.simId = 'sim_a1b2c3d4'
ORDER BY timestamp DESC
```

### Bot: Load all my scenarios in order

```dql
SELECT * FROM __des_sim_scenarios
WHERE _id.simId = 'sim_a1b2c3d4' AND _id.peerKey = 'pk_abc123'
ORDER BY _id.scenarioIndex ASC
```

### Bot: Load all steps for a specific scenario

```dql
SELECT * FROM __des_sim_steps
WHERE _id.simId = 'sim_a1b2c3d4' AND _id.peerKey = 'pk_abc123' AND _id.scenarioIndex = 0
ORDER BY _id.stepIndex ASC
```

### Bot: Find last completed step (for recovery — Q7)

```dql
SELECT * FROM __des_sim_bot_logs
WHERE _id.simId = 'sim_a1b2c3d4' AND _id.peerKey = 'pk_abc123'
  AND eventType IN ('step_completed', 'step_started')
ORDER BY _id.seq DESC
LIMIT 1
```

### Bot: Update my status to running

```dql
UPDATE __des_sim_bots
SET status = 'running', startedAt = '2026-02-22T14:00:00Z'
WHERE _id.simId = 'sim_a1b2c3d4' AND _id.peerKey = 'pk_abc123'
```

---

## Local-Only Storage (SQLCipher)

Consistent with the existing app pattern, simulation metadata should also be stored locally in SQLCipher for:
- Caching simulation list (so it loads instantly without waiting for Ditto sync)
- Storing simulation draft state before it's saved to Ditto
- Preserving simulation history even after the Ditto database is disconnected

**Proposed SQLCipher table:**

```sql
CREATE TABLE simulations (
    _id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    databaseId TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft',
    scheduledStartTime TEXT,
    scheduledEndTime TEXT,
    botCount INTEGER DEFAULT 0,
    createdAt TEXT NOT NULL,
    updatedAt TEXT NOT NULL,
    FOREIGN KEY(databaseId) REFERENCES databaseConfigs(databaseId) ON DELETE CASCADE
);
CREATE INDEX idx_simulations_databaseId ON simulations(databaseId);
```
