# MCP Server — New Tools Plan

**Date:** 2026-02-26
**Status:** Approved — Ready for Implementation
**Branch:** release-1.0.0

---

## Overview

Three new capabilities are being added to the embedded MCP server:

1. **`set_sync`** — Start or stop sync for the currently selected database
2. **`execute_dql` (extended)** — Add optional HTTP transport routing; default remains local DQL (no breaking change)
3. **`get_peers`** — One-time snapshot of connected peer details (same data shown in the Peers List tab)

Documentation (`docs/MCP_SERVER.md`) must be updated as part of this work.

---

## Feature 1: `set_sync` — Toggle Sync On/Off

### What it does
Allows an AI agent to programmatically start or stop sync on the currently selected database. Mirrors the sync toggle button in the toolbar.

### New Tool Definition
```json
{
  "name": "set_sync",
  "description": "Start or stop sync for the currently selected database.",
  "inputSchema": {
    "type": "object",
    "properties": {
      "enabled": {
        "type": "boolean",
        "description": "true to start sync, false to stop sync"
      }
    },
    "required": ["enabled"]
  }
}
```

### Implementation

**File: `SwiftUI/Edge Debug Helper/Data/MCPServer/MCPToolHandlers.swift`**

Add to `allTools` array:
```swift
// Tool definition (after configure_transport)
MCPTool(
    name: "set_sync",
    description: "Start or stop sync for the currently selected database.",
    inputSchema: [
        "type": "object",
        "properties": [
            "enabled": ["type": "boolean",
                        "description": "true to start sync, false to stop sync"]
        ],
        "required": ["enabled"]
    ]
)
```

Add to `execute()` switch:
```swift
case "set_sync":
    return try await handleSetSync(arguments: arguments)
```

Add handler:
```swift
private static func handleSetSync(arguments: [String: Any]?) async throws -> String {
    guard let args = arguments, let enabled = args["enabled"] as? Bool else {
        throw MCPError.missingArgument("enabled")
    }
    guard DittoManager.shared.dittoSelectedApp != nil else {
        throw MCPError.noActiveDatabase
    }

    if enabled {
        try await DittoManager.shared.selectedDatabaseStartSync()
        return "{\"sync\": \"started\", \"enabled\": true}"
    } else {
        await DittoManager.shared.selectedDatabaseStopSync()
        return "{\"sync\": \"stopped\", \"enabled\": false}"
    }
}
```

### Scope
- ~40 lines added to `MCPToolHandlers.swift`
- No changes to `DittoManager.swift` — uses existing `selectedDatabaseStartSync()` / `selectedDatabaseStopSync()`
- No UI state update needed from MCP (the toolbar toggle state is local to `ViewModel.isSyncEnabled`; the MCP acts on the underlying Ditto engine)

### Risk
**Low.** Existing tools are untouched. Uses same methods already called by `configure_transport`.

---

## Feature 2: `execute_dql` — Optional HTTP Transport

### What it does
The existing `execute_dql` tool always runs queries against the local embedded Ditto database. This extends it with an optional `transport` parameter so an agent can explicitly request HTTP execution (Ditto Cloud / HTTP API). The default is `"local"` — fully backward-compatible.

**Trigger phrases the agent might use:**
- "run via HTTP server"
- "run via Ditto Portal"
- "run via cloud"
- "run against the HTTP API"

### Modified Tool Definition
```json
{
  "name": "execute_dql",
  "description": "Execute a DQL query or mutation against the selected Ditto database. By default runs against the local embedded database. Set transport to 'http' to route through the HTTP API (requires httpApiUrl and httpApiKey to be configured).",
  "inputSchema": {
    "type": "object",
    "properties": {
      "query": {
        "type": "string",
        "description": "The DQL query or mutation to execute"
      },
      "transport": {
        "type": "string",
        "enum": ["local", "http"],
        "description": "Execution transport. 'local' (default) uses the embedded Ditto database. 'http' uses the HTTP API endpoint configured for this database."
      }
    },
    "required": ["query"]
  }
}
```

### Implementation

**File: `SwiftUI/Edge Debug Helper/Data/MCPServer/MCPToolHandlers.swift`**

Existing `execute_dql` tool definition update: add the optional `transport` property to `inputSchema`.

Existing handler `handleExecuteDql()` update:
```swift
private static func handleExecuteDql(arguments: [String: Any]?) async throws -> String {
    guard let args = arguments, let query = args["query"] as? String else {
        throw MCPError.missingArgument("query")
    }

    let transport = args["transport"] as? String ?? "local"  // NEW: default to local

    if transport == "http" {
        // NEW: HTTP path — check config first
        guard let config = DittoManager.shared.dittoSelectedAppConfig else {
            throw MCPError.noActiveDatabase
        }
        guard let httpUrl = config.httpApiUrl, !httpUrl.isEmpty,
              let httpKey = config.httpApiKey, !httpKey.isEmpty else {
            // Return a user-facing structured error — not a protocol error.
            // Tone: clear that this is a configuration gap the user needs to fix,
            // with enough personality that an AI agent can relay it naturally.
            return """
            {
              "error": "http_not_configured",
              "message": "You asked to run this via HTTP, but this database hasn't been introduced to the cloud yet. Add httpApiUrl and httpApiKey to this database's configuration — then it'll know where to show up.",
              "hint": "Open database configuration → set httpApiUrl and httpApiKey"
            }
            """
        }
        let results = try await QueryService.shared.executeSelectedAppQueryHttp(query: query)
        return buildResultsJSON(results)
    } else {
        // EXISTING: local path — unchanged
        let results = try await QueryService.shared.executeSelectedAppQuery(query: query)
        return buildResultsJSON(results)
    }
}

// Extract shared helper so both paths format consistently
private static func buildResultsJSON(_ results: [String]) -> String {
    let escaped = results.map { $0.replacingOccurrences(of: "\"", with: "\\\"") }
    return "[" + escaped.map { "\"\($0)\"" }.joined(separator: ",") + "]"
}
```

> **CRITICAL CONSTRAINT:** The local execution path (`transport == "local"` or omitted) MUST remain identical to current behavior. The existing tested flow calls `QueryService.shared.executeSelectedAppQuery()` and must continue to do so unchanged.

### Scope
- ~25 lines changed in `MCPToolHandlers.swift` (handler method + tool definition update)
- No changes to `QueryService.swift` — uses existing `executeSelectedAppQueryHttp()`

### Risk
**Very low.** The `transport` param is optional with default `"local"`. Any call that omits `transport` hits the exact same code path as today. The HTTP path is entirely new and gated behind a guard.

---

## Feature 3: `get_peers` — One-Time Peer Snapshot

### What it does
Returns a point-in-time snapshot of all connected remote peers with full details — the same information displayed in the Peers List tab. Returns an empty array if no peers are connected.

This avoids reusing the observer pattern (which feeds `MainStudioView.ViewModel.syncStatusItems`) and instead adds a direct one-time read to `SystemRepository`.

### New Tool Definition
```json
{
  "name": "get_peers",
  "description": "Get a one-time snapshot of all currently connected remote peers and their details. Returns an empty array if no peers are connected.",
  "inputSchema": {
    "type": "object",
    "properties": {}
  }
}
```

### Peer Data Returned (per peer)
Based on ConnectedPeersView and `SyncStatusInfo`/`PeerEnrichmentData`:

```json
{
  "peers": [
    {
      "peerKey": "abc123...xyz",
      "deviceName": "iPhone 15 Pro",
      "osType": "iOS",
      "sdkVersion": "4.9.1",
      "connectionStatus": "Connected",
      "addressInfo": "192.168.1.42",
      "connections": [
        {
          "type": "Bluetooth",
          "displayName": "Bluetooth LE",
          "distanceMeters": 2.1
        }
      ],
      "identityMetadata": "{...}",
      "peerMetadata": "{...}",
      "syncedUpToCommitId": "commit-abc123"
    }
  ],
  "count": 1
}
```

Fields match what `ConnectedPeersView` shows in each peer card:
- `peerKey` — truncated peer key string (identifier)
- `deviceName` — device name or peer type label
- `osType` — iOS / Android / macOS / Linux / Windows / Unknown
- `sdkVersion` — Ditto SDK version string (if available)
- `connectionStatus` — Connected / Connecting / Disconnected
- `addressInfo` — inferred address (BT address, IP, websocket URL)
- `connections` — array of active connection objects (type, displayName, distanceMeters)
- `identityMetadata` — JSON string of identity service metadata (if present)
- `peerMetadata` — JSON string of peer metadata (if present)
- `syncedUpToCommitId` — last synced commit ID (if available)

### Implementation

#### Step 1: Add `fetchPeersOnce()` to SystemRepository

**File: `SwiftUI/Edge Debug Helper/Data/Repositories/SystemRepository.swift`**

Add a new public method that reads the presence graph once and applies the same enrichment logic as `extractPeerEnrichment()` (which already exists in the file):

```swift
/// One-time peer snapshot for MCP. Returns enriched peer data without registering an observer.
/// Includes syncedUpToLocalCommitId sourced from a single system:data_sync_info DQL query.
func fetchPeersOnce() async -> [SyncStatusInfo] {
    guard let ditto = await DittoManager.shared.dittoSelectedApp else {
        return []
    }

    // Phase 1: read presence graph + run sync_info query concurrently on utility queue
    let (presencePeers, syncInfoRows) = await Task.detached(priority: .utility) {
        let peers = ditto.presence.graph.remotePeers
        // Query the same system table the observer uses for commit IDs.
        // Use try? — if it fails (no sync, offline) we just won't have commit IDs.
        let rows: [(peerKey: String, commitId: String)] = (try? ditto.store
            .execute(query: "SELECT * FROM system:data_sync_info")
            .items
            .compactMap { item -> (String, String)? in
                guard let key = item["peer_key"]?.stringValue,
                      let commit = item["synced_up_to_local_commit_id"]?.stringValue
                else { return nil }
                return (key, commit)
            }) ?? []
        return (peers, rows)
    }.value

    if presencePeers.isEmpty { return [] }

    // Build a lookup: peerKey → commitId
    let commitLookup = Dictionary(uniqueKeysWithValues: syncInfoRows)

    // Phase 2: enrich each peer
    var results: [SyncStatusInfo] = []
    for peer in presencePeers {
        let enrichment = extractPeerEnrichment(peer: peer)
        let info = SyncStatusInfo(
            peerKeyString: peer.peerKeyString,
            deviceName: enrichment.deviceName,
            osInfo: enrichment.osInfo,
            dittoSDKVersion: enrichment.dittoSDKVersion,
            connectionStatus: .connected,  // presence only includes connected peers
            addressInfo: enrichment.addressInfo,
            identityMetadata: enrichment.identityMetadata,
            peerMetadata: enrichment.peerMetadata,
            connections: enrichment.connections,
            syncedUpToLocalCommitId: commitLookup[peer.peerKeyString],
            lastUpdate: Date()
        )
        results.append(info)
    }
    return results
}
```

> **Implementation note:** The presence read and `system:data_sync_info` query run together on a single `.utility` task to keep the one-time fetch fast. If the DQL query fails (e.g. sync is off), commit IDs are omitted gracefully — the rest of the peer data still returns. The `peer_key` field name in `system:data_sync_info` must be confirmed against the actual SDK schema when implementing; adjust if the column name differs.

#### Step 2: Add MCP Tool Handler

**File: `SwiftUI/Edge Debug Helper/Data/MCPServer/MCPToolHandlers.swift`**

Add to `allTools`:
```swift
MCPTool(
    name: "get_peers",
    description: "Get a one-time snapshot of all currently connected remote peers and their details. Returns an empty array if no peers are connected.",
    inputSchema: ["type": "object", "properties": [:]]
)
```

Add to `execute()` switch:
```swift
case "get_peers":
    return try await handleGetPeers()
```

Add handler:
```swift
private static func handleGetPeers() async throws -> String {
    guard DittoManager.shared.dittoSelectedApp != nil else {
        throw MCPError.noActiveDatabase
    }

    let peers = await SystemRepository.shared.fetchPeersOnce()

    if peers.isEmpty {
        return "{\"peers\": [], \"count\": 0}"
    }

    let peerObjects = peers.map { peer -> String in
        let connectionsJSON = peer.connections.map { conn -> String in
            let distance = conn.distanceInMeters.map { String(format: "%.1f", $0) } ?? "null"
            return """
            {"type":"\(conn.type.displayName)","displayName":"\(conn.type.displayName)","distanceMeters":\(distance)}
            """
        }.joined(separator: ",")

        let metadata = peer.identityMetadata?.replacingOccurrences(of: "\"", with: "\\\"") ?? ""
        let peerMeta = peer.peerMetadata?.replacingOccurrences(of: "\"", with: "\\\"") ?? ""
        let commitId = peer.syncedUpToLocalCommitId ?? ""

        return """
        {
          "peerKey": "\(peer.peerKeyString)",
          "deviceName": "\(peer.deviceName ?? "Unknown")",
          "osType": "\(peer.osInfo?.osType.displayName ?? "Unknown")",
          "sdkVersion": "\(peer.dittoSDKVersion ?? "")",
          "connectionStatus": "\(peer.connectionStatus.displayName)",
          "addressInfo": "\(peer.addressInfo ?? "")",
          "connections": [\(connectionsJSON)],
          "identityMetadata": "\(metadata)",
          "peerMetadata": "\(peerMeta)",
          "syncedUpToCommitId": "\(commitId)"
        }
        """
    }.joined(separator: ",")

    return "{\"peers\": [\(peerObjects)], \"count\": \(peers.count)}"
}
```

### Scope
- ~40 lines added to `SystemRepository.swift` (new method, reuses existing `extractPeerEnrichment()`)
- ~80 lines added to `MCPToolHandlers.swift` (tool definition + handler)
- No changes to `MainStudioView.swift` or observer infrastructure

### Risk
**Low.** The existing observer path is untouched. `fetchPeersOnce()` reads `ditto.presence.graph.remotePeers` synchronously on a utility task — the same property the observer already reads.

---

## Feature 4: Documentation Update

**File: `docs/MCP_SERVER.md`**

Updates required:
1. Update tool count from "9 tools" to "12 tools" (actually we currently have 10, going to 13... need to reconcile)
2. Add new sections for each new tool with:
   - Description
   - Input schema (parameters, types, defaults)
   - Example request/response
   - Error cases
3. Add section: "Query Transport Options" — explains local vs HTTP
4. Add section: "Sync Control" — explains `set_sync`
5. Add section: "Peer Discovery" — explains `get_peers` and what data it returns
6. Update the tool table/index at top of file

---

## Files Changed Summary

| File | Change Type | Scope |
|------|------------|-------|
| `Data/MCPServer/MCPToolHandlers.swift` | Modified | Add 3 tools + handlers (~145 lines) |
| `Data/Repositories/SystemRepository.swift` | Modified | Add `fetchPeersOnce()` method (~40 lines) |
| `docs/MCP_SERVER.md` | Modified | Document all new tools + existing tools audit |

**No other files need to change.**

---

## What is NOT Changing

- `MCPServerService.swift` — no changes
- `MCPJSONRPCHandler.swift` — no changes
- `QueryService.swift` — no changes (existing methods reused as-is)
- `DittoManager.swift` — no changes (existing sync methods reused)
- `MainStudioView.swift` / `ViewModel` — no changes
- `SystemRepository` observer registration — no changes

---

## Backward Compatibility

| Existing Tool | Status |
|--------------|--------|
| `execute_dql` | ✅ Safe — `transport` is optional, defaults to `"local"`, existing code path unchanged |
| `list_databases` | ✅ Unchanged |
| `get_active_database` | ✅ Unchanged |
| `list_collections` | ✅ Unchanged |
| `create_index` | ✅ Unchanged |
| `drop_index` | ✅ Unchanged |
| `get_query_metrics` | ✅ Unchanged |
| `get_sync_status` | ✅ Unchanged |
| `configure_transport` | ✅ Unchanged |
| `insert_documents_from_file` | ✅ Unchanged |

---

## Effort Estimate

| Feature | Complexity | Estimated Work |
|---------|-----------|----------------|
| `set_sync` tool | Low | ~45 min |
| `execute_dql` HTTP option | Low | ~45 min |
| `get_peers` tool + SystemRepository method | Medium | ~90 min |
| Documentation update | Medium | ~60 min |
| **Total** | | **~4 hours** |

---

## Decisions (Resolved)

1. **`syncedUpToCommitId` in `get_peers`:** ✅ **Include it.** A single concurrent `system:data_sync_info` DQL query runs alongside the presence read on the same utility task. Commit IDs are omitted gracefully if the query fails.

2. **`set_sync` return value:** ✅ **Return action taken + new enabled state** (already in plan).

3. **HTTP not-configured error message:** ✅ **Structured JSON with personality.** Error makes it unambiguously clear the user is missing configuration and exactly what to fix:
   ```json
   {
     "error": "http_not_configured",
     "message": "You asked to run this via HTTP, but this database hasn't been introduced to the cloud yet. Add httpApiUrl and httpApiKey to this database's configuration — then it'll know where to show up.",
     "hint": "Open database configuration → set httpApiUrl and httpApiKey"
   }
   ```

4. **Tool name:** ✅ **`get_peers`** confirmed.
