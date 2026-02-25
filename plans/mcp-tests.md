# Plan: MCP Server Test Suite

**Status:** Ready for Review
**Mandatory reading:** `docs/TESTING.md` — all rules apply

---

## What We're Testing

The MCP system has four distinct layers, each with its own testing strategy:

```
┌─────────────────────────────────────────────────────────┐
│  Layer 4: End-to-End Integration (real HTTP + database) │
├─────────────────────────────────────────────────────────┤
│  Layer 3: Tool Execution (MCPToolHandlers per-tool)     │
├─────────────────────────────────────────────────────────┤
│  Layer 2: JSON-RPC Protocol (MCPJSONRPCHandler)         │
├─────────────────────────────────────────────────────────┤
│  Layer 1: Tool Manifest (MCPToolHandlers.allTools)      │
└─────────────────────────────────────────────────────────┘
```

Layers 1 and 2 need no database and no running server — pure Swift logic.
Layers 3 and 4 require a live server and some require an active Ditto database.

---

## Required Code Change Before Tests Can Be Written

`MCPHTTPConnectionHandler.tryParseRequest` is currently `private static`. The JSON-RPC handler and tool dispatch are already accessible via `@testable import`. However HTTP parsing needs one change to be unit testable:

**Extract HTTP parsing into a new internal type:**

```swift
// New file: MCPHTTPParser.swift  (inside #if os(macOS))
struct MCPHTTPParser {
    static func tryParse(_ data: Data) -> HTTPRequest? { ... }
}
```

Move the body of `tryParseRequest` into `MCPHTTPParser.tryParse`. Then `MCPHTTPConnectionHandler.scheduleRead` calls `MCPHTTPParser.tryParse` instead. This is a pure refactor — no behaviour change — and it unlocks HTTP parser unit tests.

**Files changed:** `MCPServerService.swift` (move method body) + new `MCPHTTPParser.swift`

If this refactor is deferred, the HTTP parser tests in the plan below are skipped and covered by integration tests instead. All other tests are unaffected.

---

## Test File Structure

```
SwiftUI/
├── EdgeStudioUnitTests/
│   └── MCP/
│       ├── MCPHTTPParserTests.swift          (needs refactor above)
│       ├── MCPJSONRPCHandlerTests.swift      (no dependencies)
│       └── MCPToolManifestTests.swift        (no dependencies)
│
└── EdgeStudioIntegrationTests/
    └── MCP/
        ├── MCPServerLifecycleTests.swift     (real server, test port)
        ├── MCPToolExecutionTests.swift       (real server, error paths)
        └── MCPInsertFromFileTests.swift      (file I/O + ImportService)
```

All files use Swift Testing (`import Testing`), `@Suite`, `@Test`, `#expect`. No XCTest.

---

## Tags

Add to `EdgeStudioUnitTests/TestTags.swift` and `EdgeStudioIntegrationTests/TestTags.swift`:

```swift
extension Tag {
    @Tag static var mcp: Tag
    @Tag static var mcpServer: Tag
    @Tag static var mcpTools: Tag
}
```

---

## Part 1 — Unit Tests (no server, no database)

### `MCPHTTPParserTests.swift`
*Requires the `MCPHTTPParser` refactor above. Skip if deferred.*

```
@Suite("MCP HTTP Parser Tests")
```

| Test | Inputs | Expects |
|---|---|---|
| Parses complete GET request | `"GET /health HTTP/1.1\r\nHost: localhost\r\n\r\n"` | `method == "GET"`, `path == "/health"` |
| Parses complete POST with body | POST + `Content-Length: 13` + `{"hello":"ok"}` | `method == "POST"`, `body == data` |
| Returns nil for incomplete headers | Half a request line | `nil` |
| Returns nil when body not yet complete | Header says `Content-Length: 100`, only 10 bytes of body received | `nil` |
| Parses query parameters | `GET /mcp?sessionId=abc123` | `queryParams["sessionId"] == "abc123"` |
| Parses headers case-insensitively | `Content-Type: application/json` | `headers["content-type"] == "application/json"` |
| Handles zero content-length POST | POST with `Content-Length: 0` | `body.isEmpty == true` |

### `MCPJSONRPCHandlerTests.swift`
*Calls `MCPJSONRPCHandler.handle(_ body: Data)` directly — no server, no database.*

```
@Suite("MCP JSON-RPC Handler Tests", .serialized)
```

**Routing & Protocol:**

| Test | Input JSON | Expects |
|---|---|---|
| `initialize` returns correct protocol version | `{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}` | `result.protocolVersion == "2024-11-05"`, `serverInfo.name == "ditto-edge-studio"` |
| `tools/list` returns all 10 tools | `{"jsonrpc":"2.0","id":1,"method":"tools/list"}` | `result.tools.count == 10`, each has `name`/`description`/`inputSchema` |
| Notification (no `id`) returns `isNotification = true` | `{"jsonrpc":"2.0","method":"notifications/initialized"}` | `isNotification == true`, response string is empty |
| Unknown method returns error -32601 | `{"jsonrpc":"2.0","id":1,"method":"nonexistent"}` | `error.code == -32601` |
| Empty body returns parse error -32700 | `Data()` | `error.code == -32700` |
| Malformed JSON returns parse error | `Data("not json".utf8)` | `error.code == -32700` |
| String `id` is round-tripped correctly | `{"jsonrpc":"2.0","id":"my-id","method":"tools/list"}` | response `id == "my-id"` |
| Integer `id` is round-tripped correctly | `{"jsonrpc":"2.0","id":42,"method":"tools/list"}` | response `id == 42` |
| `tools/call` with missing `name` returns error -32602 | `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{}}` | `error.code == -32602` |
| `tools/call` with unknown tool name returns error | `{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"does_not_exist"}}` | `isError == true` in content |
| Response is valid JSON | any valid request | `JSONSerialization.jsonObject(with: response)` succeeds |

### `MCPToolManifestTests.swift`
*Reads `MCPToolHandlers.allTools` — no server, no database.*

```
@Suite("MCP Tool Manifest Tests")
```

| Test | What it checks |
|---|---|
| All 10 tools are registered | `allTools.count == 10` |
| No duplicate tool names | `Set(names).count == allTools.count` |
| Every tool has a non-empty name | `tool.name.isEmpty == false` for all |
| Every tool has a non-empty description | `tool.description.isEmpty == false` for all |
| Every tool has a non-nil inputSchema | `tool.inputSchema` is not empty |
| `insert_documents_from_file` is registered | tool with that name exists |
| `insert_documents_from_file` has `file_path` in required | `inputSchema["required"]` contains `"file_path"` |
| `insert_documents_from_file` has `collection` in required | `inputSchema["required"]` contains `"collection"` |
| `insert_documents_from_file` mode enum has exactly 2 values | `["insert", "insert_initial"]` |
| `execute_dql` has `query` in required | `inputSchema["required"]` contains `"query"` |
| `create_index` has `collection` and `field` in required | both present in `required` array |

---

## Part 2 — Integration Tests (real server, test port)

All integration tests start the MCP server on **port 65270** (not 65269) to avoid conflicting with a running app instance.

### Setup helper (add to `TestHelpers.swift` or a new `MCPTestHelpers.swift`)

```swift
struct MCPTestHelpers {
    static let testPort: UInt16 = 65270
    static let baseURL = "http://[::1]:\(testPort)"

    /// Starts MCPServerService on the test port, runs body, then stops it.
    static func withServer(_ body: () async throws -> Void) async throws {
        UserDefaults.standard.set(Int(testPort), forKey: "mcpServerPort")
        await MCPServerService.shared.start()
        defer { Task { await MCPServerService.shared.stop() } }
        // Brief pause for NWListener to become ready
        try await Task.sleep(for: .milliseconds(200))
        try await body()
        UserDefaults.standard.removeObject(forKey: "mcpServerPort")
    }

    /// POST a JSON-RPC request, return the decoded response dictionary.
    static func post(id: Int = 1, method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)/mcp")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    /// Call a named tool, return the result text.
    static func callTool(_ name: String, arguments: [String: Any] = [:]) async throws -> String {
        let response = try await post(
            method: "tools/call",
            params: ["name": name, "arguments": arguments]
        )
        let content = (response["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return content?.first?["text"] as? String ?? ""
    }
}
```

> **Note on the singleton port issue:** `MCPServerService` reads `mcpServerPort` from `UserDefaults` at start time. Setting it before calling `start()` is sufficient. Tests must be `.serialized` because only one server instance can run at a time.

### `MCPServerLifecycleTests.swift`

```
@Suite("MCP Server Lifecycle Tests", .serialized)
```

| Test | Steps | Expects |
|---|---|---|
| Server responds to `/health` | `withServer { GET /health }` | `200 OK`, body `"OK"` |
| Server responds to unknown path with 404 | `GET /unknown` | HTTP 404 |
| CORS preflight returns 204 | `OPTIONS /mcp` | HTTP 204, `Access-Control-Allow-Origin: *` |
| Server stops cleanly | `start()` → `stop()` → try GET | connection refused |
| Server can restart after stop | `start()` → `stop()` → `start()` → GET /health | `"OK"` |

### `MCPToolExecutionTests.swift`

```
@Suite("MCP Tool Execution Tests", .serialized)
```

These tests exercise tool dispatch. Most will return `"no active database"` errors — which IS the correct behaviour when no database is selected, so it's still a valid assertion.

**Protocol handshake:**

| Test | Expects |
|---|---|
| `initialize` over HTTP returns valid MCP response | `protocolVersion == "2024-11-05"` |
| `tools/list` over HTTP returns 10 tools | `count == 10` |

**No-database error paths** (no Ditto instance needed):

| Tool | Expected error message |
|---|---|
| `execute_dql` with no query arg | `"Missing required argument: query"` |
| `execute_dql` with empty query | `"Missing required argument: query"` |
| `get_active_database` | `"No active database..."` |
| `list_databases` | returns `[]` (no error — reads SQLCipher, not Ditto) |
| `get_sync_status` | `"No active database..."` |
| `configure_transport` | `"No active database..."` |
| `create_index` with no collection arg | `"Missing required argument: collection"` |
| `create_index` with no field arg | `"Missing required argument: field"` |
| `drop_index` with no index_name arg | `"Missing required argument: index_name"` |
| Unknown tool name | `"Unknown tool: fake_tool"` |

### `MCPInsertFromFileTests.swift`

```
@Suite("MCP Insert From File Tests", .serialized)
```

These tests specifically cover the new `insert_documents_from_file` tool. They fall into two groups: **file/argument validation errors** (no database needed) and **happy path** (requires active database).

**Argument validation (no database needed):**

| Test | Arguments | Expects |
|---|---|---|
| Missing `file_path` | `{collection: "tasks"}` | `"Missing required argument: file_path"` |
| Missing `collection` | `{file_path: "/tmp/x.json"}` | `"Missing required argument: collection"` |
| Empty `file_path` | `{file_path: "", collection: "tasks"}` | `"Missing required argument: file_path"` |
| Empty `collection` | `{file_path: "/x.json", collection: ""}` | `"Missing required argument: collection"` |

**File I/O errors (no database needed — `ImportError` is thrown before DB access):**

| Test | File setup | Expects |
|---|---|---|
| File not found | Path to non-existent file | response contains `"Could not read file"` |
| Invalid JSON (not valid JSON) | Write `"not json"` to `~/Downloads/test_bad.json` | response contains `"File must contain an array"` |
| JSON object, not array | Write `{"_id":"a"}` to file | response contains `"File must contain an array"` |
| JSON array but missing `_id` | Write `[{"title":"x"}]` to file | response contains `"missing required '_id' field"` |
| Invalid collection name | Valid file, `collection: "bad name!"` | response contains `"invalid characters"` |

**File I/O test helper** (write temp file to `~/Downloads` since that's the only writable location):

```swift
static func withTempJSONFile(
    name: String = "mcp_test_\(UUID().uuidString).json",
    content: String,
    _ body: (String) async throws -> Void
) async throws {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Downloads/\(name)")
    try content.data(using: .utf8)!.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    try await body(url.path)
}
```

**Happy path (requires active database — mark as `.enabled(if:)` or skip with `withKnownIssue`):**

These tests only run when a Ditto database is active. Since integration tests don't set up a full Ditto instance, these are annotated to be skipped in CI and run manually:

```swift
@Test("Insert 3 documents from valid JSON file", .tags(.mcp, .external))
func testInsertValidFile() async throws {
    // Skip if no active database
    guard await DittoManager.shared.dittoSelectedApp != nil else {
        withKnownIssue("Requires active database") { Issue.record() }
        return
    }
    // ...
}
```

| Test | File content | Expects |
|---|---|---|
| Insert 3 documents (insert mode) | 3 objects each with `_id` | `inserted == 3`, `failed == 0` |
| Insert same documents again (insert_initial) | Same 3 objects | `inserted == 3`, `failed == 0` (no-op per INITIAL semantics) |
| Mixed valid/invalid batch | 2 valid + 1 missing `_id` | Error before any inserts (validateJSON throws) |
| Default mode is `insert` | No `mode` argument | Succeeds same as explicit `insert` |
| Large batch (150 docs) | 150 objects | `inserted == 150`, spans 3 batches of 50 |

---

## What Is NOT Tested Here

| Area | Why |
|---|---|
| `NWConnection` behaviour | Apple framework — trust it, don't mock it |
| SSE session keepalive timing | Timer behaviour, not business logic |
| `MCPSessionManager` SSE routing | Tested implicitly by server lifecycle tests |
| Tool handlers that need live Ditto (full happy path) | Marked `.external`, require manual run with real database |
| iOS build of MCP code | All MCP code is `#if os(macOS)` — iOS tests skip automatically |

---

## New Tags Needed

In both `TestTags.swift` files:

```swift
@Tag static var mcp: Tag          // All MCP tests
@Tag static var mcpServer: Tag    // Server lifecycle tests
@Tag static var mcpTools: Tag     // Tool manifest/dispatch tests
```

---

## Files to Create

| File | Target | Lines (est.) |
|---|---|---|
| `MCPHTTPParser.swift` | Edge Debug Helper (main app) | ~50 (refactor of existing) |
| `EdgeStudioUnitTests/MCP/MCPHTTPParserTests.swift` | Unit test target | ~100 |
| `EdgeStudioUnitTests/MCP/MCPJSONRPCHandlerTests.swift` | Unit test target | ~150 |
| `EdgeStudioUnitTests/MCP/MCPToolManifestTests.swift` | Unit test target | ~80 |
| `EdgeStudioIntegrationTests/MCP/MCPTestHelpers.swift` | Integration test target | ~60 |
| `EdgeStudioIntegrationTests/MCP/MCPServerLifecycleTests.swift` | Integration test target | ~100 |
| `EdgeStudioIntegrationTests/MCP/MCPToolExecutionTests.swift` | Integration test target | ~150 |
| `EdgeStudioIntegrationTests/MCP/MCPInsertFromFileTests.swift` | Integration test target | ~150 |

Total: ~840 lines across 8 files.

---

## Implementation Order

1. `MCPHTTPParser` refactor (unlocks parser unit tests)
2. Add tags to both `TestTags.swift` files
3. Unit tests (no server needed — run fast, validate logic)
4. `MCPTestHelpers.swift`
5. Integration tests (server lifecycle → tool execution → file insert)

The unit tests in steps 1-3 can be written and run immediately without any infrastructure changes.
