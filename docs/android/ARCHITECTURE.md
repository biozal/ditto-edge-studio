# Android Architecture Guide

Edge Studio for Android follows Clean Architecture with MVVM, using Room + SQLCipher for encrypted persistence, Koin for DI, and Kotlin Coroutines/Flow throughout.

---

## Layer Overview

```
┌─────────────────────────────────────────────────────┐
│  UI Layer (Compose)                                  │
│  ViewModels (viewModelScope + StateFlow)             │
├─────────────────────────────────────────────────────┤
│  Domain Layer                                        │
│  Repository interfaces  ·  Domain models             │
├─────────────────────────────────────────────────────┤
│  Data Layer                                          │
│  ┌─────────────────┐  ┌──────────────────────────┐  │
│  │  Ditto SDK       │  │  Room DAOs               │  │
│  │  DittoManager    │  │  AppDatabase + SQLCipher │  │
│  │  SystemRepository│  │  DatabaseKeyManager      │  │
│  │  NetworkDiagRepo │  └──────────────────────────┘  │
│  └─────────────────┘                                 │
└─────────────────────────────────────────────────────┘
```

**Layer rules:**
- UI imports Domain and Data only via injected repository interfaces
- ViewModels hold no Android `Context`; they receive repositories via Koin injection
- Repository implementations are in the Data layer; their interfaces are in Data too (same package, but the interface is what the UI/ViewModel depends on)
- Domain models have no Android or Room imports

---

## Domain Models

Located in `domain/model/`:

| Class | Description |
|-------|-------------|
| `DittoDatabase` | Database configuration (mirrors iOS `DittoConfigForDatabase`) |
| `DittoSubscription` | Stored sync subscription (name + query) |
| `DittoObservable` | Stored observable (name + query + active state) |
| `DittoQueryHistory` | Query history entry (query + timestamp) |
| `AuthMode` | Enum: `SERVER` or `SMALL_PEERS_ONLY` |
| `SyncStatusInfo` | Remote peer info from Ditto presence graph |
| `LocalPeerInfo` | This device's identity in the Ditto mesh |
| `ConnectionsByTransport` | Aggregated connection counts by transport type |
| `NetworkInterfaceInfo` | WiFi/Ethernet interface diagnostics |
| `P2PTransportInfo` | WiFi Aware / WiFi Direct hardware status |
| `PeerOS` | Enum: iOS, Android, macOS, Linux, Windows, Unknown |
| `ConnectionType` | Enum: Bluetooth, LAN, P2PWiFi, WebSocket, Unknown |

All domain models are Kotlin `data class` with no Android or Room imports.

---

## Database Layer (Room + SQLCipher)

### Encryption

`DatabaseKeyManager` manages database encryption:

1. Generates a random 32-byte passphrase on first run
2. Encrypts the passphrase with an AES-256-GCM key stored in the **Android Keystore**
3. Stores the encrypted passphrase (+ IV) in regular `SharedPreferences` (safe — protected by the Keystore key)
4. Returns the decrypted plaintext passphrase to `AppDatabase` for SQLCipher

The Keystore key is hardware-backed on devices that support it (Strongbox or TEE).

### AppDatabase

`AppDatabase` creates the Room database with SQLCipher:

```kotlin
Room.databaseBuilder(context, AppDatabase::class.java, "ditto_edge_studio.db")
    .openHelperFactory(SupportOpenHelperFactory(key))
    .fallbackToDestructiveMigration(dropAllTables = true)
    .build()
```

**Schema version:** starts at 1 (independent of iOS schema version 3 — separate devices, no cross-platform migration).

### Tables and Foreign Keys

```
databaseConfigs  ─┬─→  subscriptions  (databaseId FK, CASCADE DELETE)
                  ├─→  history         (databaseId FK, CASCADE DELETE)
                  ├─→  favorites       (databaseId FK, CASCADE DELETE)
                  └─→  observables     (databaseId FK, CASCADE DELETE)
```

Deleting a `databaseConfigs` row cascades to all child rows automatically.

### Entities

Located in `data/db/entity/`. Each entity uses `_id` as the PK column name (matching iOS schema naming).

### DAOs

Located in `data/db/dao/`. Each DAO provides:
- `observeByDatabase(databaseId)` returning `Flow<List<T>>` — live reactive stream
- `getByDatabase(databaseId)` returning `List<T>` — one-shot fetch (suspend)
- `insert`, `update`, `deleteById`, `deleteByDatabaseId`

---

## Koin Dependency Injection

### Module structure

`data/di/DataModule.kt` provides all singletons:

```kotlin
val dataModule = module {
    single { DatabaseKeyManager(androidContext()) }
    single { AppDatabase.create(androidContext(), get<DatabaseKeyManager>().getOrCreateKey()) }
    single { get<AppDatabase>().databaseConfigDao() }
    // ... other DAOs ...
    single<DatabaseRepository> { DatabaseRepositoryImpl(get()) }
    // ... other repositories ...
}
```

### Initialization

`MainApplication.onCreate()` calls `startKoin { androidLogger(); androidContext(this); modules(dataModule) }`.

Koin 4.1.x automatically provides compose context after `startKoin` — no `KoinContext {}` wrapper needed in Composables.

### Injection in ViewModels

```kotlin
class MyViewModel(
    private val repository: DatabaseRepository
) : ViewModel() {
    // ...
}

// In Compose:
val vm: MyViewModel = koinViewModel()
```

---

## Repository Pattern

Each repository is an interface in `data/repository/` with a co-located `*Impl` class.

**Interface responsibilities:**
- `observeXxx(databaseId)` — returns `Flow<List<T>>` for live UI updates
- `loadXxx(databaseId)` — suspend one-shot fetch
- `saveXxx(...)` / `removeXxx(id)` — mutations

**Implementation responsibilities:**
- Wraps all DAO calls in `withContext(Dispatchers.IO)`
- Maps entity ↔ domain model via private extension functions `toEntity()` / `toDomain()`
- Applies business rules: deduplication (History, Favorites), max-1000 cap (History)

### Entity ↔ Domain Mapping Pattern

```kotlin
// Extension functions at file scope (private to the impl file)
private fun HistoryEntity.toDomain() = DittoQueryHistory(
    id = id, databaseId = databaseId, query = query, createdDate = createdDate
)

private fun DittoQueryHistory.toEntity() = HistoryEntity(
    id = id, databaseId = databaseId, query = query, createdDate = createdDate
)
```

---

## Coroutines and Flow Conventions

| Context | Pattern |
|---------|---------|
| DAO queries in repo | `withContext(Dispatchers.IO) { dao.getXxx() }` |
| Flow from DAO | Flows from Room run on `Dispatchers.IO` automatically — no explicit dispatch needed |
| ViewModel collection | `viewModelScope.launch { repository.observeXxx().collect { _state.value = it } }` |
| ViewModel one-shot | `viewModelScope.launch { val items = repository.loadXxx(id) }` |
| UI state | `StateFlow<UiState>` in ViewModel, collected with `collectAsStateWithLifecycle()` in Compose |

---

## UI Layout Anatomy

The studio is implemented in `ui/mainstudio/StudioScaffold.kt` (chrome) hosting a Navigation 3 `NavDisplay` defined in `ui/navigation/AppNavGraph.kt`, with Material 3 Adaptive `ListDetailSceneStrategy` scenes. These are the canonical names used in all docs, plans, and task descriptions:

| Term | Code | Description |
|------|------|-------------|
| **Rail** | `NavigationRail` in `StudioScaffold` | Vertical strip of navigation icons (`StudioNavItem`); visible at ≥600dp; selection = current `StudioSectionKey` on the Nav3 back stack |
| **Data Panel** | `ListDetailSceneStrategy.listPane` (scene-managed width; preferred 320dp at ≥1200dp) | Feature/info menu for the selected Rail item; default-visible at ≥840dp |
| **Content Pane** | `ListDetailSceneStrategy.detailPane` (or `detailPlaceholder`) | Main working area: query editor, results, observers, etc. |
| **Inspector** | Inspector column in `StudioScaffold` (300dp <1200dp / 360dp ≥1200dp / 400dp ≥1600dp); `ModalBottomSheet` at compact widths | Trailing slide-out panel; default-visible at ≥1200dp |
| **Nav Drawer** | `ModalNavigationDrawer` in `StudioScaffold` | Compact-width (<600dp) collapse of Rail into a modal drawer |

See [`UI_TERMINOLOGY.md`](UI_TERMINOLOGY.md) for the full cheat sheet, including the comparison with the SwiftUI (macOS/iPadOS) app's three-column layout.

---

## Testing Strategy

### Unit Tests (`app/src/test/`)

- **Framework:** JUnit4 + MockK + kotlinx-coroutines-test
- **Scope:** Domain model logic, repository business rules
- **No Android dependencies** — runs on JVM only
- Mock DAOs with MockK `@MockK` annotation
- Use `runTest {}` for coroutine tests
- `@Before` + `MockKAnnotations.init(this)`, `@After` + `clearAllMocks()`

**Example:**
```kotlin
@Test
fun `saveFavorite returns null when duplicate exists`() = runTest {
    val existing = FavoriteEntity(...)
    coEvery { dao.findDuplicate("db1", "SELECT *") } returns existing

    val id = repository.saveFavorite("db1", "SELECT *")

    assertNull(id)
    coVerify(exactly = 0) { dao.insert(any()) }
}
```

### Instrumented DAO Tests (`app/src/androidTest/`)

- **Framework:** JUnit4 + Room in-memory database (no SQLCipher)
- **Scope:** SQL correctness, FK cascades, Flow emissions
- **Requires emulator or device**
- Build in-memory DB per test class: `Room.inMemoryDatabaseBuilder(context, AppDatabase::class.java).allowMainThreadQueries().build()`
- Always insert parent `DatabaseConfigEntity` row before child rows (FK constraint)
- Close DB in `@After`

**Run instrumented tests:**
```bash
./gradlew connectedAndroidTest
```

---

## Reference

- [Android Architecture Recommendations](https://developer.android.com/topic/architecture/recommendations)
- [Room documentation](https://developer.android.com/training/data-storage/room)
- [SQLCipher for Android](https://www.zetetic.net/sqlcipher/sqlcipher-for-android/)
- [Koin documentation](https://insert-koin.io/docs/quickstart/android)
- [Kotlin Coroutines guide](https://kotlinlang.org/docs/coroutines-guide.html)
