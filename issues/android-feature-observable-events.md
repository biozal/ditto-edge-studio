# Android Feature: Observable Events (Full Implementation)

**Priority:** High  
**Complexity:** High  
**Status:** Not Started (stub UI exists)  
**Platforms with feature:** SwiftUI, .NET/Avalonia  

## Summary

Android's Observer feature is a stub — it shows "Coming Soon" placeholder text when the Observers nav item is selected. The data model (`DittoObservable`) and repository (`ObservableRepository`) exist for saving observer definitions, but there is no observer activation, event capture, event display, or event detail UI. Both SwiftUI and .NET have complete implementations with live event streaming, diff computation, event tables, filtering, and detailed change inspection.

## Current State in Android

### What Exists
- **Model:** `DittoObservable.kt` — basic data class with `id`, `databaseId`, `name`, `query`, `isActive`, `lastUpdated`
- **Entity:** `ObservableEntity` — Room entity for persistence
- **DAO:** `ObservableDao` — standard CRUD operations
- **Repository:** `ObservableRepositoryImpl` — save, update, remove, observe (definitions only)
- **Nav item:** `StudioNavItem.OBSERVERS` with icon and help file reference
- **Help content:** `assets/help/observe.md`

### What's Missing
- **Event model** — No `DittoObserveEvent` equivalent
- **SDK integration** — No `ditto.store.registerObserver()` calls
- **Event capture** — No callback handling or diff computation
- **ViewModel methods** — No add/edit/remove/activate/deactivate observer methods
- **Observer list UI** — Only shows "No Observers" hardcoded text
- **Observer editor** — No form for creating/editing observers
- **Event table** — No event list with Time/Count/Inserted/Updated/Deleted/Moves columns
- **Event detail** — No detail view showing document data for selected events
- **Event filtering** — No All/Inserted/Updated filter

## What Needs to Be Built

### 1. Event Data Model

```kotlin
// New file: domain/model/DittoObserveEvent.kt

data class DittoObserveEvent(
    val id: String = UUID.randomUUID().toString(),
    val observeId: String,          // Links to parent DittoObservable
    val data: List<String>,         // JSON strings of all documents in result set
    val insertIndexes: List<Int>,   // Indexes of newly inserted documents
    val updatedIndexes: List<Int>,  // Indexes of updated documents
    val deletedIndexes: List<Int>,  // Indexes of deleted documents
    val movedIndexes: List<Pair<Int, Int>>,  // (from, to) pairs for moved documents
    val eventTime: String           // ISO8601 timestamp
) {
    fun getInsertedData(): List<String> = insertIndexes.mapNotNull { data.getOrNull(it) }
    fun getUpdatedData(): List<String> = updatedIndexes.mapNotNull { data.getOrNull(it) }
}
```

**Reference:** SwiftUI's `SwiftUI/EdgeStudio/Models/DittoObserveEvent.swift`

### 2. Observer ViewModel

```kotlin
// New file: viewmodel/ObserversViewModel.kt

class ObserversViewModel(
    private val observableRepository: ObservableRepository,
    private val dittoManager: DittoManager
) : ViewModel() {

    // Observer definitions
    val observers: StateFlow<List<DittoObservable>>
    
    // Active observer handles (SDK instances, not persisted)
    private val activeHandles = mutableMapOf<Long, DittoStoreObserver>()
    
    // Events (session-only, not persisted to DB)
    private val _allEvents = MutableStateFlow<List<DittoObserveEvent>>(emptyList())
    
    // Selected state
    var selectedObserver by mutableStateOf<DittoObservable?>(null)
    var selectedEvent by mutableStateOf<DittoObserveEvent?>(null)
    var editingObserver by mutableStateOf<DittoObservable?>(null)
    
    // Filtered events for selected observer
    val selectedObserverEvents: StateFlow<List<DittoObserveEvent>>
    
    // Event filter mode
    var eventFilterMode by mutableStateOf(EventFilterMode.ALL)
    
    // Pagination
    var eventPageSize by mutableStateOf(25)
    var eventCurrentPage by mutableStateOf(0)
    
    // CRUD
    fun addObserver(name: String, query: String)
    fun updateObserver(observer: DittoObservable)
    fun removeObserver(observer: DittoObservable)
    
    // Lifecycle
    fun activateObserver(observer: DittoObservable)
    fun deactivateObserver(observer: DittoObservable)
    
    // Selection
    fun selectObserver(observer: DittoObservable)
    fun selectEvent(event: DittoObserveEvent)
}

enum class EventFilterMode { ALL, INSERTED, UPDATED }
```

### 3. Observer Activation & Event Capture

The critical integration point — registering with the Ditto SDK and capturing change events:

```kotlin
fun activateObserver(observer: DittoObservable) {
    val ditto = dittoManager.currentInstance() ?: return
    
    var previousDocuments: List<String> = emptyList()
    
    val handle = ditto.store.registerObserver(observer.query) { result ->
        val currentDocuments = result.items.map { it.jsonString() }
        
        // Compute diff between previous and current result sets
        val diff = computeDiff(previousDocuments, currentDocuments)
        
        val event = DittoObserveEvent(
            observeId = observer.id.toString(),
            data = currentDocuments,
            insertIndexes = diff.insertions,
            updatedIndexes = diff.updates,
            deletedIndexes = diff.deletions,
            movedIndexes = diff.moves,
            eventTime = Instant.now().toString()
        )
        
        previousDocuments = currentDocuments
        
        viewModelScope.launch {
            _allEvents.update { it + event }
        }
    }
    
    activeHandles[observer.id] = handle
    // Update observer's isActive status in repository
}
```

**Diff computation (from .NET's ObserversViewModel.cs):**

```kotlin
data class DiffResult(
    val insertions: List<Int>,
    val updates: List<Int>,
    val deletions: List<Int>,
    val moves: List<Pair<Int, Int>>
)

fun computeDiff(previous: List<String>, current: List<String>): DiffResult {
    // Extract _id from each JSON document for matching
    // Documents in current but not in previous → insertions
    // Documents in both but with different content → updates  
    // Documents in previous but not in current → deletions
    // Documents whose index changed → moves
    
    val prevById = previous.mapIndexed { i, json -> extractId(json) to i }.toMap()
    val currById = current.mapIndexed { i, json -> extractId(json) to i }.toMap()
    
    val insertions = mutableListOf<Int>()
    val updates = mutableListOf<Int>()
    val deletions = mutableListOf<Int>()
    
    // Check current docs against previous
    current.forEachIndexed { index, json ->
        val id = extractId(json)
        if (id !in prevById) {
            insertions.add(index)
        } else {
            val prevJson = previous[prevById[id]!!]
            if (prevJson != json) {
                updates.add(index)
            }
        }
    }
    
    // Check for deletions
    previous.forEachIndexed { index, json ->
        val id = extractId(json)
        if (id !in currById) {
            deletions.add(index)
        }
    }
    
    return DiffResult(insertions, updates, deletions, emptyList())
}
```

**Reference:**
- SwiftUI: `SwiftUI/EdgeStudio/Views/MainStudioView.swift` — `registerStoreObserver()` method
- .NET: `dotnet/src/EdgeStudio.Shared/Data/Repositories/SqliteObserverRepository.cs` — `OnObserverCallback()` and `ComputeDiff()`

### 4. Observer Editor Sheet

```kotlin
// New file: ui/mainstudio/ObserverEditorSheet.kt

@Composable
fun ObserverEditorSheet(
    observer: DittoObservable?,  // null = create new, non-null = edit
    onSave: (name: String, query: String) -> Unit,
    onDismiss: () -> Unit
)
```

**UI Layout (matching SubscriptionEditorSheet pattern):**
- `ModalBottomSheet` presentation
- Title: "New Observer" or "Edit Observer"
- Name field (optional, TextField)
- Query field (TextField, monospace font)
- Save / Cancel buttons

**Reference:** Android's existing `SubscriptionEditorSheet.kt` — use identical pattern.

### 5. Observer List UI (Sidebar/DrawerPanel)

Replace the "No Observers" placeholder in `MainStudioScreen.kt`:

```kotlin
// In DrawerPanel and DataPanel, replace the OBSERVERS stub

// Header with Add button
Row(verticalAlignment = Alignment.CenterVertically) {
    Text("OBSERVERS", style = MaterialTheme.typography.labelSmall)
    Spacer(Modifier.weight(1f))
    IconButton(onClick = { observersViewModel.editingObserver = DittoObservable.new() }) {
        Icon(Icons.Default.Add, contentDescription = "Add Observer")
    }
}

// Observer list
LazyColumn {
    items(observers) { observer ->
        ObserverListItem(
            observer = observer,
            isSelected = observer == selectedObserver,
            onSelect = { observersViewModel.selectObserver(observer) },
            onActivate = { observersViewModel.activateObserver(observer) },
            onDeactivate = { observersViewModel.deactivateObserver(observer) },
            onEdit = { observersViewModel.editingObserver = observer },
            onDelete = { observersViewModel.removeObserver(observer) }
        )
    }
}
```

**Observer list item shows:**
- Observer name
- Query text (truncated, 2 lines max)
- Active/Inactive badge (green dot when active)
- Context menu or trailing icons: Activate/Stop, Edit, Delete

### 6. Observer Events Table (Detail View)

```kotlin
// New file: ui/mainstudio/ObserverEventsTable.kt

@Composable
fun ObserverEventsTable(
    events: List<DittoObserveEvent>,
    selectedEvent: DittoObserveEvent?,
    onSelectEvent: (DittoObserveEvent) -> Unit,
    pageSize: Int,
    currentPage: Int,
    onPageChange: (Int) -> Unit
)
```

**Table columns (matching SwiftUI's ObserverEventsTableView.swift):**

| Column | Width | Content |
|--------|-------|---------|
| Time | 180.dp | `event.eventTime` formatted |
| Count | 70.dp | `event.data.size` |
| Inserted | 80.dp | `event.insertIndexes.size` |
| Updated | 80.dp | `event.updatedIndexes.size` |
| Deleted | 70.dp | `event.deletedIndexes.size` |
| Moves | 70.dp | `event.movedIndexes.size` |

**Rendering:**
- Horizontally scrollable `LazyColumn` with sticky header
- Alternating row backgrounds
- Selected row highlighted with accent color at 20% opacity
- Monospace font for numeric values
- Tap row to select and show detail

### 7. Observer Event Detail View

When an event is selected, show its data in the inspector or detail panel:

```kotlin
// New file: ui/mainstudio/inspector/ObserverEventDetailView.kt

@Composable
fun ObserverEventDetailView(
    event: DittoObserveEvent,
    filterMode: EventFilterMode,
    onFilterChange: (EventFilterMode) -> Unit
)
```

**Layout:**
- **Header:** Event timestamp, total count, insert/update/delete/move counts
- **Filter segmented control:** All Items | Inserted | Updated
- **Document list:** JSON cards for filtered documents
  - "All Items" → `event.data`
  - "Inserted" → `event.getInsertedData()`
  - "Updated" → `event.getUpdatedData()`
- **Pagination** for large result sets

### 8. Detail Area Layout (50/50 Split)

When Observers nav item is selected, the detail area should show:

```
┌──────────────────────────────────────────────┐
│ Observer Events Table                        │
│ ┌──────────────────────────────────────────┐ │
│ │ Time    | Count | Ins | Upd | Del | Mov  │ │
│ │ 10:23:45|   5   |  2  |  1  |  0  |  0  │ │ ← selected
│ │ 10:23:40|   3   |  0  |  3  |  0  |  0  │ │
│ │ 10:23:35|   4   |  1  |  0  |  2  |  0  │ │
│ └──────────────────────────────────────────┘ │
├──────────────────────────────────────────────┤
│ Event Detail                                 │
│ ┌──────────────────────────────────────────┐ │
│ │ [All Items] [Inserted] [Updated]         │ │
│ │                                          │ │
│ │ { "_id": "abc", "name": "..." }          │ │
│ │ { "_id": "def", "status": "..." }        │ │
│ │                                  1/1     │ │
│ └──────────────────────────────────────────┘ │
└──────────────────────────────────────────────┘
```

On phone layout, use a single column with the event table taking priority and detail accessible via tap/navigation.

### 9. Inspector Integration

When Observers is the active nav item, the inspector should show:
- **Help tab:** Renders `assets/help/observe.md` (already exists)
- **JSON tab:** Raw JSON of selected event data

## Key Reference Files

### SwiftUI
- `SwiftUI/EdgeStudio/Models/DittoObserveEvent.swift` — Event model with insert/update/delete/move indexes
- `SwiftUI/EdgeStudio/Models/DittoObservable.swift` — Observable model with storeObserver reference
- `SwiftUI/EdgeStudio/Data/Repositories/ObservableRepository.swift` — Actor-based repository with activation
- `SwiftUI/EdgeStudio/Components/ObserverEventsTableView.swift` — Event table with platform-specific layouts, columns: Time/Count/Inserted/Updated/Deleted/Moves
- `SwiftUI/EdgeStudio/Components/SubscriptionObserverEditor.swift` — Shared editor form for subscriptions and observers
- `SwiftUI/EdgeStudio/Views/MainStudioView.swift` — `registerStoreObserver()` with diff computation, event accumulation
- `SwiftUI/EdgeStudio/Views/StudioView/Details/DetailViews.swift` — `observableEventsList()` and `observableDetailSelectedEvent()` 
- `SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift` — Observer list items with activation toggle

### .NET/Avalonia
- `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs` — Complete ViewModel with activation, events, filtering, pagination
- `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml` — Detail view with event table
- `dotnet/src/EdgeStudio/Views/StudioView/Sidebar/ObserverListingView.axaml` — Observer list
- `dotnet/src/EdgeStudio.Shared/Data/Repositories/SqliteObserverRepository.cs` — Repository with `ActivateObserverAsync()`, `OnObserverCallback()`, `ComputeDiff()`

### Android (existing files to modify)
- `android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/DittoObservable.kt` — May need storeObserver reference
- `android/app/src/main/java/com/costoda/dittoedgestudio/data/repository/ObservableRepository*.kt` — Add activation methods
- `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt` — Replace stub with real UI (lines 546-552, 638-644, 755-764)
- `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt` — Or create separate ObserversViewModel
- `android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt` — Register new ViewModel

## Acceptance Criteria

- [ ] Observer editor sheet for creating/editing observers (name + query)
- [ ] Observer list in sidebar with active/inactive status badges
- [ ] Activate/deactivate observers via context menu or toggle
- [ ] SDK integration: `ditto.store.registerObserver()` called on activation
- [ ] Event capture with diff computation (insert/update/delete/move detection)
- [ ] Event table with columns: Time, Count, Inserted, Updated, Deleted, Moves
- [ ] Event selection shows document detail
- [ ] Filter by All Items / Inserted / Updated
- [ ] Pagination for event list and event detail documents
- [ ] Events are session-only (cleared when database closes or observer stops)
- [ ] Multiple observers can be active simultaneously
- [ ] Clean shutdown: cancel all active observers on database close
