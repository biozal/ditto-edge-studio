# Plan: Android Disk Usage Monitoring — Feature Parity

**Spec:** `issues/android-feature-disk-usage-monitoring.md`  
**Priority:** Low | **Complexity:** Low  
**Status:** Ready for implementation

## Current State Assessment

After reviewing the code, here's the gap analysis:

| Acceptance Criteria | Status | Details |
|---|---|---|
| Auto-refresh every 15s | **GAP** | `DiskUsageScreen.kt:54` only calls `viewModel.refresh()` once on launch |
| Collections sorted by size | **DONE** | `AppMetricsRepositoryImpl.kt:130` already does `sortedByDescending { it.estimatedBytes }` |
| Empty state message | **DONE** | `DiskUsageScreen.kt:155-172` shows "No collections in this database" when list is empty |

## Implementation

Only **one change** is needed:

### Step 1: Add 15-second auto-refresh loop in DiskUsageScreen.kt

**File:** `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/metrics/DiskUsageScreen.kt`  
**Line 54**

**Current:**
```kotlin
LaunchedEffect(Unit) { viewModel.refresh() }
```

**Change to:**
```kotlin
LaunchedEffect(Unit) {
    while (isActive) {
        viewModel.refresh()
        delay(15_000)
    }
}
```

This uses `isActive` from the coroutine scope — when the composable leaves composition (user navigates away), the `LaunchedEffect` is cancelled, stopping the loop automatically.

**Required import** (add if not already present):
```kotlin
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
```

### Step 2: Verify & test

- Build: `cd android && ./gradlew assembleDebug`
- Manual test: open Disk Usage screen, confirm it refreshes every ~15 seconds (watch "last updated" timestamp cycle through "Just now" → "Xs ago" → back to "Just now")
- Verify refresh stops when navigating away from the screen

## No Other Changes Needed

- **Sorting:** Already implemented in the repository layer
- **Empty state:** Already implemented in the screen composable
- **ViewModel:** No changes needed — `refresh()` already handles loading state and timestamp updates correctly
