# use-edge-studio

Use the Edge Studio MCP server to query and manage the active Ditto database.

## Prerequisites

1. Edge Studio is running on macOS
2. MCP Server is enabled: Settings → General → MCP Server (toggle on, green dot appears)
3. Your agent is configured: Codex uses `.codex/config.toml`; Claude Code uses `.mcp.json` or `claude mcp add ditto-edge-studio --transport sse http://localhost:65269/mcp`

> If you get "connection refused", Edge Studio is not running or MCP is disabled.

---

## Available Tools

### `execute_dql` — Run DQL queries
```
Required: query (string)
```
Executes any DQL statement against the active database. Returns JSON documents for SELECT, or mutation IDs for INSERT/UPDATE/EVICT.

```
SELECT * FROM myCollection WHERE field = 'value' LIMIT 10
SELECT COUNT(*) as total FROM myCollection
INSERT INTO myCollection DOCUMENTS ({ 'name': 'Alice', 'age': 30 })
UPDATE myCollection SET field = 'value' WHERE _id = 'abc123'
EVICT FROM myCollection WHERE _id = 'abc123'
```

### `list_databases` — List all configured databases
```
No arguments
```
Returns: `[{ id, name, databaseId, mode }]` — never returns credentials.

### `get_active_database` — Current database details
```
No arguments
```
Returns: `{ name, databaseId, mode, url, httpApiUrl, httpApiConfigured, allowUntrustedCerts, logLevel, transport: { bluetoothLE, lan, awdl, cloudSync } }`

Credentials (token, httpApiKey, secretKey) are never included — `httpApiConfigured` is a boolean telling you whether both HTTP API fields are set, not the key itself.

Fails with error if no database is selected in Edge Studio.

### `list_collections` — Collections with counts and indexes
```
No arguments
```
Returns: `[{ name, documentCount, indexes: [{ name, fullName, collection, fields }] }]`

### `create_index` — Index a field
```
Required: collection (string), field (string)
```
Creates `idx_{collection}_{field}` index. Field paths: `"name"`, `"address.city"`.

### `drop_index` — Remove an index
```
Required: index_name (string)
Optional: collection (string)
```
Use the `name` value from `list_collections` or `list_indexes` (e.g. `"idx_orders_status"`). The owning collection is resolved automatically; pass `collection` only if the same index name exists on multiple collections.

### `get_query_metrics` — Recent query performance
```
No arguments
```
Returns up to 200 recent queries with execution time, result count, and EXPLAIN output. Requires Metrics enabled in Settings.

### `get_sync_status` — Peer connections and transport
```
No arguments
```
Returns: `{ database, connectedPeers, transport: { bluetoothLE, lan, awdl, cloudSync } }`

### `configure_transport` — Change sync transports
```
Optional: bluetooth, lan, awdl (all boolean)
```
Only specified parameters change; others keep current values. Automatically stops and restarts sync. There is no `cloud` parameter — only the three peer-to-peer transports are toggled.

### `insert_documents_from_file` — Bulk insert from JSON
```
Required: file_path (string), collection (string)
Optional: mode — "insert" (default, upserts) or "insert_initial" (skips existing _ids)
```
The file must be a JSON array of objects with an `_id` field, located in `~/Downloads` (macOS sandbox). Returns `{ inserted, failed, mode, collection, errors }`.

### `set_sync` — Start or stop sync
```
Required: enabled (boolean)
```
Returns `{ sync: "started"|"stopped", enabled: bool }`. Use to pause sync before bulk operations.

### `get_peers` — Connected peer snapshot
```
No arguments
```
One-time snapshot of all connected remote peers: device name, OS, SDK version, connection types, distances, metadata. Returns `{ "peers": [], "count": 0 }` when no peers are connected.

### `list_indexes` — All indexes across collections
```
No arguments
```
Returns a flat array of `{ name, fullName, collection, fields }` for every index in the active database.

### `get_app_logs` — Edge Studio app logs
```
Optional: lines (int, default 200), filter (string, case-insensitive substring)
```
Reads the most recent Edge Studio application log entries (plain text).

### `get_ditto_logs` — Ditto SDK logs
```
Optional: lines (int, default 200), filter (string), level (error|warning|info|debug|verbose)
```
Reads structured log entries (`{ timestamp, level, component, message }`) from the active database's Ditto SDK log files.

---

## When to Use Each Tool

| Goal | Tool |
|------|------|
| Explore data | `list_collections` → `execute_dql` |
| Query performance | `execute_dql` + `get_query_metrics` |
| Index management | `list_collections` (see existing) → `create_index` / `drop_index` |
| Debug sync | `get_sync_status` + `get_app_logs` / `get_ditto_logs` |
| Test offline behavior | `configure_transport` (disable bluetooth/lan/awdl) |
| Switch databases | Tell user to select one in Edge Studio UI |

---

## Common Workflows

### Explore a new database
```
1. list_databases → confirm which is active
2. get_active_database → verify transport settings
3. list_collections → see all collections and document counts
4. execute_dql → "SELECT * FROM {largest collection} LIMIT 5" to see schema
```

### Find slow queries
```
1. execute_dql → run the suspect query
2. get_query_metrics → check EXPLAIN output for the query
3. list_collections → check if indexes exist on filtered fields
4. create_index → create missing index if needed
5. execute_dql again → compare execution time
```

### Test local-only behavior (all P2P transports off)
```
1. get_sync_status → note current settings
2. configure_transport → { "bluetooth": false, "lan": false, "awdl": false }
3. execute_dql → INSERT test data
4. get_sync_status → verify transports are disabled
5. configure_transport → restore the original values from step 1
```

---

## Important Notes

- **All tools target the database currently selected in the Edge Studio UI.** There is no way to switch databases via MCP — ask the user to select a different database in Edge Studio.
- `execute_dql` can perform **writes** — always confirm destructive operations with the user before executing EVICT or bulk UPDATEs.
- `configure_transport` **stops and restarts sync** — connected peers will briefly disconnect.
- For DQL syntax help, see the `write-dql` skill (if installed) or the [Ditto DQL docs](https://docs.ditto.live/sdk/latest/crud/querying).

---

## Error Reference

| Error | Cause | Fix |
|-------|-------|-----|
| `connection refused` | App not running / MCP disabled | Start Edge Studio, enable MCP |
| `No active database` | No database selected in UI | Ask user to select a database |
| `Metrics are disabled` | Metrics toggle off | Enable in Settings → General |
| `Unknown tool` | Wrong tool name | Check spelling against tool list above |
