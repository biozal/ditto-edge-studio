# Ditto Edge Studio - User Guide

Welcome to **Ditto Edge Studio**, a macOS and iPadOS tool for querying, monitoring, and debugging Ditto databases.

---

## Getting Started

### Adding a Database

1. Tap **+ Database Config** on the main screen.
2. Choose your authentication mode:
   - **Online Playground** — cloud-connected with a token
   - **Shared Key** — local peers using a shared secret
   - **Small Peers Only** — no cloud, fully local mesh
3. Fill in your credentials and tap **Save**.

### Opening a Database

Tap any database card to open the Studio. On first launch you may be prompted for Bluetooth and local network permissions — grant these for full sync functionality.

---

## Getting Help Per Screen

Every screen in Edge Studio has **contextual documentation** built in.

Open the **Inspector** (the panel on the right side of the screen) and tap the **?** tab to see help specific to the screen you are on. This guide gives you a feature overview; the Inspector help covers the details.

> On macOS: click the Inspector toggle button in the toolbar (top-right) to show or hide the panel.
> On iPadOS: the Inspector slides in from the right edge.

---

## Features

### Subscriptions & Sync

Subscriptions tell Ditto which collections to sync from other peers.

- Tap **+** in the sidebar to add a subscription with a DQL `SELECT` query.
- The **Peers List** tab shows connected devices and their active transports (WiFi, Bluetooth, WebSocket, etc.).
- The **Presence Viewer** tab shows a live graph of the peer mesh.
- The **cog icon** (top-right of the detail area) lets you toggle individual transports (Bluetooth, P2P WiFi, LAN) in real time — useful for simulating connectivity constraints without changing your app code.
- Open the Inspector **?** tab for subscription syntax and sync strategy guidance.

### Collections & Query

Write and run **DQL (Ditto Query Language)** queries against your Ditto database.

- **Collections** appear in the sidebar once documents exist (via INSERT or sync from a peer).
- **SELECT**, **INSERT**, **UPDATE**, **EVICT**, and index management are all supported.
- Results display in **Raw** (JSON), **Table**, or **Profile** mode (see below) with pagination.
- Queries are automatically saved to **History**; you can star any query to add it to **Favorites**.
- Open the Inspector **?** tab for a full DQL reference including syntax examples and index management.

#### Local vs HTTP execution

Queries run against the **local embedded database** by default. If you have configured an **HTTP API URL** and **HTTP API Key** on the database (edit the database card → *Ditto Server – HTTP API* section), a second option — **HTTP** — appears in the execute-mode picker next to the Run button. Selecting HTTP routes the query through the Ditto HTTP API instead of the local store, which is useful for querying the BigPeer directly or comparing results between the cloud and your local replica.

#### Execution Profile

The third tab next to **Raw** and **Table** captures an **execution-plan profile** for the last query you ran. Profiles let you see how Ditto's query engine planned and executed your statement — which operators ran, how many documents they processed, and where the time went.

**When it captures.** A profile is captured automatically when **all three** conditions hold:
1. **Collect Metrics** is enabled in Settings (this is the same toggle that drives App Metrics and Query Metrics — see Settings below).
2. The statement is a **`SELECT`** — Ditto's `PROFILE` keyword only supports SELECT today. `INSERT`, `UPDATE`, `DELETE`, and `EVICT` won't capture a profile.
3. You ran the query through the **Local** execute mode (not HTTP).

If any condition fails, the Profile tab explains what's missing and (for the Collect Metrics case) gives you a one-tap **Open Settings…** button.

**Card view** — the default. Renders each operator in the plan as a card with:
- The operator name (`scan`, `sequence`, `limit`, `finalProjection`, …) and a row of coloured badges summarising `in` / `out` document counts and per-phase timings.
- The operator's attributes below — `collection`, `alias`, `datasource`, `limit`, etc. Selectable so you can copy values.
- Child operators nested inside the parent card so the tree structure stays visible.

**Plan view** — the high-level shape. Renders each operator as a box, connected top-down by T-junction lines: root at the top, children below. Box contents are condensed (operator name + key attribute + total time + in/out counts). An operator's box turns **orange** when its execution time exceeds 50% of the total elapsed time — that's your bottleneck. Long-running operators also get a **percent-of-total badge** (e.g. `19.1%`) next to their time when they're ≥ 5% of the request.

**Reading the badges:** `in` (documents flowing in), `out` (documents flowing out), `exec` (CPU time inside the operator), `recv` (time waiting on upstream operators to feed input), `send` (time pushing output downstream). All times are auto-scaled to the most readable unit — milliseconds for ≥ 1 ms, microseconds for sub-ms, nanoseconds for sub-µs.

For the full Ditto reference, see [docs.ditto.live/dql/profile](https://docs.ditto.live/dql/profile).

#### Attachments

Ditto documents can reference **binary attachments** — files (images, PDFs, audio, etc.) that live alongside the document and sync between peers on demand. Edge Studio lets you add, view, and remove attachments directly from the query results pane.

**Adding an attachment.** Right-click any document row in the **Raw** or **Table** viewer and choose **Add Attachment…**. Pick a file in the system file picker, then enter the field name to store the attachment under (e.g. `photo`, `invoice_pdf`). Edge Studio uploads the file, writes the resulting attachment token onto the document, and refreshes the row. A progress overlay shows upload status — large files may take a few seconds.

**Viewing attachments.** Select any row that has attachment fields. The **Attachment Viewer** section appears in the Document Viewer (Inspector → JSON Viewer) listing every detected attachment field with its size and download state. Click **Open** on any field to fetch the attachment locally and open it with the system default app for that file type.

**Deleting an attachment.** Right-click the document row and choose **Delete Attachment…**. A sheet lists every detected attachment field on that document with a toggle next to each one. Select the field(s) to remove and tap **Delete**. Edge Studio runs `UPDATE <collection> SET <field> = null WHERE _id = '<docId>'` for each selected field. The attachment binary is left on disk and will be reclaimed by Ditto's normal eviction cycle.

> **Note:** Edge Studio detects attachment fields by inspecting the field value's shape — an attachment token has a recognisable structure. If you store attachments under a non-standard field name, they're still detected as long as the value is a real Ditto attachment token.

### Observers

Observers register a live DQL query against the local store and fire an event whenever matching documents change — whether from a local write or an incoming sync.

- Tap **+** in the sidebar to add an observer with a name and a DQL `SELECT` query.
- Tap the **play** button on an observer row to activate it.
- Events appear in real time showing timestamp and a diff summary (inserts / updates / deletes).
- Select an event to see the full document snapshot and diff in the detail panel.
- Open the Inspector **?** tab for tips on effective observer usage.

### App Metrics

Displays live resource usage for the Edge Studio process and disk usage for the selected Ditto database.

- **Metrics must be enabled** in Settings before App Metrics or Query Metrics appear in the sidebar.
- Process metrics (memory, CPU, uptime) auto-refresh every 15 seconds.
- The **Storage** section breaks down disk usage by category (Store, Replication, Attachments, Auth, WAL, Logging, Other) and by individual collection.
- Open the Inspector **?** tab for a full explanation of each metric and storage category.

### Query Metrics

Records per-query `EXPLAIN` analysis for every DQL query you run — helping you understand index usage and query planner behaviour.

- Queries are colour-coded by execution time (green / orange / red).
- An index-usage badge shows whether each query used an index or performed a full collection scan.
- Select any record to see the full DQL statement and `EXPLAIN` output.
- Prometheus export is configured from the Inspector **Export** tab.
- Open the Inspector **?** tab for full documentation.

---

## Settings

Open **Edge Studio → Settings…** (⌘,) to configure application-wide behaviour.

### Collect Metrics

Toggles performance data collection. When enabled, **App Metrics** and **Query Metrics** appear in the sidebar. When disabled, those items are hidden and no data is collected. Enabled by default.

### Enable MCP Server

Starts the built-in Model Context Protocol server on port **65269**, letting AI agents (Claude Code, Cursor, etc.) query your active Ditto database. Disabled by default. A green status dot in Settings confirms the server is running.

See **MCP Integration** below for connection instructions.

---

## MCP Integration (AI Agents)

Edge Studio includes a built-in **MCP (Model Context Protocol) server** that lets Claude Code and other AI agents query and manage your Ditto databases directly — no separate binary or CLI setup required.

### Enabling

1. Open **Edge Studio → Settings…** (⌘,)
2. Toggle **Enable MCP Server** ON
3. A green dot confirms it is running on **port 65269**

### Connecting Claude Code

**Option A — This repository (auto-discovered)**

The `.mcp.json` at the root of this repo is picked up automatically by Claude Code. No extra steps needed.

**Option B — Global (available in all projects)**

Run once in your terminal:

```bash
claude mcp add ditto-edge-studio --transport sse http://localhost:65269/mcp
```

Verify: `claude mcp list` — you should see `ditto-edge-studio (sse) http://localhost:65269/mcp`.

### What You Can Ask Claude

With the server running and a database selected:

- *"List the collections in my active database and their document counts"*
- *"Run SELECT * FROM orders WHERE status = 'pending' LIMIT 5"*
- *"Create an index on the users collection for the email field"*
- *"Show me the sync status and which transports are active"*
- *"Disable Bluetooth sync and show me the peer count"*
- *"Show me all connected peers and their SDK versions"*
- *"Stop sync, insert all documents from ~/Downloads/orders.json into the orders collection, then restart sync"*

### Available Tools

| Tool | Description |
|------|-------------|
| `execute_dql` | Run any DQL query (SELECT, INSERT, UPDATE, EVICT) — see below for local vs HTTP |
| `list_databases` | List all configured databases |
| `get_active_database` | Details on the currently selected database |
| `list_collections` | Collections with document counts and indexes |
| `list_indexes` | Flat list of every index across all collections, with name, collection, and field paths |
| `create_index` | Index a collection field |
| `drop_index` | Remove an index by name |
| `get_query_metrics` | Recent query timing and EXPLAIN output (requires Metrics enabled in Settings) |
| `get_sync_status` | Connected peer count and transport config |
| `configure_transport` | Toggle Bluetooth, LAN, AWDL, or Cloud Sync |
| `insert_documents_from_file` | Insert a local JSON file into a collection |
| `set_sync` | Start or stop sync for the active database |
| `get_peers` | Snapshot of all connected peers with device, OS, and transport details |

> All tools operate on the database **currently selected** in the Edge Studio UI. The server stops automatically when Edge Studio quits.

#### execute_dql: local vs HTTP transport

By default `execute_dql` runs queries against the **local embedded database** inside Edge Studio. Pass `transport: "http"` to route the query through the **Ditto HTTP API** instead:

```json
{ "query": "SELECT * FROM orders LIMIT 5", "transport": "http" }
```

HTTP transport requires **HTTP API URL** and **HTTP API Key** to be set on the active database's configuration (edit the database card → *Ditto Server – HTTP API* section). If either field is missing the tool returns an `http_not_configured` error with a hint. HTTP transport is useful for querying the BigPeer directly or comparing cloud vs local data without leaving Claude.

#### insert_documents_from_file

Inserts documents from a local JSON file directly into a collection without you having to paste data into the query editor:

```json
{ "file_path": "/Users/you/Downloads/orders.json", "collection": "orders", "mode": "insert" }
```

- The file must be a **JSON array of objects**; every object must have an `_id` field.
- The file must be in **~/Downloads** (macOS sandbox restriction).
- `mode` defaults to `"insert"` (upsert — overwrites a document if its `_id` already exists). Use `"insert_initial"` to skip documents whose `_id` already exists instead.
- Returns a summary of how many documents were inserted and how many failed, plus any per-document error messages.

#### set_sync

Starts or stops sync for the active database:

```json
{ "enabled": false }
```

Useful for pausing sync before a bulk `insert_documents_from_file` operation so incoming peer changes don't interfere, then re-enabling with `{ "enabled": true }` afterwards.

#### get_peers

Returns a one-time snapshot of all currently connected remote peers with their device name, OS, SDK version, connection types, distances, and metadata. Returns an empty array if no peers are connected.

#### list_indexes

Returns a flat JSON array of every index across all collections in the active database. Each entry contains:

- `name` — display name (e.g. `idx_tasks_priority`)
- `fullName` — full SDK-level name including collection prefix
- `collection` — the collection the index belongs to
- `fields` — list of indexed field paths

Useful for auditing index coverage across the entire database in one call, without iterating collection by collection.

For full setup, troubleshooting, and security considerations see [`docs/MCP_SERVER.md`](docs/MCP_SERVER.md).

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| **⌘?** | Open Ditto Documentation (online) |
| **⌘H** | This User Guide |
| **⌘⇧D** | Font Debug Window |

---

## Troubleshooting

### Connection Issues

- Verify your App ID (36 characters) and auth token are correct.
- Ensure the device has outbound network access.
- Check that Bluetooth and local network permissions are granted (macOS: System Settings → Privacy & Security).

### Sync Not Working

- Confirm sync is enabled (toggle button in the Studio toolbar).
- Check the Peers List tab — if no peers appear, transports may be disabled or blocked.
- Use the cog icon to verify individual transport settings.

### No Collections Visible

Collections only appear after at least one document has been inserted locally or synced from a peer. Add a subscription first so data can arrive, then run a `SELECT *` query to confirm documents exist.

---

*For full API and SDK documentation, visit [docs.ditto.live](https://docs.ditto.live)*
