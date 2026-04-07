# Delete Attachment Fields — Design Spec

**Date:** 2026-04-06
**Platforms:** .NET (Avalonia), SwiftUI (macOS/iPadOS)

## Context

Edge Studio supports adding attachments to Ditto documents but provides no way to remove them. Users need the ability to delete attachment fields from documents through the existing right-click context menu on query results.

## User Flow

1. User right-clicks a document in query results (JSON or Table view)
2. Context menu shows "Delete Attachment..." — **disabled** if the document has no attachment tokens
3. User clicks "Delete Attachment..."
4. A dialog/sheet appears listing all attachment fields with checkboxes
5. User selects which fields to delete, then clicks **Delete** or **Cancel**
6. On Delete: app executes `UPDATE <collection> SET <field> = null WHERE _id = '<docId>'` for each selected field
7. Success toast shown; on error, error toast/alert shown
8. User re-runs query manually to see updated document

## Attachment Detection

Both platforms reuse existing token detection:
- **.NET:** `AttachmentInfo.DetectTokens(jsonString)` in `EdgeStudio.Shared/Models/AttachmentInfo.cs`
- **SwiftUI:** `AttachmentInfo.detectTokens(in: jsonString)` in `Models/AttachmentInfo.swift`

A document has attachment fields when `DetectTokens` returns a non-empty list. Each `AttachmentInfo` provides `FieldName`, `FileName`, `FormattedSize`, and `MimeType` for display.

## .NET (Avalonia) Implementation

### Context Menu Changes

**Files:** `JsonResultsView.axaml`, `TableResultsView.axaml`

Add a "Delete Attachment..." `MenuItem` after "Add Attachment...":

```xml
<Separator />
<MenuItem Header="Delete Attachment..."
          Command="..."
          CommandParameter="{Binding}"
          IsEnabled="{Binding ???}" />
```

The menu item is always visible but disabled when the document contains no attachment tokens. Since detection requires parsing JSON, the `IsEnabled` binding will call `AttachmentInfo.DetectTokens()` on the document JSON and check for any results.

### ViewModel Event Chain

Follow the existing "Add Attachment" pattern:

1. **JsonResultsViewModel / TableResultsViewModel:** Add `DeleteAttachmentRequested` event and `DeleteAttachmentCommand`
2. **QueryDocumentViewModel:** Subscribe to the event, send `DeleteAttachmentRequestedMessage`
3. **EdgeStudioViewModel:** Receive message, open dialog, execute deletion

### New Message

**File:** `EdgeStudio.Shared/Messages/AttachmentMessages.cs`

```csharp
public record DeleteAttachmentRequestedMessage(string DocumentJson, string Collection, string QueryMode);
```

### New Dialog: DeleteAttachmentWindow

**Files:** `EdgeStudio/Views/DeleteAttachmentWindow.axaml` + `.axaml.cs`

A `SukiWindow` dialog following the `AttachmentPickerWindow` pattern:

- **Header:** "Delete Attachment Fields" with collection and document ID display
- **Body:** List of attachment fields, each with a checkbox, showing: field name (bold), file name, size, mime type
- **Footer:** Cancel and Delete buttons
- **Properties returned:** `List<AttachmentInfo> SelectedAttachments`, `bool Confirmed`
- Delete button disabled until at least one field is selected

### Deletion Execution

**File:** `EdgeStudioViewModel.cs` — new handler method

```
For each selected AttachmentInfo:
    dql = "UPDATE {collection} SET {fieldName} = null WHERE _id = '{docId}'"
    await queryService.ExecuteLocalAsync(dql)
Show success toast: "Deleted {count} attachment field(s)"
On error: show error toast with message
```

Field names are validated against `SafeIdentifier` regex (already exists in AttachmentService) to prevent injection.

## SwiftUI Implementation

### Context Menu Changes

**Files:** `ResultJsonViewer.swift`, `ResultTableViewer.swift`

Add "Delete Attachment..." button to existing context menus:

```swift
Button("Delete Attachment...") {
    onDeleteAttachment?(jsonString)
}
.disabled(AttachmentInfo.detectTokens(in: jsonString).isEmpty)
```

### Callback Chain

Follow the existing "Add Attachment" pattern:

1. **ResultJsonViewer / ResultTableViewer:** Add `onDeleteAttachment` callback parameter
2. **QueryResultsView:** Propagate `onDeleteAttachment` callback
3. **DetailViews.queryDetailView:** Wire callback to ViewModel method
4. **MainStudioView ViewModel:** `requestDeleteAttachment(documentJson:)` sets state and shows sheet

### New Sheet: DeleteAttachmentSheet

**File:** `EdgeStudio/Components/DeleteAttachmentSheet.swift`

A SwiftUI sheet following the `AttachmentPickerSheet` pattern:

- **Header:** "Delete Attachment Fields" with collection and document ID
- **Body:** `List` with `Toggle` for each detected attachment field, showing: field name, file name, size, mime type
- **Footer:** Cancel and Delete buttons
- Delete button disabled until at least one field is toggled on
- `onConfirm` callback returns selected `[AttachmentInfo]`

### Deletion Execution

**File:** `MainStudioView.swift` — new ViewModel method `executeDeleteAttachment`

```
For each selected AttachmentInfo:
    query = "UPDATE \(collection) SET \(fieldName) = null WHERE _id = :docId"
    await ditto.store.execute(query: query, arguments: ["docId": documentId])
On error: show error via AppState
```

### Sheet Presentation

**File:** `MainStudioView.swift`

Add `.sheet(isPresented: $viewModel.showDeleteAttachmentPicker)` alongside the existing attachment picker sheet.

## Security

- Field names validated against identifier regex before building DQL to prevent injection
- Document IDs passed as query arguments (`:docId`) where possible, not string-interpolated

## Testing

### .NET Tests (EdgeStudioTests/AttachmentTests.cs)

- `DeleteAttachmentRequestedMessage` created with correct properties
- Dialog correctly detects and lists attachment fields from JSON
- DQL generation produces correct UPDATE statements
- SafeIdentifier validation rejects malicious field names

### SwiftUI Tests (EdgeStudioUnitTests)

- `AttachmentInfo.detectTokens` correctly identifies fields (existing tests cover this)
- DQL generation produces correct UPDATE statements
- Field name validation works
