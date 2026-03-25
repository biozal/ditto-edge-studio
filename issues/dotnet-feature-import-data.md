# .NET: Missing Feature — Import Data into Database

## Platform
.NET / Avalonia UI

## Feature Description
The ability to import JSON data into a Ditto database collection. Users can load a JSON file (or paste JSON) and insert/upsert the documents into a specified collection.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Data/DittoManager_Import.swift` — Import functionality implementation
- `SwiftUI/Edge Debug Helper/Views/` — Import UI (file picker + collection selector)

## Current .NET Status
`EdgeStudioViewModel` has an `ImportJsonData` command wired to a menu/toolbar item, but the method body is completely empty — no file picker, no parsing, no SDK call is implemented.

## Expected Behavior
- User triggers "Import Data" from the toolbar or menu
- File picker opens to select a JSON file (array of objects or single object)
- User selects target collection name
- Data is inserted/upserted into the Ditto database
- Success/error feedback shown after import
- Imported documents appear immediately in the Collections browser

## Key Implementation Notes
- `ImportJsonData` command in `EdgeStudioViewModel.cs` is the right entry point — needs implementation
- Use Avalonia's `StorageProvider` for file picker (cross-platform file dialog)
- Parse JSON with `System.Text.Json`
- Insert via DQL: `INSERT INTO <collection> DOCUMENTS (<json>)` or equivalent Ditto SDK upsert API
- Handle both JSON arrays (multiple docs) and single JSON objects
- Validate JSON before attempting import

## Acceptance Criteria
- [ ] Import Data menu/toolbar item opens a file picker
- [ ] Supports JSON files containing a single document or array of documents
- [ ] User can specify or confirm the target collection
- [ ] Documents are successfully inserted into the database
- [ ] Success message shows count of imported documents
- [ ] Error message shown if JSON is invalid or import fails
- [ ] Imported documents appear in the Collections browser immediately
