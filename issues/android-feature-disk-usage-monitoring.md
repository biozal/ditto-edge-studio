# Android Feature: Disk Usage Monitoring — Feature Parity Check

**Priority:** Low  
**Complexity:** Low  
**Status:** Mostly Complete — Minor UI Gaps  
**Platforms with feature:** SwiftUI, .NET/Avalonia, Android  

## Summary

Android already has a `DiskUsageScreen.kt` with storage breakdown by category and per-collection estimates. This issue tracks minor UI/feature gaps compared to SwiftUI and .NET to ensure full parity.

## Current State in Android

`DiskUsageScreen.kt` displays:
- Total storage card
- 7 storage categories (Store, Replication, Attachments, Auth, WAL/SHM, Logs, Other) with linear progress bars
- Per-collection breakdown with doc counts and estimated bytes
- Manual refresh button
- Last updated timestamp with relative formatting
- Loading indicator

## Gaps Compared to SwiftUI/.NET

### 1. Auto-Refresh (Minor)

**SwiftUI and .NET:** Auto-refresh every 15 seconds via a background loop.  
**Android:** Only refreshes on initial load and manual button press.

**Fix:** Add a `LaunchedEffect` with 15-second interval:
```kotlin
LaunchedEffect(Unit) {
    while (isActive) {
        viewModel.refresh()
        delay(15_000)
    }
}
```

### 2. Collection Storage Sorting

**SwiftUI:** Collections sorted by size (largest first).  
**Android:** Verify collections are sorted by `estimatedBytes` descending. If not, add `.sortedByDescending { it.estimatedBytes }`.

### 3. Empty Collection State

**SwiftUI/.NET:** Shows "No collections in this database" message.  
**Android:** Verify this empty state exists. If missing, add a centered message when collection list is empty.

## Key Reference Files

- Android: `android/app/src/main/java/com/costoda/dittoedgestudio/ui/mainstudio/metrics/DiskUsageScreen.kt`
- Android: `android/app/src/main/java/com/costoda/dittoedgestudio/viewmodel/DiskUsageViewModel.kt`
- SwiftUI: `SwiftUI/EdgeStudio/Data/Repositories/StorageRepository.swift`

## Acceptance Criteria

- [ ] Auto-refresh every 15 seconds while screen is visible
- [ ] Collections sorted by size (largest first)
- [ ] Empty state message when no collections exist
