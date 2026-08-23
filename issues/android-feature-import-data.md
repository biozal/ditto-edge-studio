# Android Feature: Import JSON Data

**Priority:** High  
**Complexity:** Medium  
**Status:** Not Started  
**Platforms with feature:** SwiftUI  

## Summary

Android is missing the ability to import JSON data files into Ditto collections. SwiftUI (`ImportDataView.swift` + `ImportService.swift`) supports importing JSON arrays of documents into existing or new collections with batch processing, progress tracking, and error recovery.

## Current State in Android

- No import data UI exists
- No import service exists
- The FAB menu in `MainStudioScreen.kt` does not have an "Import JSON Data" option
- `QueryExecutionService.kt` supports `execute()` and `explain()` but has no batch insert logic

## What Needs to Be Built

### 1. Import Service

```kotlin
// New file: data/service/ImportService.kt

data class ImportProgress(
    val current: Int,
    val total: Int,
    val currentDocumentId: String? = null
)

data class ImportResult(
    val successCount: Int,
    val failureCount: Int,
    val errors: List<String>
)

enum class InsertType {
    REGULAR,        // ON ID CONFLICT DO UPDATE
    INITIAL         // WITH INITIAL DOCUMENTS (first-time import)
}

class ImportService(private val dittoManager: DittoManager) {
    
    suspend fun importData(
        jsonContent: String,
        collection: String,
        insertType: InsertType = InsertType.REGULAR,
        onProgress: (ImportProgress) -> Unit
    ): ImportResult
}
```

**Batch processing strategy (from SwiftUI's ImportService.swift):**
- Fixed batch size: **50 documents per batch**
- Uses parameterized DQL queries with `deserialize_json(:docN)` placeholders
- Regular insert query: `INSERT INTO collection DOCUMENTS (deserialize_json(:doc0)), ... ON ID CONFLICT DO UPDATE`
- Initial insert query: `INSERT INTO collection INITIAL DOCUMENTS (deserialize_json(:doc0)), ...`
- If a batch fails, falls back to individual document insertion to identify which docs failed
- Returns combined `ImportResult` with success/failure counts and per-document error messages

**Validation requirements:**
- Input must be a JSON array of objects `[{...}, {...}]`
- Each object must have an `_id` field
- Collection name: letters, numbers, underscores only

### 2. Import Data Dialog/Sheet

```kotlin
// New file: ui/mainstudio/ImportDataSheet.kt

@Composable
fun ImportDataSheet(
    collections: List<DittoCollection>,
    onImport: suspend (uri: Uri, collection: String, insertType: InsertType, onProgress: (ImportProgress) -> Unit) -> ImportResult,
    onDismiss: () -> Unit
)
```

**UI Layout (matching SwiftUI's ImportDataView.swift):**

```
┌─────────────────────────────────────────┐
│ Import JSON Data                        │
├─────────────────────────────────────────┤
│                                         │
│ Select JSON File                        │
│ ┌─────────────────────────────────────┐ │
│ │ filename.json              [Choose] │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Target Collection                       │
│ ○ Existing Collection  ○ New Collection │
│ ┌─────────────────────────────────────┐ │
│ │ [Dropdown / Text Input]             │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ Insert Type                             │
│ ┌─────────────────────────────────────┐ │
│ │ [Switch] Use Initial Documents      │ │
│ │ (info text when enabled)            │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─ Progress (during import) ──────────┐ │
│ │ ████████░░░░░░  45 of 200           │ │
│ │ Current: doc_abc123...              │ │
│ └─────────────────────────────────────┘ │
│                                         │
│ ┌─ Result (after import) ─────────────┐ │
│ │ ✓ Successfully imported 198 docs    │ │
│ │ ✗ 2 documents failed                │ │
│ └─────────────────────────────────────┘ │
│                                         │
│              [Cancel]  [Import]         │
└─────────────────────────────────────────┘
```

**State flow:**
1. User taps "Choose" → Android file picker via `ActivityResultContracts.OpenDocument` with `application/json` MIME type
2. File selected → display filename, enable collection selection
3. User picks existing collection (dropdown) or enters new name
4. User toggles insert type (Regular vs Initial)
5. User taps "Import" → show linear progress bar with "Importing X of Y" text
6. On completion → show success/error summary with counts
7. On error → show scrollable error details with copy button

### 3. Integration into MainStudioScreen

**Entry point:** Add "Import JSON Data" to the FAB menu in `MainStudioScreen.kt`

The SwiftUI version triggers import from a circular yellow plus button menu. The Android FAB already exists — add an import option:

```kotlin
// In MainStudioScreen.kt FAB menu
DropdownMenuItem(
    text = { Text("Import JSON Data") },
    leadingIcon = { Icon(Icons.Default.Upload, contentDescription = null) },
    onClick = { showImportSheet = true }
)
```

Present as a `ModalBottomSheet` (consistent with Android's existing editor patterns like `SubscriptionEditorSheet.kt`).

### 4. ViewModel Integration

Add to `MainStudioViewModel.kt`:

```kotlin
// State
var showImportSheet by mutableStateOf(false)

// Method
suspend fun importJsonData(
    context: Context,
    uri: Uri,
    collection: String,
    insertType: InsertType,
    onProgress: (ImportProgress) -> Unit
): ImportResult {
    val inputStream = context.contentResolver.openInputStream(uri)
    val jsonContent = inputStream?.bufferedReader()?.readText() ?: throw Exception("Cannot read file")
    return importService.importData(jsonContent, collection, insertType, onProgress)
}
```

## Key Reference Files

### SwiftUI
- `SwiftUI/EdgeStudio/Components/ImportDataView.swift` — Full import UI with file picker, collection selection, insert type toggle, progress, error display
- `SwiftUI/EdgeStudio/Data/ImportService.swift` — Core import logic with batch processing (50 docs/batch), parameterized DQL queries, fallback to individual inserts
- `SwiftUI/EdgeStudio/Views/MainStudioView.swift` — FAB menu entry point (search for `showingImportView`)

### Android (existing files to modify)
- `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt` — Add FAB menu entry
- `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt` — Add import state/methods
- `android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt` — Register ImportService

## Acceptance Criteria

- [ ] FAB menu includes "Import JSON Data" option
- [ ] File picker opens for `.json` files via Android SAF (Storage Access Framework)
- [ ] User can select existing collection from dropdown or create new collection
- [ ] Insert type toggle between Regular (upsert) and Initial Documents
- [ ] Batch processing with 50 docs per batch
- [ ] Linear progress bar shows current/total during import
- [ ] Success message shows imported count
- [ ] Error handling with per-document error details
- [ ] Fallback to individual inserts when batch fails
- [ ] JSON validation: must be array of objects, each with `_id` field
- [ ] Collection name validation: letters, numbers, underscores only
