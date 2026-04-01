# Dotnet Feature: Observers

## Overview

The SwiftUI version of Edge Studio has a fully functional Observers feature that allows users to register DQL-based observers, activate them to watch for real-time data changes from syncing peers, and view diffs showing what data has changed (inserts, updates, deletes, moves). The dotnet/Avalonia version has only placeholder scaffolding for this feature.

## SwiftUI Feature Summary

The Observer feature enables users to:
1. Create named observers with a DQL query
2. Activate/deactivate observers on demand
3. Watch real-time events as sync data arrives
4. View diffs per event showing inserted, updated, deleted, and moved items
5. Browse event history with pagination
6. Filter event detail data by change type (all items, inserted only, updated only)

### SwiftUI Files Involved
| File | Purpose |
|------|---------|
| `Models/DittoObservable.swift` | Observer metadata model (id, name, query, isActive, storeObserver reference) |
| `Models/DittoObserveEvent.swift` | Event model with diff indexes and data (insertIndexes, updatedIndexes, deletedIndexes, movedIndexes, data as JSON strings) |
| `Data/Repositories/ObservableRepository.swift` | Actor-based SQLCipher persistence for observer definitions |
| `Data/DittoManager.swift` | Ditto SDK integration for observer lifecycle |
| `Views/MainStudioView.swift` | ViewModel managing observer state, registration, and event accumulation |
| `Views/StudioView/SidebarViews.swift` | Observer list in sidebar with activate/stop/delete actions |
| `Views/StudioView/Details/DetailViews.swift` | Observer detail pane (50/50 split: event list + event detail) |
| `Components/ObserverEventsTableView.swift` | Event table with columns: Time, Count, Inserted, Updated, Deleted, Moves |
| `Components/SubscriptionObserverEditor.swift` | Shared create/edit dialog for subscriptions and observers |

### SwiftUI Data Flow
```
User creates observer → ObservableRepository saves to SQLCipher
User activates observer → DittoStoreObserver registered with Ditto SDK
Ditto fires change callback → DittoDiffer calculates diff → DittoObserveEvent created
Event appended to ViewModel array → SwiftUI re-renders event list
User selects event → Detail pane shows filtered data (all/inserted/updated)
```

---

## Current Dotnet State

### What Exists (Placeholder Only)

| Component | File | Status |
|-----------|------|--------|
| ObserversViewModel | `ViewModels/ObserversViewModel.cs` | Placeholder with hardcoded strings ("Observer 1", "Observer 2", "Observer 3"). Extends `ViewModelBase` instead of `LoadableViewModelBase`. |
| ObserverListingView | `Views/StudioView/Sidebar/ObserverListingView.axaml` | Simple list binding to placeholder strings |
| ObserverDetailView | `Views/StudioView/Details/ObserverDetailView.axaml` | Empty — shows only "Observer Details View" text |
| Navigation Item | `Shared/Models/NavigationItem.cs` | `NavigationItemType.Observers` registered with Eye icon |
| DI Registration | `App.axaml.cs` | `ObserversViewModel` registered as Transient |

### Established Patterns to Follow

The dotnet app has well-established patterns from the Subscriptions feature that Observers should replicate:

- **Repository pattern**: Interface + SQLite implementation + `ICloseDatabase` for cleanup
- **ViewModel hierarchy**: `LoadableViewModelBase` with `ExecuteOperationAsync` for async operations
- **Active Ditto objects**: `Dictionary<string, DittoStoreObserver>` for tracking live observers
- **Messaging**: `WeakReferenceMessenger` for inter-component communication
- **DI**: Repositories as Singletons, ViewModels as Transient with `Lazy<T>` wrappers

---

## Required Changes

### 1. New Model: DittoDatabaseObserver

**Create:** `dotnet/src/EdgeStudio.Shared/Models/DittoDatabaseObserver.cs`

Following the pattern of `DittoDatabaseSubscription.cs`:
- `Id` (string) — unique identifier
- `Name` (string) — user-defined name
- `Query` (string) — DQL query string
- `SelectedAppId` (string) — links to parent database config
- `CreatedAt` (DateTime)
- `LastUpdated` (DateTime?)
- `IsActive` (bool) — runtime-only flag (not persisted)

### 2. New Model: ObserverEvent

**Create:** `dotnet/src/EdgeStudio.Shared/Models/ObserverEvent.cs`

Maps to SwiftUI's `DittoObserveEvent`:
- `Id` (string) — unique event identifier
- `ObserverId` (string) — links to parent observer
- `Data` (List\<string\>) — JSON strings of all result items
- `InsertIndexes` (List\<int\>) — indexes of inserted items
- `UpdatedIndexes` (List\<int\>) — indexes of updated items
- `DeletedIndexes` (List\<int\>) — indexes of deleted items
- `MovedIndexes` (List\<(int From, int To)\>) — moved item index pairs
- `EventTime` (DateTime) — when the event was received
- Helper methods: `GetInsertedData()`, `GetUpdatedData()` to extract filtered items by index

### 3. New Repository Interface: IObserverRepository

**Create:** `dotnet/src/EdgeStudio.Shared/Data/Repositories/IObserverRepository.cs`

```
IObserverRepository : ICloseDatabase
  - Task<List<DittoDatabaseObserver>> GetObserversAsync(string selectedAppId)
  - Task SaveObserverAsync(DittoDatabaseObserver observer)
  - Task DeleteObserverAsync(string observerId)
  - Task CloseDatabaseAsync()
  - void CloseSelectedDatabase()
```

### 4. New Repository Implementation: SqliteObserverRepository

**Create:** `dotnet/src/EdgeStudio.Shared/Data/Repositories/SqliteObserverRepository.cs`

Following the `SqliteSubscriptionRepository` pattern:
- Extends `SqliteRepositoryBase`
- Creates `observers` table with columns: id, name, query, selected_app_id, created_at, last_updated
- Implements `IObserverRepository` and `ICloseDatabase`
- Tracks active observers: `Dictionary<string, DittoStoreObserver> _activeObservers`
- On `CloseSelectedDatabase()`: cancels all active observers and clears dictionary

### 5. Rewrite: ObserversViewModel

**Modify:** `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs`

Major rewrite required:
- Change base class from `ViewModelBase` to `LoadableViewModelBase`
- Inject `IObserverRepository` and `IDittoManager` (via `Lazy<T>`)
- Replace `ObservableCollection<string>` with `ObservableCollection<DittoDatabaseObserver>`
- Add `ObservableCollection<ObserverEvent> Events` for event list
- Add `ObserverEvent? SelectedEvent` for detail view binding
- Add `string EventFilterMode` (items/inserted/updated) for data filtering
- Implement methods:
  - `LoadObserversAsync()` — load from repository on activation
  - `AddObserverAsync(name, query)` — save to repository
  - `DeleteObserverAsync(observer)` — remove from repository and cancel if active
  - `ActivateObserverAsync(observer)` — register `DittoStoreObserver` with Ditto SDK
  - `DeactivateObserverAsync(observer)` — cancel active observer
  - `LoadEventsForObserver(observer)` — filter events for selected observer
- Handle observer callback: create `ObserverEvent` with diff data on each change

### 6. Diffing Implementation

**Investigate:** Ditto .NET SDK equivalent of `DittoDiffer`

The SwiftUI version uses `DittoDiffer` from the Ditto Swift SDK to calculate insertions, deletions, updates, and moves between consecutive observer results. The dotnet implementation needs to:
- Check if the Ditto .NET SDK provides a `DittoDiffer` or equivalent class
- If not available, implement manual diffing by comparing previous and current result sets
- Track previous results per observer to compute diffs on each callback

### 7. New View: Observer Add/Edit Dialog

**Create:** `dotnet/src/EdgeStudio/Views/Dialogs/AddObserverDialog.axaml` (+ code-behind)

Dialog for creating/editing observers with:
- Name text field
- Query text field (DQL)
- Save/Cancel buttons
- Validation (name and query required)

In SwiftUI this is the shared `SubscriptionObserverEditor` component. The dotnet version can either create a dedicated dialog or make the existing subscription dialog reusable.

### 8. Rewrite: ObserverListingView (Sidebar)

**Modify:** `dotnet/src/EdgeStudio/Views/StudioView/Sidebar/ObserverListingView.axaml`

Replace placeholder list with:
- "Add Observer" button (opens dialog)
- List of `DittoDatabaseObserver` items showing name and query
- Active/inactive indicator per observer
- Context menu or buttons for: Activate, Stop, Delete
- Click to select observer and load its events in detail view

### 9. Rewrite: ObserverDetailView

**Modify:** `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml`

Replace empty placeholder with a split layout:

**Top pane (Events List):**
- Empty states: "No Observer Selected" / "No Observer Events"
- DataGrid or ItemsControl with columns: Time, Count, Inserted, Updated, Deleted, Moves
- Pagination controls
- Click row to select event

**Bottom pane (Event Detail):**
- Filter picker: All Items / Inserted / Updated
- Data display: JSON viewer or table view of the filtered event data
- Pagination for large result sets

### 10. DI Registration Updates

**Modify:** `dotnet/src/EdgeStudio/App.axaml.cs`

Add registrations:
```csharp
services.AddSingleton<IObserverRepository, SqliteObserverRepository>();
```

If a separate details ViewModel is created, register that as Transient as well.

### 11. Database Cleanup Integration

**Modify:** `dotnet/src/EdgeStudio.Shared/Data/DittoManager.cs` (or wherever database close is handled)

Ensure `IObserverRepository.CloseDatabaseAsync()` is called when:
- User switches databases
- User closes a database connection
- App shuts down

Follow the existing pattern used for `ISubscriptionRepository` cleanup.

### 12. Form Model (Optional)

**Create:** `dotnet/src/EdgeStudio.Shared/Models/ObserverFormModel.cs`

If the add/edit dialog needs a separate form binding model (following existing form patterns in the app):
- `Name` (string)
- `Query` (string)
- Validation attributes

---

## Implementation Priority

| Priority | Item | Effort |
|----------|------|--------|
| 1 | Models (DittoDatabaseObserver, ObserverEvent) | Small |
| 2 | Repository interface + SQLite implementation | Medium |
| 3 | DI registration + database cleanup integration | Small |
| 4 | ObserversViewModel rewrite | Large |
| 5 | Diffing implementation (SDK investigation required) | Medium |
| 6 | ObserverListingView sidebar rewrite | Medium |
| 7 | ObserverDetailView split layout | Large |
| 8 | Add/Edit observer dialog | Small |
| 9 | Pagination for events and detail data | Medium |

## Notes

- The dotnet app already uses `DittoStoreObserver` in `SystemRepository` for system-level monitoring, so the SDK integration pattern is proven
- Events are session-only (not persisted to SQLite) — they accumulate in memory during the app session, matching the SwiftUI behavior
- Observer definitions (name, query) ARE persisted to SQLite so they survive app restarts
- The active `DittoStoreObserver` references are runtime-only and must be re-activated by the user each session
