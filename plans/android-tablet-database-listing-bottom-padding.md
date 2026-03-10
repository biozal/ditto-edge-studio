# Plan: Fix Tablet Database Listing Screen Button Cutoff

**Date:** 2026-03-10
**Issue:** On tablet, the bottom button(s) in the left panel of the database listing screen are cut off by the system navigation bar.
**Screenshot:** `screens/android/database-listing-tablet.png`

---

## Root Cause

`MainActivity` calls `enableEdgeToEdge()`, which causes content to draw **behind** the system navigation bar. On phone, the `Scaffold` in `PhoneDatabaseListLayout` automatically applies window inset padding. However, `TabletDatabaseListLayout` uses a **custom `Box` layout with no Scaffold**, so it never applies bottom inset padding. The left panel's fixed `padding(32.dp)` does not account for the navigation bar height.

---

## Affected File

**`android/app/src/main/java/com/costoda/dittoedgestudio/ui/database/DatabaseListScreen.kt`**

Specifically `TabletDatabaseListLayout` — the left panel `Column` that contains the "Edge Studio" title and action buttons.

---

## Fix

Apply `WindowInsets.systemBars` (or `safeDrawing`) bottom padding to the tablet left panel so buttons are never obscured.

### Change in `TabletDatabaseListLayout`

The left panel `Column` currently has a flat `padding(32.dp)`. We need to replace the bottom portion of that padding with the max of 32.dp and the system navigation bar inset.

**Before (current):**
```kotlin
Column(
    modifier = Modifier
        .width(320.dp)
        .fillMaxHeight()
        .padding(32.dp),
    ...
)
```

**After:**
```kotlin
Column(
    modifier = Modifier
        .width(320.dp)
        .fillMaxHeight()
        .padding(start = 32.dp, top = 32.dp, end = 32.dp)
        .windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Bottom)),
    ...
)
```

> **Why `WindowInsets.systemBars.only(WindowInsetsSides.Bottom)`?**
> This adds padding equal to the system navigation bar height only on the bottom, leaving the existing 32.dp horizontal and top padding intact. It is the idiomatic Compose approach when `enableEdgeToEdge()` is active.

> **Alternative — if the right grid panel also clips:**
> Apply `.windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Bottom))` to the `LazyVerticalGrid` content padding or its container as well.

---

## Required Imports

Add to the imports in `DatabaseListScreen.kt` if not already present:

```kotlin
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.systemBars
```

---

## Steps to Implement

1. Open `DatabaseListScreen.kt`
2. Locate `TabletDatabaseListLayout` composable
3. Find the left panel `Column` modifier
4. Split `padding(32.dp)` into separate sides: `padding(start=32.dp, top=32.dp, end=32.dp)` (no bottom)
5. Chain `.windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Bottom))` after the padding modifier
6. Add any missing imports
7. Also check the `LazyVerticalGrid` in the right panel — if it has a similar issue, apply the same bottom inset padding to its `contentPadding`

---

## Verification

- Run on a tablet emulator (e.g., Pixel Tablet) in landscape mode with gesture navigation enabled
- Confirm all three buttons ("Database Config", "Ditto Portal", "Import QR Code") are fully visible and not clipped
- Confirm phone layout is unaffected (it uses `Scaffold` which handles insets independently)
- Test with both gesture navigation and 3-button navigation bar to confirm padding adapts correctly

---

## Scope

- **Tablet only** — phone layout (`PhoneDatabaseListLayout`) uses `Scaffold` and is unaffected
- **No design changes** — only bottom padding adjustment
- **Adaptive** — `windowInsetsPadding` dynamically adjusts to the actual navigation bar height, so it works with both gesture nav (zero height) and traditional nav bar
