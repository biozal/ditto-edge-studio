# Android: Missing Feature — Import Data into Database

## Platform
Android

## Feature Description
The ability to import JSON data into a Ditto database collection. Users select a JSON file and insert/upsert documents into a specified collection.

## SwiftUI Implementation Reference
- `SwiftUI/Edge Debug Helper/Data/DittoManager_Import.swift` — Core import logic
- Accessible from the toolbar/FAB menu

## Current Android Status
The FAB (floating action button) menu shows "Import JSON" and "Import Subscriptions" buttons. Tapping them calls `onExpandChange(false)` (closes the FAB menu) but performs no actual action — the import functionality is not implemented.

## Expected Behavior
- Tapping "Import JSON" opens a file picker for JSON files
- User selects target collection name
- JSON documents (single object or array) are inserted/upserted into the database
- Success feedback shows count of imported documents
- Error feedback shown for invalid JSON or failed imports
- Imported documents appear in the Collections browser immediately

## Key Implementation Notes
- FAB "Import JSON" button already exists — needs real handler
- Use Android `ActivityResultContracts.GetContent` or `OpenDocument` for file picker
- Parse JSON with `kotlinx.serialization` or `org.json`
- Insert via DQL: `INSERT INTO <collection> DOCUMENTS (<json>)` or Ditto SDK upsert API
- Handle both single JSON object and JSON array inputs
- "Import Subscriptions" may be a separate feature — import a list of subscription queries from a JSON/text file

## Acceptance Criteria
- [ ] "Import JSON" FAB button opens a file picker
- [ ] Supports JSON files with a single document or array of documents
- [ ] User can specify or confirm the target collection
- [ ] Documents are inserted into the database successfully
- [ ] Success toast/message shows count of imported documents
- [ ] Error message shown for invalid JSON or import failure
- [ ] Imported documents appear in Collections browser immediately
