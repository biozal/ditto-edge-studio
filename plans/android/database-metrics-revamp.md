# Plan: Android Database Metrics — VSC Parity Revamp

**Target screen:** the existing `DISK_USAGE` rail item, labelled **"Database Metrics"** in the rail
(`viewmodel/MainStudioViewModel.kt:41`). The implementation files are `DiskUsageScreen.kt` /
`DiskUsageViewModel.kt`. **App Metrics is a separate screen and is out of scope for this plan.**

**Design reference:** `screens/database-metrics-vsc.png` (VSC layout) plus the SwiftUI
implementation in `SwiftUI/EdgeStudio/Data/Repositories/StorageRepository.swift` and
`SwiftUI/EdgeStudio/Views/Metrics/AppMetricsDetailView.swift` (storage section).

**Status:** Ready for review

---

## 1. Goals

1. Match the VSC Database Metrics layout: header summary, a row of 7 compact storage-category
   tiles with per-category `% of total` + short description, and a tabular **Collections by CBOR
   payload size** list with `NAME / DOCUMENTS / CBOR SIZE / % OF PAYLOAD`.
2. Match the SwiftUI computation contract:
   - Storage breakdown driven by **`ditto.diskUsage.item`** tree (path-based categorization with
     WAL/SHM priority), not a raw `filesDir` walk.
   - Per-collection size driven by **`DittoQueryResultItem.cborData().size`**, not JSON byte
     length — this is the metric VSC and SwiftUI both display ("CBOR payload size").
3. Treat the snapshot as **expensive and manual** — no 15 s auto-refresh. First view loads
   once; subsequent updates only happen on tap of the Refresh button.
4. Keep `AppMetricsScreen` / `AppMetricsRepository` untouched. Database Metrics gets its own
   repository + model.

## 2. Current State Gap Analysis

| Concern | Current | Target (VSC + SwiftUI) |
|---|---|---|
| Storage source of truth | `filesDir/ditto` filesystem walk (`AppMetricsRepositoryImpl.kt:60-76`) | `ditto.diskUsage.item` tree (SDK-curated) |
| WAL/SHM detection | `.wal` / `.shm` suffix (wrong — Ditto files use `-wal` / `-shm`) | `-wal` / `-shm` suffix, checked **first** so they don't double-count into Store/Replication |
| Collection size | `item.jsonString().toByteArray(UTF_8).size` (`AppMetricsRepositoryImpl.kt:119`) | `item.cborData().size` — Ditto's native binary format |
| Refresh cadence | 15 s loop (`DiskUsageScreen.kt:56-61`) | Manual only — expensive; loop removed |
| Layout | Vertical list of category rows with progress bars + plain collection cards | Horizontal/wrapping row of compact tiles + tabular collection list |
| Per-category description | none | Short copy per tile, matches VSC wording |
| `% of total` per tile | implicit via progress bar | Explicit "X.X% of total" line |
| Collections section | "COLLECTIONS (n)" with each collection as a separate card | "Collections by CBOR payload size · N collections · X KB total" with a tabular list |
| Shares snapshot with AppMetrics | yes — same `AppMetrics` model and repo | no — dedicated `DatabaseMetrics` model + repo |

## 3. Architecture

### 3.1 New domain model — `domain/model/DatabaseMetrics.kt`

```kotlin
data class StorageCategory(
    val key: StorageCategoryKey,
    val bytes: Long,
)

enum class StorageCategoryKey(val label: String, val description: String) {
    STORE       ("Store",       "Primary document store (the SQLite files). Grows with document count and field richness."),
    REPLICATION ("Replication", "Sync state — what this peer has told other peers it has, and what it expects from them."),
    ATTACHMENTS ("Attachments", "Binary blobs linked from documents. Lives outside the document store."),
    AUTH        ("Auth",        "Auth tokens and session material. Usually tiny."),
    WAL_SHM     ("WAL / SHM",   "SQLite write-ahead log + shared-memory files. Spikes mid-transaction; reclaimed on checkpoint."),
    LOGS        ("Logs",        "SDK and extension log files. Safe to delete if you need disk space."),
    OTHER       ("Other",       "Lock files, metrics scratch, anything Ditto writes outside the named buckets."),
}

data class CollectionPayloadInfo(
    val name: String,
    val documentCount: Int,
    val cborPayloadBytes: Long,
)

data class DatabaseMetrics(
    val capturedAt: Long,
    val storage: List<StorageCategory>,         // ordered by StorageCategoryKey declaration
    val collections: List<CollectionPayloadInfo>, // sorted desc by cborPayloadBytes
) {
    val totalStorageBytes: Long = storage.sumOf { it.bytes }
    val collectionPayloadBytes: Long = collections.sumOf { it.cborPayloadBytes }
    fun percentOfTotal(category: StorageCategoryKey): Double =
        if (totalStorageBytes == 0L) 0.0 else storage.first { it.key == category }.bytes * 100.0 / totalStorageBytes
    fun percentOfPayload(c: CollectionPayloadInfo): Double =
        if (collectionPayloadBytes == 0L) 0.0 else c.cborPayloadBytes * 100.0 / collectionPayloadBytes
}
```

> **Note:** Tile descriptions are pulled straight from the VSC screenshot. If a wording change
> is needed later, it lives in one place.

### 3.2 New repository — `data/repository/DatabaseMetricsRepository{,Impl}.kt`

```kotlin
interface DatabaseMetricsRepository {
    suspend fun snapshot(ditto: Ditto): DatabaseMetrics
}

class DatabaseMetricsRepositoryImpl : DatabaseMetricsRepository {
    override suspend fun snapshot(ditto: Ditto): DatabaseMetrics = withContext(Dispatchers.IO) {
        val root = ditto.diskUsage.item
        val flat = flattenTree(root)
        val storage = categorize(flat) // pure fn — see §3.3
        val collections = computeCollectionBreakdown(ditto)
        DatabaseMetrics(
            capturedAt = System.currentTimeMillis(),
            storage = storage,
            collections = collections,
        )
    }
}
```

- `flattenTree` recursively walks `DittoDiskUsageItem.childItems` returning
  `List<Pair<String, Long>>` of `(path, sizeInBytes)`.
- `computeCollectionBreakdown` mirrors SwiftUI:
  1. `SELECT * FROM system:collections` → list of collection names.
  2. For each name, escape backticks (`` ` `` → ` `` `), `SELECT * FROM \`name\``.
  3. Sum `item.cborData().size.toLong()`, count rows, call `item.dematerialize()` to release
     CBOR / value memory immediately (matches SwiftUI's `doc.dematerialize()`).
  4. Sort by `cborPayloadBytes` descending.
- Any query failure on a single collection logs and is skipped (do **not** abort the snapshot).
  Returning an empty `collections` list when `system:collections` itself fails is acceptable.

### 3.3 Categorization — pure, testable

Top-level `internal` (or `@VisibleForTesting`) function so unit tests can call it without a
`Ditto` instance — mirroring `StorageRepository.categorizeFiles` in SwiftUI.

```kotlin
internal fun categorize(files: List<Pair<String, Long>>): List<StorageCategory> {
    var store = 0L; var rep = 0L; var att = 0L; var auth = 0L
    var walShm = 0L; var logs = 0L; var other = 0L
    for ((path, size) in files) {
        val p = path.lowercase()
        when {
            p.endsWith("-wal") || p.endsWith("-shm")             -> walShm += size
            "/ditto_logs/" in p || p.endsWith(".log") || p.endsWith(".log.gz") -> logs += size
            "/ditto_store/" in p                                  -> store += size
            "/ditto_attachments/" in p                            -> att += size
            "/ditto_auth" in p   /* matches ditto_auth/ and ditto_auth_tmp/ */ -> auth += size
            "/ditto_replication/" in p                            -> rep += size
            else                                                  -> other += size
        }
    }
    return listOf(
        StorageCategory(StorageCategoryKey.STORE,       store),
        StorageCategory(StorageCategoryKey.REPLICATION, rep),
        StorageCategory(StorageCategoryKey.ATTACHMENTS, att),
        StorageCategory(StorageCategoryKey.AUTH,        auth),
        StorageCategory(StorageCategoryKey.WAL_SHM,     walShm),
        StorageCategory(StorageCategoryKey.LOGS,        logs),
        StorageCategory(StorageCategoryKey.OTHER,       other),
    )
}
```

**Invariant:** WAL/SHM is checked first so a file like `/ditto_logs/foo-wal` lands in WAL/SHM,
not Logs — matches SwiftUI behaviour and is covered by a dedicated test.

### 3.4 DI registration

In `data/di/DataModule.kt`:

```kotlin
single<DatabaseMetricsRepository> { DatabaseMetricsRepositoryImpl() }
```

…and the existing `DiskUsageViewModel` binding loses its `AppMetricsRepository` dependency,
takes `DatabaseMetricsRepository` + `DittoManager` instead.

### 3.5 ViewModel — `viewmodel/DiskUsageViewModel.kt` (rewrite)

```kotlin
class DiskUsageViewModel(
    private val dittoManager: DittoManager,
    private val repo: DatabaseMetricsRepository,
) : ViewModel() {
    private val _metrics = MutableStateFlow<DatabaseMetrics?>(null)
    val metrics: StateFlow<DatabaseMetrics?> = _metrics.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _lastUpdatedAt = MutableStateFlow<Long?>(null)
    val lastUpdatedAt: StateFlow<Long?> = _lastUpdatedAt.asStateFlow()

    init { refresh() } // initial load only — no 15s loop

    fun refresh() {
        viewModelScope.launch {
            _isLoading.value = true
            runCatching {
                val ditto = dittoManager.currentInstance()
                    ?: error("No active Ditto instance")
                repo.snapshot(ditto)
            }.onSuccess {
                _metrics.value = it
                _lastUpdatedAt.value = it.capturedAt
            }.onFailure {
                Log.w("DiskUsageVM", "Snapshot failed", it)
            }
            _isLoading.value = false
        }
    }
}
```

- Drops `Context` (no longer needed — we don't walk the filesystem).
- Exposes `lastUpdatedAt` as `Long?` so the screen can format it as **"Refreshed at HH:MM:SS"**
  (matches VSC) — see §3.6.

### 3.6 Screen — `ui/mainstudio/metrics/DiskUsageScreen.kt` (rewrite)

Top-level structure:

```
Column {
    Header(totalOnDisk, lastUpdatedAt, isLoading, onRefresh)
    HorizontalDivider()
    when {
        isLoading && metrics == null -> CenteredProgress
        metrics == null              -> EmptyState
        else -> LazyColumn {
            item { StorageTileRow(metrics) }      // 7 tiles, wraps on narrow widths
            item { CollectionsSectionHeader(metrics) }
            item { CollectionsTableHeader() }
            items(metrics.collections) { CollectionRow(it, metrics.collectionPayloadBytes) }
        }
    }
}
```

**Header bar** (left → right): `total on disk` formatted as `XX.XX MB`, `Refreshed at HH:mm:ss`
(absolute local time, like VSC — uses `DateTimeFormatter.ofPattern("hh:mm:ss a")`), `Refresh`
`IconButton`. Falls back to `"Never"` when `lastUpdatedAt == null`.

**Storage tiles** — `FlowRow` from `androidx.compose.foundation.layout` with 7 fixed-width
children (each ~160 dp wide, ~110 dp tall). Each tile body:

```
LABEL (uppercase, labelSmall, onSurfaceVariant)
328.6 MB     (titleLarge, monospace, onSurface)
1.0% of total (labelSmall, onSurfaceVariant)
description… (bodySmall, onSurfaceVariant, maxLines = 3, ellipsize)
```

FlowRow lets the row wrap to 2/3/4/7 tiles per row depending on width — no horizontal
scrolling needed. The 7 tiles use the existing brand colors (`Color.kt`) for emphasis on the
size value.

**Collections section header:** `"Collections by CBOR payload size"` (titleSmall) with a
right-aligned `"N collections · X KB"` summary line — matches VSC.

**Collections table header row:** four labels — `NAME` / `DOCUMENTS` / `CBOR SIZE ↓` /
`% OF PAYLOAD` — in `labelSmall`, `onSurfaceVariant`. CBOR SIZE shows a down-arrow to
indicate the default sort. (Future enhancement: tap to flip; not in this plan.)

**Collection row:** `Row` with 4 weighted children: name (weight 2, monospace) — docs (weight
1, end-aligned, monospace) — CBOR (weight 1, end-aligned, monospace) — percent (weight 1,
end-aligned, monospace). Use a `HorizontalDivider` between rows.

**Empty state for collections:** when `metrics.collections.isEmpty()`, render a single
`Surface { Text("No collections in this database") }` in place of the table.

### 3.7 Optional rename (deferred — flagged for user decision)

The class names `DiskUsageScreen` / `DiskUsageViewModel` / `DiskUsageKey` /
`DiskUsageSection` predate the "Database Metrics" terminology. Renaming to
`DatabaseMetricsScreen` etc. would clarify intent but touches navigation persistence (the
`@Serializable` `DiskUsageKey` is restored from saved state on process death) and the
`diskusage.md` help reference (`MainStudioViewModel.kt:50`). Recommend **deferring** the
rename to a follow-up PR.

## 4. File-Level Change List

**New files**
- `app/src/main/java/com/costoda/dittoedgestudio/domain/model/DatabaseMetrics.kt`
- `app/src/main/java/com/costoda/dittoedgestudio/data/repository/DatabaseMetricsRepository.kt`
- `app/src/main/java/com/costoda/dittoedgestudio/data/repository/DatabaseMetricsRepositoryImpl.kt`
- `app/src/test/java/com/costoda/dittoedgestudio/data/repository/DatabaseMetricsCategorizeTest.kt`
- `app/src/test/java/com/costoda/dittoedgestudio/domain/model/DatabaseMetricsTest.kt`
- `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/DiskUsageViewModelTest.kt` (rewrite if a kept; otherwise replace)

**Edited**
- `app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/metrics/DiskUsageScreen.kt`
  — full rewrite to VSC layout.
- `app/src/main/java/com/costoda/dittoedgestudio/viewmodel/DiskUsageViewModel.kt`
  — swap dependency from `AppMetricsRepository`+`Context` to `DatabaseMetricsRepository`;
  drop the 15 s loop; expose `lastUpdatedAt: Long?`.
- `app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt`
  — register `DatabaseMetricsRepository`; update `DiskUsageViewModel` factory.
- `app/src/test/java/com/costoda/dittoedgestudio/viewmodel/DiskUsageViewModelTest.kt`
  — update for the new constructor/contract.

**Unchanged**
- `AppMetricsScreen.kt`, `AppMetricsViewModel.kt`, `AppMetrics.kt`,
  `AppMetricsRepository{,Impl}.kt` — App Metrics keeps its existing behaviour. (If a future
  cleanup wants App Metrics to also use the new tree-based storage, it can adopt
  `DatabaseMetricsRepository` then.)
- `NavKeys.kt`, `AppNavGraph.kt`, `SinglePaneSections.kt`, `MainStudioViewModel.kt` — no
  navigation or rail changes; the rail item still reads "Database Metrics".

## 5. Tests

### Unit tests (no Ditto required)

**`DatabaseMetricsCategorizeTest`** — port `StorageRepositoryTests.swift` CategorizationTests
verbatim:
- `ditto_store/` → STORE
- `ditto_replication/` → REPLICATION
- `ditto_attachments/` → ATTACHMENTS
- `ditto_auth/` and `ditto_auth_tmp/` → AUTH
- `ditto_logs/` directory + `.log` + `.log.gz` → LOGS
- `-wal` / `-shm` suffix → WAL_SHM **regardless of parent directory**
- `-wal` inside `ditto_logs/` → WAL_SHM (priority assertion)
- `ditto_system_info/`, lock files, `ditto_metrics/` → OTHER
- empty input → all zero

**`DatabaseMetricsTest`** — derived-field correctness:
- `totalStorageBytes` is the sum of all 7 categories.
- `percentOfTotal` returns 0 when total is 0 (no divide-by-zero).
- `collectionPayloadBytes` is the sum of all collection bytes.
- `percentOfPayload` returns 0 when payload total is 0.
- `collections` ordering is preserved (caller-sorted).

**`DiskUsageViewModelTest`** — using MockK on `DatabaseMetricsRepository` + `DittoManager`:
- `init` triggers one `refresh()`; no second call after the suspending one completes (no
  15 s loop).
- `refresh()` flips `isLoading` true → false even when the repo throws.
- `refresh()` updates `metrics` and `lastUpdatedAt` together on success.
- `refresh()` is a no-op for `metrics` when `dittoManager.currentInstance()` returns null
  (and logs / leaves the previous snapshot in place).

### Manual / smoke testing (Samsung tablet R5GL15XPVGA)

- Open Database Metrics from the rail. Initial snapshot appears within a few seconds, then
  no further updates until Refresh is tapped.
- 7 tiles visible at tablet width; tiles wrap to multiple rows at phone width
  (Pixel 10a 5C091JEA328801 in landscape vs portrait — verify FlowRow wraps to 4/2 cols).
- Each tile shows the brand `% of total` line; sum of the 7 percentages is ~100 (allow
  rounding).
- Collections list is sorted descending by CBOR size; percentages sum to 100.
- Backing out of the screen and re-entering does **not** trigger a new snapshot (the
  ViewModel-cached snapshot is displayed instantly).

No `connectedAndroidTest` runs — manual smoke only, per project convention.

## 6. Risks & Open Questions

1. **`ditto.diskUsage.item` cost.** The SwiftUI version wraps the `diskUsage.item` access in
   `Task.detached(priority: .utility)` because reading it walks the whole Ditto sub-tree.
   On Android we already run inside `Dispatchers.IO` in `snapshot()`, which is equivalent.
   No additional dispatch needed.

2. **Collection scan duration on large stores.** The repository iterates every document in
   every collection. For a 1 M-document collection this can take seconds — but it's exactly
   the contract VSC and SwiftUI promise ("expensive; press Refresh"). Manual refresh + the
   spinner in the header bar communicate this. No truncation / paging in this plan.

3. **`dematerialize()` semantics.** SwiftUI calls it on every doc to release the CBOR/value
   delegate. The Kotlin `DittoQueryResultItem` exposes the same method (`javap` confirms
   `public final void dematerialize()`). Calling it after `cborData()` reads is safe and
   keeps peak memory bounded. Verify behaviour on a large collection during smoke testing.

4. **System collections (`__presence`, etc.) in the list.** The VSC screenshot shows
   `__presence` so we mirror that — no filtering. If the user later wants a "user
   collections only" toggle, that's an additive feature.

5. **Tile description wording.** Pulled verbatim from VSC. Localization is out of scope —
   strings are inlined in the enum for now; can move to `strings.xml` if/when localization
   lands.

## 7. Implementation Order (suggested)

1. Add `DatabaseMetrics.kt` (model) + unit tests for derived fields.
2. Add `DatabaseMetricsRepository{,Impl}.kt` + `categorize` tests.
3. Wire DI; rewrite `DiskUsageViewModel.kt` + tests.
4. Rewrite `DiskUsageScreen.kt` (header → tiles → table).
5. Build for both phone + tablet widths; verify FlowRow wrapping.
6. Smoke test on the Pixel Tablet (large local store) — confirm CBOR sizes look sane and
   refresh completes in reasonable time.

## 8. Out of Scope (Follow-ups)

- Sortable column headers in the collections table.
- Filter to hide system collections (`__presence`, etc.).
- Class/file rename `DiskUsage*` → `DatabaseMetrics*`.
- Adopting the new tree-based storage in `AppMetricsRepository` (currently still uses the
  raw filesystem walk).
- Localization of tile descriptions.
