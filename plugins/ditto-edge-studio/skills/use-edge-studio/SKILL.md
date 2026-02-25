# use-edge-studio

Use the Edge Studio MCP server to query and manage the active Ditto database.

## Prerequisites

1. Edge Studio is running on macOS
2. MCP Server is enabled: Settings → General → MCP Server (toggle on, green dot appears)
3. Claude Code is configured: `.mcp.json` at repo root, or `claude mcp add ditto-edge-studio --transport sse http://localhost:65269/mcp`

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
Returns: `{ name, databaseId, mode, transport: { bluetoothLE, lan, awdl, cloudSync } }`

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
```
Use the `name` value from `list_collections` (e.g. `"idx_orders_status"`).

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
Optional: bluetooth, lan, awdl, cloud (all boolean)
```
Only specified parameters change; others keep current values. Automatically stops and restarts sync.

---

## When to Use Each Tool

| Goal | Tool |
|------|------|
| Explore data | `list_collections` → `execute_dql` |
| Query performance | `execute_dql` + `get_query_metrics` |
| Index management | `list_collections` (see existing) → `create_index` / `drop_index` |
| Debug sync | `get_sync_status` |
| Test offline behavior | `configure_transport` (disable cloud) |
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

### Test P2P sync without cloud
```
1. get_sync_status → note current settings
2. configure_transport → { "cloud": false }
3. execute_dql → INSERT test data
4. get_sync_status → verify cloud is disabled
5. configure_transport → { "cloud": true } to restore
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
