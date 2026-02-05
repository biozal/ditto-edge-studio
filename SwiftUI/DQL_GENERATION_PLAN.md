# DQL Auto-Generation Feature - Implementation Plan

## Overview

Add DQL (Ditto Query Language) auto-generation capabilities to help users write queries faster by generating boilerplate code based on previously executed queries, collection names, and field names discovered in results.

**Estimated Time:** Phase 1 (MVP) = 3-4 hours

## User Goals

**Problem:** Writing DQL queries from scratch is time-consuming and requires remembering exact syntax and field names.

**Solution:** Auto-generate DQL statement templates for SELECT, INSERT, UPDATE, DELETE, and EVICT operations.

**User Workflow:**
1. User executes: `SELECT * FROM crewMembers`
2. Results show fields: `_id`, `name`, `age`, `rank`, `aircraftId`
3. User clicks "Generate DQL" button → menu appears
4. Selects "UPDATE template" → copies to clipboard:
   ```sql
   UPDATE crewMembers SET name = '<value>', age = 0, rank = '<value>', aircraftId = '<value>' WHERE _id = '<document-id>'
   ```
5. User pastes into query editor, fills in actual values, executes

## Implementation Phases

### Phase 1: MVP (Implement First) - ~3-4 hours
**Goal:** Basic DQL generation with clipboard copy

1. Create `DQLGenerator.swift` service with all 5 statement types
2. Add unit tests for `DQLGenerator`
3. Add `onGetLastQuery` callback to `QueryResultsView`
4. Add "Generate DQL" button to footer with menu
5. Implement generation logic (extract collection, extract fields)
6. Implement clipboard copy with notification
7. Update `MainStudioView` to pass callback
8. Manual testing with various queries

### Phase 2: Enhanced UX (Optional) - ~2 hours
- Add context menu on collections in sidebar
- Add "Insert into editor" option (directly set `viewModel.selectedQuery`)
- Better error handling for edge cases
- Add keyboard shortcuts (Cmd+G for Generate DQL?)

### Phase 3: Advanced Features (Future) - ~4-6 hours
- Right-click on table rows → generate with actual values
- Multi-select fields → generate SELECT with only selected
- Generate with WHERE clause builder
- Save generated queries to favorites automatically

## Architecture

### Data Flow
```
User clicks "Generate DQL" button
    ↓
QueryResultsView extracts:
    - Collection name from selectedQuery (via callback)
    - Field names from jsonResults
    ↓
DQLGenerator.generate[Select|Insert|Update|Delete|Evict]()
    ↓
Copy to clipboard + show toast notification
    ↓
User pastes into query editor
```

### Key Components
- **DQLGenerator** (`Data/DQLGenerator.swift`) - Core service with static methods
- **QueryResultsView** (`Components/QueryResultsView.swift`) - UI integration
- **QueryInfo** (`Models/SmallPeerInfoModels.swift`) - Collection name parsing (already exists!)

## Files to Create

### 1. DQLGenerator Service
**File:** `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Data/DQLGenerator.swift`

```swift
import Foundation

struct DQLGenerator {

    // MARK: - SELECT Statement

    static func generateSelect(collection: String, fields: [String]) -> String {
        let fieldList = fields.joined(separator: ", ")
        return "SELECT \(fieldList) FROM \(collection)"
    }

    static func generateSelectAll(collection: String) -> String {
        return "SELECT * FROM \(collection)"
    }

    // MARK: - INSERT Statement

    static func generateInsert(collection: String, fields: [String], fieldTypes: [String: TableCellValue]? = nil) -> String {
        let placeholders = fields.map { field in
            let placeholder = placeholderValue(for: field, type: fieldTypes?[field])
            return "\"\(field)\": \(placeholder)"
        }.joined(separator: ", ")

        return "INSERT INTO \(collection) DOCUMENTS ({ \(placeholders) })"
    }

    // MARK: - UPDATE Statement

    static func generateUpdate(collection: String, fields: [String], fieldTypes: [String: TableCellValue]? = nil) -> String {
        // Exclude _id from SET clause
        let fieldsToUpdate = fields.filter { $0 != "_id" }

        let setClause = fieldsToUpdate.map { field in
            let placeholder = placeholderValue(for: field, type: fieldTypes?[field])
            return "\(field) = \(placeholder)"
        }.joined(separator: ", ")

        return "UPDATE \(collection) SET \(setClause) WHERE _id = '<document-id>'"
    }

    // MARK: - DELETE Statement

    static func generateDelete(collection: String) -> String {
        return "DELETE FROM \(collection) WHERE _id = '<document-id>'"
    }

    // MARK: - EVICT Statement

    static func generateEvict(collection: String) -> String {
        return "EVICT FROM \(collection) WHERE _id = '<document-id>'"
    }

    // MARK: - Helper Methods

    private static func placeholderValue(for field: String, type: TableCellValue?) -> String {
        if field == "_id" {
            return "\"<document-id>\""
        }

        if let type = type {
            switch type {
            case .string: return "\"<value>\""
            case .number: return "0"
            case .bool: return "true"
            case .null: return "null"
            case .nested: return "{}"
            }
        }

        return "\"<value>\""
    }
}
```

### 2. Unit Tests
**File:** `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper Tests/DQLGeneratorTests.swift`

```swift
import Testing
@testable import Edge_Debug_Helper

@Test("Generate SELECT with all fields")
func testGenerateSelect() {
    let dql = DQLGenerator.generateSelect(
        collection: "crewMembers",
        fields: ["_id", "name", "age", "rank"]
    )
    #expect(dql == "SELECT _id, name, age, rank FROM crewMembers")
}

@Test("Generate INSERT with placeholders")
func testGenerateInsert() {
    let dql = DQLGenerator.generateInsert(
        collection: "crewMembers",
        fields: ["_id", "name", "age"]
    )
    #expect(dql.contains("INSERT INTO crewMembers DOCUMENTS"))
    #expect(dql.contains("\"_id\": \"<document-id>\""))
}

@Test("Generate UPDATE excluding _id from SET")
func testGenerateUpdate() {
    let dql = DQLGenerator.generateUpdate(
        collection: "crewMembers",
        fields: ["_id", "name", "age"]
    )
    #expect(dql.contains("UPDATE crewMembers SET"))
    #expect(!dql.contains("SET _id"))
    #expect(dql.contains("WHERE _id = '<document-id>'"))
}

@Test("Generate DELETE with WHERE clause")
func testGenerateDelete() {
    let dql = DQLGenerator.generateDelete(collection: "crewMembers")
    #expect(dql == "DELETE FROM crewMembers WHERE _id = '<document-id>'")
}

@Test("Generate EVICT with WHERE clause")
func testGenerateEvict() {
    let dql = DQLGenerator.generateEvict(collection: "crewMembers")
    #expect(dql == "EVICT FROM crewMembers WHERE _id = '<document-id>'")
}
```

## Files to Modify

### 1. QueryResultsView.swift
**File:** `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Components/QueryResultsView.swift`

**Changes:**

#### A. Add callback parameter
```swift
struct QueryResultsView: View {
    @Binding var jsonResults: [String]
    var onGetLastQuery: (() -> String)? = nil  // NEW

    @State private var copiedDQLNotification: String? = nil  // NEW
```

#### B. Add Generate DQL button to footer
```swift
private var paginationFooter: some View {
    HStack {
        Spacer()
        PaginationControls(...)
        Spacer()

        // NEW: Generate DQL Button
        generateDQLButton

        // Existing Export Button
        Button { isExporting = true } label: {
            Image(systemName: "square.and.arrow.down")
        }
        ...
    }
}

private var generateDQLButton: some View {
    Menu {
        Button("SELECT with all fields") { generateAndCopy(.select) }
        Button("INSERT template") { generateAndCopy(.insert) }
        Button("UPDATE template") { generateAndCopy(.update) }
        Button("DELETE template") { generateAndCopy(.delete) }
        Button("EVICT template") { generateAndCopy(.evict) }
    } label: {
        Label("Generate DQL", systemImage: "chevron.left.forwardslash.chevron.right")
    }
    .disabled(jsonResults.isEmpty)
    .help("Generate DQL statement templates based on query results")
    .padding(.trailing, 8)
}
```

#### C. Add generation logic
```swift
private enum DQLStatementType {
    case select, insert, update, delete, evict
}

private func generateAndCopy(_ type: DQLStatementType) {
    // 1. Get last executed query
    guard let lastQuery = onGetLastQuery?() else {
        showNotification("No query available")
        return
    }

    // 2. Extract collection name
    let queryInfo = QueryInfo(query: lastQuery)
    guard let collectionName = queryInfo.collectionName else {
        showNotification("Could not extract collection name from query")
        return
    }

    // 3. Get field names from first JSON result
    let fieldNames = extractFieldNamesFromJSON()

    // 4. Generate DQL
    let dql: String
    switch type {
    case .select:
        dql = DQLGenerator.generateSelect(collection: collectionName, fields: fieldNames)
    case .insert:
        dql = DQLGenerator.generateInsert(collection: collectionName, fields: fieldNames)
    case .update:
        dql = DQLGenerator.generateUpdate(collection: collectionName, fields: fieldNames)
    case .delete:
        dql = DQLGenerator.generateDelete(collection: collectionName)
    case .evict:
        dql = DQLGenerator.generateEvict(collection: collectionName)
    }

    // 5. Copy to clipboard
    copyToClipboard(dql)
    showNotification("DQL copied to clipboard")
}

private func extractFieldNamesFromJSON() -> [String] {
    guard let firstResult = jsonResults.first,
          let jsonData = firstResult.data(using: .utf8),
          let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
        return []
    }

    // Sort: _id first, then alphabetically
    var keys = Array(jsonObject.keys).sorted()
    if let idIndex = keys.firstIndex(of: "_id") {
        keys.remove(at: idIndex)
        keys.insert("_id", at: 0)
    }
    return keys
}

private func copyToClipboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #else
    UIPasteboard.general.string = text
    #endif
}

private func showNotification(_ message: String) {
    copiedDQLNotification = message
    Task {
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await MainActor.run {
            copiedDQLNotification = nil
        }
    }
}
```

#### D. Add notification overlay
```swift
var body: some View {
    VStack(spacing: 0) {
        TabView(selection: $selectedTab) { ... }
        paginationFooter
    }
    .overlay(alignment: .top) {
        if let message = copiedDQLNotification {
            Text(message)
                .padding()
                .background(Color.green.opacity(0.9))
                .foregroundColor(.white)
                .cornerRadius(8)
                .padding(.top, 20)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
```

### 2. MainStudioView.swift
**File:** `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Views/MainStudioView.swift`

**Find `queryDetailView()` method (around line 941):**

**Change from:**
```swift
QueryResultsView(
    jsonResults: $viewModel.jsonResults
)
```

**To:**
```swift
QueryResultsView(
    jsonResults: $viewModel.jsonResults,
    onGetLastQuery: { viewModel.selectedQuery }
)
```

## DQL Statement Examples

Based on query: `SELECT * FROM crewMembers`
With results: `_id`, `name`, `age`, `rank`, `aircraftId`

**SELECT:**
```sql
SELECT _id, name, age, rank, aircraftId FROM crewMembers
```

**INSERT:**
```sql
INSERT INTO crewMembers DOCUMENTS ({ "_id": "<document-id>", "name": "<value>", "age": 0, "rank": "<value>", "aircraftId": "<value>" })
```

**UPDATE:**
```sql
UPDATE crewMembers SET name = "<value>", age = 0, rank = "<value>", aircraftId = "<value>" WHERE _id = '<document-id>'
```

**DELETE:**
```sql
DELETE FROM crewMembers WHERE _id = '<document-id>'
```

**EVICT:**
```sql
EVICT FROM crewMembers WHERE _id = '<document-id>'
```

## Testing Strategy

### Manual Testing Scenarios

**Test 1: Basic SELECT**
1. Execute: `SELECT * FROM crewMembers`
2. Click "Generate DQL" → "SELECT with all fields"
3. ✓ Clipboard contains field names
4. ✓ Notification shows "DQL copied to clipboard"

**Test 2: INSERT Template**
1. Execute: `SELECT * FROM aircraft`
2. Click "Generate DQL" → "INSERT template"
3. ✓ Has all field names with placeholders

**Test 3: UPDATE Template**
1. Execute: `SELECT * FROM statusUpdates`
2. Click "Generate DQL" → "UPDATE template"
3. ✓ `_id` NOT in SET clause
4. ✓ `_id` IS in WHERE clause

**Test 4: Complex Query**
1. Execute: `SELECT name FROM crewMembers WHERE age > 30`
2. Click "Generate DQL" → any option
3. ✓ Collection name is "crewMembers" (WHERE doesn't affect it)

### Build Commands
```bash
# Build
xcodebuild -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build

# Run tests
xcodebuild -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" test
```

## Edge Cases

1. **No query executed yet:** Button disabled (jsonResults.isEmpty)
2. **Collection name not extractable:** Show error notification
3. **Empty field names:** Fallback to `SELECT * FROM collection`
4. **Mutation results:** Works (generates templates based on result fields)
5. **System collections:** Works normally

## Success Criteria - Phase 1

- ✓ DQLGenerator service created with all 5 methods
- ✓ Unit tests pass (5+ tests)
- ✓ Generate DQL button in QueryResultsView footer
- ✓ Menu shows all 5 statement types
- ✓ Generates DQL and copies to clipboard
- ✓ Visual notification confirms copy
- ✓ Uses actual collection name from query
- ✓ Uses actual field names from results
- ✓ Smart placeholders (strings vs numbers)
- ✓ _id excluded from UPDATE SET clause
- ✓ Zero build warnings

## Future Enhancements (Phase 2 & 3)

- Context menu on collections in sidebar
- "Insert into editor" option (not just clipboard)
- Right-click table rows → generate with actual values
- Multi-select fields → SELECT with only selected
- Query builder UI
- Smart suggestions based on history
- Keyboard shortcuts (Cmd+G)

## Notes

1. **Collection name extraction** already exists in `QueryInfo.collectionName`
2. **Clipboard code** can be reused from `ResultTableViewer.swift`
3. **Keep it simple** - Phase 1 focuses on core functionality only
4. **Performance** - Generation should be instant (<100ms)
5. **Manual testing critical** - Automated tests won't catch UX issues
