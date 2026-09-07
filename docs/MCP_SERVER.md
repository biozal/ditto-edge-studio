# Edge Studio MCP Server

Edge Studio embeds an MCP (Model Context Protocol) server that lets AI agents
such as Codex and Claude Code query and manage the active Ditto database
directly. When the app quits, the server stops.

---

## Overview

- **Transport:** HTTP/SSE on `localhost:65269` (configurable)
- **Platform:** macOS only
- **Opt-in:** Disabled by default — enable in Settings
- **Security:** Localhost only, no authentication by default
- **No external dependencies:** Uses macOS Network.framework, no separate process

---

## Enabling the MCP Server

1. Open Edge Studio
2. Go to **Edge Studio → Settings…** (⌘,)
3. Toggle **Enable MCP Server** on
4. A green status dot confirms the server is running on port 65269

To disable, toggle it off. The server also stops automatically when the app quits.

---

## Configuring Codex

A project-scoped `.codex/config.toml` is included in this repository:

```toml
[mcp_servers.ditto-edge-studio]
url = "http://localhost:65269/mcp"
enabled = true
default_tools_approval_mode = "writes"
```

Trust the project and restart Codex after enabling the Edge Studio server.
Verify the connection with `/mcp` in the Codex TUI or `codex mcp list`.

To use the server in every project, add the same table to
`~/.codex/config.toml` instead.

## Configuring Claude Code

### Option A: Repo-scoped (auto-discovered)

A `.mcp.json` file already exists at the root of this repository. Claude Code picks it up automatically when you open this project:

```json
{
  "mcpServers": {
    "ditto-edge-studio": {
      "type": "sse",
      "url": "http://localhost:65269/mcp"
    }
  }
}
```

### Option B: Global config

To make the server available in all projects:

```bash
claude mcp add ditto-edge-studio --transport sse http://localhost:65269/mcp
```

### Verify the connection

```bash
claude mcp list
# Should show: ditto-edge-studio (sse) http://localhost:65269/mcp

# Test directly
curl -X POST http://localhost:65269/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

---

## Available Tools

| Tool | Description |
|------|-------------|
| `execute_dql` | Execute a DQL query against the active database (local or HTTP) |
| `list_databases` | List all configured databases (name, ID, mode) |
| `get_active_database` | Get details about the currently selected database |
| `list_collections` | List collections with document counts and indexes |
| `create_index` | Create an index on a collection field |
| `drop_index` | Drop an index by name |
| `get_query_metrics` | Get recent query execution metrics and EXPLAIN output |
| `get_sync_status` | Get peer count and transport configuration |
| `configure_transport` | Enable/disable Bluetooth, LAN, or AWDL transports |
| `insert_documents_from_file` | Insert documents from a local JSON file |
| `set_sync` | Start or stop sync for the active database |
| `get_peers` | Get a one-time snapshot of all connected peers with full details |
| `list_indexes` | List all indexes across every collection |
| `get_app_logs` | Read recent Edge Studio application log entries |
| `get_ditto_logs` | Read Ditto SDK log entries from the active database's log files |

### Tool Details

#### `execute_dql`
```
Arguments:
  query     (required) DQL statement to execute
  transport (optional) "local" (default) or "http"

Returns:
  "local":  JSON array of result documents, or mutation IDs for writes
  "http":   Same format, routed through the HTTP API endpoint

Notes:
  - "local" executes against the embedded Ditto database — no network required
  - "http" requires httpApiUrl and httpApiKey to be configured on the database;
    returns a structured error if they are missing (see HTTP Transport section below)
  - Both paths support SELECT, INSERT, UPDATE, EVICT, and all DQL statements
```

#### `list_databases`
```
Arguments: (none)
Returns: Array of { id, name, databaseId, mode }
Note: Never returns credentials (token, httpApiKey, secretKey)
```

#### `get_active_database`
```
Arguments: (none)
Returns: {
    name, databaseId, mode,
    url, httpApiUrl,
    httpApiConfigured,   // true when both httpApiUrl and httpApiKey are set
    allowUntrustedCerts, // TLS setting
    logLevel,
    transport: { bluetoothLE, lan, awdl, cloudSync }
  }
Note: Credentials are never included — token, httpApiKey, and secretKey are
      stripped; httpApiConfigured is a boolean, not the key itself.
      Returns error if no database is selected in Edge Studio
```

#### `list_collections`
```
Arguments: (none)
Returns: Array of { name, documentCount, indexes: [{ name, fullName, collection, fields }] }
```

#### `create_index`
```
Arguments: { "collection": "myCollection", "field": "fieldName" }
Returns: Success message with index name
Example field paths: "name", "address.city", "tags[*]"
```

#### `drop_index`
```
Arguments: { "index_name": "idx_myCollection_name", "collection": "myCollection"? }
Returns: Success or error message
Note: The owning collection is resolved automatically from the database's index
      metadata. Pass "collection" only to disambiguate when several collections
      have an index with the same name.
```

#### `get_query_metrics`
```
Arguments: (none)
Returns: Array of recent queries with timing, result counts, and EXPLAIN output
Note: Requires Metrics to be enabled in Settings
```

#### `get_sync_status`
```
Arguments: (none)
Returns: { database, connectedPeers, meshPeers, transport: { bluetoothLE, lan, awdl, cloudSync } }

  connectedPeers is the number of peers with a link to THIS device.
  meshPeers is every peer visible anywhere in the mesh, including ones reachable
  only through another peer. The two differ in any multi-hop mesh; see
  docs/PRESENCE_GRAPH.md.
```

#### `configure_transport`
```
Arguments: { "bluetooth": bool?, "lan": bool?, "awdl": bool? }
Returns: Applied configuration summary
Note: Omitted parameters are unchanged. Stops and restarts sync automatically.
      There is no "cloud" parameter — this tool only toggles the three
      peer-to-peer transports.
```

#### `insert_documents_from_file`
```
Arguments:
  file_path  (required) Absolute path to a JSON file (must be in ~/Downloads)
  collection (required) Target collection name
  mode       (optional) "insert" (default, upserts) or "insert_initial" (skips existing)

Returns: { inserted, failed, mode, collection, errors }
Note: File must contain a JSON array; each object must have an _id field.
```

#### `set_sync`
```
Arguments: { "enabled": bool }
Returns: { sync: "started"|"stopped", enabled: bool }

Examples:
  { "enabled": false }  →  { "sync": "stopped", "enabled": false }
  { "enabled": true  }  →  { "sync": "started", "enabled": true  }

Note: Mirrors the sync toggle button in the Edge Studio toolbar. Use to pause
sync before bulk operations and resume it after. Does not affect transport
configuration — use configure_transport to change which transports are active.
```

#### `get_peers`
```
Arguments: (none)
Returns:
  {
    "count": 2,
    "peers": [
      {
        "peerKey":            "abc123...",
        "deviceName":         "iPhone 15 Pro",
        "osType":             "iOS",
        "sdkVersion":         "4.9.1",
        "connectionStatus":   "Connected",          // "Indirect" for multi-hop peers
        "isDirectlyConnected": true,
        "addressInfo":        "192.168.1.42",
        "connections": [
          { "type": "Bluetooth LE" },
          { "type": "P2P WiFi" }
        ],
        "identityMetadata":   "{ ... }",
        "peerMetadata":       "{ ... }",
        "syncedUpToCommitId": "commit-xyz"
      }
    ]
  }

Notes:
  - Returns { "peers": [], "count": 0 } if no peers are currently connected
  - This is a one-time read from the presence graph; it does not register an
    observer and will not reflect subsequent connection changes
  - Peers are NOT filtered to direct connections — the full mesh is returned, with
    isDirectlyConnected marking which peers this device actually has a link to.
    connections[] lists only the transports that touch THIS device.
  - syncedUpToCommitId may be empty if sync info is unavailable
  - identityMetadata and peerMetadata are JSON strings (empty string if absent)
```

#### `list_indexes`
```
Arguments: (none)
Returns: Flat array of { name, fullName, collection, fields } for every index
         across all collections in the active database
```

#### `get_app_logs`
```
Arguments: { "lines": int?, "filter": string? }
Returns: The most recent Edge Studio application log entries (plain text,
         newest last). "lines" defaults to 200; "filter" is a case-insensitive
         substring match (e.g. "[Peers]", "error").
Note: Reads the app's own log files written by Log.info/warning/error/debug.
```

#### `get_ditto_logs`
```
Arguments: { "lines": int?, "filter": string?, "level": string? }
Returns: JSON array of { timestamp, level, component, message } parsed from
         the active database's Ditto SDK log files (.log and .log.gz).
         "level" is a minimum severity: error|warning|info|debug|verbose.
Note: Requires an active database. Reads the SDK logs from
      <persistenceDirectory>/ditto_logs/ (falling back to logs/ for older SDK
      layouts). Returns an explanatory message, not an empty array, when the
      database has no log directory yet.
```

---

## Query Transport Options

`execute_dql` supports two execution paths selectable via the `transport` parameter.

### Local (default)

Queries run directly against the embedded Ditto database process on this machine. No network connectivity required. This is the path used by the Edge Studio query editor and is tested and stable.

```
{ "query": "SELECT * FROM orders LIMIT 5" }
{ "query": "SELECT * FROM orders LIMIT 5", "transport": "local" }
```

### HTTP

Queries are sent to the Ditto HTTP API endpoint configured on the active database. This targets the cloud/server-side database rather than the local replica.

```
{ "query": "SELECT * FROM orders LIMIT 5", "transport": "http" }
```

**Requirements:** The active database must have both `httpApiUrl` and `httpApiKey` configured. If either is missing, the tool returns a structured error instead of throwing:

```json
{
  "error": "http_not_configured",
  "message": "You asked to run this via HTTP, but this database hasn't been introduced to the cloud yet. Add httpApiUrl and httpApiKey to this database's configuration — then it'll know where to show up.",
  "hint": "Open database configuration → set httpApiUrl and httpApiKey"
}
```

---

## Example Workflows

### Explore a database
```
"List the collections in my active database and show me the 5 largest ones"
→ Claude calls list_collections, sorts by documentCount
```

### Debug a query
```
"Run this query and show me the EXPLAIN output: SELECT * FROM orders WHERE status = 'pending'"
→ Claude calls execute_dql, then get_query_metrics for EXPLAIN output
```

### Manage indexes
```
"Create an index on the 'orders' collection for the 'status' field"
→ Claude calls create_index with collection="orders", field="status"
```

### Test sync scenarios
```
"Disable Bluetooth and LAN transports, then show me the current sync status"
→ Claude calls configure_transport then get_sync_status
```

### Explore schema
```
"Show me the structure of the first 3 documents in each collection"
→ Claude calls list_collections, then execute_dql for each collection
```

### Pause sync for a bulk import
```
"Stop sync, insert all documents from ~/Downloads/seed.json into the orders collection, then restart sync"
→ Claude calls set_sync(enabled=false), insert_documents_from_file, set_sync(enabled=true)
```

### Compare local vs cloud data
```
"Run SELECT * FROM orders WHERE status = 'pending' against both local and the HTTP API and compare the results"
→ Claude calls execute_dql twice — once with transport="local", once with transport="http"
```

### Inspect connected peers
```
"Show me all currently connected peers and what transport they're using"
→ Claude calls get_peers, summarizes the connections array for each peer
```

### Check peer SDK versions before a migration
```
"Are any connected peers running an older SDK version than 4.9?"
→ Claude calls get_peers, filters by sdkVersion field
```

---

## Security Considerations

- The server binds to the loopback interface only (`NWParameters.requiredInterfaceType = .loopback`) — not accessible from other machines on your network
- No authentication by default — any process on your Mac can connect
- The server emits no CORS headers and does not answer CORS preflight requests — browser-based clients are not supported; MCP clients are CLI agents, not browsers
- All tools target the **currently selected database in the Edge Studio UI** — be mindful of what database is active
- The `execute_dql` tool can perform writes (INSERT, UPDATE, EVICT) — use with care
- `set_sync(enabled: false)` stops all replication for the active database until re-enabled

### Recommendations for shared machines
- Disable the MCP server when not actively using it (Settings toggle)
- Review which database is selected before running agent tasks that modify data

---

## Troubleshooting

### "Connection refused" when an agent tries to connect
Edge Studio is not running, or the MCP Server is disabled. Start the app and enable the server in Settings.

### Port conflict (address already in use)
Another process is using port 65269. Change the port via a `defaults write` command (future: Settings UI) or kill the conflicting process.

### No active database error from tools
Select a database in Edge Studio by clicking on it in the database list. Tools like `execute_dql` and `list_collections` require an active database.

### Metrics tools return "disabled" message
Enable metrics in Settings → General → Metrics.

### execute_dql with transport="http" returns http_not_configured
Open the database configuration in Edge Studio and set both `httpApiUrl` and `httpApiKey`. These fields are only required for HTTP transport — local queries work without them.

### get_peers returns empty peers array
No peers are currently connected to the active database. Check sync status with `get_sync_status` and ensure sync is running with `set_sync(enabled: true)`.

### Claude Code doesn't show `ditto-edge-studio` in `claude mcp list`
- Ensure `.mcp.json` is at the project root (it is, in this repo)
- Or run: `claude mcp add ditto-edge-studio --transport sse http://localhost:65269/mcp`
- Restart Claude Code if needed

---

## Technical Details

The MCP server implements the [MCP SSE transport](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/transports/) using Apple's Network.framework:

- **`GET /mcp`** — SSE endpoint; responds with `event: endpoint` pointing to the message URL
- **`POST /mcp?sessionId=<id>`** — JSON-RPC message handler; response delivered via SSE stream. An unknown (stale or never-established) `sessionId` is rejected with `404` **before** the message is processed, so mutating tools never execute for dead sessions. All sessions are drained when the server stops, so `sessionId`s never survive a restart.
- **`POST /mcp`** — Direct JSON-RPC (for HTTP transport clients); response in HTTP body
- **`GET /health`** — Simple health check returning `200 OK`

No external Swift packages are required. The implementation is ~1600 lines across four files in `EdgeStudio/Data/MCPServer/`.
