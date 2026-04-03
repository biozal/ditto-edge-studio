# Android Observable Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the full Observer Events feature for Android, enabling users to create observers with DQL queries, activate them for live change events, and inspect event details with insert/update/delete/move diffs.

**Architecture:** Extend `MainStudioViewModel` with observer state following the existing subscription pattern (`activeHandles` map, `editingSubscription` sheet state, CRUD methods). New UI composables for editor sheet, list item, events table, and event detail. `DittoDiffer` from the Kotlin SDK handles diff computation.

**Tech Stack:** Kotlin, Jetpack Compose (Material3), Ditto Kotlin SDK v5 (`DittoStoreObserver`, `DittoDiffer`), Room (existing tables), Koin DI, MockK for tests.

**Design Spec:** `docs/superpowers/specs/2026-04-03-android-observable-events-design.md`

**Base path:** `android/app/src/main/java/com/costoda/dittoedgestudio`  
**Test path:** `android/app/src/test/java/com/costoda/dittoedgestudio`

---

### Task 1: Create DittoObserveEvent Model

**Files:**
- Create: `domain/model/DittoObserveEvent.kt`
- Create test: `domain/model/DittoObserveEventTest.kt`

- [ ] **Step 1: Write the test file**

Create `android/app/src/test/java/com/costoda/dittoedgestudio/domain/model/DittoObserveEventTest.kt`:

```kotlin
package com.costoda.dittoedgestudio.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DittoObserveEventTest {

    @Test
    fun `default values are correct`() {
        val event = DittoObserveEvent(observeId = "obs1")
        assertTrue(event.id.isNotBlank())
        assertEquals("obs1", event.observeId)
        assertTrue(event.data.isEmpty())
        assertTrue(event.insertIndexes.isEmpty())
        assertTrue(event.updatedIndexes.isEmpty())
        assertTrue(event.deletedIndexes.isEmpty())
        assertTrue(event.movedIndexes.isEmpty())
        assertTrue(event.eventTime.isEmpty())
    }

    @Test
    fun `getInsertedData returns documents at insert indexes`() {
        val event = DittoObserveEvent(
            observeId = "obs1",
            data = listOf("""{"_id":"a"}""", """{"_id":"b"}""", """{"_id":"c"}"""),
            insertIndexes = listOf(0, 2),
            eventTime = "2026-04-03T12:00:00Z",
        )
        val inserted = event.getInsertedData()
        assertEquals(2, inserted.size)
        assertEquals("""{"_id":"a"}""", inserted[0])
        assertEquals("""{"_id":"c"}""", inserted[1])
    }

    @Test
    fun `getUpdatedData returns documents at updated indexes`() {
        val event = DittoObserveEvent(
            observeId = "obs1",
            data = listOf("""{"_id":"a"}""", """{"_id":"b"}"""),
            updatedIndexes = listOf(1),
            eventTime = "2026-04-03T12:00:00Z",
        )
        val updated = event.getUpdatedData()
        assertEquals(1, updated.size)
        assertEquals("""{"_id":"b"}""", updated[0])
    }

    @Test
    fun `getInsertedData handles out-of-bounds indexes gracefully`() {
        val event = DittoObserveEvent(
            observeId = "obs1",
            data = listOf("""{"_id":"a"}"""),
            insertIndexes = listOf(0, 5),
            eventTime = "2026-04-03T12:00:00Z",
        )
        val inserted = event.getInsertedData()
        assertEquals(1, inserted.size)
        assertEquals("""{"_id":"a"}""", inserted[0])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
cd android && ./gradlew testDebugUnitTest --tests "com.costoda.dittoedgestudio.domain.model.DittoObserveEventTest" 2>&1 | tail -5
```

Expected: FAIL — class not found.

- [ ] **Step 3: Create the model**

Create `android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/DittoObserveEvent.kt`:

```kotlin
package com.costoda.dittoedgestudio.domain.model

import java.util.UUID

data class DittoObserveEvent(
    val id: String = UUID.randomUUID().toString(),
    val observeId: String,
    val data: List<String> = emptyList(),
    val insertIndexes: List<Int> = emptyList(),
    val updatedIndexes: List<Int> = emptyList(),
    val deletedIndexes: List<Int> = emptyList(),
    val movedIndexes: List<Pair<Int, Int>> = emptyList(),
    val eventTime: String = "",
) {
    fun getInsertedData(): List<String> = insertIndexes.mapNotNull { data.getOrNull(it) }
    fun getUpdatedData(): List<String> = updatedIndexes.mapNotNull { data.getOrNull(it) }
}

enum class EventFilterMode { ALL, INSERTED, UPDATED }
```

- [ ] **Step 4: Run test to verify it passes**

```bash
cd android && ./gradlew testDebugUnitTest --tests "com.costoda.dittoedgestudio.domain.model.DittoObserveEventTest" 2>&1 | tail -5
```

Expected: 4 tests PASSED.

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/domain/model/DittoObserveEvent.kt \
       android/app/src/test/java/com/costoda/dittoedgestudio/domain/model/DittoObserveEventTest.kt
git commit -m "feat(android): add DittoObserveEvent model with tests"
```

---

### Task 2: Add Observer State and CRUD to MainStudioViewModel

**Files:**
- Modify: `viewmodel/MainStudioViewModel.kt`
- Modify: `data/di/DataModule.kt`
- Modify test: `viewmodel/MainStudioViewModelTest.kt`

- [ ] **Step 1: Write tests for observer CRUD**

Add to the existing `android/app/src/test/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModelTest.kt`. Add these imports at the top alongside existing imports:

```kotlin
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.domain.model.DittoObservable
```

Add a new mock field alongside existing mocks in the class body (near the other `lateinit var` declarations):

```kotlin
private lateinit var observableRepository: ObservableRepository
```

In `setUp()`, add after the other mock initializations:

```kotlin
observableRepository = mockk()
coEvery { observableRepository.loadObservables(any()) } returns emptyList()
```

Update the `createViewModel()` helper to include the new parameter:

```kotlin
private fun createViewModel() = MainStudioViewModel(
    databaseId = 1L,
    databaseRepository = databaseRepository,
    dittoManager = dittoManager,
    systemRepository = systemRepository,
    networkRepo = networkRepo,
    subscriptionsRepository = subscriptionsRepository,
    collectionsRepository = collectionsRepository,
    loggingCaptureService = loggingCaptureService,
    observableRepository = observableRepository,
    ioDispatcher = testDispatcher,
)
```

Add these test methods:

```kotlin
@Test
fun `hydrate loads observers from repository`() = runTest {
    val obs = listOf(DittoObservable(id = 1, databaseId = "testDb", name = "Obs1", query = "SELECT * FROM c"))
    coEvery { observableRepository.loadObservables("testDb") } returns obs

    val vm = createViewModel()
    advanceUntilIdle()

    assertEquals(1, vm.observers.value.size)
    assertEquals("Obs1", vm.observers.value[0].name)
}

@Test
fun `addObserver saves to repository and updates state`() = runTest {
    val vm = createViewModel()
    advanceUntilIdle()

    coEvery { observableRepository.saveObservable(any()) } returns 10L
    coEvery { observableRepository.loadObservables(any()) } returns listOf(
        DittoObservable(id = 10, databaseId = "testDb", name = "New", query = "SELECT * FROM t"),
    )

    vm.addObserver("New", "SELECT * FROM t")
    advanceUntilIdle()

    coVerify { observableRepository.saveObservable(any()) }
    assertEquals(1, vm.observers.value.size)
}

@Test
fun `removeObserver deletes from repository and updates state`() = runTest {
    val obs = DittoObservable(id = 5, databaseId = "testDb", name = "Obs", query = "SELECT * FROM c")
    coEvery { observableRepository.loadObservables(any()) } returns listOf(obs)

    val vm = createViewModel()
    advanceUntilIdle()

    coEvery { observableRepository.loadObservables(any()) } returns emptyList()
    vm.removeObserver(obs)
    advanceUntilIdle()

    coVerify { observableRepository.removeObservable(5) }
    assertTrue(vm.observers.value.isEmpty())
}

@Test
fun `onCleared closes active observer handles`() = runTest {
    val vm = createViewModel()
    advanceUntilIdle()
    // Verify onCleared doesn't crash with no active handles
    vm.onCleared()
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd android && ./gradlew testDebugUnitTest --tests "com.costoda.dittoedgestudio.viewmodel.MainStudioViewModelTest" 2>&1 | tail -10
```

Expected: FAIL — `MainStudioViewModel` constructor doesn't accept `observableRepository` yet.

- [ ] **Step 3: Add ObservableRepository to MainStudioViewModel constructor and state**

Modify `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt`:

Add import at top:

```kotlin
import com.costoda.dittoedgestudio.data.repository.ObservableRepository
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.EventFilterMode
import com.ditto.kotlin.DittoStoreObserver
```

Add `observableRepository` parameter to the constructor (after `loggingCaptureService`):

```kotlin
class MainStudioViewModel(
    private val databaseId: Long,
    private val databaseRepository: DatabaseRepository,
    private val dittoManager: DittoManager,
    private val systemRepository: SystemRepository,
    private val networkRepo: NetworkDiagnosticsRepository,
    private val subscriptionsRepository: SubscriptionsRepository,
    val collectionsRepository: CollectionsRepository,
    val loggingCaptureService: DittoLogCaptureService,
    private val observableRepository: ObservableRepository,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
) : ViewModel() {
```

Add observer state properties after the subscription state block (after `private val activeHandles = ...` line):

```kotlin
    // ── Observer state ──────────────────────────────────────────────
    private val _observers = MutableStateFlow<List<DittoObservable>>(emptyList())
    val observers: StateFlow<List<DittoObservable>> = _observers.asStateFlow()

    var editingObserver by mutableStateOf<DittoObservable?>(null)

    private val activeObserverHandles = mutableMapOf<Long, DittoStoreObserver>()

    private val _observerEvents = MutableStateFlow<List<DittoObserveEvent>>(emptyList())
    val observerEvents: StateFlow<List<DittoObserveEvent>> = _observerEvents.asStateFlow()

    var selectedObserver by mutableStateOf<DittoObservable?>(null)
    var selectedEvent by mutableStateOf<DittoObserveEvent?>(null)
    var eventFilterMode by mutableStateOf(EventFilterMode.ALL)
    var eventPageSize by mutableStateOf(25)
    var eventCurrentPage by mutableStateOf(0)
```

Add observer loading to the `hydrate()` method, after `_subscriptions.value = saved`:

```kotlin
                val savedObservers = observableRepository.loadObservables(database.databaseId)
                _observers.value = savedObservers
```

Add CRUD methods after the existing `removeSubscription()` method:

```kotlin
    // ── Observer CRUD ───────────────────────────────────────────────

    fun addObserver(name: String, query: String) {
        val db = currentDatabase ?: return
        viewModelScope.launch(ioDispatcher) {
            runCatching {
                val obs = DittoObservable(databaseId = db.databaseId, name = name, query = query)
                observableRepository.saveObservable(obs)
                _observers.value = observableRepository.loadObservables(db.databaseId)
            }.onFailure { e -> hydrateError = e.message }
            editingObserver = null
        }
    }

    fun updateObserver(observer: DittoObservable, name: String, query: String) {
        val db = currentDatabase ?: return
        viewModelScope.launch(ioDispatcher) {
            runCatching {
                // Deactivate if active before updating query
                activeObserverHandles.remove(observer.id)?.close()
                _observerEvents.update { events -> events.filter { it.observeId != observer.id.toString() } }
                val updated = observer.copy(name = name, query = query, isActive = false)
                observableRepository.updateObservable(updated)
                _observers.value = observableRepository.loadObservables(db.databaseId)
                if (selectedObserver?.id == observer.id) selectedObserver = updated
            }.onFailure { e -> hydrateError = e.message }
            editingObserver = null
        }
    }

    fun removeObserver(observer: DittoObservable) {
        val db = currentDatabase ?: return
        viewModelScope.launch(ioDispatcher) {
            activeObserverHandles.remove(observer.id)?.close()
            observableRepository.removeObservable(observer.id)
            _observerEvents.update { events -> events.filter { it.observeId != observer.id.toString() } }
            _observers.value = observableRepository.loadObservables(db.databaseId)
            if (selectedObserver?.id == observer.id) {
                selectedObserver = null
                selectedEvent = null
            }
        }
    }
```

Add observer cleanup to `onCleared()`, before the closing brace:

```kotlin
        activeObserverHandles.values.forEach { it.close() }
        activeObserverHandles.clear()
        _observers.value = emptyList()
        _observerEvents.value = emptyList()
```

- [ ] **Step 4: Update Koin DI registration**

Modify `android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt`.

Update the MainStudioViewModel registration line (currently 9 `get()` calls for 8 params + id) to add `get()` for `observableRepository`:

Change:
```kotlin
    viewModel { (id: Long) -> MainStudioViewModel(id, get(), get(), get(), get(), get(), get(), get()) }
```
To:
```kotlin
    viewModel { (id: Long) -> MainStudioViewModel(id, get(), get(), get(), get(), get(), get(), get(), get()) }
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd android && ./gradlew testDebugUnitTest --tests "com.costoda.dittoedgestudio.viewmodel.MainStudioViewModelTest" 2>&1 | tail -10
```

Expected: All tests PASSED (existing + 4 new).

- [ ] **Step 6: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt \
       android/app/src/main/java/com/costoda/dittoedgestudio/data/di/DataModule.kt \
       android/app/src/test/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModelTest.kt
git commit -m "feat(android): add observer state and CRUD to MainStudioViewModel"
```

---

### Task 3: Add Observer Activation and Event Capture

**Files:**
- Modify: `viewmodel/MainStudioViewModel.kt`

- [ ] **Step 1: Add activation and deactivation methods**

Add after the `removeObserver()` method in `MainStudioViewModel.kt`:

```kotlin
    // ── Observer lifecycle ───────────────────────────────────────────

    fun activateObserver(observer: DittoObservable) {
        val ditto = dittoManager.currentInstance() ?: return
        val db = currentDatabase ?: return
        if (activeObserverHandles.containsKey(observer.id)) return

        val differ = com.ditto.kotlin.DittoDiffer()

        val handle = ditto.store.registerObserver(observer.query) { results ->
            val diff = differ.diff(results.items)
            val docs = results.items.map { it.jsonString() }

            val event = DittoObserveEvent(
                observeId = observer.id.toString(),
                data = docs,
                insertIndexes = diff.insertions.toList(),
                updatedIndexes = diff.updates.toList(),
                deletedIndexes = diff.deletions.toList(),
                movedIndexes = diff.moves.map { it.from to it.to },
                eventTime = java.time.Instant.now().toString(),
            )

            viewModelScope.launch {
                _observerEvents.update { it + event }
            }
        }

        activeObserverHandles[observer.id] = handle
        viewModelScope.launch(ioDispatcher) {
            val updated = observer.copy(isActive = true, lastUpdated = System.currentTimeMillis())
            observableRepository.updateObservable(updated)
            _observers.value = observableRepository.loadObservables(db.databaseId)
        }
    }

    fun deactivateObserver(observer: DittoObservable) {
        val db = currentDatabase ?: return
        activeObserverHandles.remove(observer.id)?.close()
        _observerEvents.update { events -> events.filter { it.observeId != observer.id.toString() } }

        viewModelScope.launch(ioDispatcher) {
            val updated = observer.copy(isActive = false)
            observableRepository.updateObservable(updated)
            _observers.value = observableRepository.loadObservables(db.databaseId)
        }

        if (selectedObserver?.id == observer.id) {
            selectedEvent = null
            eventCurrentPage = 0
        }
    }

    fun isObserverActive(observer: DittoObservable): Boolean =
        activeObserverHandles.containsKey(observer.id)

    fun selectObserver(observer: DittoObservable) {
        selectedObserver = observer
        selectedEvent = null
        eventCurrentPage = 0
        eventFilterMode = EventFilterMode.ALL
    }

    fun selectEvent(event: DittoObserveEvent) {
        selectedEvent = event
    }

    fun selectedObserverEvents(): List<DittoObserveEvent> {
        val obsId = selectedObserver?.id?.toString() ?: return emptyList()
        return _observerEvents.value.filter { it.observeId == obsId }
    }
```

- [ ] **Step 2: Verify build compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL. (Note: the exact `DittoDiffer` and `DittoStoreObserver` API may need minor adjustments based on the actual Kotlin SDK. If `diff.insertions` is a different property name, adjust accordingly.)

- [ ] **Step 3: Run all existing tests still pass**

```bash
cd android && ./gradlew testDebugUnitTest 2>&1 | tail -5
```

Expected: All tests PASSED.

- [ ] **Step 4: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/MainStudioViewModel.kt
git commit -m "feat(android): add observer activation with DittoDiffer event capture"
```

---

### Task 4: Create ObserverEditorSheet

**Files:**
- Create: `ui/mainstudio/ObserverEditorSheet.kt`

- [ ] **Step 1: Create the editor sheet composable**

Create `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverEditorSheet.kt`:

```kotlin
@file:OptIn(ExperimentalMaterial3Api::class)

package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObservable

@Composable
fun ObserverEditorSheet(
    initial: DittoObservable,
    onSave: (name: String, query: String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    var name by remember { mutableStateOf(initial.name) }
    var query by remember { mutableStateOf(initial.query) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(bottom = 24.dp),
        ) {
            Text(
                text = if (initial.id == 0L) "New Observer" else "Edit Observer",
                modifier = Modifier.padding(bottom = 16.dp),
            )

            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text("Name (optional)") },
                placeholder = { Text("My Observer") },
                singleLine = true,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(12.dp))

            OutlinedTextField(
                value = query,
                onValueChange = { query = it },
                label = { Text("Query") },
                placeholder = { Text("SELECT * FROM collection") },
                minLines = 4,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(modifier = Modifier.height(16.dp))

            Row(modifier = Modifier.fillMaxWidth()) {
                OutlinedButton(
                    onClick = onDismiss,
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Cancel")
                }
                Spacer(modifier = Modifier.width(8.dp))
                Button(
                    onClick = { onSave(name.trim(), query.trim()) },
                    enabled = query.isNotBlank(),
                    modifier = Modifier.weight(1f),
                ) {
                    Text("Save")
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverEditorSheet.kt
git commit -m "feat(android): add ObserverEditorSheet composable"
```

---

### Task 5: Create ObserverListItem

**Files:**
- Create: `ui/mainstudio/ObserverListItem.kt`

- [ ] **Step 1: Create the list item composable**

Create `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverListItem.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObservable

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun ObserverListItem(
    observer: DittoObservable,
    isSelected: Boolean,
    isActive: Boolean,
    onSelect: () -> Unit,
    onActivate: () -> Unit,
    onDeactivate: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var showMenu by remember { mutableStateOf(false) }

    val backgroundColor = if (isSelected) {
        MaterialTheme.colorScheme.primary.copy(alpha = 0.12f)
    } else {
        Color.Transparent
    }

    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClick = onSelect,
                    onLongClick = { showMenu = true },
                )
                .background(backgroundColor)
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = observer.name.ifBlank { observer.query.take(30) },
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                if (isActive) {
                    Spacer(modifier = Modifier.width(8.dp))
                    Box(
                        modifier = Modifier
                            .size(8.dp)
                            .clip(CircleShape)
                            .background(Color(0xFF4CAF50)),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(
                        text = "Active",
                        style = MaterialTheme.typography.labelSmall,
                        color = Color(0xFF4CAF50),
                    )
                }
            }
            Text(
                text = observer.query,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }

        DropdownMenu(
            expanded = showMenu,
            onDismissRequest = { showMenu = false },
        ) {
            if (isActive) {
                DropdownMenuItem(
                    text = { Text("Stop") },
                    onClick = { showMenu = false; onDeactivate() },
                )
            } else {
                DropdownMenuItem(
                    text = { Text("Activate") },
                    onClick = { showMenu = false; onActivate() },
                )
            }
            DropdownMenuItem(
                text = { Text("Edit") },
                onClick = { showMenu = false; onEdit() },
            )
            DropdownMenuItem(
                text = { Text("Delete") },
                onClick = { showMenu = false; onDelete() },
            )
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverListItem.kt
git commit -m "feat(android): add ObserverListItem composable"
```

---

### Task 6: Create ObserverEventsTable

**Files:**
- Create: `ui/mainstudio/ObserverEventsTable.kt`

- [ ] **Step 1: Create the events table composable**

Create `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverEventsTable.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent

private data class TableColumn(val label: String, val width: Dp)

private val columns = listOf(
    TableColumn("Time", 180.dp),
    TableColumn("Count", 70.dp),
    TableColumn("Inserted", 80.dp),
    TableColumn("Updated", 80.dp),
    TableColumn("Deleted", 70.dp),
    TableColumn("Moves", 70.dp),
)

@Composable
fun ObserverEventsTable(
    events: List<DittoObserveEvent>,
    selectedEvent: DittoObserveEvent?,
    onSelectEvent: (DittoObserveEvent) -> Unit,
    modifier: Modifier = Modifier,
) {
    val scrollState = rememberScrollState()

    Column(modifier = modifier) {
        // Sticky header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(scrollState)
                .background(MaterialTheme.colorScheme.surfaceVariant)
                .padding(vertical = 8.dp),
        ) {
            columns.forEach { col ->
                Text(
                    text = col.label,
                    style = MaterialTheme.typography.labelSmall,
                    fontFamily = FontFamily.Monospace,
                    modifier = Modifier
                        .width(col.width)
                        .padding(horizontal = 8.dp),
                )
            }
        }

        // Event rows
        LazyColumn(modifier = Modifier.fillMaxWidth()) {
            itemsIndexed(events, key = { _, event -> event.id }) { index, event ->
                val isSelected = event.id == selectedEvent?.id
                val rowBackground = when {
                    isSelected -> MaterialTheme.colorScheme.primary.copy(alpha = 0.2f)
                    index % 2 == 1 -> MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.3f)
                    else -> MaterialTheme.colorScheme.surface
                }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .horizontalScroll(scrollState)
                        .clickable { onSelectEvent(event) }
                        .background(rowBackground)
                        .padding(vertical = 6.dp),
                ) {
                    val values = listOf(
                        event.eventTime.substringAfter("T").substringBefore("."),
                        event.data.size.toString(),
                        event.insertIndexes.size.toString(),
                        event.updatedIndexes.size.toString(),
                        event.deletedIndexes.size.toString(),
                        event.movedIndexes.size.toString(),
                    )
                    values.forEachIndexed { i, value ->
                        Text(
                            text = value,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier
                                .width(columns[i].width)
                                .padding(horizontal = 8.dp),
                        )
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverEventsTable.kt
git commit -m "feat(android): add ObserverEventsTable composable"
```

---

### Task 7: Create ObserverEventDetailView

**Files:**
- Create: `ui/mainstudio/ObserverEventDetailView.kt`

- [ ] **Step 1: Create the event detail composable**

Create `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverEventDetailView.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.EventFilterMode

@Composable
fun ObserverEventDetailView(
    event: DittoObserveEvent,
    filterMode: EventFilterMode,
    onFilterChange: (EventFilterMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    val filteredDocs = when (filterMode) {
        EventFilterMode.ALL -> event.data
        EventFilterMode.INSERTED -> event.getInsertedData()
        EventFilterMode.UPDATED -> event.getUpdatedData()
    }

    Column(modifier = modifier.fillMaxSize().padding(8.dp)) {
        // Header with counts
        Text(
            text = "Event: ${event.eventTime.substringAfter("T").substringBefore(".")}",
            style = MaterialTheme.typography.titleSmall,
        )
        Text(
            text = "Docs: ${event.data.size}  Ins: ${event.insertIndexes.size}  " +
                "Upd: ${event.updatedIndexes.size}  Del: ${event.deletedIndexes.size}  " +
                "Mov: ${event.movedIndexes.size}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(8.dp))

        // Filter chips
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .horizontalScroll(rememberScrollState()),
        ) {
            EventFilterMode.entries.forEach { mode ->
                FilterChip(
                    selected = filterMode == mode,
                    onClick = { onFilterChange(mode) },
                    label = {
                        Text(
                            when (mode) {
                                EventFilterMode.ALL -> "All Items (${event.data.size})"
                                EventFilterMode.INSERTED -> "Inserted (${event.insertIndexes.size})"
                                EventFilterMode.UPDATED -> "Updated (${event.updatedIndexes.size})"
                            },
                        )
                    },
                    modifier = Modifier.padding(end = 8.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Document cards
        if (filteredDocs.isEmpty()) {
            Text(
                text = "No documents for this filter",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(16.dp),
            )
        } else {
            LazyColumn {
                itemsIndexed(filteredDocs) { _, doc ->
                    Card(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                    ) {
                        Text(
                            text = doc,
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                            modifier = Modifier.padding(12.dp),
                        )
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverEventDetailView.kt
git commit -m "feat(android): add ObserverEventDetailView composable"
```

---

### Task 8: Create ObserverDetailScreen (Container)

**Files:**
- Create: `ui/mainstudio/ObserverDetailScreen.kt`

- [ ] **Step 1: Create the container composable**

Create `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverDetailScreen.kt`:

```kotlin
package com.costoda.dittoedgestudio.ui.mainstudio

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.costoda.dittoedgestudio.domain.model.DittoObserveEvent
import com.costoda.dittoedgestudio.domain.model.DittoObservable
import com.costoda.dittoedgestudio.domain.model.EventFilterMode

@Composable
fun ObserverDetailScreen(
    selectedObserver: DittoObservable?,
    events: List<DittoObserveEvent>,
    selectedEvent: DittoObserveEvent?,
    filterMode: EventFilterMode,
    onSelectEvent: (DittoObserveEvent) -> Unit,
    onFilterChange: (EventFilterMode) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (selectedObserver == null) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(
                    imageVector = Icons.Outlined.Visibility,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 8.dp),
                )
                Text(
                    text = "Select an observer and activate it to see events",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
        return
    }

    if (events.isEmpty()) {
        Box(
            modifier = modifier.fillMaxSize(),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    text = selectedObserver.name.ifBlank { "Observer" },
                    style = MaterialTheme.typography.titleSmall,
                )
                Text(
                    text = "No events captured yet. Activate the observer to start.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        return
    }

    Column(modifier = modifier.fillMaxSize()) {
        // Top half: events table
        ObserverEventsTable(
            events = events,
            selectedEvent = selectedEvent,
            onSelectEvent = onSelectEvent,
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f),
        )

        HorizontalDivider()

        // Bottom half: event detail
        if (selectedEvent != null) {
            ObserverEventDetailView(
                event = selectedEvent,
                filterMode = filterMode,
                onFilterChange = onFilterChange,
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            )
        } else {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = "Tap an event row above to see details",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}
```

- [ ] **Step 2: Verify build compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/ObserverDetailScreen.kt
git commit -m "feat(android): add ObserverDetailScreen container composable"
```

---

### Task 9: Integrate into MainStudioScreen

**Files:**
- Modify: `ui/mainstudio/MainStudioScreen.kt`

This is the most complex task — replacing three OBSERVERS stubs and wiring the editor sheet.

- [ ] **Step 1: Add imports to MainStudioScreen.kt**

Add these imports at the top of `MainStudioScreen.kt` (alongside existing imports):

```kotlin
import com.costoda.dittoedgestudio.domain.model.DittoObservable
```

- [ ] **Step 2: Replace OBSERVERS stub in PhoneDrawerContent (lines ~546-552)**

Replace:
```kotlin
        SectionHeader(title = "OBSERVERS")
        Text(
            text = "No Observers",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
```

With:
```kotlin
        SectionHeader(
            title = "OBSERVERS",
            trailing = {
                androidx.compose.material3.IconButton(
                    onClick = { viewModel.editingObserver = DittoObservable() },
                ) {
                    androidx.compose.material3.Icon(
                        imageVector = androidx.compose.material.icons.Icons.Filled.Add,
                        contentDescription = "Add Observer",
                    )
                }
            },
        )
        val observers = viewModel.observers.collectAsState().value
        if (observers.isEmpty()) {
            Text(
                text = "No Observers",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
            )
        } else {
            observers.forEach { observer ->
                ObserverListItem(
                    observer = observer,
                    isSelected = viewModel.selectedObserver?.id == observer.id,
                    isActive = viewModel.isObserverActive(observer),
                    onSelect = {
                        viewModel.selectObserver(observer)
                        viewModel.selectedNavItem = StudioNavItem.OBSERVERS
                    },
                    onActivate = { viewModel.activateObserver(observer) },
                    onDeactivate = { viewModel.deactivateObserver(observer) },
                    onEdit = { viewModel.editingObserver = observer },
                    onDelete = { viewModel.removeObserver(observer) },
                )
            }
        }
```

**Important:** If `SectionHeader` doesn't support a `trailing` parameter, use a `Row` instead:
```kotlin
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
        ) {
            Text("OBSERVERS", style = MaterialTheme.typography.labelSmall)
            Spacer(modifier = Modifier.weight(1f))
            androidx.compose.material3.IconButton(
                onClick = { viewModel.editingObserver = DittoObservable() },
            ) {
                androidx.compose.material3.Icon(
                    imageVector = androidx.compose.material.icons.Icons.Filled.Add,
                    contentDescription = "Add Observer",
                )
            }
        }
```

- [ ] **Step 3: Replace OBSERVERS stub in DataPanel (lines ~638-644)**

Apply the same replacement pattern as Step 2 to the DataPanel's OBSERVERS section.

- [ ] **Step 4: Replace "Coming Soon" placeholder in content area (lines ~755-766)**

Find the `else ->` branch in the content area that shows "Coming Soon" and add the OBSERVERS case. Change from:

```kotlin
                else -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "${viewModel.selectedNavItem.label} — Coming Soon",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
```

To add a specific branch for OBSERVERS before the `else`:

```kotlin
                StudioNavItem.OBSERVERS -> {
                    ObserverDetailScreen(
                        selectedObserver = viewModel.selectedObserver,
                        events = viewModel.selectedObserverEvents(),
                        selectedEvent = viewModel.selectedEvent,
                        filterMode = viewModel.eventFilterMode,
                        onSelectEvent = { viewModel.selectEvent(it) },
                        onFilterChange = { viewModel.eventFilterMode = it },
                    )
                }
                else -> {
                    Box(
                        modifier = Modifier.fillMaxSize(),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            text = "${viewModel.selectedNavItem.label} — Coming Soon",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
```

- [ ] **Step 5: Add ObserverEditorSheet**

Find where `SubscriptionEditorSheet` is rendered (search for `editingSubscription?.let`). Add the observer sheet nearby, using the same pattern:

```kotlin
    viewModel.editingObserver?.let { observer ->
        ObserverEditorSheet(
            initial = observer,
            onSave = { name, query ->
                if (observer.id == 0L) {
                    viewModel.addObserver(name, query)
                } else {
                    viewModel.updateObserver(observer, name, query)
                }
            },
            onDismiss = { viewModel.editingObserver = null },
        )
    }
```

- [ ] **Step 6: Verify build compiles**

```bash
cd android && ./gradlew compileDebugKotlin 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL. If there are compilation issues (e.g., `SectionHeader` not accepting `trailing`), adjust accordingly using the Row fallback pattern.

- [ ] **Step 7: Commit**

```bash
git add android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/MainStudioScreen.kt
git commit -m "feat(android): integrate observer UI into MainStudioScreen"
```

---

### Task 10: Full Build and Test Verification

**Files:** None (verification only)

- [ ] **Step 1: Run all unit tests**

```bash
cd android && ./gradlew testDebugUnitTest 2>&1 | tail -10
```

Expected: All tests PASSED.

- [ ] **Step 2: Run full debug build**

```bash
cd android && ./gradlew assembleDebug 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL.

- [ ] **Step 3: Run lint check**

```bash
cd android && ./gradlew lintDebug 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL (lint warnings are acceptable, errors are not).

- [ ] **Step 4: Final commit if any fixes were needed**

Only if Steps 1-3 required changes:

```bash
git add -u android/
git commit -m "fix(android): resolve build/test issues from observer integration"
```
