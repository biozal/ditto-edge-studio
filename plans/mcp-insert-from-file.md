# Plan: MCP `insert_documents_from_file` Tool

**Status:** Ready for Review
**Scope:** `MCPToolHandlers.swift` only — no other files need to change

---

## Overview

Add a new MCP tool `insert_documents_from_file` that lets an AI agent seed a Ditto collection from a local JSON file. The tool delegates entirely to the existing `ImportService`, which already handles batching (50 docs/batch), `deserialize_json()` parameterised queries, INSERT vs INSERT INITIAL, fallback to per-document inserts on batch failure, and collection name validation.

---

## DQL Syntax (confirmed from docs + ImportService)

```sql
-- Regular insert (upsert on conflict)
INSERT INTO tasks
DOCUMENTS (deserialize_json(:doc0)), (deserialize_json(:doc1)), ...
ON ID CONFLICT DO UPDATE

-- Initial insert (no-op if _id already exists)
INSERT INTO tasks
INITIAL DOCUMENTS (deserialize_json(:doc0)), (deserialize_json(:doc1)), ...
```

Both are already implemented in `ImportService.buildBatchInsertQuery()` and `buildSingleInsertQuery()`.

---

## New Tool: `insert_documents_from_file`

### Input Schema

| Argument | Type | Required | Description |
|---|---|---|---|
| `file_path` | string | ✅ | Absolute path to the JSON file on the local machine |
| `collection` | string | ✅ | Target collection name (letters, numbers, underscores only) |
| `mode` | string | ❌ | `"insert"` (default, upsert) or `"insert_initial"` (skip if `_id` exists) |

### Accepted JSON File Format

`ImportService.validateJSON` requires a **JSON array of objects, each with an `_id` field**:

```json
[
  { "_id": "abc123", "title": "Buy groceries", "done": false, "deleted": false },
  { "_id": "def456", "title": "Fix login bug",  "done": true,  "deleted": false }
]
```

> Documents without `_id` will be rejected by `validateJSON` with a clear error message.

### Return Value

```json
{
  "inserted": 8,
  "failed": 2,
  "mode": "insert_initial",
  "collection": "tasks",
  "errors": [
    "Document abc123: duplicate _id ..."
  ]
}
```

---

## Implementation Plan

### Step 1 — Add tool definition to `allTools`

Append to the `allTools` array in `MCPToolHandlers.swift`:

```swift
MCPTool(
    name: "insert_documents_from_file",
    description: """
        Insert documents from a local JSON file into a Ditto collection. \
        The file must contain a JSON array of objects; each object must have an '_id' field. \
        Use mode 'insert' (default) to upsert on conflict, or 'insert_initial' to \
        skip documents whose '_id' already exists in the collection.
        """,
    inputSchema: [
        "type": "object",
        "properties": [
            "file_path": [
                "type": "string",
                "description": "Absolute path to the JSON file on the local filesystem (e.g. '/Users/you/tasks.json')"
            ],
            "collection": [
                "type": "string",
                "description": "Target collection name — letters, numbers, and underscores only"
            ],
            "mode": [
                "type": "string",
                "enum": ["insert", "insert_initial"],
                "description": "'insert' upserts on conflict (default). 'insert_initial' skips documents whose _id already exists."
            ]
        ],
        "required": ["file_path", "collection"]
    ]
)
```

### Step 2 — Add dispatch case

```swift
case "insert_documents_from_file": return try await insertDocumentsFromFile(arguments: arguments)
```

### Step 3 — Implement the handler

```swift
private static func insertDocumentsFromFile(arguments: [String: Any]) async throws -> String {
    // 1. Extract and validate arguments
    guard let filePath = arguments["file_path"] as? String, !filePath.isEmpty else {
        throw MCPError.missingArgument("file_path")
    }
    guard let collection = arguments["collection"] as? String, !collection.isEmpty else {
        throw MCPError.missingArgument("collection")
    }
    let modeString = arguments["mode"] as? String ?? "insert"
    let insertType: ImportService.InsertType = modeString == "insert_initial" ? .initial : .regular

    // 2. Build a plain file URL (startAccessingSecurityScopedResource is a no-op for
    //    non-security-scoped URLs and returns true, so importData works with plain paths)
    let url = URL(fileURLWithPath: filePath)

    // 3. Delegate to ImportService — it handles batching, deserialize_json,
    //    fallback to per-document inserts, and collection name validation
    let result = try await MainActor.run {
        try await ImportService.shared.importData(
            from: url,
            to: collection,
            insertType: insertType,
            progressHandler: { _ in }   // progress not needed for MCP
        )
    }

    // 4. Return JSON summary
    let summary: [String: Any] = [
        "inserted":   result.successCount,
        "failed":     result.failureCount,
        "mode":       modeString,
        "collection": collection,
        "errors":     result.errors
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: summary, options: .prettyPrinted),
          let json = String(data: data, encoding: .utf8) else
    {
        return "Inserted \(result.successCount) documents, \(result.failureCount) failed."
    }
    return json
}
```

---

## Why `importData` Works with a Plain File Path

`ImportService.importData(from:)` calls `url.startAccessingSecurityScopedResource()` before reading. Per Apple's documentation, this method returns `true` and has no effect for URLs that are **not** security-scoped bookmarks — which is the case for any plain `URL(fileURLWithPath:)`. So no changes to `ImportService` are needed.

---

## Error Handling

All error cases are already handled by `ImportService` and will surface as thrown errors to `MCPJSONRPCHandler`, which wraps them in an MCP error response:

| Scenario | Error thrown by |
|---|---|
| File not found / unreadable | `ImportError.fileAccessDenied` |
| Not a JSON array | `ImportError.invalidJSON` |
| Document missing `_id` | `ImportError.missingID` |
| Invalid collection name | `ImportError.invalidCollectionName` |
| No active database | `ImportError.noDittoInstance` |
| Per-document DQL failure | Collected in `ImportResult.errors` (non-fatal) |

---

## Files Changed

| File | Change |
|---|---|
| `Edge Debug Helper/Data/MCPServer/MCPToolHandlers.swift` | +1 tool in `allTools`, +1 case in `execute()`, +1 private method (~25 lines) |

`ImportService.swift` — **no changes needed.**

---

## Out of Scope (v1)

- No streaming progress over MCP
- No CSV/NDJSON support
- Documents without `_id` are rejected (same constraint as the UI importer)
