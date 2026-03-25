# Android Tablet UI Fixes — Plan

**Status:** Pending approval
**Affects:** Tablet only (≥600dp width). Phone layout must not change.
**Target:** Android 16, Pixel Tablet, landscape + portrait, gesture nav + 3-button nav.

---

## Screenshots

| Screen | Issue |
|--------|-------|
| `screens/android/peer-list-android-tablet.png` | OS nav bar covers bottom of peers list; time overlaps top |
| `screens/android/query-android-tablet.png` | Query editor/results side-by-side instead of stacked |

---

## Issue 1 & 2 — Safe Areas / System Insets (Top and Bottom)

### Root Cause

`MainActivity.kt` correctly calls `enableEdgeToEdge()`, which tells Android to draw the app behind the system status bar (top) and navigation bar (bottom). However, consuming those insets so content stays clear of them is the app's responsibility — and the tablet layout doesn't do it.

- **`PhoneLayout`** uses `Scaffold { TopAppBar + content }`. `Scaffold` automatically applies top padding equal to the status bar height, so the phone is fine.
- **`TabletLayout`** (line 237 in `MainStudioScreen.kt`) builds a raw `Row { NavigationRail + content }` — **no `Scaffold`, no inset handling at all**. The result: content draws under both the status bar (top overlap) and the OS navigation bar (bottom cut-off).

### Fix

Apply `WindowInsets.safeDrawing` to the tablet's root container. `safeDrawing` covers status bar height (top), navigation bar height (bottom), display cutout (usually top or sides on tablets), and gesture insets on Android 16 with gesture navigation.

**File:** `MainStudioScreen.kt` — `TabletLayout` function

```kotlin
// BEFORE (approximate — root Row has no inset handling)
Row(modifier = Modifier.fillMaxSize()) {
    NavigationRail { ... }
    // content column
}

// AFTER — apply safeDrawingPadding() on the root container only
Row(
    modifier = Modifier
        .fillMaxSize()
        .safeDrawingPadding()   // <-- adds padding for status bar, nav bar, cutouts
) {
    NavigationRail { ... }
    // content column — unchanged
}
```

**Import to add:**
```kotlin
import androidx.compose.foundation.layout.safeDrawingPadding
```

**Why `safeDrawingPadding()` and not `safeContentPadding()`?**
`safeDrawingPadding()` covers everything including display cutouts. `safeContentPadding()` only covers safe content (excludes cutout). On a tablet in landscape, the cutout is often on the long edge, so `safeDrawing` is the right choice.

**Why not put it on `NavigationRail` and content separately?**
Splitting insets across children is more complex and error-prone (e.g. double-applying insets). A single `safeDrawingPadding()` on the root Row is simpler, correct, and only 1 line.

**Applies to tablet only:** `TabletLayout` is only reached when `isTablet = true` (`screenWidthDp >= 600`), so phone is unaffected.

---

## Issue 3 — Unreadable Collection / Index Names in Dark Mode

### Root Cause

In `CollectionListItem.kt`:

- **Collection name** (line 67): `Text(text = collection.name, ...)` — no explicit `color`, inherits `LocalContentColor`
- **Index name** (line 127): `Text(text = index.displayName, ...)` — no explicit `color`, inherits `LocalContentColor`

`LocalContentColor` is set by the nearest enclosing `Surface`. In the tablet layout the sidebar panel's surface may not be deriving its `contentColor` correctly in dark mode (e.g. if the panel uses a raw `Box` or `Column` with a background modifier rather than a `Surface`, `LocalContentColor` is never updated and stays at whatever the parent set — which can be very dark).

### Fix

Add explicit `color = MaterialTheme.colorScheme.onSurface` to both Text composables so they are always readable regardless of the parent surface context.

**File:** `CollectionListItem.kt`

```kotlin
// Collection name — add color:
Text(
    text = collection.name,
    style = MaterialTheme.typography.bodySmall,
    color = MaterialTheme.colorScheme.onSurface,   // <-- add this
    modifier = Modifier.weight(1f),
    maxLines = 1,
    overflow = TextOverflow.Ellipsis,
)

// Index name — add color:
Text(
    text = index.displayName,
    style = MaterialTheme.typography.labelSmall,
    color = MaterialTheme.colorScheme.onSurface,   // <-- add this
    maxLines = 1,
    overflow = TextOverflow.Ellipsis,
)
```

`MaterialTheme.colorScheme.onSurface` = `TrafficWhite` (0xFFF1F0EA) in dark mode — off-white, clearly readable.
`MaterialTheme.colorScheme.onSurface` = `JetBlack` (0xFF0A0A0A) in light mode — black on white, also correct.

**Affects both phone and tablet** but is a correct fix regardless — phone just happened not to show the bug if its sidebar always had the right `LocalContentColor`. Safe to apply universally.

---

## Issue 4 — Query Editor/Results Side-by-Side on Tablet (Should be Stacked)

### Root Cause

`QueryEditorScreen.kt` has an explicit `isTablet` branch:

```kotlin
if (isTablet) {
    // Side-by-side layout — WRONG per design requirements
    Row(modifier = modifier.fillMaxSize()) {
        QueryEditorView(modifier = Modifier.weight(0.35f).fillMaxHeight())
        VerticalDivider()
        QueryResultsView(modifier = Modifier.weight(0.65f).fillMaxHeight())
    }
} else {
    // Stacked layout — correct, and what tablet should also use
    Column(modifier = modifier.fillMaxSize()) {
        QueryEditorView(modifier = Modifier.weight(0.4f))
        HorizontalDivider()
        QueryResultsView(modifier = Modifier.weight(0.6f))
    }
}
```

The tablet branch forces a side-by-side `Row`. The desired layout is stacked (editor top, results bottom) on all screen sizes.

### Fix

Remove the tablet/phone split in `QueryEditorScreen` — always use the `Column` (stacked) layout. The `isTablet` parameter becomes unused and can be removed from the signature.

**File:** `QueryEditorScreen.kt`

```kotlin
// AFTER — always stacked, isTablet parameter removed
@Composable
fun QueryEditorScreen(
    viewModel: QueryEditorViewModel,
    modifier: Modifier = Modifier,
) {
    val queryText by viewModel.queryText.collectAsState()
    val isExecuting by viewModel.isExecuting.collectAsState()
    val executionError by viewModel.executionError.collectAsState()
    val queryResult by viewModel.queryResult.collectAsState()
    val displayedDocuments by viewModel.displayedDocuments.collectAsState()

    Column(modifier = modifier.fillMaxSize()) {
        QueryEditorView(
            queryText = queryText,
            onQueryTextChange = { viewModel.onQueryTextChange(it) },
            modifier = Modifier.weight(0.4f),
        )
        HorizontalDivider()
        QueryResultsView(
            queryResult = queryResult,
            displayedDocuments = displayedDocuments,
            isExecuting = isExecuting,
            executionError = executionError,
            onDocumentSelected = { viewModel.selectDocument(it) },
            modifier = Modifier.weight(0.6f),
        )
    }
}
```

**Also update callers** in `MainStudioScreen.kt` where `QueryEditorScreen` is called with `isTablet = ...` — remove that parameter from both the phone and tablet call sites.

---

## Files to Change (Summary)

| File | Change | Issue |
|------|--------|-------|
| `MainStudioScreen.kt` | Add `.safeDrawingPadding()` to `TabletLayout` root `Row` | 1 & 2 |
| `MainStudioScreen.kt` | Remove `isTablet` param from `QueryEditorScreen` call sites | 4 |
| `QueryEditorScreen.kt` | Remove `isTablet` param + `Row` branch, always use `Column` | 4 |
| `CollectionListItem.kt` | Add `color = MaterialTheme.colorScheme.onSurface` to collection name and index name Text | 3 |

---

## Risks

| Risk | Mitigation |
|------|-----------|
| `safeDrawingPadding()` applies padding to all 4 sides — NavigationRail left edge gets status bar-side padding | Acceptable: NavigationRail content still renders correctly. In landscape, the inset on the nav rail side is usually 0 anyway. |
| Removing `isTablet` from `QueryEditorScreen` is a breaking signature change | Update all call sites in same commit. There are only 2 (phone + tablet in `MainStudioScreen`). |
| Dark mode text color fix applies to phone too | Correct fix on both: phone happened to not show the bug, but adding explicit color is safer. |

---

## Out of Scope

- Landscape vs portrait orientation switching (same insets fix covers both)
- Navigation bar color / scrim styling
- Any phone layout changes
