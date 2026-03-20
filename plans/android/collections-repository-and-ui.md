# Android Collections Repository & UI — Plan

## Overview

The Android app currently shows a static "No Collections" placeholder in the sidebar. This plan implements a live collection browser matching the SwiftUI version: real-time collection listing with document counts, per-collection index expansion, per-index field expansion, and an "Add Index" sheet.

**Reference implementation:** `SwiftUI/EdgeStudio/Data/Repositories/CollectionsRepository.swift` and `SwiftUI/EdgeStudio/Views/StudioView/SidebarViews.swift`.

---

## What the SwiftUI Version Does

The SwiftUI reference shows three layers of data, all live-updating:

```
COLLECTIONS [refresh]
└── collection_name  (doc count badge)           ← DQL: SELECT * FROM __collections
    └── index_display_name                        ← DQL: SELECT * FROM system:indexes
        └── field_name                            ← from fields array in index row
```

**Data sources (all DQL):**
| Query | Purpose |
|-------|---------|
| `SELECT * FROM __collections` | Lists all user collections |
| `SELECT * FROM system:indexes` | All indexes across all collections |
| `SELECT COUNT(*) as numDocs FROM {name}` | Doc count per collection |

**Observer:** `ditto.store.registerObserver("SELECT * FROM __collections")` fires whenever collections change, triggering a full refresh of counts and indexes.

**Filtering:** Collections whose name starts with `__` are hidden (Ditto system collections). The `DES_SIM`-prefixed collections from the DittoSim feature would also be filtered here in a future update.

**Index display name:** Index `_id` is stored as `collectionName.indexName` — the UI strips the `collectionName.` prefix.

**Field name display:** Field names from the SDK may be wrapped in backticks (`` `fieldName` ``) — these are stripped for display.

---

## Ditto Kotlin SDK APIs Used

```kotlin
// Execute a DQL query once (suspend)
val result: DittoQueryResult = ditto.store.execute("SELECT * FROM __collections")
result.items.forEach { item ->
    val json = JSONObject(item.jsonString())  // cleanest parsing approach
}

// Register a live observer (not suspend — synchronous registration)
val observer: DittoStoreObserver = ditto.store.registerObserver(
    query = "SELECT * FROM __collections"
) { _ ->
    // suspend lambda — safe to call suspend functions here
    scope.launch(Dispatchers.IO) { refreshInternal() }
}

// Cancel observer when done
observer.close()
```

`DittoQueryResultItem.jsonString()` returns the item as a JSON string — used with `org.json.JSONObject` (already a dependency from the logging work).

---

## Architecture

```
Ditto SDK (__collections observer)
    ↓ fires on change
CollectionsRepositoryImpl (Dispatchers.IO)
    ├── fetchCollections()     → SELECT * FROM __collections
    ├── fetchIndexes()         → SELECT * FROM system:indexes
    └── fetchDocCounts()       → SELECT COUNT(*) as numDocs FROM {name}
    ↓ emits
StateFlow<List<DittoCollection>>
    ↓ collectAsState()
MainStudioViewModel.collections
    ↓
DataPanel / PhoneDrawerContent
    └── CollectionListItem (expandable tree)
            └── IndexListItem (expandable)
                    └── FieldListItem
```

---

## New Files

| File | Purpose |
|------|---------|
| `domain/model/DittoCollection.kt` | `DittoCollection` + `DittoIndex` data classes |
| `data/repository/CollectionsRepository.kt` | Interface |
| `data/repository/CollectionsRepositoryImpl.kt` | DQL queries + live observer |
| `ui/mainstudio/CollectionListItem.kt` | Expandable collection tree composable |
| `ui/mainstudio/AddIndexSheet.kt` | ModalBottomSheet for creating a new index |
| `test/.../CollectionsRepositoryImplTest.kt` | Unit tests for parsing + error paths |

---

## Modified Files

| File | Change |
|------|--------|
| `data/di/DataModule.kt` | Register `CollectionsRepository` singleton; add to `MainStudioViewModel` factory |
| `viewmodel/MainStudioViewModel.kt` | Inject repo; start/stop observing; expose `collections` StateFlow; add `addIndex()` and `showAddIndex` state |
| `ui/mainstudio/MainStudioScreen.kt` | Replace "No Collections" placeholders in `DataPanel` and `PhoneDrawerContent`; wire "Index" FAB item to open `AddIndexSheet` |
| `viewmodel/MainStudioViewModelTest.kt` | Add mock for `CollectionsRepository` |

---

## Domain Models — `domain/model/DittoCollection.kt`

```kotlin
data class DittoCollection(
    val name: String,
    val docCount: Int? = null,
    val indexes: List<DittoIndex> = emptyList(),
)

data class DittoIndex(
    val id: String,           // full ID, e.g. "comments.idx_comments_movie_id"
    val collection: String,
    val fields: List<String>, // may have backtick-wrapped names from SDK
) {
    /** Strips the "collectionName." prefix for display. */
    val displayName: String
        get() = id.substringAfter('.', id)

    /** Fields with backticks stripped, e.g. "`movie_id`" → "movie_id" */
    val displayFields: List<String>
        get() = fields.map { it.removePrefix("`").removeSuffix("`") }
}
```

**Why no `_id` field?** Android doesn't need a Room entity for collections — they're live-queried from Ditto. `name` is the natural key.

---

## Repository Interface — `data/repository/CollectionsRepository.kt`

```kotlin
interface CollectionsRepository {
    /** Live list of user collections, updated by the Ditto store observer. */
    val collections: StateFlow<List<DittoCollection>>

    /** Start observing the Ditto store. Call after a Ditto instance is ready. */
    fun startObserving(ditto: Ditto)

    /** Stop observing and clear state. Call when closing the database. */
    fun stopObserving()

    /** Manually re-fetch all collection data (for pull-to-refresh). */
    suspend fun refresh()

    /**
     * Create a single-field index on a collection.
     * Index is named `idx_{collection}_{fieldName}` with dots/spaces → underscores.
     */
    suspend fun createIndex(collection: String, fieldName: String)
}
```

---

## Repository Implementation — `data/repository/CollectionsRepositoryImpl.kt`

### Key constants

```kotlin
private const val QUERY_COLLECTIONS  = "SELECT * FROM __collections"
private const val QUERY_INDEXES      = "SELECT * FROM system:indexes"
private const val QUERY_COUNT_TMPL   = "SELECT COUNT(*) as numDocs FROM %s"
```

### State

```kotlin
class CollectionsRepositoryImpl(
    private val scope: CoroutineScope,
) : CollectionsRepository {

    private val _collections = MutableStateFlow<List<DittoCollection>>(emptyList())
    override val collections: StateFlow<List<DittoCollection>> = _collections.asStateFlow()

    private var observer: DittoStoreObserver? = null
    private var activeDitto: Ditto? = null
```

### `startObserving(ditto)`

1. Store `ditto` reference
2. Close any existing observer
3. Call `scope.launch(Dispatchers.IO) { refreshInternal() }` for the initial load
4. Register `ditto.store.registerObserver(QUERY_COLLECTIONS) { _ → scope.launch(IO) { refreshInternal() } }`

The observer fires immediately on registration with current data, and again on any change.

### `stopObserving()`

```kotlin
observer?.close()
observer = null
activeDitto = null
_collections.value = emptyList()
```

### `refreshInternal()` (private suspend)

```kotlin
private suspend fun refreshInternal() {
    val ditto = activeDitto ?: return
    val collections = fetchCollections(ditto)
    _collections.value = collections
}
```

### `fetchCollections(ditto)` (private suspend)

```kotlin
// 1. Fetch collection names
val collResult = ditto.store.execute(QUERY_COLLECTIONS)
val rawNames = collResult.items.mapNotNull { item ->
    runCatching { JSONObject(item.jsonString()).optString("_id") }
        .getOrNull()
        ?.takeIf { it.isNotBlank() && !it.startsWith("__") }
}
collResult.close()

// 2. Fetch all indexes in one query
val indexesByCollection: Map<String, List<DittoIndex>> = fetchIndexes(ditto)

// 3. Fetch doc counts concurrently
val countsByName: Map<String, Int> = fetchDocCounts(ditto, rawNames)

// 4. Assemble and return sorted
return rawNames.map { name ->
    DittoCollection(
        name = name,
        docCount = countsByName[name],
        indexes = indexesByCollection[name] ?: emptyList(),
    )
}.sortedBy { it.name }
```

**Note:** `collResult.close()` is called after consuming items — matches the SwiftUI pattern of calling `dematerialize()`.

### `fetchIndexes(ditto)` (private suspend) → `Map<String, List<DittoIndex>>`

```kotlin
val result = ditto.store.execute(QUERY_INDEXES)
val map = mutableMapOf<String, MutableList<DittoIndex>>()
for (item in result.items) {
    runCatching {
        val json = JSONObject(item.jsonString())
        val id = json.optString("_id").takeIf { it.isNotBlank() } ?: return@runCatching
        val collection = json.optString("collection").takeIf { it.isNotBlank() } ?: return@runCatching
        val fieldsJson = json.optJSONArray("fields")
        val fields = buildList {
            if (fieldsJson != null) {
                for (i in 0 until fieldsJson.length()) {
                    fieldsJson.optString(i).takeIf { it.isNotBlank() }?.let { add(it) }
                }
            }
        }
        map.getOrPut(collection) { mutableListOf() }
            .add(DittoIndex(id = id, collection = collection, fields = fields))
    }
}
result.close()
return map
```

### `fetchDocCounts(ditto, names)` (private suspend) → `Map<String, Int>`

```kotlin
val counts = mutableMapOf<String, Int>()
for (name in names) {
    runCatching {
        val result = ditto.store.execute(QUERY_COUNT_TMPL.format(name))
        val count = result.items.firstOrNull()?.let {
            JSONObject(it.jsonString()).optInt("numDocs", 0)
        } ?: 0
        result.close()
        counts[name] = count
    }
    // One failing collection doesn't block others
}
return counts
```

### `createIndex(collection, fieldName)` (override suspend)

```kotlin
val safeName = "idx_${collection}_${fieldName}"
    .replace('.', '_')
    .replace(' ', '_')
    .replace('-', '_')
val dql = "CREATE INDEX IF NOT EXISTS $safeName ON $collection ($fieldName)"
activeDitto?.store?.execute(dql)
// Refresh to show the new index in the UI
refreshInternal()
```

### `refresh()` (override suspend)

```kotlin
scope.launch(Dispatchers.IO) { refreshInternal() }
```

---

## ViewModel Changes — `MainStudioViewModel.kt`

### Constructor addition

```kotlin
class MainStudioViewModel(
    // ... existing params ...
    val collectionsRepository: CollectionsRepository,
    // ...
) : ViewModel() {
```

### New state

```kotlin
var showAddIndex by mutableStateOf(false)
```

### In `hydrate()` — after `systemRepository.startObserving(ditto)`:

```kotlin
collectionsRepository.startObserving(ditto)
```

### New function

```kotlin
fun addIndex(collection: String, fieldName: String) {
    viewModelScope.launch(ioDispatcher) {
        runCatching {
            collectionsRepository.createIndex(collection, fieldName)
        }.onFailure { e ->
            hydrateError = e.message
        }
        showAddIndex = false
    }
}
```

### In `onCleared()`:

```kotlin
collectionsRepository.stopObserving()
```

### Exposed StateFlow (delegated directly)

```kotlin
val collections: StateFlow<List<DittoCollection>> = collectionsRepository.collections
    .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())
```

---

## UI Components

### `CollectionListItem.kt`

A fully self-contained composable that renders one collection and its nested tree.

**Visual design (matches SwiftUI sidebar):**

```
▶ collection_name        47 docs          ← tappable chevron expands
  ▶ idx_name                              ← index row (tappable)
      field1                              ← leaf field row
      field2
  (No indexes)                            ← when empty
```

**Implementation sketch:**

```kotlin
@Composable
fun CollectionListItem(
    collection: DittoCollection,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }

    Column(modifier = modifier.fillMaxWidth()) {
        // Collection header row
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(horizontal = 16.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = if (expanded) Icons.Outlined.ExpandMore else Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Icon(Icons.Outlined.TableChart, contentDescription = null, modifier = Modifier.size(16.dp))
            Text(
                text = collection.name,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            collection.docCount?.let { count ->
                DocCountBadge(count)
            }
        }

        // Expanded: index tree
        AnimatedVisibility(visible = expanded) {
            Column(modifier = Modifier.padding(start = 24.dp)) {
                if (collection.indexes.isEmpty()) {
                    Text(
                        text = "No indexes",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
                    )
                } else {
                    collection.indexes.forEach { index ->
                        IndexListItem(index = index)
                    }
                }
            }
        }
    }
}

@Composable
private fun IndexListItem(index: DittoIndex) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = !expanded }
                .padding(horizontal = 16.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(chevronIcon, modifier = Modifier.size(14.dp))
            Icon(Icons.Outlined.Label, modifier = Modifier.size(14.dp))
            Text(index.displayName, style = MaterialTheme.typography.labelSmall)
        }
        AnimatedVisibility(visible = expanded) {
            Column(modifier = Modifier.padding(start = 20.dp)) {
                index.displayFields.forEach { field ->
                    FieldListItem(field)
                }
            }
        }
    }
}

@Composable
private fun FieldListItem(field: String) {
    Row(
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 2.dp),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Outlined.Code, modifier = Modifier.size(12.dp))
        Text(field, style = MaterialTheme.typography.labelSmall,
             color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun DocCountBadge(count: Int) {
    Surface(
        color = SulfurYellow,
        shape = MaterialTheme.shapes.extraSmall,
    ) {
        Text(
            text = count.toString(),
            style = MaterialTheme.typography.labelSmall,
            color = JetBlack,
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp),
        )
    }
}
```

---

### `AddIndexSheet.kt`

A `ModalBottomSheet` matching the SwiftUI `AddIndexView`:

```
Add Index
─────────────────────────────────────────
Collection:  [ExposedDropdownMenuBox ▼]
Field Name:  [OutlinedTextField          ]

ℹ️  Each index covers one field. Multiple indexes
   can exist on the same collection.

[Cancel]              [Create Index]
```

**State:**
- `selectedCollection: String` — populated from `viewModel.collections`
- `fieldName: String` — text input
- `errorMessage: String?` — shown in red if blank inputs

**On create:**
```kotlin
if (selectedCollection.isBlank() || fieldName.isBlank()) {
    errorMessage = "Collection and field name are required"
    return
}
viewModel.addIndex(selectedCollection, fieldName)
// Sheet closed by ViewModel setting showAddIndex = false
```

---

### `MainStudioScreen.kt` changes

**1. DataPanel — replace "No Collections" placeholder:**

```kotlin
SectionHeader(
    title = "COLLECTIONS",
    trailingIcon = Icons.Outlined.Refresh,
    onTrailingClick = { scope.launch { viewModel.collectionsRepository.refresh() } },
)
val collections by viewModel.collections.collectAsState()
if (collections.isEmpty()) {
    Text(
        text = "No Collections",
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
    )
} else {
    collections.forEach { collection ->
        CollectionListItem(collection = collection)
    }
}
```

Same change applied to `PhoneDrawerContent` COLLECTIONS section.

**2. FAB "Index" item:**

Change the no-op `onClick` to:
```kotlin
onClick = {
    viewModel.showAddIndex = true
    onExpandChange(false)
}
```

**3. AddIndexSheet invocation** (in both `PhoneLayout` and `TabletLayout`):

```kotlin
if (viewModel.showAddIndex) {
    AddIndexSheet(
        collections = viewModel.collections.collectAsState().value,
        onAdd = { collection, field -> viewModel.addIndex(collection, field) },
        onDismiss = { viewModel.showAddIndex = false },
    )
}
```

---

## DI — `DataModule.kt`

```kotlin
single<CollectionsRepository> { CollectionsRepositoryImpl(get<CoroutineScope>()) }
```

Update `MainStudioViewModel` factory:
```kotlin
viewModel { (id: Long) -> MainStudioViewModel(id, get(), get(), get(), get(), get(), get(), get()) }
```
_(adds CollectionsRepository as 7th parameter before DittoLogCaptureService)_

---

## Tests — `CollectionsRepositoryImplTest.kt`

```kotlin
class CollectionsRepositoryImplTest {

    @Test
    fun `stopObserving without startObserving does not crash`()

    @Test
    fun `stopObserving clears collections StateFlow`()

    @Test
    fun `createIndex generates correct DQL for simple field`()
    // Assert the DQL string: "CREATE INDEX IF NOT EXISTS idx_myCol_myField ON myCol (myField)"

    @Test
    fun `createIndex sanitizes dots and spaces in field name`()
    // "my.field name" → idx name becomes "idx_myCol_my_field_name"

    @Test
    fun `DittoCollection displayName strips collection prefix from index id`()
    // DittoIndex(id = "comments.idx_comments_movie_id", ...).displayName == "idx_comments_movie_id"

    @Test
    fun `DittoIndex displayFields strips backtick wrapping`()
    // fields = ["`movie_id`", "`year`"] → displayFields = ["movie_id", "year"]

    @Test
    fun `DittoIndex displayName returns id unchanged when no dot present`()
    // DittoIndex(id = "orphan_index", ...).displayName == "orphan_index"
}
```

The parsing logic (`fetchCollections`, `fetchIndexes`, `fetchDocCounts`) is tested indirectly via integration tests (future). Unit tests cover pure model logic and DQL string generation.

---

## Data Flow Diagram (Live Updates)

```
User opens MainStudio
        ↓
hydrate() → dittoManager.hydrate(database)
        ↓
collectionsRepository.startObserving(ditto)
        ├── Registers DittoStoreObserver on __collections
        └── scope.launch(IO) { refreshInternal() }
                ├── SELECT * FROM __collections  ← user collections only
                ├── SELECT * FROM system:indexes ← all indexes, grouped by collection
                └── SELECT COUNT(*) as numDocs FROM {each} ← doc counts
                ↓ (all parallel in future; sequential for now)
        _collections.value = enriched sorted list
                ↓
        DataPanel.collectAsState() recomposes
                ↓
        CollectionListItem tree renders

Any Ditto store change that affects __collections
        ↓
Observer fires → refreshInternal() again
        ↓
UI recomposes automatically
```

---

## Implementation Order

1. `domain/model/DittoCollection.kt`
2. `data/repository/CollectionsRepository.kt` (interface)
3. `data/repository/CollectionsRepositoryImpl.kt`
4. `data/di/DataModule.kt` (register singleton)
5. `viewmodel/MainStudioViewModel.kt` (inject + wire)
6. `ui/mainstudio/CollectionListItem.kt`
7. `ui/mainstudio/AddIndexSheet.kt`
8. `ui/mainstudio/MainStudioScreen.kt` (replace placeholders)
9. `test/.../CollectionsRepositoryImplTest.kt`
10. `./gradlew assembleDebug testDebugUnitTest` — verify

---

## Open Questions

1. **Concurrent doc count fetching:** Should `fetchDocCounts` run all COUNT queries concurrently using `async`/`awaitAll`? On large databases with many collections, sequential queries could be slow. The plan currently shows sequential for simplicity; concurrent is a trivial upgrade.

2. **Collection context menu:** The SwiftUI version offers a right-click context menu on each collection to populate `SELECT * FROM {name}` in the query editor. The Android Query tab is still "Coming Soon". Should the collection rows include a long-press menu now that populates clipboard, in anticipation of the query editor?

3. **`__des_sim` filtering:** The DittoSim feature plan mentions collections prefixed `__des_sim` should be hidden from the Collections UI. Should this filter be added now or deferred until DittoSim is implemented?

4. **Scroll position in sidebar:** The `DataPanel` uses a `verticalScroll`. As collections grow, the sidebar may be very long. Should collections be in a `LazyColumn` within the data panel (bounded height), or left as a regular scrolling Column?

5. **Initial expand state:** Should all collections be collapsed by default, or should the first collection auto-expand? SwiftUI starts all collapsed.

---

## Non-Goals for This Plan

- Query editor integration (QUERY tab is still "Coming Soon")
- Drop index functionality (SwiftUI doesn't have this either)
- Collection document browsing (future feature)
- DittoSim collection filtering (separate feature)
