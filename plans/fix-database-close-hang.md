# Fix Database Close Hang — Design Spec

**Date:** 2026-04-01
**Status:** Approved

## Problem

When closing a database with sync enabled, the UI sometimes hangs for 6-10 seconds before returning to the database list. The hang is intermittent — it depends on whether presence observer callbacks are mid-flight when close is triggered.

## Root Cause

**Actor contention between close flow and in-flight presence observer callbacks.**

The close flow (`performCleanupOperations`) needs actor locks on both `SystemRepository` and `DittoManager`. Meanwhile, the two presence observers in `SystemRepository` fire callbacks that:

1. Create a `Task` that acquires the `SystemRepository` actor lock
2. Inside that task, `await dittoManager.dittoSelectedAppConfig` — acquires the `DittoManager` actor lock
3. The sync status observer also runs `await ditto.store.execute(query: "SELECT * FROM system:data_sync_info")` — a DQL query

When close is triggered while an observer callback is mid-flight (holding actor locks and doing a DQL query), the cleanup tasks must wait for the callback to finish. With many peers or a slow DQL query, this adds up to 6-10 seconds.

**Why the stop sync button is instant:** It calls the same `ditto.sync.stop()` but doesn't need actor locks on `SystemRepository` — it doesn't tear down observers or nil out the Ditto object.

## Approach: Cancellation Token + Guarded Navigation (Hybrid)

Three mechanisms working together:

1. **Guarded navigation** — user sees a "Closing database..." transition state immediately, database list only appears after cleanup is done (prevents race conditions)
2. **Session-based cancellation** — in-flight observer callbacks bail early instead of finishing expensive DQL queries
3. **Diagnostic logging** — timestamped logs at every close milestone for future debugging

## Design

### 1. ContentView Transition State

Add `@State private var isClosingDatabase = false` on ContentView, passed as a binding to MainStudioView.

```swift
// ContentView body
if isMainStudioViewPresented {
    if isClosingDatabase {
        ProgressView("Closing database...")
    } else {
        MainStudioView(..., isClosingDatabase: $isClosingDatabase)
    }
} else {
    // Normal database list
}
```

When close is tapped, MainStudioView is immediately replaced with the progress indicator (no interaction with stale UI). Once cleanup finishes, the database list appears.

### 2. Session-Based Cancellation in SystemRepository

A `sessionId` counter on `SystemRepository`. Incremented on both observer registration (new session starts) and invalidation (session ends). Observer callbacks capture the current ID and check it before doing expensive work.

```swift
// SystemRepository additions
private var sessionId: Int = 0

func invalidateSession() {
    sessionId += 1  // Causes all in-flight callbacks with old ID to bail
}

// Called at the start of registerSyncStatusObserver() and registerConnectionsPresenceObserver()
func startNewSession() -> Int {
    sessionId += 1
    return sessionId  // Returned so observer closures can capture it
}
```

Both `syncStatusObserver` and `connectionsPresenceObserver` callbacks check the session ID before expensive operations (DQL queries, actor hops to DittoManager):

```swift
syncStatusObserver = ditto.presence.observe { [weak self] presenceGraph in
    Task { [weak self] in
        guard let self else { return }
        let capturedSession = await self.sessionId
        
        // ... lightweight work ...
        
        // Before expensive DQL query:
        guard await self.sessionId == capturedSession else {
            Log.info("[SystemRepository] Observer callback bailed: session invalidated")
            return
        }
        
        // ... continue with expensive work ...
    }
}
```

`invalidateSession()` is called as the very first step of close.

### 3. Close Flow Restructuring

The close button handler:

```swift
Button {
    isClosingDatabase = true  // Show transition state immediately
    Task {
        await viewModel.closeSelectedApp()
        isClosingDatabase = false
        isMainStudioViewPresented = false  // Show database list
    }
}
```

`closeSelectedApp()` ordering:

1. **Invalidate sessions** — `await SystemRepository.shared.invalidateSession()` (instant, causes in-flight callbacks to bail)
2. **Clear UI state** — nil out all published properties (existing code, MainActor)
3. **Run cleanup TaskGroup** — same as today but faster because observers bail early
4. **Return** — caller flips navigation flags

### 4. Diagnostic Logging

Every close step gets timestamped logging using `CFAbsoluteTimeGetCurrent()`.

**In `closeSelectedApp()`:**
```
[Close] Starting database close
[Close] Session invalidated (0.001s)
[Close] UI state cleared (0.002s)
[Close] Cleanup operations complete (0.145s)
[Close] Total close time: 0.147s
```

**In `performCleanupOperations()` — each TaskGroup child:**
```
[Close:Observers] Cancelling store observers (0.003s)
[Close:Repos] Caches cleared, observers stopped (0.042s)
[Close:Ditto] sync.stop() complete (0.089s)
[Close:Ditto] Log capture stopped (0.091s)
[Close:Ditto] Ditto reference released (0.092s)
```

**In SystemRepository observer callbacks — on early bail:**
```
[SystemRepository] Observer callback bailed: session invalidated
```

## Files to Modify

| File | Change |
|------|--------|
| `ContentView.swift` | Add `isClosingDatabase` state, transition view, pass binding |
| `MainStudioView.swift` | Accept `isClosingDatabase` binding, restructure close button, add logging to `closeSelectedApp()` and `performCleanupOperations()` |
| `SystemRepository.swift` | Add `sessionId`, `invalidateSession()`, cancellation checks in both observer callbacks |
| `DittoManager.swift` | Add logging to `closeDittoSelectedDatabase()` |

## Expected Outcome

- Close with sync enabled: user sees "Closing database..." for <1 second instead of 6-10 seconds of frozen UI
- No race conditions: database list only appears after cleanup is fully done
- Full diagnostic trail in logs for any future slowness
