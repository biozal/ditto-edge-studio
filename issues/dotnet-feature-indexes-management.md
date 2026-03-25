# .NET: Missing Feature — Indexes Management

## Platform
.NET / Avalonia UI

## Feature Description
The ability to view, create, and drop indexes on Ditto collections. Users can see what indexes currently exist on a collection and add new indexes to improve query performance, or drop indexes that are no longer needed.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Views/` — Indexes panel in the Inspector
- `SwiftUI/Edge Debug Helper/Data/MCPServer/MCPToolHandlers.swift` — `create_index` and `drop_index` MCP tools show the underlying SDK calls
- Collections repository exposes index data alongside collection metadata

## Current .NET Status
`IndexesToolView.axaml` exists and shows in the Inspector panel, but displays only static "No indexes available" text. `IndexesToolViewModel.cs` is an empty class with no implementation — no data loading, no create, no drop functionality.

## Expected Behavior
- List all indexes for the currently selected collection
- Allow users to create a new index by specifying collection name and index fields
- Allow users to drop an existing index
- Refresh index list after create/drop operations
- Show index details (fields, type)

## Key Implementation Notes
- Ditto SDK: use `ditto.Store.ExecuteAsync("CREATE INDEX ...")` or equivalent DQL
- Drop: `ditto.Store.ExecuteAsync("DROP INDEX ...")` or equivalent
- The MCP tool handlers in the SwiftUI project show exact DQL syntax for create/drop
- `IndexesToolViewModel` needs to be wired to the active database and selected collection

## Acceptance Criteria
- [ ] Indexes tab in Inspector shows all indexes for the selected collection
- [ ] "Create Index" action allows specifying collection and fields
- [ ] "Drop Index" action removes the selected index with confirmation
- [ ] Index list refreshes automatically after create/drop
- [ ] Empty state shown when no indexes exist (not just static text)
- [ ] Error handling shown if index creation/drop fails
