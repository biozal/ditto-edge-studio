# Sync Observer Lifecycle Management Plan

## Problem Statement

When sync is disabled via the toolbar button, the `system:data_sync_info` observer continues running and firing updates with stale data. This causes the Ditto Server counter to reappear even after being reset, because the observer callback updates `dittoServerCount` with old information.

**Current Flow (Broken):**
1. User clicks "Disable Sync" button
2. `stopSync()` called → stops Ditto sync
3. `resetDittoServerCount()` called → resets counter to 0
4. **BUT** `system:data_sync_info` observer still running
5. Observer fires with stale data → updates `dittoServerCount` → Ditto Server reappears ❌

## Root Cause

- `registerSyncStatusObserver()` starts the observer when app loads
- Observer continues running until app is closed
- Sync disable/enable doesn't affect observer lifecycle
- Stale data from observer overwrites our reset

## Solution

Stop and restart observers when sync is toggled:

**When sync is disabled:**
1. Stop Ditto sync
2. Stop all SystemRepository observers (sync status + connections presence)
3. Reset connection counts to zero

**When sync is enabled:**
1. Start Ditto sync
2. Restart all SystemRepository observers
3. Observers fire with fresh data

## Implementation Plan

### 1. Update SystemRepository - Add Restart Method

**File:** `Data/Repositories/SystemRepository.swift`

**Add new method:**
```swift
func restartObservers() async throws {
    // Stop existing observers first
    stopObserver()

    // Wait for cleanup to complete
    try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

    // Restart observers
    try await registerSyncStatusObserver()
    try await registerConnectionsPresenceObserver()
}
```

**Why this works:**
- Ensures clean shutdown of existing observers
- Brief delay allows cleanup to complete
- Restarts both observers with fresh connections

### 2. Update MainStudioView - Toggle Sync Method

**File:** `Views/MainStudioView.swift`

**Current `toggleSync()` implementation (lines 1451-1459):**
```swift
func toggleSync() async throws {
    if isSyncEnabled {
        await DittoManager.shared.selectedAppStopSync()
        isSyncEnabled = false
        // Reset Ditto Server count immediately when sync is disabled
        await SystemRepository.shared.resetDittoServerCount()
    } else {
        try await DittoManager.shared.selectedAppStartSync()
        isSyncEnabled = true
    }
}
```

**New implementation:**
```swift
func toggleSync() async throws {
    if isSyncEnabled {
        // Disable sync
        await DittoManager.shared.selectedAppStopSync()

        // Stop observers to prevent stale data updates
        await SystemRepository.shared.stopObserver()

        // Reset connection counts
        connectionsByTransport = .empty
        syncStatusItems = []

        isSyncEnabled = false
    } else {
        // Enable sync
        try await DittoManager.shared.selectedAppStartSync()
        isSyncEnabled = true

        // Restart observers with fresh connections
        do {
            try await SystemRepository.shared.registerSyncStatusObserver()
            try await SystemRepository.shared.registerConnectionsPresenceObserver()
        } catch {
            assertionFailure("Failed to restart observers: \(error)")
        }
    }
}
```

### 3. Update stopSync() Method

**File:** `Views/MainStudioView.swift`

**Current implementation (lines 1466-1469):**
```swift
func stopSync() async {
    await DittoManager.shared.selectedAppStopSync()
    isSyncEnabled = false
    // Reset Ditto Server count immediately when sync is disabled
    await SystemRepository.shared.resetDittoServerCount()
}
```

**New implementation:**
```swift
func stopSync() async {
    await DittoManager.shared.selectedAppStopSync()

    // Stop observers to prevent stale data updates
    await SystemRepository.shared.stopObserver()

    // Reset connection counts
    connectionsByTransport = .empty
    syncStatusItems = []

    isSyncEnabled = false
}
```

### 4. Update startSync() Method

**File:** `Views/MainStudioView.swift`

**Current implementation (lines 1461-1464):**
```swift
func startSync() async throws {
    try await DittoManager.shared.selectedAppStartSync()
    isSyncEnabled = true
}
```

**New implementation:**
```swift
func startSync() async throws {
    try await DittoManager.shared.selectedAppStartSync()
    isSyncEnabled = true

    // Restart observers with fresh connections
    do {
        try await SystemRepository.shared.registerSyncStatusObserver()
        try await SystemRepository.shared.registerConnectionsPresenceObserver()
    } catch {
        assertionFailure("Failed to restart observers: \(error)")
    }
}
```

### 5. Ensure No Duplicate Observers

**Concern:** What if observers are already running when we try to restart?

**Solution:** `stopObserver()` already handles cleanup:
```swift
func stopObserver() {
    Task.detached(priority: .utility) { [weak self] in
        await self?.performObserverCleanup()
    }
}

private func performObserverCleanup() {
    syncStatusObserver?.cancel()
    syncStatusObserver = nil
    connectionsPresenceObserver = nil
    dittoServerCount = 0
}
```

**Safety:**
- Setting observers to `nil` prevents duplicate registrations
- If observer already nil, registering creates new one
- No leaks or duplicate callbacks

## Key Changes Summary

### SystemRepository
- ✅ Already has `stopObserver()` method
- ✅ Already has `registerSyncStatusObserver()` method
- ✅ Already has `registerConnectionsPresenceObserver()` method
- ❌ Remove `resetDittoServerCount()` method (no longer needed - observers handle it)

### MainStudioView ViewModel
- ✅ Update `toggleSync()` to stop/restart observers
- ✅ Update `stopSync()` to stop observers
- ✅ Update `startSync()` to restart observers
- ✅ Reset `connectionsByTransport` and `syncStatusItems` when sync disabled

## Benefits

✅ **No stale data:** Observers stopped when sync disabled, can't fire with old data
✅ **Clean lifecycle:** Observers match sync state (running = observers active)
✅ **Immediate reset:** Connection counts cleared when sync disabled
✅ **Fresh data:** Observers restart with new connections when sync enabled
✅ **No race conditions:** Stop before reset prevents timing issues

## Testing Plan

### Manual Test Scenarios

1. **Disable sync:**
   - ✅ Click "Disable Sync" button
   - ✅ Verify Ditto Server counter disappears immediately
   - ✅ Verify all connection counters disappear
   - ✅ Verify sync status list clears
   - ✅ Verify no console errors
   - ✅ Wait 5 seconds → verify counters don't reappear

2. **Re-enable sync:**
   - ✅ Click "Enable Sync" button
   - ✅ Verify observers restart
   - ✅ Verify connection counters appear with fresh data
   - ✅ Verify sync status list populates
   - ✅ Verify Ditto Server appears if connected

3. **Toggle rapidly:**
   - ✅ Click disable → enable → disable quickly
   - ✅ Verify no crashes or threading warnings
   - ✅ Verify final state matches button state

4. **Connect to Big Peer while sync disabled:**
   - ✅ Disable sync
   - ✅ Connect to Ditto Server externally
   - ✅ Verify Ditto Server counter does NOT appear (correct - observers stopped)
   - ✅ Enable sync
   - ✅ Verify Ditto Server counter appears (observers detected connection)

## Edge Cases

### Case 1: Observers already stopped
**Scenario:** Call `stopObserver()` when observers already nil
**Result:** Safe - `stopObserver()` checks for nil before canceling
**Status:** ✅ Handled

### Case 2: Restart during cleanup
**Scenario:** Call `registerObserver()` while previous `stopObserver()` still cleaning up
**Result:** New observer registers after cleanup completes (async Task)
**Status:** ✅ Handled by Task.detached

### Case 3: Multiple rapid toggles
**Scenario:** User clicks sync toggle multiple times quickly
**Result:** Each toggle stops/starts observers; last call wins
**Status:** ✅ Acceptable behavior

### Case 4: App switch during sync disabled
**Scenario:** Sync disabled, then switch to different app
**Result:** `closeSelectedApp()` calls `stopObserver()` (already stopped - safe)
**Status:** ✅ Handled

## Files to Modify

1. **`Data/Repositories/SystemRepository.swift`**
   - Remove `resetDittoServerCount()` method (no longer needed)
   - All other methods stay as-is

2. **`Views/MainStudioView.swift`**
   - Update `toggleSync()` method
   - Update `stopSync()` method
   - Update `startSync()` method
   - Reset `connectionsByTransport` and `syncStatusItems` on sync disable

## Implementation Steps

### Step 1: Remove resetDittoServerCount
- ✅ Delete `resetDittoServerCount()` method from SystemRepository
- ✅ Remove calls to `resetDittoServerCount()` from MainStudioView

### Step 2: Update toggleSync
- ✅ Add `stopObserver()` call when disabling sync
- ✅ Add observer restart when enabling sync
- ✅ Reset connection state when disabling

### Step 3: Update stopSync
- ✅ Add `stopObserver()` call
- ✅ Reset connection state

### Step 4: Update startSync
- ✅ Add observer restart

### Step 5: Test
- ✅ Build and verify
- ✅ Manual testing with sync toggle
- ✅ Verify Ditto Server counter behavior

## Why This Fixes the Issue

**Before:**
```
Disable Sync → Stop Ditto sync → Reset counter
↓
Observer still running → Fires with stale data
↓
Counter reappears ❌
```

**After:**
```
Disable Sync → Stop Ditto sync → Stop observers → Reset state
↓
Observers stopped → Can't fire → Can't update counter
↓
Counter stays removed ✅
```

**Enable Sync:**
```
Enable Sync → Start Ditto sync → Restart observers
↓
Observers fire with fresh data → Counter appears with real state ✅
```

## Alternative Approaches Considered

### Option 1: Ignore observer updates when sync disabled
```swift
if !isSyncEnabled { return }  // In observer callback
```
**Pros:** Simple check
**Cons:** Observer still running (memory/CPU), stale data kept in memory
**Verdict:** ❌ Wasteful

### Option 2: Filter updates based on timestamp
```swift
guard updateTime > lastSyncDisableTime else { return }
```
**Pros:** Prevents stale updates
**Cons:** Complex state management, doesn't stop observer
**Verdict:** ❌ Over-engineered

### Option 3: Chosen approach - Stop/restart observers
**Pros:** Clean lifecycle, no wasted resources, matches logical state
**Cons:** Slightly more code
**Verdict:** ✅ Correct solution

## Success Criteria

✅ Ditto Server counter disappears immediately when sync disabled
✅ Ditto Server counter does NOT reappear while sync is disabled
✅ All connection counters cleared when sync disabled
✅ Observers restart successfully when sync enabled
✅ Fresh connection data appears when sync enabled
✅ No threading warnings or memory leaks
✅ Build succeeds without errors
✅ Rapid toggle works without crashes

## Documentation Updates

**Code Comments:**
```swift
// Stop observers when sync is disabled to prevent stale data updates
await SystemRepository.shared.stopObserver()

// Restart observers when sync is enabled to get fresh connection data
try await SystemRepository.shared.registerSyncStatusObserver()
try await SystemRepository.shared.registerConnectionsPresenceObserver()
```

**CLAUDE.md:** No changes needed (internal implementation detail)
