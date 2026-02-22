# DittoSim — Research References

**Status:** Complete
**Compiled:** 2026-02-22

This document summarizes research from workflow engines, simulation frameworks, and Ditto SDK internals that informed the DittoSim design.

---

## 1. Ditto SDK — Critical Constraints for the Simulation Engine

### 1.1 CRDT Data Types and Conflict Semantics

Understanding Ditto's CRDT behavior is essential for designing the data model correctly.

| Type | Merge Strategy | Implication for DittoSim |
|------|---------------|--------------------------|
| **Register** (scalar: string, number, bool, null) | Last-Write-Wins (LWW) | Safe for status fields owned by one writer (bot updates its own status) |
| **Array** | **Atomic (LWW)** | ⚠️ **CRITICAL**: Arrays are a single register. Concurrent appends from multiple peers = data loss. Never use arrays for instruction queues or log entries that multiple peers write to. |
| **Map** (nested object) | Add-wins per key | Maps let different peers modify different keys independently. Safe for multi-writer fields. |
| **Counter** | Distributed counter | Use for increment-only metrics. |

**Key Design Decision:** Every instruction step, every log entry, every bot status must be its own top-level document. No arrays of instructions inside a simulation document.

### 1.2 Document Model

- `_id` can be a **string** or a **composite map key** (e.g., `{ "simId": "sim-1", "seq": 5 }`)
- Composite keys allow highly selective subscriptions and queries
- No nesting of documents — use foreign key references
- Collections are cheap (no limit) — create as many as needed
- **Schema versioning pattern**: rename collection for new schema version (e.g., `__des_sim_scenarios_v2`)

### 1.3 Subscriptions and Observers

```swift
// Bot subscribes only to its own docs
let sub = ditto.sync.registerSubscription("""
    SELECT * FROM __des_sim_scenarios
    WHERE simId = :simId AND peerKey = :myPeerKey
""", ["simId": simId, "myPeerKey": myPeerKey])

// Bot observes for immediate reaction
let observer = try await ditto.store.registerObserver("""
    SELECT * FROM __des_sim_bots
    WHERE simId = :simId AND peerKey = :myPeerKey AND status = 'ready'
""", ...) { result in ... }
```

- Subscriptions = what to sync from the network
- Observers = react to local database changes (whether from local write or arriving sync)
- **Performance tip**: Filter on immutable fields (IDs, creation timestamps) when possible. Avoid filtering on frequently-mutated fields combined with LIMIT.

### 1.4 HTTP API Constraints

- Maximum 1,000 documents per request (queries and mutations)
- EVICT is **not available** via HTTP API (local-only operation)
- Use `ON ID CONFLICT DO NOTHING` for idempotent inserts
- Use `ON ID CONFLICT DO UPDATE` for upserts

### 1.5 System Collections Insight

Ditto exposes `system:data_sync_info` (v4.9+) for monitoring per-remote sync status via DQL. Useful for the orchestrator to track which bots have received which data:

```dql
SELECT * FROM system:data_sync_info
```

This could tell the orchestrator which bots have synced which documents.

---

## 2. Workflow Engine Patterns — What We Learned

### 2.1 n8n.io — Node-Based Workflow

**Architecture:** Nodes connected by edges. Each node has a `type`, `parameters`, and `position`. Data flows as JSON arrays between nodes.

**Relevant pattern:** The concept of named node IDs that can be referenced in connections maps directly to our step IDs that can be referenced in template variables (`{{step.insert_order.result}}`).

**n8n Workflow JSON structure:**
```json
{
  "name": "My Workflow",
  "active": true,
  "nodes": [
    { "id": "start", "name": "Start", "type": "trigger", "parameters": {} },
    { "id": "action", "name": "Do Thing", "type": "action", "parameters": {} }
  ],
  "connections": {
    "Start": { "main": [[{ "node": "Do Thing", "type": "main", "index": 0 }]] }
  }
}
```

**What we borrow:** The concept of named step IDs and typed step definitions. We use a simpler linear array (not a DAG) since bot scenarios are sequential or reactive, not arbitrarily branched.

### 2.2 Apache Airflow — DAG + Task Instance Model

**Architecture:** DAG (Directed Acyclic Graph) with Tasks. Each `DAGRun` has `TaskInstance` records.

**TaskInstance fields:** `dag_id`, `task_id`, `run_id`, `state` (scheduled/queued/running/success/failed), `start_date`, `end_date`, `try_number`, `max_tries`

**What we borrow:**
- State machine vocabulary: `pending → running → success/failed`
- Separate execution record per task instance (our `__des_sim_bot_logs` documents)
- `try_number` concept for retry tracking
- `start_date` / `end_date` → `startedAt` / `completedAt` in our log docs

### 2.3 AWS Step Functions — Amazon States Language (ASL)

**Architecture:** JSON state machine definition with typed states: `Task`, `Choice`, `Parallel`, `Map`, `Pass`, `Wait`, `Succeed`, `Fail`

**Most relevant state types:**
```json
{
  "Wait30Seconds": {
    "Type": "Wait",
    "Seconds": 30,
    "Next": "ProcessPayment"
  },
  "ProcessPayment": {
    "Type": "Task",
    "Resource": "arn:aws:lambda:...:ProcessPayment",
    "End": true
  }
}
```

**What we borrow:**
- Explicit `Type` field on each state/step — our equivalent is the `"type"` field on each step
- `Wait` state → our `sleep` step type
- `Succeed` / `Fail` terminal states → our `completed` / `failed` bot status
- The idea that each step is a named state machine node with a `Next` pointer (we simplify this to sequential array execution)

### 2.4 Temporal / Dapr — Durable Execution

**Architecture:** Workflows are code. State is automatically persisted between steps. If a workflow crashes, it resumes from the last completed step.

**Dapr workflow patterns:**
- **Task Chaining**: A → B → C sequentially
- **Fan-Out/Fan-In**: Execute N tasks in parallel, wait for all
- **Human Interaction**: `waitForEvent()` pauses workflow until external signal received
- **Durable Timers**: Sleep for minutes, days, even years without blocking threads
- **External Events**: Resume paused workflow when an event arrives

**Cloudflare Workflows** step types:
```javascript
// Execute (with auto-retry and checkpointing)
await step.do("process-payment", async () => { ... })

// Sleep
await step.sleep("wait-for-prep", "30 seconds")

// Wait for external event (user/webhook/state change)
await step.waitForEvent("order-ready", { timeout: "1 hour" })
```

**What we borrow:**
- The `step.sleep` concept → our `sleep` step type with `minMs`/`maxMs` range
- The `step.waitForEvent` concept → our `reactive` scenario type (bot pauses and waits for Ditto observer to fire)
- The idea of **checkpointing** — bots write log entries after each step so we know where they are if they crash
- The **compensation/saga pattern** — if a bot fails, it can write to `__des_sim_problems` to signal the orchestrator

### 2.5 Workflow-Core (danielgerlag/workflow-core) — JSON Workflow Definition

**Architecture:** .NET workflow engine with JSON-loadable definitions.

**WaitFor step in JSON:**
```json
{
  "Id": "WaitForOrderReady",
  "StepType": "WorkflowCore.Primitives.WaitFor",
  "Inputs": {
    "EventName": "\"OrderReady\"",
    "EventKey": "\"{{order._id}}\""
  },
  "Outputs": {
    "OrderData": "step.EventData"
  }
}
```

**What we borrow:** The `WaitFor` pattern maps directly to our reactive scenario type. The bot registers a Ditto observer (= the event subscription) and "waits" for it to fire.

---

## 3. Simulation / Load Testing Frameworks

### 3.1 Artillery.io — Scenario-Based Load Testing

**Architecture:** YAML test scripts with `config` (target, phases) and `scenarios` (flow of steps).

**Most relevant concept: "think" pauses:**
```yaml
scenarios:
  - flow:
      - post:
          url: "/orders"
          json: { "items": ["burger", "fries"] }
      - think: 30          # pause 30 seconds (simulates customer interaction)
      - get:
          url: "/orders/{{ orderId }}"
```

The `think` concept is our `sleep` step. Artillery's scenario `flow` array is our `steps` array.

**What we borrow:**
- The `flow` as a sequential array of typed steps
- `think` → our `sleep` step
- Variable interpolation with `{{ variable }}` — we use `{{variable}}` (no spaces)
- The distinction between **phases** (load ramp-up) and **scenarios** (what a user does) — we call these `repeat` config and `steps`

### 3.2 FlowSpec — Lightweight Automation Workflow JSON Schema

**GitHub:** [woodyhayday/FlowSpec](https://github.com/woodyhayday/FlowSpec)

A lightweight JSON schema for defining automations. Inspired by container-based CI/CD but for orchestrating AI workflows. Heavily influences our scenario file format.

**FlowSpec approach:** A workflow is a `title` + `description` + sequence of `steps`. Each step has a `type` and `params`.

**What we borrow:** The minimalist JSON schema philosophy — typed steps with a `params` object, a `description`, and an `id` for referencing from template variables.

### 3.3 Robot Framework — Keyword-Driven Automation

**Architecture:** Test suites → test cases → keywords (reusable step definitions). Sequential execution by default. Parallel via Pabot.

**IoT application:** Used for "hardware in the loop" (HIL) testing — generating signals for device sensors and monitoring outputs. This is analogous to DittoSim where bots generate Ditto data events.

**What we borrow:** The idea of named, reusable step types (keywords) that can be composed into scenarios. Our step type catalog (`dqlExecute`, `sleep`, `httpRequest`, etc.) follows this keyword-driven philosophy.

### 3.4 DFrame (Cysharp) — Distributed Load Testing for Unity / .NET

**Architecture:** Controller (web UI) + Workers (C# scenario scripts connected via gRPC). Workers can run on Unity devices — which is the closest analogy to running on mobile devices.

**Relevant for bot app:** DFrame.Worker architecture (connect to controller on startup, receive scenario config via gRPC, execute, report metrics) is essentially what DittoBot does — except using Ditto P2P sync instead of gRPC.

---

## 3b. Load Testing Frameworks — Detailed Pattern Research

This section contains the detailed findings from deep research into Gatling, k6, Locust, JMeter, Artillery, and IoT simulation tools. These directly informed the scenario file format in `03-scenario-file-format.md`.

### Universal Pattern: How All Tools Define a "Script"

> A script is a **named, ordered list of typed steps**, where each step has a **type identifier** and **typed parameters**.

| Tool | Script Container | Step Representation |
|------|-----------------|---------------------|
| Gatling | `scenario("name").exec(...).pause(...)` | Fluent DSL chain |
| k6 | JS function referenced by `exec:` | JS function body |
| Locust | `SequentialTaskSet` class | `@task` methods in declaration order |
| JMeter | `ThreadGroup > hashTree` | XML element hierarchy |
| Robot Framework | Test case keyword table | `{ type, name, args, body }` JSON |
| Artillery | `scenarios[].flow[]` | Array of `{ stepType: params }` |
| Workflow-Core | `Steps[]` JSON array | `{ Id, StepType, Inputs, NextStepId }` |
| Wokwi | `steps:` YAML array | `- stepType: { params }` |

**DittoSim conclusion:** The Artillery/Wokwi pattern is the cleanest — a `steps[]` array where each element is `{ "type": "stepType", ...params }`.

---

### k6 — Scenario Options (Per-Bot Start Timing)

k6's `options.scenarios` provides the most direct model for multi-bot staggered starts:

```javascript
export const options = {
  scenarios: {
    order_takers: {
      executor: 'constant-vus',
      exec: 'insertOrder',
      vus: 3,
      duration: '10m',
      startTime: '0s',       // start offset from simulation start
      gracefulStop: '30s',   // time to finish current work after simulation ends
      tags: { role: 'order_taker' },
      env: { BOT_ID: 'bot-001' }
    },
    kitchen_display: {
      executor: 'per-vu-iterations',
      exec: 'processOrders',
      vus: 1,
      iterations: 100,
      startTime: '10s',      // starts 10 seconds after order takers
      maxDuration: '10m',
    }
  }
};
```

**Key patterns for DittoSim:**
- `startTime` per scenario → `startOffsetSeconds` per bot assignment
- `gracefulStop` → bots finish current step before simulation hard-stop
- `tags` + `env` → bot identity metadata passed with the script
- `per-vu-iterations` with `iterations: N` → "repeat N times" unit of work

---

### Locust — SequentialTaskSet (Closest to DittoBot Architecture)

Locust's `SequentialTaskSet` is the closest existing model to DittoSim's ordered step list:

```python
class OrderTakerWorkflow(SequentialTaskSet):

    def on_start(self):
        """Called ONCE on bot start — like simulation setup"""
        pass

    @task
    def step_1_sleep(self):
        time.sleep(2)

    @task
    def step_2_insert_order(self):
        response = self.client.post("/ditto/execute", json={
            "query": "INSERT INTO orders DOCUMENTS ({item: 'Burger'})"
        })
        self.inserted_id = response.json().get("id")

    def on_stop(self):
        """Called ONCE on bot stop — sync logs back"""
        pass
```

**Key patterns for DittoSim:**
- `on_start` / `on_stop` = bot initialization + log sync teardown (exact match to our requirement)
- `@task` methods in declaration order = our `steps[]` array
- State is passed via `self.*` instance variables = our `setVar` step and template variables

---

### Artillery — Cleanest JSON Flow Schema

Artillery's `flow[]` is the cleanest pure-JSON step array across all tools:

```yaml
scenarios:
  - name: "Order Taker Bot"
    weight: 3                 # 3 of N bots run this script
    flow:
      - think: 2              # sleep 2 seconds
      - post:
          url: "/api/v4/store/execute"
          json:
            statement: "INSERT INTO orders DOCUMENTS ({item: '{{ item_name }}'})"
          capture:
            - json: "$.results[0].id"
              as: "order_id"   # capture result for next step
      - loop:
          - think: 0.5
        count: 10              # repeat 10 times
      - loop:
          - get:
              url: "/orders?status=pending"
              capture:
                - json: "$.count"
                  as: "order_count"
          - think: 0.5
        whileTrue: "{{ order_count }} == 0"  # reactive polling
```

**Key patterns for DittoSim:**
- `think: N` → our `sleep` step
- `capture` → extracting step results into variables (our template variable system)
- `loop: { count: N }` → repeat N times
- `loop: { whileTrue: "condition" }` → reactive polling (closest without native observers)
- `weight: 3` → assigning multiple bots the same script

---

### Wokwi — Native Reactive Steps (Most Relevant IoT Tool)

Wokwi is the only tool with **native reactive event waiting** in a YAML step format:

```yaml
steps:
  - delay: 500ms
  - set-control:
      part-id: "order_button"
      control: "pressed"
      value: "1"
  - wait-serial:              # REACTIVE: blocks until this text appears on serial output
      text: "Order received"
      timeout: 5000ms         # fails if not seen within 5s
  - delay: 2000ms
```

The `wait-serial` step is the closest analogue to our `reactive` scenario type. DittoSim's equivalent is a step that blocks until a Ditto observer fires. The `timeout` parameter is critical — prevents bots from waiting forever.

---

### OSP (Open Simulation Platform) — Timed Event Model

OSP's scenario format handles "change transport at a specific simulation timestamp" — useful for network chaos testing:

```yaml
scenario:
  end: 600.0     # seconds
  events:
    - time: 0.0
      model: "POS_Terminal"
      variable: "wifi_enabled"
      value: true
    - time: 180.0            # at T+3 minutes, disable WiFi
      model: "POS_Terminal"
      variable: "wifi_enabled"
      value: false
    - time: 300.0            # at T+5 minutes, restore WiFi
      model: "POS_Terminal"
      variable: "wifi_enabled"
      value: true
```

This models "change transport at T+3 minutes" — an alternative to putting a transport config step inside the bot's script. Could be a future DittoSim feature.

---

### Multi-Script Bundled Scenario File — Alternative Design

The research surfaced an alternative to the current "one JSON file per bot" design. The **bundled format** puts all scripts and bot assignments in a single file:

```json
{
  "scripts": [
    {
      "id": "order-taker-script",
      "name": "POS Order Taker",
      "repeat": { "mode": "count", "count": 50 },
      "steps": [...]
    },
    {
      "id": "kitchen-display-script",
      "name": "Kitchen Display",
      "repeat": { "mode": "forever" },
      "steps": [...]
    }
  ],
  "botAssignments": [
    { "peerKey": "PEER-1", "deviceName": "iPad Counter 1", "scriptId": "order-taker-script", "startOffsetSeconds": 0 },
    { "peerKey": "PEER-2", "deviceName": "iPad Counter 2", "scriptId": "order-taker-script", "startOffsetSeconds": 5 },
    { "peerKey": "PEER-3", "deviceName": "Kitchen Display", "scriptId": "kitchen-display-script", "startOffsetSeconds": 0 }
  ]
}
```

**Advantages of bundled format:**
- Multiple bots can share the same script (3 POS terminals all run "order-taker")
- `startOffsetSeconds` per bot declared upfront
- Entire simulation in one uploadable file
- Easier to share and version

**Current design (per-bot files):**
- Each bot gets its own file in wizard Step 2
- Wizard maps peer → file visually (drag/drop per device)
- Simpler mental model: "this file is for this device"

**See Q19 in `05-questions-and-decisions.md` for the decision.**

---

### Reactive Step Comparison Table

| Approach | Tool | Pattern | Native? |
|----------|------|---------|---------|
| **Native observer wait** | Wokwi | `wait-serial` blocks until event | ✅ Yes |
| **Native event wait** | Workflow-Core | `WaitFor` suspends until external event | ✅ Yes |
| **Polling loop** | k6, Locust, JMeter | `while condition: check; sleep(0.5)` | ❌ No |
| **No support** | Gatling | Not applicable | ❌ No |
| **DittoSim design** | Reactive scenario | Ditto observer fires → runs `steps[]` | ✅ Yes (native) |

DittoSim's reactive scenario type (native Ditto observer) is superior to all load testing tools' polling approximations.

---

### `gracefulStop` Pattern for Simulation End

From k6 and JMeter: bots should finish their **current step** before stopping, not be killed mid-operation. This matches our existing design (bot finishes current step on TERMINATE), confirmed as best practice across all tools.

```
Simulation end time reached →
  Bot receives "stop" signal →
  Bot finishes current step (doesn't interrupt) →
  Bot writes completion log →
  Bot updates status to "completed"
```

---

## 4. Kotlin Multiplatform (KMP) — Bot App Technology

### 4.1 KMP Suitability for DittoBot

**Why KMP is the right choice:**
- Ditto SDK has native Android (Kotlin/Java) SDK — wrappable via expect/actual pattern for iOS
- Kotlin Coroutines provide excellent support for timers, background tasks, and concurrent execution
- Compose Multiplatform 1.8.0 is now stable for iOS (96% code reuse)
- StateFlow + collectAsStateWithLifecycle() for reactive UI updates
- No Flutter/React Native threading issues

**Why NOT Flutter/React Native:**
- Flutter: Dart isolates are not great for running many concurrent timers + long-lived background tasks with native SDK access
- React Native: JS bridge overhead, background execution limitations on iOS, threading complexity

### 4.2 KMP Architecture for DittoBot

**Platform-specific (expect/actual):**
- Ditto SDK initialization (Android: `Ditto(context, identity)`, iOS: `Ditto(identity)`)
- QR code scanning (Android: CameraX + ML Kit, iOS: AVFoundation)
- Background task scheduling (Android: WorkManager, iOS: BGTaskScheduler)
- File logging (Android: internal storage, iOS: Application Support)

**Shared KMP code:**
- Scenario engine (step execution, template variable resolution)
- Bot state machine
- Ditto SDK wrapper for DQL execution and sync management
- Log aggregation and heartbeat writing
- UI ViewModels (using StateFlow)

**Compose Multiplatform shared UI:**
- QR scan screen
- Simulation list screen
- Running status screen (progress bars, current step display)
- Error/problem display

### 4.3 Scenario Runner Architecture (Kotlin Coroutines)

```kotlin
// Bot scenario runner concept
class ScenarioRunner(
    val ditto: Ditto,
    val botConfig: BotConfig,
    val scenarios: List<Scenario>
) {
    val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    fun start() {
        // Sequential scenarios: run in sequence
        scope.launch {
            for (scenario in scenarios.filter { it.type == "sequential" }) {
                executeSequentialScenario(scenario)
            }
        }

        // Reactive scenarios: run concurrently, each with its own observer
        for (scenario in scenarios.filter { it.type == "reactive" }) {
            scope.launch {
                setupReactiveScenario(scenario)
            }
        }
    }

    private suspend fun executeStep(step: Step, context: StepContext): StepResult {
        return when (step.type) {
            "sleep" -> {
                val duration = step.params.getRandomDuration()
                delay(duration)
                StepResult.success(durationMs = duration)
            }
            "dqlExecute" -> executeDql(step, context)
            "httpRequest" -> executeHttp(step, context)
            "dittoTransportConfig" -> applyTransportConfig(step)
            "log" -> writeLog(step, context)
            "updateScreen" -> updateBotUI(step, context)
            else -> StepResult.error("Unknown step type: ${step.type}")
        }
    }
}
```

### 4.4 Important: iOS Background Execution

**Challenge:** iOS aggressively suspends background apps. A bot simulation could run for 60+ minutes.

**Solution options:**
1. **Background Processing Task** (`BGProcessingTaskRequest`) — iOS allows up to 30 minutes for background processing tasks when device is charging and on WiFi. May not be enough.
2. **Background app refresh** — Limited to ~30 seconds per background interval.
3. **Keep app in foreground** — Most reliable for simulation accuracy. Bot screen stays on during simulation.
4. **Recommendation for POC:** Require the bot app to stay in foreground during simulation (screen stays on, app doesn't background). Add a setting to prevent device sleep during simulation.

---

## 5. Key Open-Source References

| System | Repo / URL | Relevance |
|--------|-----------|-----------|
| n8n | [github.com/n8n-io/n8n](https://github.com/n8n-io/n8n) | Node-based workflow JSON, step ID references |
| Temporal | [github.com/temporalio/temporal](https://github.com/temporalio/temporal) | Durable execution, retry patterns |
| workflow-core | [github.com/danielgerlag/workflow-core](https://github.com/danielgerlag/workflow-core) | JSON workflow definition, WaitFor pattern |
| Artillery | [artillery.io](https://www.artillery.io) | Scenario flow, think pauses, variable interpolation |
| FlowSpec | [github.com/woodyhayday/FlowSpec](https://github.com/woodyhayday/FlowSpec) | Lightweight step-based JSON schema |
| Dapr Workflows | [docs.dapr.io/workflows](https://docs.dapr.io/developing-applications/building-blocks/workflow/workflow-patterns/) | Fan-out/fan-in, external events |
| Cloudflare Workflows | [developers.cloudflare.com/workflows](https://developers.cloudflare.com/workflows/) | step.do, step.sleep, step.waitForEvent pattern |

---

## 5b. Detailed Workflow Engine Entity Models (Deep Research)

This section contains the full entity schemas discovered during deep research of each system. These informed the `__des_sim_*` collection designs in `02-data-model-design.md`.

### n8n — Execution Entity (TypeORM)

**`workflow_entity` table:**
```json
{
  "id": "uuid",
  "name": "string",
  "active": "boolean",
  "nodes": "json[]",
  "connections": "json",
  "settings": {
    "errorWorkflow": "workflowId",
    "executionOrder": "v1",
    "timeout": 3600
  },
  "staticData": "json",
  "versionId": "string",
  "triggerCount": "integer"
}
```

**`execution_entity` table:**
```json
{
  "id": "integer",
  "workflowId": "uuid",
  "finished": "boolean",
  "mode": "manual | trigger | webhook | retry | scheduled",
  "retryOf": "integer",
  "retrySuccessId": "integer",
  "startedAt": "timestamp",
  "stoppedAt": "timestamp",
  "waitTill": "timestamp",
  "status": "new | running | success | error | waiting | canceled",
  "workflowData": "json",
  "data": "json"
}
```

**Critical pattern:** `workflowData` is a **snapshot** of the workflow definition at execution time — not a live reference. This prevents version drift if the scenario definition changes while a simulation is running. DittoSim should apply the same pattern: embed a `scenarioSnapshot` on the simulation run document, not just a reference to the scenario.

**Node JSON (within `workflow.nodes[]`):**
```json
{
  "id": "uuid",
  "name": "HTTP Request",
  "type": "n8n-nodes-base.httpRequest",
  "typeVersion": 4,
  "parameters": { "method": "GET", "url": "https://api.example.com/data" },
  "onError": "continueRegularOutput"
}
```

**Connection adjacency map:**
```json
{
  "TriggerNode": {
    "main": [[{ "node": "HTTPNode", "type": "main", "index": 0 }]]
  }
}
```

The `waitTill` field is the right model for bot `sleep` steps — a bot sets a "resume at" timestamp and yields.

---

### Temporal.io — Workflow Execution + Event History

**WorkflowExecution fields:**
```
WorkflowId     string       — user-assigned, stable across retries
RunId          string       — UUID per run; new on each retry/continue-as-new
Namespace      string       — isolation boundary
WorkflowType   string       — the workflow function name
Status:
  RUNNING | COMPLETED | FAILED | CANCELED | TERMINATED
  CONTINUED_AS_NEW | TIMED_OUT
HistoryLength  integer      — events recorded (max 50,000)
ParentExecution { WorkflowId, RunId }  — for child workflows
```

**Complete event type list (for designing `__des_sim_bot_logs`):**
```
Workflow:   Started, Completed, Failed, TimedOut, CancelRequested, Canceled, Terminated, ContinuedAsNew
WorkflowTask:  Scheduled, Started, Completed, TimedOut, Failed
Activity:   Scheduled, Started, Completed, Failed, TimedOut, CancelRequested, Canceled
Timers:     Started, Fired, Canceled
Signals:    WorkflowExecutionSignaled
Child:      StartChildInitiated, StartChildFailed, ChildStarted, ChildCompleted, ChildFailed, ChildCanceled
Markers:    MarkerRecorded (side-effect records)
```

**Signals — the reactive pattern:**
```go
// In workflow code — blocks until signal arrives
signalChan := workflow.GetSignalChannel(ctx, "device-event")
var payload DeviceEvent
signalChan.Receive(ctx, &payload)

// External code sends the signal
client.SignalWorkflow(ctx, workflowId, runId, "device-event", payload)
```

**Continue-As-New** resets history at 50K events while preserving workflow identity — essential for multi-hour sessions. Bot can call this to prevent log document explosion.

**Key Insights:**
- Signals are the ideal model for reactive steps triggered by Ditto document changes
- Child workflows = one execution per bot (orchestrator spawns them)
- Continue-As-New solves indefinitely-running simulations

---

### Apache Airflow — `task_instance` (Gold Standard for Step Tracking)

The Airflow `task_instance` table is the definitive model for per-step execution tracking:

```
task_id              string (PK component)
dag_id               string (PK component)
run_id               string (PK component)
map_index            integer     — -1 for normal, 0+ for dynamic parallel instances

state:
  none | scheduled | queued | running | success | failed |
  up_for_retry | up_for_reschedule | skipped | removed | deferred

start_date           timestamp
end_date             timestamp
duration             float
try_number           integer     — current attempt (1-based)
max_tries            integer     — from task.retries config
hostname             string      — which worker ran it
operator             string      — class name
queued_dttm          timestamp
pid                  integer
trigger_id           integer     — for deferred (async sensor) tasks
next_method          string      — for deferred resumption
next_kwargs          json
```

**Task State Lifecycle:**
```
none → scheduled → queued → running → success
                                     ↘ failed → (try_number < max_tries)
                                               → up_for_retry → queued
                                             → (try_number >= max_tries) → failed (terminal)
                                     ↘ up_for_reschedule (sensor poll)
                                     ↘ skipped (conditional)
                                     ↘ deferred (async trigger — releases worker slot)
                                         → running (event fires)
```

**Dynamic mapping (`map_index`):** Creates one `task_instance` row per bot per step — enables N-bot parallel execution in a single model.

**`deferred` state** — non-blocking for observe steps. The bot releases processing capacity while waiting for a Ditto event; resumes when the event fires.

---

### BullMQ — Job JSON Structure

```typescript
interface JobJson {
  id: string                // auto-incremented or custom
  name: string              // job type name
  data: string              // JSON payload
  timestamp: number         // creation time (ms epoch)
  processedOn?: number
  finishedOn?: number
  delay: number             // ms before active
  priority: number          // 0=none, 1=highest
  attemptsMade: number
  stacktrace: string[]      // one stack per failed attempt — KEY PATTERN
  returnvalue: string       // JSON result on success
  failedReason: string      // error message on failure
  progress: number | object // 0-100 or custom { rowsProcessed: 42, totalRows: 100 }
  repeatJobKey?: string
  parentKey?: string
}
```

**Exponential backoff with full jitter (AWS recommended formula):**
```
delay = random(0, min(maxDelay, initialDelay * (backoffRate ^ (attempt - 1))))
```

**Errors that should NOT retry:**
- `AssertionError` — expected result mismatch; retry won't fix it
- `AuthenticationError` — credentials issue
- `InvalidQueryError` — malformed DQL

**Key patterns for DittoSim:**
- `stacktrace: string[]` (one per attempt) → per-attempt error tracking in `__des_sim_problems`
- `progress: object` → rich progress in heartbeat (`{ currentStep: 3, totalSteps: 12, currentIteration: 2 }`)

---

### AWS Step Functions — Complete State Type Taxonomy

| State Type | Purpose | Key Fields |
|-----------|---------|-----------|
| `Task` | Execute work | Resource, Retry[], Catch[], TimeoutSeconds, HeartbeatSeconds |
| `Wait` | Sleep/pause | Seconds, SecondsPath, Timestamp, TimestampPath |
| `Choice` | Conditional branch | Choices[], Default |
| `Parallel` | Fixed concurrent branches | Branches[] (all run) |
| `Map` | Fan-out over array | ItemsPath, MaxConcurrency, Iterator |
| `Pass` | Data transform only | InputPath, OutputPath, Parameters |
| `Succeed` | Terminal success | — |
| `Fail` | Terminal failure | Error, Cause |

**`waitForTaskToken` — the reactive pattern:**
Task pauses indefinitely (up to `HeartbeatSeconds`) for external code to call `SendTaskSuccess(token, result)`. For DittoSim: bot registers a Ditto observer, captures the task token, calls back when the event fires.

**`Map` with `MaxConcurrency: 12`** is the precise model for running 12 bots in parallel with a bounded cap.

**Full retry policy:**
```json
{
  "ErrorEquals": ["States.TaskFailed", "States.Timeout"],
  "IntervalSeconds": 2,
  "MaxAttempts": 3,
  "BackoffRate": 2.0,
  "MaxDelaySeconds": 300,
  "JitterStrategy": "FULL"
}
```

---

### Synthesized Step Type Taxonomy

| Step Type | Blocking | Reactive | Parallel | Reference Pattern |
|-----------|----------|----------|----------|-------------------|
| `sleep` | Yes (duration) | No | No | ASL `Wait`, BullMQ `delay`, n8n Wait node |
| `dqlExecute` | Yes (sync) | No | No | ASL `Task`, Airflow `PythonOperator` |
| `httpRequest` | Yes (sync) | No | No | ASL `Task`, n8n HTTP node |
| `loadData` | Yes (sync) | No | No | Custom (data injection) |
| `setVar` | No | No | No | n8n `Set` node |
| `log` | No | No | No | Custom |
| `updateScreen` | No | No | No | Custom |
| `alertOrchestrator` | No | No | No | Temporal Signal to parent |
| `dittoStartSync` | Yes | No | No | Custom |
| `dittoStopSync` | Yes | No | No | Custom |
| `dittoTransportConfig` | Yes | No | No | Custom |
| `reactive` (observe) | Yes (until event/timeout) | **Yes** | No | Temporal Signal, ASL `waitForTaskToken`, Airflow Deferrable Sensor |

---

### Step Execution Status State Machine (Synthesized)

```
pending
  → running
      → success (terminal)
      → failed
          → (attempt < maxAttempts) → retrying → pending (after backoff)
          → (attempt >= maxAttempts) → failed (terminal)
      → skipped (terminal — onError: continue)
      → waiting (reactive/observe step — blocked on Ditto observer)
          → running (event fired)
          → failed (timeout expired)
```

Backoff formula (AWS Full Jitter, recommended for retry delays in `__des_sim_bot_logs`):
```
delay = random(0, min(maxDelay, initialDelay * (backoffRate ^ (attempt - 1))))
```

---

## 6. Summary of Design Decisions from Research

| Decision | Chosen Approach | Rationale |
|----------|----------------|-----------|
| Step format | Linear array (not DAG) | Bot scenarios are sequential; DAG adds complexity without benefit for this use case |
| Instruction storage | One document per instruction | Ditto arrays are atomic LWW; concurrent writes would lose data |
| Bot filtering | Subscription filtered by `peerKey` | Each bot only syncs its own docs — reduces Bluetooth bandwidth |
| Scenario file format | JSON (not YAML) | Easier to parse on KMP, better LLM generation, simpler schema validation |
| Template variables | Simple `{{key}}` interpolation | Sufficient for POC; full expression evaluation is future enhancement |
| Step typing | `"type"` field on each step | Follows AWS ASL, n8n, workflow-core conventions |
| Bot app technology | Kotlin Multiplatform + Compose Multiplatform | Native performance, shared UI, Ditto SDK wrapper pattern |
| Foreground requirement | Bot stays in foreground during simulation | Most reliable for iOS background execution constraints |
| Scenario snapshot | Embed full scenario definition on run start | From n8n `workflowData` pattern — prevents version drift mid-simulation |
| Retry tracking | `(attempt, maxAttempts, state)` triple | From Airflow `task_instance` — the gold standard for step retry state |
| Error tracking | Per-attempt `stacktrace[]` in problems docs | From BullMQ — enables diagnosing which attempt failed and why |
| Backoff formula | Full jitter exponential backoff | From AWS — `random(0, min(maxDelay, initialDelay * backoffRate^(attempt-1)))` |
| Reactive observe | Native Ditto observer (not polling) | DittoSim's reactive scenario is superior to all load testing tools' polling |
| gracefulStop | Bot finishes current step before stopping | Confirmed by k6, JMeter, Locust as universal best practice |
| Per-bot start offset | `startOffsetSeconds` per bot in wizard | From k6 `startTime` + JMeter `ThreadGroup.delay` — enables realistic staggered starts |
| Script format | Per-bot JSON file (Phase 1) | Simpler wizard UX; bundled multi-script format considered for Phase 2 |
| `capture` pattern | Output variable from each step | From Artillery `capture` — each step can write a result to `{{variable}}` for next steps |
