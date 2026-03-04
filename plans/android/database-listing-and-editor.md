# Plan: Database Listing & Editor — Android

**Feature:** Convert iOS Database Listing and Database Configuration Editor screens to Android
**Platform:** Android (Jetpack Compose + Material Design 3)
**Status:** Ready for review

---

## Background Image Format Research

### Question: What image format should Android use for a scalable background (currently a PDF/SVG on iOS)?

**Answer: Android Vector Drawable (`.xml`)**

Android Vector Drawables are the direct equivalent of iOS PDF/SVG scalable assets. They:
- Scale to any screen size and density with zero quality loss
- Require no external libraries
- Are supported on all Android versions >= 21 (we target 28+)
- Are referenced with `painterResource(R.drawable.bg_pattern)` in Compose

**Conversion steps (required before implementing the tablet layout):**
1. Open Android Studio → `File → New → Vector Asset`
2. Select "Local SVG/PSD file" and choose your SVG source file
3. Tweak size/padding if needed (set viewport to match the design)
4. Android Studio outputs `app/src/main/res/drawable/bg_pattern.xml`
5. Use in Compose:
   ```kotlin
   Image(
       painter = painterResource(R.drawable.bg_pattern),
       contentDescription = null,
       contentScale = ContentScale.Crop,
       modifier = Modifier.fillMaxSize()
   )
   ```

**Caveats:**
- Android's SVG→Vector Drawable converter handles paths, shapes, and basic fills/gradients
- It does NOT support SVG filters, masks, or some complex gradient types
- If the dot/diamond pattern from the macOS screenshot uses only paths and fills, it will convert perfectly
- If conversion fails visually: fall back to WebP images at multiple densities (`res/drawable-mdpi/`, `hdpi/`, `xhdpi/`, `xxhdpi/`, `xxxhdpi/`)

**File location:** `android/app/src/main/res/drawable/bg_pattern.xml`

---

## Screen Inventory

### Phone screens (< 600dp width)

| Screen | iOS equivalent | M3 Component |
|--------|---------------|-------------|
| Database listing (empty) | `DatabaseList.swift` + `NoDatabaseConfigurationView` | `Scaffold` + `LargeTopAppBar` + `FloatingActionButton` |
| Database listing (with items) | `DatabaseList.swift` + `DatabaseCard` | Same scaffold + `LazyColumn` of `ElevatedCard` |
| Context menu (long press) | SwiftUI `.contextMenu` | M3 `DropdownMenu` |
| Register/Edit database | `DatabaseEditorView.swift` | Full-screen Compose destination with `TopAppBar` |
| Log level picker | SwiftUI `.pickerStyle(.menu)` | M3 `ExposedDropdownMenuBox` |

### Large screen / tablet screens (≥ 600dp width)

| Element | iOS/macOS equivalent | Android approach |
|---------|---------------------|-----------------|
| Full-screen background | PDF background image (scalable) | Android Vector Drawable via `painterResource` |
| Left panel | Ditto logo + action buttons sidebar | Fixed-width `Column` overlay |
| Database list | Semi-transparent `List` | `LazyColumn` in a `Card` with `alpha` modifier |
| Register/Edit form | Same `DatabaseEditorView` sheet | Same full-screen destination |

---

## Architecture Overview

This feature adds the following files. All paths are relative to
`android/app/src/main/java/com/costoda/dittoedgestudio/`.

```
ui/
├── navigation/
│   └── AppNavGraph.kt               NEW — NavHost + route constants
├── database/
│   ├── DatabaseListScreen.kt        NEW — phone + tablet layouts
│   ├── DatabaseCard.kt              NEW — M3 ElevatedCard composable
│   ├── EmptyDatabasesView.kt        NEW — empty state composable
│   └── DatabaseEditorScreen.kt      NEW — register/edit full-screen form
└── mainstudio/
    └── MainStudioScreen.kt          NEW — stub "MainStudioView" screen

viewmodel/
├── DatabaseListViewModel.kt         NEW — replaces HomeViewModel for this flow
└── DatabaseEditorViewModel.kt       NEW — form state + save/update logic

data/di/
└── DataModule.kt                    MODIFY — register both new ViewModels
```

**Modified files:**
- `MainActivity.kt` — swap `HomeScreen()` for `AppNavGraph()`
- `domain/model/AuthMode.kt` — add `displayName` property

---

## New Dependencies

Add to `gradle/libs.versions.toml` and `app/build.gradle.kts`:

### `libs.versions.toml` additions

```toml
[versions]
navigationCompose = "2.8.9"          # Stable as of early 2026

[libraries]
androidx-navigation-compose = { group = "androidx.navigation", name = "navigation-compose", version.ref = "navigationCompose" }
```

### `app/build.gradle.kts` addition

```kotlin
implementation(libs.androidx.navigation.compose)
```

> **No additional library needed for tablet detection.** Use
> `LocalConfiguration.current.screenWidthDp >= 600` to branch between
> phone and tablet layouts.

---

## Implementation Steps

### Step 1 — Add navigation dependency

Update `gradle/libs.versions.toml` and `app/build.gradle.kts` as shown above, then sync Gradle.

---

### Step 2 — Add `displayName` to `AuthMode`

`domain/model/AuthMode.kt`:

```kotlin
enum class AuthMode(val value: String, val displayName: String) {
    SERVER("server", "Server"),
    SMALL_PEERS_ONLY("smallpeersonly", "Small Peers Only");
    ...
}
```

---

### Step 3 — Create `DatabaseListViewModel`

`viewmodel/DatabaseListViewModel.kt`

- Observes `DatabaseRepository.observeAll()` as `StateFlow<List<DittoDatabase>>`
- Exposes `uiState: StateFlow<DatabaseListUiState>` (Loading / Empty / Databases)
- Event handlers: `deleteDatabase(id)`, no business logic in composables

```kotlin
sealed class DatabaseListUiState {
    object Loading : DatabaseListUiState()
    object Empty : DatabaseListUiState()
    data class Databases(val items: List<DittoDatabase>) : DatabaseListUiState()
}
```

---

### Step 4 — Create `DatabaseEditorViewModel`

`viewmodel/DatabaseEditorViewModel.kt`

- Holds all form field state as `MutableStateFlow` (name, databaseId, token, authUrl, httpApiUrl, httpApiKey, mode, allowUntrustedCerts, secretKey, logLevel)
- **No websocketUrl field** — Android SDK 5.0 does not require it
- `isNewItem: Boolean` — controls title and save vs. update
- `canSave: StateFlow<Boolean>` — derived from required field validation
- `save(): suspend fun` — calls `DatabaseRepository.save()`
- `loadForEdit(database: DittoDatabase)` — populates fields from existing item

---

### Step 5 — Create `DatabaseListScreen`

`ui/database/DatabaseListScreen.kt`

#### Phone layout (screenWidthDp < 600)

```
Scaffold(
  topBar = LargeTopAppBar(
    title = "Edge Studio",
    actions = [
      IconButton(QR Code icon)      // placeholder — future feature
      IconButton(Cloud icon)         // opens https://portal.ditto.live/
    ]
  ),
  floatingActionButton = FloatingActionButton(
    containerColor = SulfurYellow,
    contentColor = JetBlack,
    icon = Icons.Filled.Add
  )
) { padding ->
  when (uiState) {
    Loading  → CircularProgressIndicator centered
    Empty    → EmptyDatabasesView()
    Databases → LazyColumn { items(databases) { DatabaseCard(it) } }
  }
}
```

**Toolbar buttons (M3 `IconButton` in `TopAppBar` actions):**
- QR Code: `Icons.Outlined.QrCodeScanner` — shows `Toast("Coming soon")` for now
- Cloud: `Icons.Outlined.Cloud` — launches `Intent(ACTION_VIEW, Uri.parse("https://portal.ditto.live/"))` via `LocalContext`

**Empty state message (M3):** "No Databases" (headline) + "Tap + to register a database configuration" (body, secondary color)

#### Large screen layout (screenWidthDp ≥ 600)

```
Box(fillMaxSize) {
  // Layer 1: full-screen background image
  Image(bg_pattern, contentScale = ContentScale.Crop, fillMaxSize, alpha = 1f)

  // Layer 2: left panel (fixed 320dp wide)
  Column(modifier = Modifier.fillMaxHeight().width(320.dp).padding(32.dp)) {
    // Ditto logo + "Edge Studio" title
    // Spacer
    Button "+ Database Config"       // → navigate to editor (add)
    OutlinedButton "Ditto Portal"    // → open browser
    OutlinedButton "Import QR Code"  // → future feature
  }

  // Layer 3: right panel — semi-transparent card list
  Box(modifier = Modifier.fillMaxHeight().padding(start=320.dp)) {
    LazyColumn with alpha=0.85 surface background {
      items(databases) { DatabaseListRow(it) }
    }
  }
}
```

---

### Step 6 — Create `DatabaseCard`

`ui/database/DatabaseCard.kt`

M3 `ElevatedCard` (or `Card`) matching the iOS design:

```
ElevatedCard(
  modifier = Modifier.fillMaxWidth().pointerInput(Unit) {
    detectTapGestures(
      onTap = { onTap() },
      onLongPress = { showContextMenu = true }
    )
  },
  colors = CardDefaults.elevatedCardColors(
    containerColor = MaterialTheme.colorScheme.surface  // TrafficBlack / TrafficWhite
  )
) {
  Row {
    Icon(database icon, tint = SulfurYellow)   // database icon from Material Icons
    Column {
      Text(name, color = SulfurYellow, style = titleMedium)
      Text("Database ID", style = labelSmall, color = secondary)
      Row { Text(masked/unmasked databaseId, monospace) + IconButton(eye toggle) }
      Text("Token", style = labelSmall, color = secondary)
      Text(masked token, monospace)
    }
  }
  // DropdownMenu for long-press context
  DropdownMenu(expanded = showContextMenu, onDismissRequest = { showContextMenu = false }) {
    DropdownMenuItem("Edit",     icon = Icons.Outlined.Edit,    onClick = onEdit)
    DropdownMenuItem("QR Code",  icon = Icons.Outlined.QrCode,  onClick = { /* future */ })
    Divider()
    DropdownMenuItem("Delete",   icon = Icons.Outlined.Delete,  onClick = onDelete,
                     colors = red/error tint)
  }
}
```

> **Eye toggle:** same reveal/mask behavior as iOS `DatabaseListRow` — tap the eye icon to reveal the full databaseId.

---

### Step 7 — Create `DatabaseEditorScreen`

`ui/database/DatabaseEditorScreen.kt`

Full-screen Compose destination (pushed via nav graph, not a dialog/sheet):

```
Scaffold(
  topBar = TopAppBar(
    navigationIcon = IconButton(X close / navigate back),
    title = if (isNewItem) "Register Database" else "Edit Database",
    actions = [ TextButton("Save", enabled = canSave, onClick = onSave) ]
  )
) { padding ->
  Column(scroll) {

    // --- Mode selector (M3 Secondary Tabs) ---
    SecondaryTabRow(selectedTabIndex = selectedMode.ordinal) {
      AuthMode.values().forEach { mode ->
        Tab(selected = selectedMode == mode, text = { Text(mode.displayName) })
      }
    }

    // --- Sections (M3 OutlinedTextField) ---
    FormSection("Basic Information") {
      OutlinedTextField(label = "Name", value = name, ...)
    }

    FormSection("Authorization Information") {
      OutlinedTextField(label = "Database ID", value = databaseId,
                        keyboardType = Ascii, fontFamily = Monospace, ...)
      OutlinedTextField(
        label = if SERVER "Token" else "Offline Token",
        value = token, ...
      )
      if (mode == SMALL_PEERS_ONLY) {
        Text("Required for sync activation... Obtain from https://portal.ditto.live",
             style = labelSmall, color = secondary)
      }
    }

    // Server-only sections
    if (mode == SERVER) {
      FormSection("Ditto Server (BigPeer) Information") {
        OutlinedTextField("Auth URL", ...)
        // NOTE: No Websocket URL — Android SDK 5.0 does not require it
      }
      FormSection("Ditto Server - HTTP API - Optional") {
        OutlinedTextField("HTTP API URL", ...)
        OutlinedTextField("HTTP API Key", ...)
        Row {
          Switch(checked = allowUntrustedCerts, ...)
          Text("Allow untrusted certificates")
        }
        Text("By allowing untrusted certificates...", style = labelSmall, color = secondary)
      }
    }

    // Small Peers Only section
    if (mode == SMALL_PEERS_ONLY) {
      FormSection("Optional Secret Key") {
        OutlinedTextField("Shared Key", ...)
        Text("Optional secret key for shared key identity...",
             style = labelSmall, color = secondary)
      }
    }

    // Developer Options (both modes)
    FormSection("Developer Options") {
      // M3 ExposedDropdownMenuBox
      ExposedDropdownMenuBox {
        OutlinedTextField("SDK Log Level", readOnly = true, trailingIcon = dropdown arrow)
        ExposedDropdownMenu {
          DropdownMenuItem("Error",        onClick = { logLevel = "error" })
          DropdownMenuItem("Warning",      onClick = { logLevel = "warning" })
          DropdownMenuItem("Info (Default)", onClick = { logLevel = "info" })
          DropdownMenuItem("Debug",        onClick = { logLevel = "debug" })
          DropdownMenuItem("Verbose",      onClick = { logLevel = "verbose" })
        }
      }
      Text("Controls DittoLogger.minimumLogLevel...", style = labelSmall, color = secondary)
    }

    // Info banner (new item only)
    if (isNewItem) {
      InfoBanner(
        "This information comes from the Ditto Portal and is required to register a Ditto Database.",
        linkText = "Ditto Portal",
        linkUrl = "https://portal.ditto.live"
      )
    }
  }
}
```

**Save validation (disable Save button when):**
- `databaseId.isBlank()`
- `name.isBlank()`
- `token.isBlank()`

---

### Step 8 — Create `MainStudioScreen` stub

`ui/mainstudio/MainStudioScreen.kt`

```kotlin
@Composable
fun MainStudioScreen(database: DittoDatabase, onBack: () -> Unit) {
    Scaffold(
        topBar = { TopAppBar(title = { Text("MainStudioView") }, navigationIcon = { BackButton(onBack) }) }
    ) { Text("MainStudioView") }
}
```

---

### Step 9 — Create `AppNavGraph`

`ui/navigation/AppNavGraph.kt`

```kotlin
sealed class Screen(val route: String) {
    object DatabaseList : Screen("database_list")
    object DatabaseEditor : Screen("database_editor?id={id}") // id=-1 for new
    object MainStudio : Screen("main_studio/{databaseId}")
}

@Composable
fun AppNavGraph() {
    val navController = rememberNavController()
    NavHost(navController, startDestination = Screen.DatabaseList.route) {
        composable(Screen.DatabaseList.route) {
            DatabaseListScreen(
                onAddDatabase  = { navController.navigate(Screen.DatabaseEditor.route.replace("{id}", "-1")) },
                onEditDatabase = { db -> navController.navigate("database_editor?id=${db.id}") },
                onOpenDatabase = { db -> navController.navigate("main_studio/${db.id}") }
            )
        }
        composable(Screen.DatabaseEditor.route) { backStack ->
            val id = backStack.arguments?.getString("id")?.toLongOrNull() ?: -1L
            DatabaseEditorScreen(
                databaseId = id,
                onDismiss = { navController.popBackStack() }
            )
        }
        composable(Screen.MainStudio.route) { backStack ->
            val dbId = backStack.arguments?.getString("databaseId")?.toLongOrNull() ?: -1L
            MainStudioScreen(databaseId = dbId, onBack = { navController.popBackStack() })
        }
    }
}
```

---

### Step 10 — Update `MainActivity`

Replace `HomeScreen()` with `AppNavGraph()`:

```kotlin
setContent {
    EdgeStudioTheme {
        AppNavGraph()
    }
}
```

---

### Step 11 — Update `DataModule` (Koin DI)

Register both new ViewModels:

```kotlin
viewModel { DatabaseListViewModel(get()) }
viewModel { (id: Long) -> DatabaseEditorViewModel(id, get()) }
```

---

## M3 Design Decisions

| Element | M3 Component | Rationale |
|---------|-------------|-----------|
| Screen scaffold | `Scaffold` + `LargeTopAppBar` | "Edge Studio" large title matches iOS large title style |
| Database list | `LazyColumn` of `ElevatedCard` | Elevated cards give depth; matches iOS rounded-rect cards |
| Mode selector | `SecondaryTabRow` + `Tab` | M3 secondary tabs ≈ iOS segmented control (same visual weight) |
| Form fields | `OutlinedTextField` | Standard M3 form pattern; clear label + border |
| Log level | `ExposedDropdownMenuBox` | M3 standard for in-form selectors |
| Context menu | `DropdownMenu` (on long press) | Nearest M3 equivalent to iOS context menu |
| FAB | `FloatingActionButton` | `containerColor = SulfurYellow`, `contentColor = JetBlack` |
| App bar actions | `IconButton` in `TopAppBar` | Standard M3 toolbar action pattern |
| Info banner | Custom `Row` in `Surface` | Blue tinted surface matching iOS info panel |
| Delete item | Red `DropdownMenuItem` with error color | Destructive action follows M3 color guidance |

---

## Platform Differences: iOS vs Android

| Feature | iOS (SDK 4.13.3) | Android (SDK 5.0) |
|---------|-----------------|------------------|
| Websocket URL field | ✅ Required | ❌ Omitted — SDK 5.0 handles automatically |
| Toolbar style | Apple Liquid Glass | M3 `TopAppBar` with action icons |
| Mode selector | `segmentedPickerStyle` | M3 `SecondaryTabRow` |
| Log level picker | `.pickerStyle(.menu)` | M3 `ExposedDropdownMenuBox` |
| Context menu | `.contextMenu` (long press) | M3 `DropdownMenu` (long press via `pointerInput`) |
| Form presentation | `.sheet` full screen | Compose navigation destination |
| Swipe to delete | `.swipeActions` | Context menu (Delete option) |
| Eye reveal toggle | Button in list row | Same — `IconButton` with `Icons.Outlined.Visibility` |

---

## Tests Required

### Unit Tests (`app/src/test/`)

#### `DatabaseListViewModelTest.kt`
- `uiState emits Loading then Empty when repository returns empty list`
- `uiState emits Databases when repository returns items`
- `deleteDatabase calls repository delete with correct id`
- `uiState updates after delete`

#### `DatabaseEditorViewModelTest.kt`
- `canSave is false when name is blank`
- `canSave is false when databaseId is blank`
- `canSave is false when token is blank`
- `canSave is true when all required fields are populated`
- `save calls repository with correct DittoDatabase (new item, id=0)`
- `save calls repository update when editing existing item (id != 0)`
- `loadForEdit populates all fields correctly`
- `websocketUrl field does not exist on ViewModel` (ensures SDK 5.0 adaptation)
- `mode defaults to AuthMode.SERVER`
- `logLevel defaults to "info"`
- `switching mode from SERVER to SMALL_PEERS_ONLY clears authUrl and httpApiUrl`

### Instrumented / Compose UI Tests (`app/src/androidTest/`)

#### `DatabaseListScreenTest.kt`
- `empty state shows database icon and correct message`
- `empty state message reads "Tap + to register a database configuration"`
- `FAB is visible and tappable`
- `tapping FAB navigates to DatabaseEditorScreen`
- `database card shows name, masked databaseId, masked token`
- `tapping eye icon reveals databaseId`
- `long pressing card shows context menu`
- `context menu contains Edit, QR Code, Delete`
- `tapping Delete in context menu removes card from list`
- `tapping Edit in context menu navigates to editor with pre-filled form`
- `tapping card navigates to MainStudioScreen`
- `QR Code action button in top bar is present`
- `Cloud action button in top bar opens browser intent`

#### `DatabaseEditorScreenTest.kt`
- `screen shows "Register Database" title for new item`
- `screen shows "Edit Database" title for existing item`
- `Server tab is selected by default`
- `switching to Small Peers Only tab hides Auth URL field`
- `switching to Small Peers Only tab shows Shared Key field`
- `Server tab shows Auth URL field`
- `Server tab does NOT show Websocket URL field`
- `Save button is disabled when required fields are empty`
- `Save button enables when name, databaseId, and token are filled`
- `tapping Save navigates back to database list`
- `saved item appears in database list`
- `info banner shows when databaseId is empty`
- `info banner hides when databaseId is populated`
- `log level dropdown shows Error, Warning, Info (Default), Debug, Verbose`
- `selecting log level updates the field`
- `Cancel (X) button navigates back without saving`

---

## File Creation Order

1. `gradle/libs.versions.toml` — add navigation dependency
2. `app/build.gradle.kts` — add navigation dependency
3. `domain/model/AuthMode.kt` — add `displayName`
4. `viewmodel/DatabaseListViewModel.kt`
5. `viewmodel/DatabaseEditorViewModel.kt`
6. `ui/database/EmptyDatabasesView.kt`
7. `ui/database/DatabaseCard.kt`
8. `ui/database/DatabaseListScreen.kt`
9. `ui/database/DatabaseEditorScreen.kt`
10. `ui/mainstudio/MainStudioScreen.kt`
11. `ui/navigation/AppNavGraph.kt`
12. `data/di/DataModule.kt` — update
13. `MainActivity.kt` — update
14. `test/viewmodel/DatabaseListViewModelTest.kt`
15. `test/viewmodel/DatabaseEditorViewModelTest.kt`
16. `androidTest/ui/DatabaseListScreenTest.kt`
17. `androidTest/ui/DatabaseEditorScreenTest.kt`

**Tablet background (deferred to when user provides SVG):**
- Convert SVG → `res/drawable/bg_pattern.xml` (Android Vector Drawable)
- Wire into large-screen layout branch in `DatabaseListScreen.kt`

---

## Open Questions for User

1. **SVG file location:** ✅ Located at `screens/android/background-login.svg`. Convert to `res/drawable/bg_pattern.xml` using Android Studio's "Import Vector Asset" wizard.
2. **Delete confirmation:** ✅ Delete immediately — no confirmation dialog, matching iOS swipe-to-delete behaviour.
3. **Large screen breakpoint:** 600dp is the Android standard tablet breakpoint. Is that acceptable, or should the large-screen layout activate at a different width?
