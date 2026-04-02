# Fix Database Close Hang — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the 6-10 second hang when closing a database with sync enabled by using session-based cancellation, guarded navigation, and diagnostic logging.

**Architecture:** Add a `sessionId` counter to `SystemRepository` so in-flight observer callbacks bail early. Show a "Closing database..." transition in `ContentView` while cleanup runs. Add timestamped logging to every close step for future debugging.

**Tech Stack:** SwiftUI, Swift actors, CocoaLumberjack (via `Log`)

**Spec:** `plans/fix-database-close-hang.md`

---

### Task 1: Add Session-Based Cancellation to SystemRepository

**Files:**
- Modify: `SwiftUI/EdgeStudio/Data/Repositories/SystemRepository.swift:4-27` (actor properties + new methods)
- Modify: `SwiftUI/EdgeStudio/Data/Repositories/SystemRepository.swift:199-358` (syncStatus observer callback)
- Modify: `SwiftUI/EdgeStudio/Data/Repositories/SystemRepository.swift:441-508` (connections observer callback)

- [ ] **Step 1: Add sessionId property and invalidateSession method**

In `SystemRepository.swift`, add the `sessionId` property after the existing private properties (after line 16), and add the `invalidateSession()` method after `deinit` (after line 27):

```swift
// After line 16 (private var pendingStatusItems: [SyncStatusInfo]?)
private var sessionId: Int = 0
```

```swift
// After deinit block (after line 27)

/// Invalidates the current session, causing all in-flight observer callbacks to bail early.
/// Call this as the very first step when closing a database.
func invalidateSession() {
    sessionId += 1
    Log.info("[Close:SystemRepo] Session invalidated, new sessionId=\(sessionId)")
}
```

- [ ] **Step 2: Add session check to syncStatusObserver callback**

In `registerSyncStatusObserver()`, capture the session ID at the start of the Task and add a guard before the expensive DQL query. Modify the observer callback (lines 205-357):

Replace the Task body opening (lines 206-207):
```swift
// BEFORE
Task { [weak self] in
    guard let self else { return }
```

With:
```swift
// AFTER
Task { [weak self] in
    guard let self else { return }
    let capturedSession = await self.sessionId
```

Add a guard before the DQL query (before line 226, after fetching appConfig):
```swift
// Bail early if session was invalidated during actor hop
guard await sessionId == capturedSession else {
    Log.info("[SystemRepository] syncStatus callback bailed: session invalidated")
    return
}
```

Add a second guard before building status items (before line 242, after the DQL query completes):
```swift
// Bail early if session was invalidated during DQL query
guard await sessionId == capturedSession else {
    Log.info("[SystemRepository] syncStatus callback bailed: session invalidated after DQL")
    return
}
```

- [ ] **Step 3: Add session check to connectionsPresenceObserver callback**

In `registerConnectionsPresenceObserver()`, apply the same pattern. Modify the observer callback (lines 447-508):

Replace the Task body opening (lines 448-449):
```swift
// BEFORE
Task { [weak self] in
    guard let self else { return }
```

With:
```swift
// AFTER
Task { [weak self] in
    guard let self else { return }
    let capturedSession = await self.sessionId
```

Add a guard before the connection processing loop (before line 458, after capturing self):
```swift
// Bail early if session was invalidated
guard await sessionId == capturedSession else {
    Log.info("[SystemRepository] connections callback bailed: session invalidated")
    return
}
```

- [ ] **Step 4: Increment sessionId on observer registration**

At the top of `registerSyncStatusObserver()` (line 199), after the ditto guard, add:
```swift
sessionId += 1
let currentSession = sessionId
Log.info("[SystemRepository] Registering syncStatus observer, sessionId=\(currentSession)")
```

At the top of `registerConnectionsPresenceObserver()` (line 441), after the ditto guard, add:
```swift
sessionId += 1
let currentSession = sessionId
Log.info("[SystemRepository] Registering connections observer, sessionId=\(currentSession)")
```

- [ ] **Step 5: Build and verify**

Run:
```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

Run:
```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add SwiftUI/EdgeStudio/Data/Repositories/SystemRepository.swift
git commit -m "feat: add session-based cancellation to SystemRepository observers

Adds a sessionId counter that in-flight presence observer callbacks check
before doing expensive work (DQL queries, actor hops). invalidateSession()
increments the counter so callbacks bail early during database close.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add Diagnostic Logging to DittoManager.closeDittoSelectedDatabase()

**Files:**
- Modify: `SwiftUI/EdgeStudio/Data/DittoManager.swift:16-28`

- [ ] **Step 1: Add timestamped logging to closeDittoSelectedDatabase**

Replace the entire `closeDittoSelectedDatabase()` method (lines 16-28) with:

```swift
func closeDittoSelectedDatabase() async {
    let closeStart = CFAbsoluteTimeGetCurrent()

    // Stop sync
    if let ditto = dittoSelectedApp {
        await Task.detached(priority: .utility) {
            ditto.sync.stop()
        }.value
        let syncStopElapsed = CFAbsoluteTimeGetCurrent() - closeStart
        Log.info("[Close:Ditto] sync.stop() complete (\(String(format: "%.3f", syncStopElapsed))s)")
    }

    // Stop log capture observers
    await MainActor.run {
        DittoLogCaptureService.shared.stopTransportConditionObserver()
        DittoLogCaptureService.shared.stopConnectionRequestHandler()
    }
    let logCaptureElapsed = CFAbsoluteTimeGetCurrent() - closeStart
    Log.info("[Close:Ditto] Log capture stopped (\(String(format: "%.3f", logCaptureElapsed))s)")

    // Release Ditto reference
    dittoSelectedApp = nil
    let totalElapsed = CFAbsoluteTimeGetCurrent() - closeStart
    Log.info("[Close:Ditto] Ditto reference released (\(String(format: "%.3f", totalElapsed))s)")
}
```

- [ ] **Step 2: Build and verify**

Run:
```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add SwiftUI/EdgeStudio/Data/DittoManager.swift
git commit -m "feat: add diagnostic logging to closeDittoSelectedDatabase

Timestamped logs at each step (sync.stop, log capture, reference release)
for diagnosing future close performance issues.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Add Diagnostic Logging to MainStudioView Close Flow

**Files:**
- Modify: `SwiftUI/EdgeStudio/Views/MainStudioView.swift:725-805` (closeSelectedApp + performCleanupOperations)

- [ ] **Step 1: Add timestamped logging to closeSelectedApp()**

Replace the `closeSelectedApp()` method (lines 725-750) with:

```swift
func closeSelectedApp() async {
    let closeStart = CFAbsoluteTimeGetCurrent()
    Log.info("[Close] Starting database close")

    // 1. Invalidate observer sessions FIRST so in-flight callbacks bail early
    await SystemRepository.shared.invalidateSession()
    let invalidateElapsed = CFAbsoluteTimeGetCurrent() - closeStart
    Log.info("[Close] Session invalidated (\(String(format: "%.3f", invalidateElapsed))s)")

    // 2. Clean up UI state immediately on main actor
    editorObservable = nil
    editorSubscription = nil
    selectedEventId = nil
    selectedObservable = nil

    subscriptions = []
    collections = []
    history = []
    favorites = []
    observerables = []
    observableEvents = []
    syncStatusItems = []
    connectionsByTransport = .empty
    isSyncEnabled = false

    // Clear peer info
    localPeerDeviceName = nil
    localPeerSDKLanguage = nil
    localPeerSDKPlatform = nil
    localPeerSDKVersion = nil

    let uiClearElapsed = CFAbsoluteTimeGetCurrent() - closeStart
    Log.info("[Close] UI state cleared (\(String(format: "%.3f", uiClearElapsed))s)")

    // 3. Perform heavy cleanup operations on background queue
    await performCleanupOperations()

    let totalElapsed = CFAbsoluteTimeGetCurrent() - closeStart
    Log.info("[Close] Total close time: \(String(format: "%.3f", totalElapsed))s")
}
```

- [ ] **Step 2: Add timestamped logging to performCleanupOperations()**

Replace the `performCleanupOperations()` method (lines 775-805) with:

```swift
private func performCleanupOperations() async {
    let cleanupStart = CFAbsoluteTimeGetCurrent()

    // Capture observables on main actor before moving to background queues
    let observablesToCleanup = observerables

    // Use TaskGroup to run cleanup operations concurrently on background queues
    await withTaskGroup(of: Void.self) { group in
        group.addTask(priority: .utility) {
            // Cancel observable store observers
            for observable in observablesToCleanup {
                observable.storeObserver?.cancel()
            }
            let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
            Log.info("[Close:Observers] Store observers cancelled (\(String(format: "%.3f", elapsed))s)")
        }

        group.addTask(priority: .utility) {
            // Clear repository caches
            await HistoryRepository.shared.clearCache()
            await FavoritesRepository.shared.clearCache()
            await ObservableRepository.shared.clearCache()
            await SubscriptionsRepository.shared.clearCache()

            // Stop other repository observers
            await SystemRepository.shared.stopObserver()
            await CollectionsRepository.shared.stopObserver()

            let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
            Log.info("[Close:Repos] Caches cleared, observers stopped (\(String(format: "%.3f", elapsed))s)")
        }

        group.addTask(priority: .utility) {
            // Close DittoManager selected app
            await DittoManager.shared.closeDittoSelectedDatabase()
            let elapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
            Log.info("[Close:DittoManager] closeDittoSelectedDatabase complete (\(String(format: "%.3f", elapsed))s)")
        }
    }

    let totalElapsed = CFAbsoluteTimeGetCurrent() - cleanupStart
    Log.info("[Close] All cleanup operations complete (\(String(format: "%.3f", totalElapsed))s)")
}
```

- [ ] **Step 3: Build and verify**

Run:
```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add SwiftUI/EdgeStudio/Views/MainStudioView.swift
git commit -m "feat: add diagnostic logging to close flow and invalidate sessions first

closeSelectedApp() now calls SystemRepository.invalidateSession() as its
first action, causing in-flight observer callbacks to bail early. Both
closeSelectedApp() and performCleanupOperations() log elapsed time at
each milestone for diagnosing future performance issues.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Add Closing Transition State to ContentView

**Files:**
- Modify: `SwiftUI/EdgeStudio/Views/ContentView.swift:4-58` (View body + state)
- Modify: `SwiftUI/EdgeStudio/Views/ContentView.swift:373-398` (ViewModel)
- Modify: `SwiftUI/EdgeStudio/Views/MainStudioView.swift:4-60` (init + properties)
- Modify: `SwiftUI/EdgeStudio/Views/MainStudioView.swift:306-316` (close button)

- [ ] **Step 1: Add isClosingDatabase state to ContentView.ViewModel**

In `ContentView.swift`, add `isClosingDatabase` to the ViewModel (after line 397):

```swift
// After: var isMainStudioViewPresented = false
var isClosingDatabase = false
```

- [ ] **Step 2: Update ContentView body to show transition state**

Replace the body's Group content (lines 9-27) with:

```swift
Group {
    if viewModel.isClosingDatabase {
        closingDatabaseView
    } else if viewModel.isMainStudioViewPresented,
       let selectedApp = viewModel.selectedDittoConfigForDatabase
    {
        MainStudioView(
            isMainStudioViewPresented: Binding(
                get: { viewModel.isMainStudioViewPresented },
                set: { viewModel.isMainStudioViewPresented = $0 }
            ),
            isClosingDatabase: Binding(
                get: { viewModel.isClosingDatabase },
                set: { viewModel.isClosingDatabase = $0 }
            ),
            dittoAppConfig: selectedApp
        )
        .environmentObject(appState)
    } else {
        #if os(iOS)
        iPadPickerView
        #else
        macOSPickerView
        #endif
    }
}
```

- [ ] **Step 3: Add the closingDatabaseView computed property**

Add this after the `body` property (before the closing brace of `ContentView`, around line 58):

```swift
private var closingDatabaseView: some View {
    VStack(spacing: 16) {
        ProgressView()
            .controlSize(.large)
        Text("Closing database...")
            .font(.headline)
            .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

- [ ] **Step 4: Update the frame modifier to handle closing state**

Update the macOS frame modifier (lines 30-35) to include the closing state. Replace:

```swift
.frame(
    minWidth: viewModel.isMainStudioViewPresented ? 1400 : 800,
    maxWidth: viewModel.isMainStudioViewPresented ? .infinity : 800,
    minHeight: viewModel.isMainStudioViewPresented ? 820 : 540,
    maxHeight: viewModel.isMainStudioViewPresented ? .infinity : 540
)
```

With:

```swift
.frame(
    minWidth: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? 1400 : 800,
    maxWidth: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? .infinity : 800,
    minHeight: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? 820 : 540,
    maxHeight: (viewModel.isMainStudioViewPresented || viewModel.isClosingDatabase) ? .infinity : 540
)
```

This prevents the window from resizing to the small picker size while the closing transition is active.

- [ ] **Step 5: Add isClosingDatabase binding to MainStudioView**

In `MainStudioView.swift`, add the binding property (after line 6):

```swift
// After: @Binding var isMainStudioViewPresented: Bool
@Binding var isClosingDatabase: Bool
```

Update the init (lines 54-60) to accept the new binding:

```swift
init(
    isMainStudioViewPresented: Binding<Bool>,
    isClosingDatabase: Binding<Bool>,
    dittoAppConfig: DittoConfigForDatabase
) {
    _isMainStudioViewPresented = isMainStudioViewPresented
    _isClosingDatabase = isClosingDatabase
    _viewModel = State(initialValue: ViewModel(dittoAppConfig))
}
```

- [ ] **Step 6: Update close button to use guarded navigation**

Replace the close button handler (lines 306-316) with:

```swift
private var closeButtonContent: some View {
    Button {
        isClosingDatabase = true
        Task {
            await viewModel.closeSelectedApp()
            isClosingDatabase = false
            isMainStudioViewPresented = false
        }
    } label: {
        Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
    }
    .buttonStyle(.glass)
    .clipShape(Circle())
    .help("Close App")
    .accessibilityIdentifier("CloseButton")
}
```

- [ ] **Step 7: Build for both platforms**

Run:
```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

Run:
```bash
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED

- [ ] **Step 8: Commit**

```bash
git add SwiftUI/EdgeStudio/Views/ContentView.swift SwiftUI/EdgeStudio/Views/MainStudioView.swift
git commit -m "feat: add closing transition state to prevent race conditions

Close button now shows a 'Closing database...' ProgressView while cleanup
runs. Database list only appears after cleanup fully completes, preventing
users from selecting a new database while the old one is still tearing down.
Window stays at studio size during the transition to avoid resize flicker.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Verify Full Close Flow

- [ ] **Step 1: Run all tests**

```bash
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" 2>&1 | tail -20
```
Expected: All tests pass

- [ ] **Step 2: Manual verification checklist**

Open the app, connect to a database with sync enabled, then click close. Verify:

1. "Closing database..." ProgressView appears immediately (no frozen UI)
2. Database list appears after cleanup completes (should be <1 second with cancellation)
3. Check Xcode console for `[Close]` log lines — verify all steps have timestamps
4. Check for `[SystemRepository] ... bailed: session invalidated` messages confirming callbacks exited early
5. No errors or warnings in console during close
6. Repeat 3-4 times to catch the intermittent case

- [ ] **Step 3: Commit any fixes from manual testing**

If any issues found during manual testing, fix and commit with descriptive message.
