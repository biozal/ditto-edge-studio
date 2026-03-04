# DittoSim — n8n.io as Orchestration Engine: Research Report

**Status:** Research Complete
**Date:** 2026-02-21
**Scope:** Evaluate whether n8n can replace or supplement the custom DittoSim orchestration engine

---

## Executive Summary

n8n is a capable, free, self-hostable workflow automation platform that **can supplement DittoSim but cannot replace the custom orchestrator**. The strongest use case is using n8n as a scenario authoring and workflow design tool that drives data into Ditto's HTTP API — essentially letting n8n act as the "brain" that inserts/updates documents, while the mobile bot remains a pure Ditto observer and DQL executor. This is complementary to, not a replacement for, the Ditto-native P2P sync architecture.

The verdict in one sentence: n8n is an excellent tool for building the *scenario simulation logic* (what DQL to run, when, with what data) but it **cannot replace the Ditto sync layer** that makes the bot system resilient, offline-capable, and P2P-native.

---

## Section 1: n8n Community Edition (Free/Self-Hosted)

### License

n8n is distributed under the **Sustainable Use License** (fair-code, not OSI open source). Key rules:

- **Allowed:** Internal business use, personal use, consulting/support services related to n8n
- **Allowed:** Running n8n internally to automate your own workflows (this use case — DittoSim tooling — is clearly allowed)
- **Restricted:** Selling a product or service whose value derives substantially from n8n, or hosting n8n and charging users for access
- **Bottom line for DittoSim:** Using n8n as an internal developer tool to drive simulations is unambiguously allowed at no cost

### What Is Free vs. Paid

The community (self-hosted) edition includes:

| Feature | Community (Free) | Cloud Starter ($20/mo) | Cloud Pro ($50/mo) |
|---------|-----------------|------------------------|---------------------|
| Webhook node | YES | YES | YES |
| HTTP Request node | YES | YES | YES |
| Code node (JS/Python) | YES | YES | YES |
| MQTT node | YES | YES | YES |
| Wait/Sleep node | YES | YES | YES |
| Loop/Split in Batches | YES | YES | YES |
| Custom nodes (community) | YES | YES | YES |
| Unlimited workflows | YES | YES | YES |
| Unlimited executions | YES | 2,500/mo | More |
| Concurrent executions | Unlimited (configurable) | 5 | More |
| SSO / SAML | NO | NO | YES (Enterprise) |
| Audit logs | NO | NO | YES (Enterprise) |
| Source control (Git) | NO | NO | YES (Enterprise) |
| Multi-user projects | NO | 1 project | 3 projects |

**Key finding:** Every feature relevant to DittoSim orchestration — webhooks, HTTP Request, Code node, MQTT, Wait, Loop, expression builder — is fully available in the free community edition with no execution limits when self-hosted.

### Execution Limits

- **Self-hosted community:** No execution limits. Concurrency control is disabled by default (unlimited parallel executions)
- If you want to throttle: you can set `N8N_CONCURRENCY_PRODUCTION_LIMIT=N` as an environment variable
- No step limits, no workflow count limits, no time limits per execution
- The Wait node can pause workflows indefinitely (state is offloaded to SQLite/Postgres, survives restarts)

---

## Section 2: Docker on Mac — Setup Complexity

### Fastest Path: Two Commands

```bash
# Step 1: Create persistent volume (one-time)
docker volume create n8n_data

# Step 2: Start n8n
docker run -it --rm \
  --name n8n \
  -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e N8N_SECURE_COOKIE=false \
  docker.n8n.io/n8nio/n8n
```

Open http://localhost:5678 — you will see the account setup screen. From zero to a running n8n instance is under 5 minutes on a Mac with Docker Desktop already installed (image is ~500MB, pull is the main delay).

**If Docker Desktop is not installed:** Add ~10 minutes to download and install Docker Desktop from docker.com. No configuration is required.

### Default Port

n8n exposes port **5678**. The default URL is `http://localhost:5678`.

### State Persistence

- All workflow definitions, execution history, and credentials are stored in `/home/node/.n8n` inside the container
- Mapping this to a Docker named volume (`-v n8n_data:/home/node/.n8n`) ensures all data survives container restarts
- Default database is **SQLite** (embedded, zero configuration required)
- For production/team use, switch to PostgreSQL (see docker-compose below)
- The Wait node specifically offloads paused execution state to the database — it survives restarts

### Apple Silicon (M1/M2/M3/M4) Compatibility

n8n's Docker image is a **multi-arch image** supporting both `linux/amd64` and `linux/arm64`. On Apple Silicon Macs, Docker Desktop automatically pulls the `arm64` variant. There are no known compatibility issues as of 2025-2026. The image runs natively (not through Rosetta emulation) on Apple Silicon.

### docker-compose.yml for DittoSim Use

```yaml
version: "3.8"

services:
  n8n:
    image: docker.n8n.io/n8nio/n8n:latest
    container_name: dittosim-n8n
    restart: unless-stopped
    ports:
      - "5678:5678"
    environment:
      # Required for Safari/localhost cookie behavior
      - N8N_SECURE_COOKIE=false
      # Optional: set a fixed encryption key so credentials survive image updates
      - N8N_ENCRYPTION_KEY=your-32-char-encryption-key-here
      # Optional: enable community nodes as AI tools
      - N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true
      # Optional: set timezone
      - GENERIC_TIMEZONE=America/New_York
      # Database (defaults to SQLite if not set)
      # - DB_TYPE=postgresdb
      # - DB_POSTGRESDB_HOST=postgres
      # - DB_POSTGRESDB_PORT=5432
      # - DB_POSTGRESDB_DATABASE=n8n
      # - DB_POSTGRESDB_USER=n8n
      # - DB_POSTGRESDB_PASSWORD=n8n_password
    volumes:
      - n8n_data:/home/node/.n8n
      # Optional: mount local workflow JSON files for import on first run
      # - ./workflows:/home/node/workflows
    networks:
      - dittosim-net

  # Optional: Add Mosquitto MQTT broker for Option E (MQTT transport)
  # mqtt:
  #   image: eclipse-mosquitto:2
  #   container_name: dittosim-mqtt
  #   ports:
  #     - "1883:1883"
  #     - "9001:9001"  # WebSocket port for browser/mobile clients
  #   volumes:
  #     - ./mosquitto.conf:/mosquitto/config/mosquitto.conf
  #     - mosquitto_data:/mosquitto/data
  #   networks:
  #     - dittosim-net

volumes:
  n8n_data:
  # mosquitto_data:

networks:
  dittosim-net:
    driver: bridge
```

Start with: `docker compose up -d`
Stop with: `docker compose down`

### Shell Script: Zero-to-Running in One Shot

```bash
#!/bin/bash
# setup-n8n-dittosim.sh
# Prerequisites: Docker Desktop must be installed

set -e

echo "Starting DittoSim n8n orchestration server..."

# Check Docker is running
if ! docker info > /dev/null 2>&1; then
  echo "Error: Docker is not running. Please start Docker Desktop."
  exit 1
fi

# Create volume if it doesn't exist
docker volume create n8n_data 2>/dev/null || true

# Stop existing container if running
docker rm -f dittosim-n8n 2>/dev/null || true

# Start n8n
docker run -d \
  --name dittosim-n8n \
  --restart unless-stopped \
  -p 5678:5678 \
  -v n8n_data:/home/node/.n8n \
  -e N8N_SECURE_COOKIE=false \
  -e N8N_ENCRYPTION_KEY="dittosim-dev-key-change-in-prod" \
  docker.n8n.io/n8nio/n8n

echo ""
echo "n8n is starting..."
sleep 3
echo "Open: http://localhost:5678"
echo ""
echo "To stop: docker stop dittosim-n8n"
echo "To view logs: docker logs -f dittosim-n8n"
```

---

## Section 3: n8n ↔ Mobile App Communication Options

### Option A: Webhooks (n8n SENDS to Mobile App)

**How it works:** The mobile app runs an embedded HTTP server on a local port. n8n uses its HTTP Request node to POST to that server's IP address.

**n8n side:** The HTTP Request node can POST to any URL with any headers and body. This is standard and fully available in community edition.

**iOS side:** Yes, an iOS app can run an embedded HTTP server. The most practical libraries are:
- **Swifter** (`github.com/httpswift/swifter`) — Pure Swift, minimal, Swift Package Manager compatible
- **GCDWebServer** — Well-established, Objective-C with Swift support
- A Vapor-based embedded server (heavier, but full HTTP/2 support)

Example Swifter setup in Swift:
```swift
import Swifter

let server = HttpServer()
server["/instruction"] = { request in
    let body = String(bytes: request.body, encoding: .utf8) ?? ""
    // Parse JSON instruction and trigger bot action
    return HttpResponse.ok(.text("ACK"))
}
try? server.start(8080)
```

**Android side:** NanoHTTPD is the de-facto standard for embedding an HTTP server in an Android/Kotlin app:
```kotlin
class BotServer : NanoHTTPD(8080) {
    override fun serve(session: IHTTPSession): Response {
        val body = mutableMapOf<String, String>()
        session.parseBody(body)
        val instruction = body["postData"] ?: ""
        // Process instruction
        return newFixedLengthResponse("ACK")
    }
}

val server = BotServer()
server.start()
```

**Practical challenges:**
- The Mac running n8n and the physical devices must be on the same LAN
- Device IP addresses change (DHCP) — the bot app would need to register its current IP with n8n
- iOS can background-suspend apps, which kills the HTTP server — requires `UIBackgroundModes` entitlement and active audio/location session to stay alive
- Android has similar background restrictions since Android 8+
- Not suitable for production but workable for a controlled lab simulation environment

**Verdict on Option A:** Workable for a wired/known-network lab but brittle. Each bot must register its IP with n8n, and background app killing is a real issue on both platforms.

---

### Option B: Polling (Mobile Polls n8n)

**How it works:** The bot calls a URL like `GET http://n8n-mac:5678/webhook/bot-instructions?botId=pk_abc123` every few seconds to get its next instruction.

**n8n side:**
- The **Webhook node** can receive GET/POST requests and return data
- However, n8n webhooks are stateless triggers — they start a new workflow execution each time they're called
- There is no built-in "queue" or "task inbox" in n8n community edition
- To implement a polling endpoint, you would need to: (1) store pending instructions in n8n's built-in storage (via Code node + file system), or (2) use an external store (Redis, SQLite via exec node), or (3) use Ditto itself as the queue (see Option C)

**Implementation pattern:**
```
Webhook (GET /bot-instructions)
  → Code Node (reads next pending instruction from file or DB)
  → Respond to Webhook (returns JSON instruction or empty {})
```

**Practical challenges:**
- n8n doesn't have a native "queue" or "message inbox" data structure
- Every poll triggers a fresh workflow execution — fine for low frequency but adds overhead
- Timing of "next instruction" is controlled entirely by the bot's polling frequency, not n8n's orchestration logic
- State management (which instruction has been sent to which bot) must be handled externally

**Verdict on Option B:** Possible but requires external state storage. The bot already needs network connectivity to reach n8n, so you've introduced a central dependency. At this point you're essentially building a mini-backend anyway.

---

### Option C: n8n HTTP Request → Ditto HTTP API (RECOMMENDED APPROACH)

**This is the most architecturally elegant option and aligns perfectly with DittoSim's existing design.**

**How it works:**
1. n8n workflow builds a DQL statement (e.g., `INSERT INTO orders DOCUMENTS (:order)`)
2. n8n HTTP Request node POSTs it to Ditto's Big Peer HTTP API
3. Ditto syncs the new/updated document to all connected devices via P2P mesh
4. The mobile bot (already subscribed to the relevant collection) receives the change via its existing Ditto observer
5. Bot reacts and executes its local DQL

The bot app does NOT need to know n8n exists at all. It only talks to Ditto. n8n only talks to Ditto. The P2P sync layer is the message bus.

**Ditto HTTP API Request:**

```
POST https://<your-ditto-cloud-endpoint>/api/v4/store/execute
Authorization: Bearer <your-api-key>
Content-Type: application/json

{
  "statement": "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE",
  "args": {
    "order": {
      "_id": "order_sim_001",
      "status": "pending",
      "items": [{"sku": "burger", "qty": 1}],
      "createdAt": "2026-02-21T14:00:00Z"
    }
  }
}
```

**Response:**
```json
{
  "transactionId": 42,
  "queryType": "mutation",
  "mutatedDocumentIds": ["order_sim_001"]
}
```

**n8n HTTP Request node configuration:**

In the HTTP Request node:
- Method: `POST`
- URL: `https://your-app.cloud.ditto.live/api/v4/store/execute`
- Authentication: Header Auth → Name: `Authorization`, Value: `Bearer your-api-key`
- Body Content Type: `JSON`
- Body: Use n8n expression to build dynamic DQL:

```json
{
  "statement": "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE",
  "args": {
    "order": {
      "_id": "={{ 'order_sim_' + $now.toMillis() }}",
      "status": "pending",
      "customerId": "={{ $json.customerId }}",
      "createdAt": "={{ $now.toISO() }}"
    }
  }
}
```

**n8n expressions are JavaScript-based** and support:
- `$json.fieldName` — access data from previous nodes
- `$now` — current timestamp (Luxon DateTime object)
- `$vars.myVariable` — workflow-level variables
- IIFE for complex logic: `={{ (() => { const x = ...; return x; })() }}`
- Code node for full JS/Python before the HTTP Request node

**Verdict on Option C:** This is the architecturally correct approach. n8n acts as the scenario author and data injector. Ditto handles all sync. The bot remains a pure Ditto-native app with no knowledge of n8n. Zero new dependencies on the bot side.

---

### Option D: WebSockets

**n8n does NOT natively support WebSocket connections (as of 2026).**

There are open feature requests for a WebSocket node, but it is not in the community edition. The Webhook node only handles standard HTTP request-response, not persistent connections.

Workarounds that have been used by community members:
- Using a Code node with `ws` npm library (requires custom Docker image with ws pre-installed)
- Running a separate WebSocket server alongside n8n and using HTTP Request to bridge

**iOS/Android WebSocket support:** Both platforms have excellent native WebSocket support (URLSession for iOS, OkHttp/Ktor for Android). The mobile side is not the constraint.

**Verdict on Option D:** Not practically available in community edition without significant hacking. Skip this option.

---

### Option E: MQTT

**n8n has native MQTT support** in community edition — both a trigger node (subscribe) and an action node (publish). This is one of n8n's strongest IoT integration patterns.

**n8n MQTT capabilities:**
- `MQTT Trigger` node: subscribes to a topic and triggers a workflow when a message arrives
- `MQTT` action node: publishes a message to a topic as a workflow step
- Connects to any MQTT broker (Mosquitto, HiveMQ, EMQX, etc.)

**Mobile MQTT client libraries:**
- **iOS/Swift:** CocoaMQTT (`github.com/emqx/CocoaMQTT`) — supports MQTT 5.0, available as Swift Package
- **Android/Kotlin:** Paho MQTT Android Client, or Eclipse Paho Kotlin, or EMQX's kotlin-mqtt

**Architecture with MQTT:**
```
n8n workflow
  → MQTT Publish (topic: "dittosim/bot/pk_abc123/instruction")
    → Mosquitto broker (running in Docker alongside n8n)
      → iOS/Android bot subscribes to its topic
        → Bot receives instruction, executes DQL via local Ditto SDK
          → Bot publishes result to "dittosim/bot/pk_abc123/result" topic
            → n8n MQTT Trigger listens for result
              → n8n workflow continues
```

**Adding Mosquitto to docker-compose:**
```yaml
mqtt:
  image: eclipse-mosquitto:2
  ports:
    - "1883:1883"   # MQTT
    - "9001:9001"   # MQTT over WebSocket (for browser clients)
  volumes:
    - ./mosquitto.conf:/mosquitto/config/mosquitto.conf

# mosquitto.conf:
# listener 1883
# listener 9001
# protocol websockets
# allow_anonymous true
```

**Verdict on Option E:** This is the most IoT-appropriate pattern and gives true bidirectional real-time communication. However, it adds another dependency (MQTT broker) and requires the bot app to maintain two connections: Ditto (for P2P sync) and MQTT (for instructions from n8n). The hybrid complexity may not be worth it vs. Option C.

---

## Section 4: Custom n8n Nodes for Ditto Integration

### Does a Ditto Node Exist?

A search of the npm registry for `n8n-nodes-ditto` and `n8n-nodes-dittolive` returned **no results** as of February 2026. There is no published Ditto node in the n8n community marketplace.

### How Hard Is It to Write One?

Building a custom n8n node requires TypeScript and Node.js. The development experience is well-documented with official tooling.

**Scaffold a new node:**
```bash
npm create @n8n/node@latest
# Follow prompts: package name, node name, etc.
```

**Minimal "Ditto DQL" node structure:**

```typescript
// DittoDQL.node.ts
import {
  IExecuteFunctions,
  INodeExecutionData,
  INodeType,
  INodeTypeDescription,
} from 'n8n-workflow';

export class DittoDQL implements INodeType {
  description: INodeTypeDescription = {
    displayName: 'Ditto DQL',
    name: 'dittoDQL',
    icon: 'file:ditto.svg',
    group: ['transform'],
    version: 1,
    description: 'Execute a DQL statement against a Ditto Big Peer HTTP API',
    defaults: { name: 'Ditto DQL' },
    inputs: ['main'],
    outputs: ['main'],
    credentials: [{ name: 'dittoApi', required: true }],
    properties: [
      {
        displayName: 'DQL Statement',
        name: 'statement',
        type: 'string',
        default: 'SELECT * FROM orders',
        description: 'The DQL statement to execute',
      },
      {
        displayName: 'Arguments (JSON)',
        name: 'args',
        type: 'json',
        default: '{}',
        description: 'Arguments object for parameterized DQL',
      },
    ],
  };

  async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
    const statement = this.getNodeParameter('statement', 0) as string;
    const args = this.getNodeParameter('args', 0) as object;
    const credentials = await this.getCredentials('dittoApi');

    const response = await this.helpers.request({
      method: 'POST',
      url: `${credentials.cloudEndpoint}/api/v4/store/execute`,
      headers: {
        Authorization: `Bearer ${credentials.apiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ statement, args }),
    });

    return this.helpers.returnJsonArray([JSON.parse(response)]);
  }
}
```

**Credentials file:**
```typescript
// DittoApi.credentials.ts
import { ICredentialType, INodeProperties } from 'n8n-workflow';

export class DittoApi implements ICredentialType {
  name = 'dittoApi';
  displayName = 'Ditto API';
  properties: INodeProperties[] = [
    {
      displayName: 'Cloud Endpoint',
      name: 'cloudEndpoint',
      type: 'string',
      default: 'https://your-app.cloud.ditto.live',
    },
    {
      displayName: 'API Key',
      name: 'apiKey',
      type: 'string',
      typeOptions: { password: true },
      default: '',
    },
  ];
}
```

**Installing in Docker:**

For Docker deployments, the easiest approach is to install via the n8n GUI (Settings → Community Nodes → Install), pointing to the local package. For local development packages not on npm, create a custom Docker image:

```dockerfile
FROM docker.n8n.io/n8nio/n8n:latest
USER root
WORKDIR /usr/local/lib/node_modules/n8n
COPY ./n8n-nodes-ditto /home/node/.n8n/custom/
RUN cd /home/node/.n8n/custom/n8n-nodes-ditto && npm install
USER node
```

**Time estimate:** A working Ditto DQL custom node takes approximately 2-4 hours for a developer familiar with TypeScript. The official starter template does most of the heavy lifting. Publishing to npm takes another 1-2 hours for package setup.

---

## Section 5: n8n Workflow Design for DittoSim Scenarios

### Node Inventory Available in Community Edition

| Need | n8n Node | Available Free? |
|------|----------|----------------|
| Manual trigger | Manual Trigger | YES |
| Schedule trigger | Schedule Trigger | YES |
| Webhook trigger | Webhook | YES |
| HTTP call to Ditto API | HTTP Request | YES |
| Sleep/pause N seconds | Wait (After Time Interval) | YES |
| Pause until event | Wait (On Webhook Call) | YES |
| Repeat N times | Loop Over Items / Split in Batches | YES |
| Conditional branch | IF node | YES |
| Merge parallel paths | Merge node | YES |
| Run JavaScript | Code node | YES |
| Set variables | Set node | YES |
| MQTT publish | MQTT node | YES |
| MQTT subscribe trigger | MQTT Trigger | YES |

### Example DittoSim Scenario as n8n Workflow

The following maps a typical DittoSim scenario to n8n nodes:

```
[Manual Trigger]
      ↓
[Set Node] ← Define simulation parameters:
  - simId = "sim_test_001"
  - botPeerKey = "pk_abc123"
  - orderCount = 10
      ↓
[Code Node] ← Generate array of N order objects
  // JavaScript:
  const orders = [];
  for (let i = 0; i < $json.orderCount; i++) {
    orders.push({
      _id: `order_sim_${i.toString().padStart(3, '0')}`,
      status: 'pending',
      customerId: `cust_${i}`,
      total: (Math.random() * 50 + 5).toFixed(2),
      createdAt: new Date().toISOString()
    });
  }
  return orders.map(o => ({ json: o }));
      ↓
[Loop Over Items] ← Batch size: 1 (process one order at a time)
  ↓ (Loop body):
  │
  ├── [Wait Node] ← Sleep 30-90 seconds (simulate customer ordering)
  │      Mode: After Time Interval
  │      Amount: {{ Math.floor(Math.random() * 60) + 30 }} seconds
  │
  ├── [HTTP Request] ← INSERT order into Ditto
  │      POST https://app.cloud.ditto.live/api/v4/store/execute
  │      Auth: Bearer <api-key>
  │      Body: {
  │        "statement": "INSERT INTO orders DOCUMENTS (:order) ON ID CONFLICT DO UPDATE",
  │        "args": { "order": {{ $json }} }
  │      }
  │
  ├── [HTTP Request] ← Poll Ditto until order status = 'ready'
  │    (POLLING LOOP — see below)
  │
  └── [Code Node] ← Log result to console / n8n execution log
  ↓ (Done)
[HTTP Request] ← Mark simulation completed in Ditto
```

### Implementing "Wait Until Condition Met" (Polling Pattern)

n8n does not have a native "wait until a Ditto document changes" node. You simulate it with a polling loop:

```
[IF Node] ← Check: is order status = 'ready'?
   YES → continue workflow
   NO  → [Wait Node (10 seconds)] → [HTTP Request: re-query Ditto] → loop back to IF
```

**Practical polling loop:**

```
[HTTP Request] ← Query Ditto for order status
  POST .../api/v4/store/execute
  Body: { "statement": "SELECT status FROM orders WHERE _id = :id", "args": { "id": "order_sim_001" } }
      ↓
[Code Node] ← Extract status from response
  const status = $json.items?.[0]?.status;
  return [{ json: { status, found: !!status } }];
      ↓
[IF Node] ← status == 'ready'?
   TRUE → [Continue workflow]
   FALSE → [Wait 10 seconds] → [Loop back to HTTP Request]
```

**Caveat:** This polling approach means n8n is repeatedly hitting Ditto's HTTP API. For a simulation tool running for minutes at a time with a handful of bots, this is perfectly fine. For production scale with hundreds of bots and millisecond latency requirements, polling introduces delay and API load.

### Reactive/Event-Driven Step Simulation

n8n can approximate reactive scenarios using the **Wait node with On Webhook Call**:

1. n8n inserts an order document into Ditto
2. n8n pauses at a Wait node, generating a unique resume URL (`$execution.resumeUrl`)
3. n8n stores that resume URL in a Ditto document (or sends it via MQTT to the relevant bot)
4. When the bot finishes its work, it calls the resume URL via HTTP
5. n8n workflow resumes and continues to the next step

This is the same pattern n8n uses for Human-in-the-Loop (HITL) workflows — "wait for an external event, then resume." The bot becomes the "human" in this model.

**Resume URL example:**

When a workflow hits a Wait node in "On Webhook Call" mode, n8n creates a URL like:
```
https://your-n8n:5678/webhook-waiting/<unique-execution-id>
```

This URL can be embedded in the Ditto document the bot reads:
```json
{
  "_id": "instruction_001",
  "step": "process_order",
  "orderId": "order_sim_001",
  "callbackUrl": "http://192.168.1.100:5678/webhook-waiting/abc123xyz"
}
```

The bot, after completing its step, fires:
```kotlin
// Kotlin (Android)
val client = OkHttpClient()
val request = Request.Builder()
    .url(callbackUrl)
    .post("""{"result": "success", "durationMs": 450}""".toRequestBody())
    .build()
client.newCall(request).execute()
```

This is genuinely reactive — the bot drives the timing of each step, not a timer.

### Workflow Version Control (JSON)

Every n8n workflow can be exported as a JSON file:

1. In n8n editor: ⋮ menu → Download
2. Via n8n CLI: `n8n export:workflows --all --output=./workflows/`
3. Via API: `GET /api/v1/workflows` (returns all workflows as JSON)

Import workflows:
1. In n8n editor: drag-drop JSON file onto canvas
2. Via CLI: `n8n import:workflow --input=./workflows/dittosim-order-flow.json`
3. Docker entrypoint script can auto-import on startup

**Git workflow for DittoSim scenarios:**
```
/dittosim-workflows/
  order-flow.json       ← n8n workflow export
  kds-reaction.json     ← another scenario
  stress-test.json      ← high-load scenario
  README.md             ← documents what each workflow does
```

Team members clone the repo, import the JSON files into their local n8n instance, and share scenarios as code.

---

## Section 6: Build vs. Integrate Assessment

### What n8n Handles That DittoSim Currently Builds From Scratch

| Capability | DittoSim Custom Build | n8n Handles |
|-----------|----------------------|-------------|
| Scenario step sequencing | Custom state machine in KMP bot | n8n workflow nodes |
| Sleep/delay between steps | `delay(ms)` coroutine in KMP | Wait node |
| Conditional branching | Custom if/else logic | IF node |
| Looping (repeat N times) | Kotlin for-loop + coroutine | Loop Over Items node |
| Calling Ditto HTTP API | (not in current design) | HTTP Request node |
| Scenario sharing/versioning | Proprietary JSON format | Standard n8n JSON export |
| Workflow visualization | Custom SwiftUI UI (not built yet) | n8n canvas (already built) |
| Execution history/logs | `__des_sim_bot_logs` Ditto collection | n8n execution log |

### What the Bot App Still Needs Even With n8n

Even if n8n orchestrates the scenario logic, the bot app cannot be eliminated:

1. **Ditto SDK integration** — The bot must initialize Ditto, set up sync, and execute DQL locally. n8n calls the Big Peer HTTP API; it cannot execute queries against the on-device Ditto database.
2. **P2P mesh participation** — The bot must be a Ditto peer for P2P sync to work (BLE, P2P WiFi). This requires the native Ditto SDK. n8n cannot join a Ditto mesh.
3. **Reactive observers** — If a bot needs to react to documents synced from other bots (not from the cloud), it must register a Ditto observer. n8n has no way to receive data directly from the P2P mesh.
4. **Offline resilience** — When the bot loses internet/network, Ditto continues syncing over BLE/P2P WiFi. n8n cannot operate in this mode — it requires network access to its own server.
5. **Heartbeat and status updates** — The bot must still write to `__des_sim_bots` to report progress.
6. **Platform-native behavior** — UI display (updateScreen step type), device sensors, OS-level networking are beyond n8n's reach.

### What Is Harder or Lost With n8n

1. **P2P-native reactive scenarios** — The most powerful DittoSim scenario type is a bot reacting to documents that arrived via Bluetooth from another bot with zero cloud involvement. n8n lives entirely in the cloud/LAN; it cannot trigger off P2P mesh events. The current custom architecture handles this natively.

2. **Offline simulation execution** — The current design allows a simulation to run entirely without internet: all scenario data is pre-loaded into Ditto documents, bots execute from local DB, and everything syncs back when connectivity resumes. n8n requires network connectivity to operate.

3. **Step-level parallelism across bots** — The current design allows 12 bots to simultaneously execute different scenarios against a shared Ditto database and observe each other's changes. n8n can coordinate this via HTTP calls but cannot observe the resulting mesh interactions.

4. **Latency measurement** — A key DittoSim feature is measuring sync latency: when Bot A writes a document, when does Bot B (observing that collection) receive it? This measurement happens inside the bot's Ditto observer callback. n8n has no way to observe this; it only sees HTTP API responses.

### Fundamental Architectural Tension

The DittoSim system's core value proposition is **demonstrating and measuring Ditto's P2P sync behavior**. The scenarios are designed to:
- Write documents in one place
- Measure how fast they appear on other devices
- Test different transport paths (BLE vs WiFi vs Cloud)
- Run without internet in P2P-only mode

n8n is inherently a **centralized, internet-dependent workflow engine**. These two philosophies conflict at the edges:

| Requirement | Custom DittoSim | n8n Approach |
|------------|----------------|-------------|
| Offline simulation | Native (Ditto offline-first) | Impossible (n8n requires server) |
| P2P mesh reactive | Native (Ditto observers) | Not possible without cloud relay |
| Cross-bot sync measurement | Native (observer timestamps) | Would require custom instrumentation |
| Scenario visualization | Need to build | n8n canvas provides it free |
| Scenario authoring | Need to build wizard | n8n provides visual builder |
| Execution history | Stored in Ditto | n8n execution log |

### Recommended Hybrid Architecture

The strongest outcome is a **hybrid model**:

```
n8n (Mac, Docker)                    Ditto Big Peer (Cloud)
     │                                       │
     │── Scenario 1: Insert orders ─────────►│
     │── Scenario 2: Update statuses ────────►│
     │                                       │
     │                           ┌───────────┴────────────────┐
     │                           │      P2P Mesh              │
     │                           │  Bot A ←──BLE──→ Bot B     │
     │                           │  Bot B ←──WiFi─→ Bot C     │
     │                           └───────────────────────────-┘
     │                                       │
     │◄── n8n polls status (HTTP) ───────────│
```

**Use n8n for:**
- Cloud-driven scenarios (simulate backend systems inserting data into Ditto)
- Scenario authoring and sharing (export as JSON, version control in Git)
- Simple sequential step workflows that only touch the Ditto HTTP API
- Integration testing of app behavior when cloud data arrives

**Keep custom bot orchestration for:**
- P2P reactive scenarios (Bot A reacts to what Bot B wrote over BLE)
- Offline simulation runs
- Cross-device sync latency measurement
- Scenario types that require native DQL execution on-device

---

## Section 7: Practical Recommendations

### Recommendation 1: Start With n8n for Cloud Scenario Authoring

Before committing to the full custom orchestrator architecture, validate the concept by building 2-3 DittoSim scenarios as n8n workflows using Option C (HTTP Request → Ditto API). This will:
- Prove out the Ditto HTTP API integration in hours, not weeks
- Produce shareable scenario JSON files that non-developers can understand
- Create a visual diagram of the scenario flow for documentation

### Recommendation 2: Use n8n as a Parallel Tool, Not a Replacement

The DittoSim scenarios that truly demonstrate Ditto's value (P2P sync, offline resilience, cross-transport latency measurement) require the native bot app with the Ditto SDK. n8n cannot replace these scenarios. Build the KMP bot app as planned.

However, n8n can replace the orchestrator's scenario wizard for **cloud-triggered scenarios** — removing the need to build a custom JSON format parser and execution engine for cloud-side scenario steps.

### Recommendation 3: If You Do Use n8n, Write a Ditto Custom Node

The 3-4 hours to write a `Ditto DQL` custom node pays off quickly:
- Cleaner workflow design (no raw HTTP Request node setup each time)
- Credential management in n8n (API key stored securely, not in workflow JSON)
- Reusable across all DittoSim workflows
- Easy to publish as an npm package for community use

### Recommendation 4: Version-Control Workflows as JSON

n8n workflow JSON files should be stored in this repository under:
```
/plans/dittosim/n8n-workflows/
  order-flow-scenario.json
  kds-reactive-scenario.json
  stress-test.json
```

This makes scenarios reproducible and shareable — a developer clones the repo, runs `setup-n8n-dittosim.sh`, imports the workflows, and has a running simulation environment in under 10 minutes.

---

## Section 8: Quick-Reference Summary

### Can n8n replace the custom orchestrator?
**Partially.** For cloud-driven scenario steps only. Not for P2P mesh scenarios, offline runs, or latency measurement.

### What's free in n8n community?
Everything needed for DittoSim: webhooks, HTTP Request, Code node, Wait/Sleep, Loop, MQTT, unlimited executions.

### How long to set up on a Mac?
Under 5 minutes if Docker Desktop is installed. Two commands: `docker volume create n8n_data` + `docker run ...`.

### Best integration option?
**Option C** (n8n → Ditto HTTP API → P2P sync to bot). Bot app doesn't need to know n8n exists.

### Does a Ditto n8n node exist?
No. Would need to be written (3-4 hours of TypeScript work).

### Is the license OK for this use?
Yes. Running n8n internally as a developer tool is explicitly allowed under the Sustainable Use License at no cost.

### Apple Silicon compatible?
Yes. Multi-arch Docker image runs natively on M1/M2/M3/M4.

---

## Sources

- [n8n Community Edition Features](https://docs.n8n.io/hosting/community-edition-features/)
- [n8n Sustainable Use License](https://docs.n8n.io/sustainable-use-license/)
- [n8n Pricing Plans](https://n8n.io/pricing/)
- [n8n Docker Installation](https://docs.n8n.io/hosting/installation/docker/)
- [n8n Docker Compose](https://docs.n8n.io/hosting/installation/server-setups/docker-compose/)
- [n8n HTTP Request Node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.httprequest/)
- [n8n Webhook Node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.webhook/)
- [n8n Wait Node](https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-base.wait/)
- [n8n Looping](https://docs.n8n.io/flow-logic/looping/)
- [n8n Waiting](https://docs.n8n.io/flow-logic/waiting/)
- [n8n MQTT Trigger](https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.mqtttrigger/)
- [n8n MQTT Node](https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.mqtt/)
- [n8n Custom Node Overview](https://docs.n8n.io/integrations/creating-nodes/overview/)
- [n8n Nodes Starter Repository](https://github.com/n8n-io/n8n-nodes-starter)
- [n8n Export/Import Workflows](https://docs.n8n.io/workflows/export-import/)
- [n8n Concurrency Control](https://docs.n8n.io/hosting/scaling/concurrency-control/)
- [n8n New Pricing (No Active Workflow Limits)](https://blog.n8n.io/build-without-limits-everything-you-need-to-know-about-n8ns-new-pricing/)
- [Ditto HTTP API DQL Queries](https://docs.ditto.live/cloud/http-api/dql-queries)
- [Ditto Auth and Parameters](https://docs.ditto.live/cloud/http-api/auth-and-params)
- [Ditto Execute DQL Endpoint](https://docs.ditto.live/cloud/http-api/api/post-storeexecute)
- [Ditto Mesh Networking](https://docs.ditto.live/key-concepts/mesh-networking)
- [GCDWebServer (iOS HTTP Server)](https://github.com/swisspol/GCDWebServer)
- [Swifter (iOS HTTP Server)](https://github.com/httpswift/swifter)
- [NanoHTTPD (Android HTTP Server)](https://github.com/NanoHttpd/nanohttpd)
- [CocoaMQTT iOS Library](https://github.com/emqx/CocoaMQTT)
- [Eclipse Mosquitto Docker](https://hub.docker.com/_/eclipse-mosquitto)
- [n8n Hub Docker Image](https://hub.docker.com/r/n8nio/n8n)
- [n8n Human-in-the-Loop Patterns](https://blog.nocodecreative.io/n8n-v2-wait-node-hitl-sub-workflows/)
