# Fix: Activate Observer Navigates to observeDetailView

## Status
READY TO IMPLEMENT

## What's Happening Today

In `observerTreeRows()` (`SidebarViews.swift`), there are two separate interactions:

**1. Tapping the observer row label** — already works correctly:
```swift
Button {
    expandedObserverIds.formSymmetricDifference([observer.id])
    viewModel.selectedObservable = observer                        // ✅ selects it
    viewModel.selectedSidebarMenuItem = ...Observers menu item...  // ✅ switches detail view
    Task { await viewModel.loadObservedEvents() }                  // ✅ loads events
} label: { ... }
```

**2. Tapping "Activate" (context menu macOS / swipe action iOS)** — broken:
```swift
Button {
    Task {
        do {
            try await viewModel.registerStoreObserver(observer)    // registers only
            // ❌ does NOT select the observer
            // ❌ does NOT switch detail view to Observers
            // ❌ does NOT load events
        } catch { appState.setError(error) }
    }
} label: { Label("Activate", ...) }
```

After tapping Activate, the observer registration succeeds (the "Active" badge appears on
the row), but the detail pane stays on whatever was showing before — nothing happens visually.
The user has to also tap the row label to get to `observeDetailView`.

The routing in `MainStudioView.body` is simple:
```swift
case "Observers":
    observeDetailView()
```
All that's needed is for the Activate action to also set the same state the row tap already sets.

---

## Root Cause

The Activate button does one thing (`registerStoreObserver`) but the row-tap label does four
things (register + select + switch + load). The navigation half was never added to Activate.

---

## Fix

**File:** `SwiftUI/Edge Debug Helper/Views/StudioView/SidebarViews.swift`

In `observerTreeRows()`, update the Activate button action in **both** the macOS `contextMenu`
block and the iOS `swipeActions` block to add the same three navigation steps that the row
label already performs — **after** `registerStoreObserver` succeeds:

```swift
// BEFORE (macOS contextMenu — same pattern in iOS swipeActions)
Button {
    Task {
        do {
            try await viewModel.registerStoreObserver(observer)
        } catch { appState.setError(error) }
    }
} label: {
    Label("Activate", systemImage: "play.circle")
        .labelStyle(.titleAndIcon)
}

// AFTER
Button {
    Task {
        do {
            try await viewModel.registerStoreObserver(observer)
            // Navigate to the observer detail view — same as tapping the row label
            viewModel.selectedObservable = observer
            viewModel.selectedSidebarMenuItem =
                viewModel.sidebarMenuItems.first { $0.name == "Observers" }
                ?? viewModel.sidebarMenuItems[0]
            await viewModel.loadObservedEvents()
        } catch { appState.setError(error) }
    }
} label: {
    Label("Activate", systemImage: "play.circle")
        .labelStyle(.titleAndIcon)
}
```

Apply identically to both:
- macOS `contextMenu` Activate button (line ~354)
- iOS `swipeActions` Activate button (line ~392)

---

## Files to Change

| File | Change |
|------|--------|
| `Views/StudioView/SidebarViews.swift` | Add 3 lines to both Activate button actions |

---

## Verification

1. Build macOS + iOS
2. Open the app → open a database → go to Observers in the sidebar
3. Right-click (macOS) or swipe (iOS) an inactive observer → tap **Activate**
4. Verify:
   - Observer registers (green "Active" badge appears on the row) ✅
   - Detail pane immediately switches to `observeDetailView` ✅
   - The activated observer is selected (its events list or empty state is shown) ✅
   - Tapping the row label still works as before ✅
   - Stopping an observer (Stop action) does NOT navigate away — no change needed there ✅
