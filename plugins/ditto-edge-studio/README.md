# ditto-edge-studio Claude Code Plugin

Gives Claude Code access to the [Edge Studio](../../README.md) MCP server for querying and managing Ditto databases directly from your AI coding sessions.

## Prerequisites

- **Edge Studio** running on macOS with MCP Server enabled
- **Claude Code** 1.x+

## Setup

### 1. Enable the MCP Server in Edge Studio

1. Open Edge Studio
2. Go to **Settings…** (⌘,)
3. Toggle **Enable MCP Server** ON
4. Confirm the green status dot appears (Running on port 65269)

### 2. Connect Claude Code

The `.mcp.json` at the repository root is auto-discovered by Claude Code when you work in this project. No additional steps needed.

To make it available globally across all projects:

```bash
claude mcp add ditto-edge-studio --transport sse http://localhost:65269/mcp
```

Verify:

```bash
claude mcp list
# ditto-edge-studio (sse) http://localhost:65269/mcp
```

### 3. Test the connection

```bash
curl -X POST http://localhost:65269/mcp \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

Should return a JSON array of 9 tools.

## Usage

Once connected, ask Claude Code naturally:

- *"List the collections in my active database"*
- *"Run this DQL query and explain what it's doing: SELECT * FROM orders WHERE status = 'pending'"*
- *"How many documents are in each collection?"*
- *"Create an index on the users collection for the email field"*
- *"Show me the sync status and connected peers"*

## Available Tools

| Tool | What it does |
|------|-------------|
| `execute_dql` | Run any DQL query (SELECT, INSERT, UPDATE, EVICT) |
| `list_databases` | List all configured databases |
| `get_active_database` | Get the currently selected database details |
| `list_collections` | List collections with document counts and indexes |
| `create_index` | Create an index on a collection field |
| `drop_index` | Drop an index by name |
| `get_query_metrics` | Recent query performance and EXPLAIN output |
| `get_sync_status` | Connected peer count and transport config |
| `configure_transport` | Toggle Bluetooth, LAN, AWDL, or Cloud Sync |

For detailed parameter and return value docs, see [`skills/use-edge-studio/SKILL.md`](./skills/use-edge-studio/SKILL.md) or [`docs/MCP_SERVER.md`](../../docs/MCP_SERVER.md).

## Notes

- All tools operate on the **currently selected database** in the Edge Studio UI
- The `execute_dql` tool can write data — review queries before executing
- MCP server stops when Edge Studio quits
