# DittoSim — Scenario File Format (JSON Schema)

**Status:** Updated — All decisions applied (2026-02-22)
**Last Updated:** 2026-02-22

This document defines the JSON file format that users upload per bot in Step 2 of the simulation wizard. This file is designed to be:
- Human-readable and editable
- LLM-generatable (developers can prompt Claude/GPT to generate these)
- Parsed by both Edge Studio (Swift) and DittoBot (Kotlin Multiplatform)

---

## File Overview

Each bot gets ONE scenario file. The file contains:
1. **Bot metadata** — name, role, description
2. **Global config** — timing between scenarios, logging verbosity
3. **Sample data** — pre-defined documents used in DQL statements
4. **Scenarios** — list of workflows the bot executes during the simulation

A scenario is either:
- **Sequential** — runs through its steps once (or N times), then moves to the next scenario
- **Reactive** — continuously listens to a Ditto observer and runs its steps each time a match fires

---

## Root Structure

```json
{
  "schemaVersion": "1.0",
  "botName": "Kitchen Display Unit 1",
  "role": "Kitchen Display",
  "description": "Simulates the kitchen display unit monitoring incoming orders and marking them ready",

  "globalConfig": { ... },
  "sampleData": { ... },
  "scenarios": [ ... ]
}
```

### Root Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `schemaVersion` | string | Yes | Always `"1.0"` for now |
| `botName` | string | Yes | Human-readable name (can be overridden in wizard) |
| `role` | string | Yes | Role description (e.g., "POS Terminal", "Kitchen Display") |
| `description` | string | No | Longer description of what this bot simulates |
| `globalConfig` | object | Yes | Global timing and logging settings |
| `sampleData` | object | No | Named data sets keyed by dataset name |
| `scenarios` | array | Yes | List of Scenario objects (at least 1) |

---

## Global Config

```json
"globalConfig": {
  "interScenarioDelayMs": 500,
  "logVerbosity": "info",
  "heartbeatIntervalMs": 5000,
  "stepTimeoutMs": 30000,
  "onStepError": "continue"
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `interScenarioDelayMs` | int | 500 | Delay between completing one sequential scenario and starting the next |
| `logVerbosity` | string | `"info"` | `"debug"` \| `"info"` \| `"warning"` \| `"error"` |
| `heartbeatIntervalMs` | int | 5000 | How often the bot writes a heartbeat to `__des_sim_bots` |
| `stepTimeoutMs` | int | 30000 | Default timeout per step (0 = no timeout) |
| `onStepError` | string | `"continue"` | `"continue"` \| `"stop_scenario"` \| `"stop_simulation"` |

> **Note:** `maxConcurrentReactiveScenarios` was removed (Q10). Kotlin Flows handle backpressure natively — the observer does not re-fire until the current execution completes. No manual concurrency cap is needed or useful.

---

## Sample Data

```json
"sampleData": {
  "orders": [
    {
      "_id": "order_sim_001",
      "items": [
        { "sku": "burger_classic", "qty": 1, "price": 8.99 },
        { "sku": "fries_large",    "qty": 1, "price": 3.49 }
      ],
      "total": 12.48,
      "customerName": "Alice",
      "orderType": "dine_in",
      "status": "pending"
    },
    { "_id": "order_sim_002", "..." : "..." }
  ],

  "payments": [
    { "_id": "payment_sim_001", "method": "credit_card", "last4": "1234" }
  ]
}
```

The `sampleData` object is a map where keys are dataset names (e.g., `"orders"`, `"payments"`) and values are arrays of JSON documents.

**When sample data runs out:**
- Default behavior: loop back to index 0 (repeat indefinitely)
- Can be overridden per scenario with `onDataExhausted: "stop"` or `"loop"` or `"error"`

---

## Scenario Object

### Sequential Scenario

```json
{
  "id": "scenario_take_order",
  "name": "Take Order at POS",
  "description": "Simulates a POS terminal worker taking a customer order",
  "type": "sequential",

  "repeat": {
    "count": -1,
    "delayMs": 3000,
    "maxRuns": 100,
    "onDataExhausted": "loop"
  },

  "steps": [ ... ]
}
```

### Reactive Scenario

```json
{
  "id": "scenario_watch_orders",
  "name": "Watch and Process Orders",
  "description": "Reacts to new pending orders arriving in the collection",
  "type": "reactive",

  "observer": {
    "query": "SELECT * FROM orders WHERE status = 'pending' ORDER BY createdAt ASC",
    "args": {},
    "triggerOn": ["insert"],
    "debounceMs": 0
  },

  "measurePropagationLatency": true,
  "propagationLatencyField": "__des_sim_ts",

  "steps": [ ... ]
}
```

### Scenario Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique ID within this file, used in log references |
| `name` | string | Yes | Human-readable display name |
| `description` | string | No | What this scenario simulates |
| `type` | string | Yes | `"sequential"` or `"reactive"` |
| `repeat` | object | For sequential | Repeat config (see below) |
| `observer` | object | For reactive | Observer config (see below) |
| `measurePropagationLatency` | bool | For reactive | If true, bot logs INSERT→observer latency for each triggered doc |
| `propagationLatencyField` | string | For reactive | Field name embedded in source docs containing relative timestamp (default: `"__des_sim_ts"`) |
| `steps` | array | Yes | List of Step objects |

### Repeat Config (sequential only)

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `count` | int | 1 | Number of times to run. `-1` = infinite until simulation end. |
| `delayMs` | int | 0 | Fixed delay between repetitions |
| `maxRuns` | int | null | Hard cap (overrides `count` = -1) |
| `onDataExhausted` | string | `"loop"` | `"loop"` \| `"stop"` \| `"error"` |

### Observer Config (reactive only)

| Field | Type | Description |
|-------|------|-------------|
| `query` | string | DQL SELECT query to observe |
| `args` | object | Query arguments (template variables resolved at runtime) |
| `triggerOn` | array | `["insert"]` \| `["update"]` \| `["insert", "update"]` |
| `debounceMs` | int | Ignore duplicate triggers within this window |

---

## Step Types

### `sleep` — Pause Execution

Simulates human actions (taking an order, making food, scanning ID).

```json
{
  "type": "sleep",
  "id": "customer_selection_time",
  "description": "Customer selects items (30s - 90s)",
  "params": {
    "minMs": 30000,
    "maxMs": 90000
  }
}
```

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `minMs` | int | Yes | Minimum sleep duration in milliseconds |
| `maxMs` | int | No | Maximum sleep duration (random between min and max) |

If `maxMs` is omitted, sleeps exactly `minMs`.

---

### `dqlExecute` — Execute a DQL Statement

```json
{
  "type": "dqlExecute",
  "id": "insert_order",
  "description": "Insert order into the database",
  "params": {
    "statement": "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE",
    "args": {
      "order": "{{current.item}}"
    },
    "timeoutMs": 5000,
    "expectMutations": true
  }
}
```

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `statement` | string | Yes | DQL statement (SELECT, INSERT, UPDATE, EVICT) |
| `args` | object | No | Named parameters. Values can use template variables. |
| `timeoutMs` | int | No | Step-specific timeout override |
| `expectMutations` | bool | No | If true, fails if no documents were mutated |

**Step Result:** The step result includes `{ mutatedDocumentIds: [...], rowCount: N, durationMs: N }`. Available via `{{step.<id>.result.mutatedDocumentIds}}` in subsequent steps.

---

### `httpRequest` — Call the Ditto HTTP API (or any endpoint)

```json
{
  "type": "httpRequest",
  "id": "submit_online_order",
  "description": "Insert order via Ditto Big Peer HTTP API",
  "params": {
    "method": "POST",
    "url": "{{config.httpApiUrl}}/api/v4/store/execute",
    "headers": {
      "Authorization": "Bearer {{config.httpApiKey}}",
      "Content-Type": "application/json"
    },
    "body": {
      "statement": "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO NOTHING",
      "args": { "order": "{{current.item}}" }
    },
    "timeoutMs": 10000,
    "expectStatusCode": 200
  }
}
```

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `method` | string | Yes | `"GET"` \| `"POST"` \| `"PUT"` \| `"PATCH"` \| `"DELETE"` |
| `url` | string | Yes | Full URL (template variables supported) |
| `headers` | object | No | HTTP headers (template variables supported) |
| `body` | object or string | No | Request body (template variables supported) |
| `timeoutMs` | int | No | Request timeout |
| `expectStatusCode` | int | No | If set, fails step if response code doesn't match |

---

### `dittoStartSync` — Start Ditto Sync

```json
{
  "type": "dittoStartSync",
  "id": "resume_sync",
  "description": "Re-enable Ditto sync after simulated outage"
}
```

No params required.

---

### `dittoStopSync` — Stop Ditto Sync

```json
{
  "type": "dittoStopSync",
  "id": "disable_sync",
  "description": "Pause Ditto sync to simulate network outage"
}
```

No params required.

---

### `dittoTransportConfig` — Change Transport Settings

```json
{
  "type": "dittoTransportConfig",
  "id": "disable_wifi",
  "description": "Disable WiFi/cloud, keep Bluetooth to simulate WiFi outage",
  "params": {
    "isBluetoothLeEnabled": true,
    "isLanEnabled": false,
    "isAwdlEnabled": false,
    "isCloudSyncEnabled": false
  }
}
```

| Param | Type | Description |
|-------|------|-------------|
| `isBluetoothLeEnabled` | bool | Enable/disable Bluetooth LE transport |
| `isLanEnabled` | bool | Enable/disable LAN (WiFi) transport |
| `isAwdlEnabled` | bool | Enable/disable Apple Wireless Direct Link (P2P WiFi, iOS/Mac) |

Any omitted fields retain their current value.

---

### `loadData` — Load Next Sample Data Item

```json
{
  "type": "loadData",
  "id": "load_next_order",
  "description": "Load next order from sample data set",
  "params": {
    "dataSetKey": "orders",
    "strategy": "sequential",
    "updateTimestamp": true
  }
}
```

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `dataSetKey` | string | Yes | Key in `sampleData` object |
| `strategy` | string | No | `"sequential"` (default) \| `"random"` \| `"shuffle"` |
| `updateTimestamp` | bool | No | If true, updates any `createdAt` field in the loaded item to now |

After this step, `{{current.item}}` and `{{current.index}}` are available.

---

### `setVar` — Set a Variable

```json
{
  "type": "setVar",
  "id": "set_order_id",
  "params": {
    "varName": "currentOrderId",
    "value": "{{current.item._id}}"
  }
}
```

Sets a named variable available via `{{vars.currentOrderId}}` in subsequent steps.

---

### `log` — Write a Log Entry

```json
{
  "type": "log",
  "id": "log_order_complete",
  "params": {
    "message": "Order {{current.item._id}} completed in {{step.insert_order.durationMs}}ms",
    "level": "info",
    "metadata": {
      "orderId": "{{current.item._id}}",
      "processingTime": "{{step.insert_order.durationMs}}"
    }
  }
}
```

| Param | Type | Required | Description |
|-------|------|----------|-------------|
| `message` | string | Yes | Log message (template variables supported) |
| `level` | string | No | `"debug"` \| `"info"` \| `"warning"` \| `"error"` |
| `metadata` | object | No | Structured metadata for the log entry |

Logs are written to `__des_sim_bot_logs` in Ditto.

---

### `updateScreen` — Update Bot Device Display

```json
{
  "type": "updateScreen",
  "id": "show_order_status",
  "params": {
    "message": "Order {{current.item._id}} submitted ✓",
    "style": "success",
    "duration": 3000
  }
}
```

| Param | Type | Description |
|-------|------|-------------|
| `message` | string | Text to display on the bot device screen |
| `style` | string | `"info"` \| `"success"` \| `"warning"` \| `"error"` |
| `duration` | int | Milliseconds to show (0 = until next updateScreen) |

Updates the bot app's status screen via StateFlow in the ViewModel.

---

### `alertOrchestrator` — Send Alert to Edge Studio

```json
{
  "type": "alertOrchestrator",
  "id": "alert_no_orders",
  "params": {
    "message": "No orders received in 5 minutes — possible sync issue",
    "isFatal": false,
    "errorType": "timeout"
  }
}
```

Writes a document to `__des_sim_problems`. If `isFatal: true`, the bot stops all scenario execution.

---

## Template Variables Reference

Template variables use `{{path}}` syntax in any string parameter value.

| Variable | Type | Available In | Description |
|----------|------|-------------|-------------|
| `{{now}}` | string (ISO8601) | Always | Current timestamp |
| `{{nowMs}}` | int | Always | Current time as Unix milliseconds |
| `{{simId}}` | string | Always | Current simulation ID |
| `{{peerKey}}` | string | Always | This bot's Ditto peer key |
| `{{botName}}` | string | Always | This bot's name |
| `{{role}}` | string | Always | This bot's role |
| `{{config.httpApiUrl}}` | string | Always | Ditto database HTTP API URL |
| `{{config.httpApiKey}}` | string | Always | Ditto database HTTP API key |
| `{{config.appId}}` | string | Always | Ditto database app ID |
| `{{current.item}}` | object | After `loadData` | Current sample data item |
| `{{current.index}}` | int | After `loadData` | Index of current item in dataset |
| `{{trigger.document}}` | object | Reactive scenarios | The document that triggered the observer |
| `{{trigger.event}}` | string | Reactive scenarios | `"insert"` or `"update"` |
| `{{step.<id>.result}}` | object | After step with id | Full result object from a named step |
| `{{step.<id>.durationMs}}` | int | After step with id | Duration of a named step |
| `{{step.<id>.result.mutatedDocumentIds}}` | array | After dqlExecute | List of mutated doc IDs |
| `{{loop.iteration}}` | int | In repeat loops | Current repeat index (0-based) |
| `{{loop.total}}` | int | In repeat loops | Total repeat count (-1 if infinite) |
| `{{vars.<name>}}` | any | After setVar | Value set by a `setVar` step |

---

## Complete Fast Food Restaurant Example

This example shows a complete scenario file for the **Kitchen Display Unit** bot:

```json
{
  "schemaVersion": "1.0",
  "botName": "Kitchen Display Unit - Main",
  "role": "Kitchen Display",
  "description": "Simulates the kitchen display unit. Watches for incoming orders, processes them in order of arrival, and marks them ready after a prep time.",

  "globalConfig": {
    "interScenarioDelayMs": 0,
    "logVerbosity": "info",
    "heartbeatIntervalMs": 5000,
    "stepTimeoutMs": 60000,
    "onStepError": "stop_scenario"
  },

  "sampleData": {},

  "scenarios": [
    {
      "id": "scenario_watch_orders",
      "name": "Watch and Process Incoming Orders",
      "type": "reactive",
      "observer": {
        "query": "SELECT * FROM orders WHERE status = 'pending' ORDER BY createdAt ASC",
        "args": {},
        "triggerOn": ["insert"],
        "debounceMs": 500
      },
      "measurePropagationLatency": true,
      "propagationLatencyField": "__des_sim_ts",
      "steps": [
        {
          "type": "updateScreen",
          "id": "show_new_order",
          "params": {
            "message": "New order: {{trigger.document._id}} — starting prep",
            "style": "info"
          }
        },
        {
          "type": "log",
          "id": "log_order_received",
          "params": {
            "message": "Order {{trigger.document._id}} received at {{now}}",
            "level": "info",
            "metadata": { "orderId": "{{trigger.document._id}}", "itemCount": "{{trigger.document.items.length}}" }
          }
        },
        {
          "type": "dqlExecute",
          "id": "mark_order_in_progress",
          "description": "Mark order as being prepared",
          "params": {
            "statement": "UPDATE orders SET status = 'in_progress', kdsStartedAt = :now WHERE _id = :orderId",
            "args": { "orderId": "{{trigger.document._id}}", "now": "{{now}}" }
          }
        },
        {
          "type": "sleep",
          "id": "kitchen_prep_time",
          "description": "Simulate prep time (3-8 minutes for typical order)",
          "params": { "minMs": 180000, "maxMs": 480000 }
        },
        {
          "type": "dqlExecute",
          "id": "mark_order_ready",
          "description": "Mark order as ready for pickup",
          "params": {
            "statement": "UPDATE orders SET status = 'ready', kdsCompletedAt = :now WHERE _id = :orderId",
            "args": { "orderId": "{{trigger.document._id}}", "now": "{{now}}" }
          }
        },
        {
          "type": "updateScreen",
          "id": "show_order_ready",
          "params": {
            "message": "Order {{trigger.document._id}} READY ✓",
            "style": "success",
            "duration": 5000
          }
        },
        {
          "type": "log",
          "id": "log_order_ready",
          "params": {
            "message": "Order {{trigger.document._id}} ready. Prep time: {{step.kitchen_prep_time.durationMs}}ms",
            "level": "info",
            "metadata": {
              "orderId": "{{trigger.document._id}}",
              "prepTimeMs": "{{step.kitchen_prep_time.durationMs}}"
            }
          }
        }
      ]
    }
  ]
}
```

And for the **POS Terminal** bot:

```json
{
  "schemaVersion": "1.0",
  "botName": "POS Terminal - Drive Through",
  "role": "POS Terminal",
  "description": "Simulates the drive-through order terminal. Takes orders from sample data, inserts them into Ditto with a delay to simulate the customer interaction.",

  "globalConfig": {
    "interScenarioDelayMs": 500,
    "logVerbosity": "info",
    "heartbeatIntervalMs": 5000,
    "onStepError": "continue"
  },

  "sampleData": {
    "orders": [
      { "_id": "order_sim_001", "items": [{"sku":"burger_classic","qty":1,"price":8.99}], "total": 8.99, "orderType": "drive_through", "status": "pending" },
      { "_id": "order_sim_002", "items": [{"sku":"chicken_sandwich","qty":2,"price":7.49},{"sku":"fries_medium","qty":2,"price":2.99}], "total": 20.96, "orderType": "drive_through", "status": "pending" },
      { "_id": "order_sim_003", "items": [{"sku":"coffee_large","qty":1,"price":4.99}], "total": 4.99, "orderType": "drive_through", "status": "pending" }
    ]
  },

  "scenarios": [
    {
      "id": "scenario_take_drive_through_order",
      "name": "Take Drive-Through Order",
      "type": "sequential",
      "repeat": { "count": -1, "delayMs": 5000, "onDataExhausted": "loop" },
      "steps": [
        {
          "type": "loadData",
          "id": "load_order",
          "params": { "dataSetKey": "orders", "strategy": "sequential", "updateTimestamp": true }
        },
        {
          "type": "sleep",
          "id": "customer_ordering_time",
          "description": "Simulate customer at the drive-through speaker (45-120 seconds)",
          "params": { "minMs": 45000, "maxMs": 120000 }
        },
        {
          "type": "dqlExecute",
          "id": "insert_order",
          "params": {
            "statement": "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE",
            "args": { "order": "{{current.item}}" },
            "expectMutations": true
          }
        },
        {
          "type": "log",
          "id": "log_order_placed",
          "params": {
            "message": "Drive-through order {{current.item._id}} inserted (total: ${{current.item.total}})",
            "level": "info"
          }
        },
        {
          "type": "updateScreen",
          "id": "show_order_sent",
          "params": { "message": "Order #{{current.item._id}} sent to kitchen →", "style": "success" }
        }
      ]
    },
    {
      "id": "scenario_simulate_lunch_rush_outage",
      "name": "Simulate Lunch Rush WiFi Congestion",
      "type": "sequential",
      "repeat": { "count": 1 },
      "steps": [
        {
          "type": "sleep",
          "id": "wait_for_rush_start",
          "description": "Wait 5 minutes before simulating WiFi degradation",
          "params": { "minMs": 300000, "maxMs": 300000 }
        },
        {
          "type": "dittoTransportConfig",
          "id": "go_bluetooth_only",
          "description": "Disable WiFi — simulate congestion (Bluetooth only mode)",
          "params": { "isLanEnabled": false, "isCloudSyncEnabled": false, "isBluetoothLeEnabled": true }
        },
        {
          "type": "log",
          "id": "log_wifi_off",
          "params": { "message": "WiFi disabled — Bluetooth only for 2 minutes", "level": "warning" }
        },
        {
          "type": "sleep",
          "id": "outage_window",
          "params": { "minMs": 120000, "maxMs": 120000 }
        },
        {
          "type": "dittoTransportConfig",
          "id": "restore_wifi",
          "params": { "isLanEnabled": true, "isCloudSyncEnabled": true, "isBluetoothLeEnabled": true }
        },
        {
          "type": "log",
          "id": "log_wifi_restored",
          "params": { "message": "WiFi restored — back to full mesh", "level": "info" }
        }
      ]
    }
  ]
}
```

---

## Schema Validation

Edge Studio should validate uploaded scenario files before accepting them. Key validation rules:

1. `schemaVersion` must be `"1.0"` (or supported version)
2. `scenarios` must have at least 1 entry
3. Each scenario must have `id`, `name`, `type`, and `steps`
4. Scenario `id` values must be unique within the file
5. Step `id` values must be unique within a scenario
6. Each step `type` must be in the supported set
7. Required params must be present per step type
8. `repeat.count` must be `-1` (infinite) or a positive integer
9. Reactive scenarios must have an `observer` with a valid `query`

**Validation errors should be displayed inline in the wizard**, listing each issue with its scenario and step location.
