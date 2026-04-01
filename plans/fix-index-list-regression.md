# Fix: Collections Index List Regression (SwiftUI)

## Problem

When clicking the chevron to expand a collection in the sidebar, the index list never renders. The DisclosureGroup expands but shows nothing inside.

## Root Cause

The `DittoIndex` model in `DittoCollectionModel.swift` declares `fields` as `[String]`:

```swift
struct DittoIndex: Codable, Identifiable {
    let _id: String
    let collection: String
    let fields: [String]  // ← WRONG TYPE
}
```

But the Ditto SDK's `system:indexes` query returns each field entry as a **dictionary object**, not a plain string:

```json
{
    "_id": "myCollection.idx_myCollection_status",
    "collection": "myCollection",
    "fields": [
        { "direction": "asc", "key": ["`status`"] }
    ]
}
```

The `JSONDecoder` fails to decode `fields` as `[String]` because it's actually an array of dictionaries. The error is **silently swallowed** in `CollectionsRepository.swift:122-124`, so every `DittoIndex` decode fails and all collections end up with empty `indexes` arrays.

This was already discovered and fixed in the dotnet implementation (see `dotnet/plans/bug-fixes-index-ui-toolbar.md` and `dotnet/src/EdgeStudio.Shared/Data/Repositories/CollectionsRepository.cs:148-161`).

## Fix Plan

### Step 1: Update `DittoIndex` model (`EdgeStudio/Models/DittoCollectionModel.swift`)

Change `fields` from `[String]` to a type that matches the actual SDK response. Two approaches:

**Option A (Recommended): Custom decoding**

Add a nested `IndexField` struct and custom `init(from:)` to extract the field name from the dictionary:

```swift
struct DittoIndex: Codable, Identifiable {
    let _id: String
    let collection: String
    let fields: [String]  // Keep as [String] for display purposes
    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id, collection, fields
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        _id = try container.decode(String.self, forKey: ._id)
        collection = try container.decode(String.self, forKey: .collection)

        // SDK returns fields as [{"direction": "asc", "key": ["`fieldName`"]}]
        // We need to extract the field name from the "key" array
        var rawFields: [String] = []
        if let fieldDicts = try? container.decode([[String: AnyCodable]].self, forKey: .fields) {
            for dict in fieldDicts {
                if let keyArray = dict["key"]?.value as? [String],
                   let fieldName = keyArray.first {
                    rawFields.append(fieldName)
                }
            }
        } else if let stringFields = try? container.decode([String].self, forKey: .fields) {
            // Fallback: if fields ARE plain strings (future SDK changes)
            rawFields = stringFields
        }
        fields = rawFields
    }
}
```

**Option B (Simpler): Manual JSON parsing in `fetchIndexes`**

Instead of using `JSONDecoder` for `DittoIndex`, parse the JSON manually in `CollectionsRepository.fetchIndexes()` — similar to what the Android/Kotlin implementation does:

```swift
private func fetchIndexes(for collections: [DittoCollection]) async throws -> [String: [DittoIndex]] {
    guard let ditto = await dittoManager.dittoSelectedApp else {
        throw InvalidStateError(message: "No Ditto selected app available")
    }
    let results = try await ditto.store.execute(query: "SELECT * FROM system:indexes")
    var indexesByCollection: [String: [DittoIndex]] = [:]
    for item in results.items {
        let jsonData = item.jsonData()
        item.dematerialize()
        guard let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let id = json["_id"] as? String,
              let collection = json["collection"] as? String,
              let rawFields = json["fields"] as? [[String: Any]]
        else { continue }

        let fields = rawFields.compactMap { dict -> String? in
            guard let keyArray = dict["key"] as? [String] else { return nil }
            return keyArray.first
        }
        let index = DittoIndex(id: id, collection: collection, fields: fields)
        indexesByCollection[collection, default: []].append(index)
    }
    return indexesByCollection
}
```

With Option B, change `DittoIndex` to use a memberwise init instead of Codable:

```swift
struct DittoIndex: Identifiable {
    let _id: String
    let collection: String
    let fields: [String]
    var id: String { _id }

    init(id: String, collection: String, fields: [String]) {
        self._id = id
        self.collection = collection
        self.fields = fields
    }
}
```

### Step 2: Add logging to `fetchIndexes` (`EdgeStudio/Data/Repositories/CollectionsRepository.swift`)

Add `Log.error()` calls in the catch blocks so future decode failures are visible:

```swift
} catch {
    item.dematerialize()
    Log.error("Failed to decode index: \(error.localizedDescription)")
}
```

### Step 3: Secondary fix — Remove double-toggle Button in collection label (`EdgeStudio/Views/StudioView/SidebarViews.swift`)

The `DisclosureGroup` label wraps content in a `Button` that also toggles expand state via `formSymmetricDifference`. This duplicates the DisclosureGroup's built-in toggle and can cause double-toggle (expand + immediately collapse). 

Change the label's Button to instead set the selected query (like the old code did):

```swift
} label: {
    HStack {
        HStack(spacing: 8) {
            Image(systemName: "book.pages")
                .foregroundStyle(.secondary)
            Text(collection.name)
                .font(sidebarItemFont)
        }
        Spacer()
        if let count = collection.documentCount {
            // count badge...
        }
    }
    .contentShape(Rectangle())
    .onTapGesture {
        viewModel.selectedQuery = "SELECT * FROM \(collection.name)"
        viewModel.selectedSidebarMenuItem =
            viewModel.sidebarMenuItems.first { $0.name == "Query" }
                ?? viewModel.sidebarMenuItems[0]
    }
}
```

### Step 4: Build for both platforms

```bash
# macOS
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build

# iOS
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build
```

### Step 5: Manual verification

1. Launch app, connect to a database that has indexes
2. Click chevron on a collection → should show index names
3. Click chevron on an index → should show field names (without backticks)
4. Verify the refresh button still works
5. Verify new index creation still works and shows up in the tree

## Files to Modify

1. `SwiftUI/EdgeStudio/Models/DittoCollectionModel.swift` — Fix `DittoIndex` to handle dictionary-based fields
2. `SwiftUI/EdgeStudio/Data/Repositories/CollectionsRepository.swift` — Add error logging, potentially switch to manual JSON parsing
3. `SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift` — Fix double-toggle Button in DisclosureGroup label (secondary)

## Recommendation

**Option B** (manual JSON parsing in `fetchIndexes`) is recommended because:
- Matches the pattern used by Android and dotnet implementations
- More resilient to future SDK schema changes
- Avoids the complexity of a custom Codable conformance
- The field extraction logic is isolated in the repository where it belongs
