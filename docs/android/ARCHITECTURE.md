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
Room.databaseBuilder(context, AppDatabase::class.java, DB_NAME)
    .openHelperFactory(SupportOpenHelperFactory(key))
    .addMigrations(MIGRATION_1_2, MIGRATION_2_3, /* … */)
    .build()
```

**Migration policy:** every schema version bump requires a hand-written `Migration`
in `AppDatabase.kt` plus a committed schema JSON under `app/schemas/`, validated by
`MigrationTest` (`app/src/androidTest/.../data/db/MigrationTest.kt`).
`fallbackToDestructiveMigration` is deliberately NOT used — a missing migration throws
on launch so the bug surfaces in QA instead of silently wiping every saved database
config, subscription, observer, favorite, and history row in production (see the policy
comment in `AppDatabase.kt` and `plans/android/config-loss-investigation.md` item B1).
See `AppDatabase.kt` for the current schema version (independent of the iOS schema
version — separate devices, no cross-platform migration).

### Tables and Foreign Keys

```
databaseConfigs  ─┬─→  subscriptions  (databaseId FK, CASCADE DELETE)
                  ├─→  history         (databaseId FK, CASCADE DELETE)
                  ├─→  favorites       (databaseId FK, CASCADE DELETE)
                  └─→  observables     (databaseId FK, CASCADE DELETE)

query_metrics     standalone — no foreign key; its history_id column references
                  history._id by convention only (see QueryMetricsEntity.kt)
```

Deleting a `databaseConfigs` row cascades to all child rows automatically.
`query_metrics` (per-execution EXPLAIN stats, 200-record cap) is intentionally
standalone — check `QueryMetricsEntity.kt` for its current columns.

### Entities

Located in `data/db/entity/`. Each entity uses `_id` as the PK column name (matching iOS schema naming).

### DAOs

Located in `data/db/dao/`. Each DAO provides:
- `observeByDatabase(databaseId)` returning `Flow<List<T>>` — live reactive stream
- `getByDatabase(databaseId)` returning `List<T>` — one-shot fetch (suspend)
- `insert`, `update`, `deleteById`, `deleteByDatabaseId`

### User Preferences (DataStore)

Simple user settings live outside Room in Jetpack DataStore (Preferences):
`data/preferences/AppPreferences.kt` (implements `AppPreferencesGateway`), backed by
the `Context.appPreferencesDataStore` singleton (`app_prefs`). Currently exposes:

- `metricsEnabled` — the Settings screen's "Collect Metrics" toggle (default ON);
  gates the App Metrics / Query Metrics rail items and query-metrics capture
- `presenceSplitView` — the Settings screen's "Split Presence view" toggle
  (default OFF); see `docs/android/RAIL_FEATURES.md` §1

The Settings screen (`ui/settings/SettingsScreen.kt`, opened from the Database List
top bar) edits these via `SettingsViewModel`.

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
| **Rail** | `NavigationRail` in `StudioScaffold` | Vertical strip of navigation icons (`StudioNavItem`); visible as a column at ≥840dp; folded into the Nav Drawer below 840dp |
| **Data Panel** | `ListDetailSceneStrategy.listPane` (scene-managed width; preferred 300dp at 600–1199dp, 320dp at ≥1200dp) | Feature/info menu for the selected Rail item; visible side-by-side at ≥600dp; below 600dp lives inside the Nav Drawer alongside the rail items. Exception: Presence with "Split Presence view" off (the default) keeps the Content Pane full-width and the list in the drawer (drawer widths) or a toolbar dialog (rail widths) |
| **Content Pane** | `ListDetailSceneStrategy.detailPane` (or `detailPlaceholder`) | Main working area: query editor, results, observers, etc. Side-by-side with the Data Panel at ≥600dp; full-width below 600dp (list-first drill-in for Query Metrics / Observation). |
| **Inspector** | Inspector column in `StudioScaffold` (300dp <1200dp / 360dp ≥1200dp / 400dp ≥1600dp); `ModalBottomSheet` below 840dp | Trailing slide-out panel; default-visible at ≥1200dp |
| **Nav Drawer** | `ModalNavigationDrawer` in `StudioScaffold` | Below 840dp: holds the Rail items; below 600dp ALSO the section's Data Panel (rail items at top, divider, Data Panel below). Selecting any item closes the drawer. |

See [`UI_TERMINOLOGY.md`](UI_TERMINOLOGY.md) for the full cheat sheet, including the comparison with the SwiftUI (macOS/iPadOS) app's three-column layout.

---

## Networking and Security Posture

- **Local database encryption:** Room database encrypted with SQLCipher; passphrase
  wrapped by an Android Keystore key (see Database Layer above).
- **Cleartext traffic is deliberately permitted.** The manifest sets neither
  `android:usesCleartextTraffic="false"` nor a `networkSecurityConfig`, so the
  platform default (cleartext allowed) applies. This is intentional: Edge Studio is
  a database administration tool that must reach `ws://` Ditto peers on LANs and
  user-supplied HTTP auth/websocket endpoints that may not offer TLS. Do not add a
  cleartext restriction without a per-endpoint opt-out story.
- **Ditto sync traffic** itself is encrypted by the Ditto SDK regardless of
  transport; the cleartext allowance only affects plain HTTP/WebSocket endpoints
  the user explicitly configures.

---

## Release Build Posture

The `release` build type (`app/build.gradle.kts`) currently ships **unminified**
(`isMinifyEnabled = false`) and with **no `signingConfig`** (debug signing). This is
a deliberate choice for the beta: it keeps stack traces readable and sidesteps
release-keystore management while the app is not yet broadly distributed.
`app/proguard-rules.pro` already exists and is wired via `proguardFiles(...)` so it
is ready for when minify is enabled. **Revisit both settings before GA** — a
shrunk/obfuscated build with a proper release keystore will be required for
distribution outside the beta channel.

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
