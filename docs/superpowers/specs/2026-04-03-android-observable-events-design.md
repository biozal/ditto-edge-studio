# Android Observable Events — Design Spec

**Date:** 2026-04-03  
**Status:** Approved  
**Issue:** `issues/android-feature-observable-events.md`

## Overview

Implement the full Observer Events feature for Android, bringing it to parity with SwiftUI and .NET. Users can create observers with DQL queries, activate them to receive live change events from the Ditto SDK, and inspect event details including insert/update/delete/move diffs.

## Architecture Decision

**Approach:** Extend `MainStudioViewModel` with observer state, following the exact pattern established for subscriptions. No separate ViewModel.

**Rationale:** Subscriptions already use this pattern (`activeHandles` map, `editingSubscription` sheet state, CRUD methods). Consistency outweighs file size concerns. Observer code adds ~150-200 lines.

## Data Model

### DittoObserveEvent (New file)

`domain/model/DittoObserveEvent.kt`

```kotlin
data class DittoObserveEvent(
    val id: String = UUID.randomUUID().toString(),
    val observeId: String,
    val data: List<String>,
    val insertIndexes: List<Int>,
    val updatedIndexes: List<Int>,
    val deletedIndexes: List<Int>,
    val movedIndexes: List<Pair<Int, Int>>,
    val eventTime: String
) {
    fun getInsertedData(): List<String> = insertIndexes.mapNotNull { data.getOrNull(it) }
    fun getUpdatedData(): List<String> = updatedIndexes.mapNotNull { data.getOrNull(it) }
}
```

- Session-only — not persisted to Room
- `observeId` links to the parent `DittoObservable.id`

### DittoObservable (Existing — no changes needed)

Already has: `id`, `databaseId`, `name`, `query`, `isActive`, `lastUpdated`. Persisted to Room via existing `ObservableEntity` table and `ObservableDao`.

### EventFilterMode (New enum)

```kotlin
enum class EventFilterMode { ALL, INSERTED, UPDATED }
```

## SDK Integration

### Observer Activation

Uses `DittoDiffer` from the Kotlin Ditto SDK (same as SwiftUI's `DittoDiffer`):

```kotlin
fun activateObserver(observer: DittoObservable) {
    val ditto = dittoManager.currentInstance() ?: return
    val differ = DittoDiffer()

    val handle = ditto.store.registerObserver(observer.query) { results ->
        val diff = differ.diff(results.items)
        val currentDocuments = results.items.map { it.jsonString() }

        val event = DittoObserveEvent(
            observeId = observer.id.toString(),
            data = currentDocuments,
            insertIndexes = diff.insertions.toList(),
            updatedIndexes = diff.updates.toList(),
            deletedIndexes = diff.deletions.toList(),
            movedIndexes = diff.moves.map { it.from to it.to },
            eventTime = Instant.now().toString()
        )

        viewModelScope.launch {
            _observerEvents.update { it + event }
        }
    }

    activeObserverHandles[observer.id] = handle
    // Update isActive = true in repository
}
```

### Observer Deactivation

```kotlin
fun deactivateObserver(observer: DittoObservable) {
    activeObserverHandles.remove(observer.id)?.close()
    // Update isActive = false in repository
    // Clear events for this observer from _observerEvents
}
```

### Hydration

On ViewModel init: load all observer definitions from Room. Do NOT auto-activate — user must explicitly activate. `isActive` flags from DB are display-only until user reactivates.

## State in MainStudioViewModel

### New Properties

```kotlin
// Observer definitions (persisted to Room)
private val _observers = MutableStateFlow<List<DittoObservable>>(emptyList())
val observers: StateFlow<List<DittoObservable>> = _observers.asStateFlow()

// Active SDK handles (in-memory only)
private val activeObserverHandles = mutableMapOf<Long, DittoStoreObserver>()

// Events (session-only, not persisted)
private val _observerEvents = MutableStateFlow<List<DittoObserveEvent>>(emptyList())
val observerEvents: StateFlow<List<DittoObserveEvent>> = _observerEvents.asStateFlow()

// Selection state
var selectedObserver by mutableStateOf<DittoObservable?>(null)
var selectedEvent by mutableStateOf<DittoObserveEvent?>(null)
var editingObserver by mutableStateOf<DittoObservable?>(null)

// Event display state
var eventFilterMode by mutableStateOf(EventFilterMode.ALL)
var eventPageSize by mutableStateOf(25)
var eventCurrentPage by mutableStateOf(0)
```

### New Methods

```kotlin
// CRUD
fun addObserver(name: String, query: String)
fun updateObserver(observer: DittoObservable, name: String, query: String)
fun removeObserver(observer: DittoObservable)

// Lifecycle
fun activateObserver(observer: DittoObservable)
fun deactivateObserver(observer: DittoObservable)

// Selection
fun selectObserver(observer: DittoObservable)
fun selectEvent(event: DittoObserveEvent)
```

### Derived State

```kotlin
// Events filtered to selected observer
val selectedObserverEvents: StateFlow<List<DittoObserveEvent>>
    // Combine _observerEvents + selectedObserver → filter by observeId
```

### Cleanup (in onCleared)

```kotlin
// Close all observer handles (alongside existing subscription cleanup)
activeObserverHandles.values.forEach { it.close() }
activeObserverHandles.clear()
```

## UI Components

### ObserverEditorSheet (New file)

`ui/mainstudio/ObserverEditorSheet.kt`

- `ModalBottomSheet` with `skipPartiallyExpanded = true`
- Fields: Name (optional OutlinedTextField), Query (required OutlinedTextField, monospace)
- Save button disabled when query is blank
- Identical pattern to `SubscriptionEditorSheet.kt`
- Shown when `editingObserver != null`; `null` with `id = 0L` means create new

### ObserverListItem (New file)

`ui/mainstudio/ObserverListItem.kt`

- Observer name (primary text)
- Query preview (secondary text, 2 lines max, truncated)
- Green "Active" badge when `observer.id` is in `activeObserverHandles`
- Tap to select observer (loads its events)
- Long-press context menu:
  - Activate (if inactive) / Stop (if active)
  - Edit (opens editor sheet)
  - Delete (deactivates first if active, then removes)

### ObserverDetailScreen (New file)

`ui/mainstudio/ObserverDetailScreen.kt`

Container composable for the OBSERVERS detail area:

- **Tablet:** Vertical 50/50 split — top half event table, bottom half event detail
- **Phone:** Event table fills area; tap event shows detail (could use bottom sheet or navigate)
- **Empty state:** "Select an observer and activate it to see events" (centered, with icon)

### ObserverEventsTable (New file)

`ui/mainstudio/ObserverEventsTable.kt`

Horizontally scrollable table with sticky header:

| Column | Width | Content |
|--------|-------|---------|
| Time | 180.dp | Formatted ISO8601 timestamp |
| Count | 70.dp | `event.data.size` |
| Inserted | 80.dp | `event.insertIndexes.size` |
| Updated | 80.dp | `event.updatedIndexes.size` |
| Deleted | 70.dp | `event.deletedIndexes.size` |
| Moves | 70.dp | `event.movedIndexes.size` |

- Alternating row backgrounds
- Selected row: accent color at 20% opacity
- Monospace font for numeric values
- Tap row to select → populates event detail below
- Pagination controls below (page size 25)

### ObserverEventDetailView (New file)

`ui/mainstudio/ObserverEventDetailView.kt`

- **Header:** Event timestamp, total doc count, change count summary
- **Filter row:** Segmented buttons — All Items | Inserted | Updated
  - ALL → `event.data`
  - INSERTED → `event.getInsertedData()`
  - UPDATED → `event.getUpdatedData()`
- **Document list:** JSON cards (reuse `ResultJsonView` card pattern)
- **Pagination:** For large document sets within a single event

## MainStudioScreen Modifications

### Sidebar/DrawerPanel (replace OBSERVERS stub)

```
OBSERVERS                          [+]
┌─────────────────────────────────────┐
│ 👁 My Observer          ● Active   │
│   SELECT * FROM orders...          │
├─────────────────────────────────────┤
│ 👁 User Watcher                    │
│   SELECT * FROM users...           │
└─────────────────────────────────────┘
```

### Data Panel (replace OBSERVERS stub)

Same observer list content for the collapsed sidebar data panel view.

### Content Area (replace "Coming Soon" placeholder)

```kotlin
StudioNavItem.OBSERVERS -> {
    ObserverDetailScreen(
        events = selectedObserverEvents,
        selectedEvent = viewModel.selectedEvent,
        filterMode = viewModel.eventFilterMode,
        // ... callbacks
    )
}
```

### Editor Sheet (add alongside subscription sheet)

```kotlin
viewModel.editingObserver?.let { observer ->
    ObserverEditorSheet(
        observer = observer,
        onSave = { name, query -> viewModel.addOrUpdateObserver(observer, name, query) },
        onDismiss = { viewModel.editingObserver = null }
    )
}
```

## Inspector Integration

When OBSERVERS is the active nav item:
- **Help tab:** Renders `assets/help/observe.md` (already exists)
- **JSON tab:** Raw JSON of `selectedEvent?.data` (pretty-printed)

## Lifecycle Summary

| Action | Observer Def (Room) | SDK Handle | Events (Memory) |
|--------|-------------------|------------|-----------------|
| Create | INSERT | — | — |
| Activate | UPDATE isActive=true | registerObserver() | Start accumulating |
| Receive event | — | Callback fires | Append new event |
| Deactivate | UPDATE isActive=false | close() | Clear for this observer |
| Delete | DELETE | close() if active | Clear for this observer |
| Switch database | — | close() all | Clear all |
| ViewModel cleared | — | close() all | Clear all |

## File Inventory

### New Files (6)

| File | Purpose |
|------|---------|
| `domain/model/DittoObserveEvent.kt` | Event data model with diff indexes |
| `ui/mainstudio/ObserverEditorSheet.kt` | Create/edit observer bottom sheet |
| `ui/mainstudio/ObserverListItem.kt` | Sidebar list item composable |
| `ui/mainstudio/ObserverDetailScreen.kt` | Container: table + detail vertical split |
| `ui/mainstudio/ObserverEventsTable.kt` | Event table with 6 columns |
| `ui/mainstudio/ObserverEventDetailView.kt` | Selected event detail with filtering |

### Modified Files (2)

| File | Changes |
|------|---------|
| `MainStudioViewModel.kt` | Add ~150-200 lines: observer state, CRUD, activation, event capture, cleanup |
| `MainStudioScreen.kt` | Replace 3 OBSERVERS stubs (sidebar, data panel, content area), add editor sheet |

### No Changes Needed

- `DittoObservable.kt` — existing model sufficient
- `ObservableRepository*.kt` — existing CRUD sufficient
- `ObservableDao.kt` / `ObservableEntity.kt` — table already exists
- `DataModule.kt` — `ObservableRepository` already registered in Koin
- `AppDatabase.kt` — no migration needed
- `DittoManager.kt` — accessed via existing `currentInstance()`
