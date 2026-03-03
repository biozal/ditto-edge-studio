# Plan: Fix FAB Menu with M3 `FloatingActionButtonMenu`

## Problem

The current `SpeedDialItem` composable renders only the **first letter** of each action
label inside a tiny `SmallFloatingActionButton`. This makes all six items indistinguishable
("A", "A", "A", "I", "I", "I").

On **tablet** the situation is worse: the FAB and its items are placed in the
`NavigationRail.header` slot, which is only ~80 dp wide. There is no room to expand
meaningful labels there.

---

## Solution

1. Replace the custom `SpeedDialItem` + `AnimatedVisibility` column with the M3
   [`FloatingActionButtonMenu`](https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#FloatingActionButtonMenu(kotlin.Boolean,kotlin.Function0,androidx.compose.ui.Modifier,androidx.compose.ui.Alignment.Horizontal,kotlin.Function1))
   component. Each item uses `FloatingActionButtonMenuItem` which renders a proper
   **icon + text label** pair.

2. On **tablet**: remove the FAB from the `NavigationRail` entirely and move it to the
   bottom of the `DataPanel` (~200 dp wide — plenty of room for labels). This is what the
   user requested.

3. On **phone**: keep the FAB in the drawer but replace the broken implementation with
   `FloatingActionButtonMenu` (left-aligned, items expand upward).

---

## API Used

```kotlin
@OptIn(ExperimentalMaterial3ExpressiveApi::class)
FloatingActionButtonMenu(
    expanded  = fabMenuExpanded,
    button    = { ToggleFloatingActionButton(checked = fabMenuExpanded, ...) { ... } },
) {
    FloatingActionButtonMenuItem(
        onClick = { fabMenuExpanded = false },
        icon    = { Icon(Icons.Outlined.Add, null) },
        text    = { Text("Add Subscription") },
    )
    // …
}
```

**Annotation required:** `@ExperimentalMaterial3ExpressiveApi`

**Material3 version:** The component is available with `@ExperimentalMaterial3ExpressiveApi`
in the `material3` artifact bundled with BOM 2025.12.00 (Material3 1.4.x). If the first
build attempt fails with "unresolved reference: FloatingActionButtonMenu", upgrade the
single artifact (without touching the BOM):
```toml
# gradle/libs.versions.toml
material3Override = "1.5.0-alpha10"
```
```kotlin
// build.gradle.kts — override BOM-managed version
implementation("androidx.compose.material3:material3:1.5.0-alpha10")
```

---

## Files Changed

| File | Change |
|---|---|
| `ui/mainstudio/MainStudioScreen.kt` | Major refactor — see sections below |
| `viewmodel/MainStudioViewModel.kt` | No change (keeps `fabMenuExpanded`) |
| `data/di/DataModule.kt` | No change |
| `gradle/libs.versions.toml` | Add `material3Override` entry **only if** BOM version doesn't compile |
| `app/build.gradle.kts` | Add override dependency **only if** needed |

---

## `MainStudioScreen.kt` Changes

### 1. File-level opt-in

Change the existing file-level annotation to also include the expressive API:

```kotlin
// Before
@file:OptIn(ExperimentalMaterial3Api::class)

// After
@file:OptIn(ExperimentalMaterial3Api::class, ExperimentalMaterial3ExpressiveApi::class)
```

### 2. New `StudioFabMenu` composable (replaces `SpeedDialItem`)

Delete `SpeedDialItem` entirely. Add:

```kotlin
@Composable
private fun StudioFabMenu(
    expanded: Boolean,
    onExpandChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    horizontalAlignment: Alignment.Horizontal = Alignment.End,
) {
    FloatingActionButtonMenu(
        expanded = expanded,
        modifier = modifier,
        horizontalAlignment = horizontalAlignment,
        button = {
            ToggleFloatingActionButton(
                checked = expanded,
                onCheckedChange = onExpandChange,
                containerColor = SulfurYellow,
                contentColor = JetBlack,
            ) {
                val rotation by animateFloatAsState(
                    targetValue = if (expanded) 45f else 0f,
                    label = "fabRotation",
                )
                Icon(
                    imageVector = Icons.Filled.Add,
                    contentDescription = if (expanded) "Close actions menu" else "Open actions menu",
                    modifier = Modifier.rotate(rotation),
                )
            }
        },
    ) {
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.Sync, null) },
            text = { Text("Add Subscription") },
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.Visibility, null) },
            text = { Text("Add Observer") },
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.Storage, null) },
            text = { Text("Add Index") },
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.QrCodeScanner, null) },
            text = { Text("Import Subscriptions → QR Code") },
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.Cloud, null) },
            text = { Text("Import Subscriptions → Server") },
        )
        FloatingActionButtonMenuItem(
            onClick = { onExpandChange(false) },
            icon = { Icon(Icons.Outlined.FileDownload, null) },
            text = { Text("Import JSON Data") },
        )
    }
}
```

New imports needed:
```kotlin
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.material3.ExperimentalMaterial3ExpressiveApi
import androidx.compose.material3.FloatingActionButtonMenu
import androidx.compose.material3.FloatingActionButtonMenuItem
import androidx.compose.material3.ToggleFloatingActionButton
import androidx.compose.ui.draw.rotate
import androidx.compose.material.icons.outlined.Cloud
import androidx.compose.material.icons.outlined.FileDownload
```

### 3. `NavigationRail` — remove `header` slot

The rail no longer contains any FAB. Change:

```kotlin
// Before
NavigationRail(
    header = {
        Column(...) {
            AnimatedVisibility(viewModel.fabMenuExpanded) { ... SpeedDialItem calls ... }
            FloatingActionButton(...)  { Icon(Add) }
            Spacer(16.dp)
        }
    },
) { ... nav items ... }

// After
NavigationRail {
    ... nav items only ...
}
```

### 4. `DataPanel` — add FAB menu at bottom

`DataPanel` currently takes no `viewModel` parameter. Change its signature and wrap it in a
`Box` so the FAB can float over the scrollable content:

```kotlin
@Composable
private fun DataPanel(viewModel: MainStudioViewModel, modifier: Modifier = Modifier) {
    Box(modifier = modifier) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(bottom = 88.dp),  // reserve space so FAB doesn't cover last item
        ) {
            SectionHeader("SUBSCRIPTIONS", ...)
            Text("No Subscriptions", ...)
            SectionHeader("COLLECTIONS", ...)
            Text("No Collections", ...)
            SectionHeader("OBSERVERS")
            Text("No Observers", ...)
        }
        StudioFabMenu(
            expanded = viewModel.fabMenuExpanded,
            onExpandChange = { viewModel.fabMenuExpanded = it },
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(8.dp),
        )
    }
}
```

Update the call site in `TabletLayout` to pass `viewModel`:
```kotlin
DataPanel(
    viewModel = viewModel,
    modifier = Modifier.width(200.dp).fillMaxHeight(),
)
```

### 5. `PhoneDrawerContent` — replace broken speed dial

Remove the entire `Column` block that contains `AnimatedVisibility` + `SpeedDialItem` calls +
the old `FloatingActionButton`. Replace with a `Box` at the bottom of the drawer:

```kotlin
// Remove this entire block:
Column(
    modifier = Modifier.padding(horizontal = 16.dp),
    verticalArrangement = Arrangement.spacedBy(8.dp),
) {
    AnimatedVisibility(visible = viewModel.fabMenuExpanded) {
        Column(...) { SpeedDialItem("Add Subscription") ... }
    }
    FloatingActionButton(
        containerColor = SulfurYellow, ...
    ) { Icon(Add) }
}

// Replace with:
Box(
    modifier = Modifier
        .fillMaxWidth()
        .padding(horizontal = 16.dp, vertical = 8.dp),
) {
    StudioFabMenu(
        expanded = viewModel.fabMenuExpanded,
        onExpandChange = { viewModel.fabMenuExpanded = it },
        modifier = Modifier.align(Alignment.CenterStart),
        horizontalAlignment = Alignment.Start,
    )
}
```

---

## Resulting Visual Behaviour

### Phone (drawer)
- Yellow `+` FAB at bottom-left of drawer
- Tap → 6 items animate upward, each showing icon on the right + text label on the left
  (M3 FAB Menu default for `Alignment.Start`)
- Tap any item → menu closes
- `+` rotates 45° to form an `×` while open

### Tablet (data panel)
- Nav Rail shows **only** the 6 navigation items — no FAB cluttering it
- Data Panel (200 dp) has yellow `+` FAB at bottom-right
- Tap → items expand upward within/above the panel, each with clear icon + text
- `+` rotates to `×` while open

---

## Verification

```bash
cd android && ./gradlew assembleDebug   # zero errors
./gradlew test                          # all unit tests pass
```

Manual checks — phone:
1. Open drawer → see yellow `+` FAB at bottom-left (not letter buttons)
2. Tap `+` → 6 labelled items animate up: "Add Subscription", "Add Observer", etc.
3. Tap an item → menu closes, `+` icon returns

Manual checks — tablet:
1. Nav Rail shows no FAB at all — only 6 nav items
2. Data Panel has yellow `+` FAB at bottom-right
3. Tap `+` → 6 labelled items expand upward with icon + text
4. Drawer-level FAB references all removed
