# Edge Studio MCP Server

Edge Studio embeds an MCP (Model Context Protocol) server that lets AI agents like Claude Code query and manage the active Ditto database directly. When the app is running with MCP enabled, Claude Code connects automatically. When the app quits, the server stops.

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
| `execute_dql` | Execute a DQL query against the active database |
| `list_databases` | List all configured databases (name, ID, mode) |
| `get_active_database` | Get details about the currently selected database |
| `list_collections` | List collections with document counts and indexes |
| `create_index` | Create an index on a collection field |
| `drop_index` | Drop an index by name |
| `get_query_metrics` | Get recent query execution metrics and EXPLAIN output |
| `get_sync_status` | Get peer count and transport configuration |
| `configure_transport` | Enable/disable Bluetooth, LAN, AWDL, or Cloud Sync |

### Tool Details

#### `execute_dql`
```
Arguments: { "query": "SELECT * FROM myCollection LIMIT 10" }
Returns: JSON array of result documents, or mutation IDs for writes
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
Returns: { name, databaseId, mode, transport: { bluetoothLE, lan, awdl, cloudSync } }
Note: Returns error if no database is selected in Edge Studio
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
Arguments: { "index_name": "idx_myCollection_name" }
Returns: Success or error message
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
Returns: { database, connectedPeers, transport: { bluetoothLE, lan, awdl, cloudSync } }
```

#### `configure_transport`
```
Arguments: { "bluetooth": bool?, "lan": bool?, "awdl": bool?, "cloud": bool? }
Returns: Applied configuration summary
Note: Omitted parameters are unchanged. Stops and restarts sync automatically.
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

---

## Security Considerations

- The server only binds to `127.0.0.1` (localhost) — not accessible from other machines on your network
- No authentication by default — any process on your Mac can connect
- All tools target the **currently selected database in the Edge Studio UI** — be mindful of what database is active
- The `execute_dql` tool can perform writes (INSERT, UPDATE, EVICT) — use with care

### Recommendations for shared machines
- Disable the MCP server when not actively using it (Settings toggle)
- Review which database is selected before running agent tasks that modify data

---

## Troubleshooting

### "Connection refused" when Claude tries to connect
Edge Studio is not running, or the MCP Server is disabled. Start the app and enable the server in Settings.

### Port conflict (address already in use)
Another process is using port 65269. Change the port via a `defaults write` command (future: Settings UI) or kill the conflicting process.

### No active database error from tools
Select a database in Edge Studio by clicking on it in the database list. Tools like `execute_dql` and `list_collections` require an active database.

### Metrics tools return "disabled" message
Enable metrics in Settings → General → Metrics.

### Claude Code doesn't show `ditto-edge-studio` in `claude mcp list`
- Ensure `.mcp.json` is at the project root (it is, in this repo)
- Or run: `claude mcp add ditto-edge-studio --transport sse http://localhost:65269/mcp`
- Restart Claude Code if needed

---

## Technical Details

The MCP server implements the [MCP SSE transport](https://spec.modelcontextprotocol.io/specification/2024-11-05/basic/transports/) using Apple's Network.framework:

- **`GET /mcp`** — SSE endpoint; responds with `event: endpoint` pointing to the message URL
- **`POST /mcp?sessionId=<id>`** — JSON-RPC message handler; response delivered via SSE stream
- **`POST /mcp`** — Direct JSON-RPC (for HTTP transport clients); response in HTTP body
- **`GET /health`** — Simple health check returning `200 OK`

No external Swift packages are required. The implementation is ~350 lines across three files in `Edge Debug Helper/Data/MCPServer/`.
