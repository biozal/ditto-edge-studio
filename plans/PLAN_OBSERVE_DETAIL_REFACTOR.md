# Plan: Refactor observeDetailView + queryDetailView Cleanup

## Goal
- Fix `observeDetailView()` to use the same `GeometryReader`-based split pattern as `queryDetailView()`
- Eliminate the separate "No Observer Selected" view — show it inline in the top pane
- Remove the `#if os(macOS)` / `#else` duplication in both detail views
- Leave only genuinely iOS-specific modifiers (toolbar items, `.navigationBarTitleDisplayMode`) guarded by `#if os(iOS)`

---

## File: `SwiftUI/Edge Debug Helper/Views/StudioView/Details/DetailViews.swift`

---

### Change 1 — Rewrite `observeDetailView()`

**Remove** the current implementation (lines 166–196) which has:
- `#if os(macOS)` → `VSplitView { ... }`
- `#else` → `VStack { ... }`
- `#if os(iOS)` toolbar block

**Replace with** the same `GeometryReader` pattern used by `queryDetailView()`:

```swift
func observeDetailView() -> some View {
    VStack(alignment: .leading, spacing: 0) {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top pane (50%) — events list, or "no observer" / "no events" states inline
                observableEventsList()
                    .frame(height: geometry.size.height * 0.5)

                Divider()

                // Bottom pane (50%) — selected event detail
                observableDetailSelectedEvent(observeEvent: viewModel.selectedEventObject)
                    .frame(height: geometry.size.height * 0.5)
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.bottom, 28) // status bar clearance
}
```

Key points:
- `VSplitView` is gone — no more constraint loop risk
- Single implementation, no platform `#if` split
- The `#if os(iOS)` toolbar block is removed; iOS toolbar work is deferred to the iPad phase

---

### Change 2 — Merge "No Observer Selected" into `observableEventsList()`

**Delete** the entire `observableDetailNoContent()` private function (~8 lines).

**Update** `observableEventsList()` to handle all three states in one place:

```swift
private func observableEventsList() -> some View {
    VStack {
        if viewModel.selectedObservable == nil {
            // No observer chosen yet
            ContentUnavailableView(
                "No Observer Selected",
                systemImage: "exclamationmark.triangle.fill",
                description: Text("Select an observer from the sidebar to view events.")
            )
        } else if viewModel.observableEvents.isEmpty {
            // Observer selected but no events yet
            ContentUnavailableView(
                "No Observer Events",
                systemImage: "exclamationmark.triangle.fill",
                description: Text("Activate an observer to see observable events.")
            )
        } else {
            // Events table (unchanged)
            Table(viewModel.observableEvents, selection: ...) { ... }
                .navigationTitle("Observer Events")
        }
    }
}
```

This eliminates the need to choose between `observableDetailNoContent()` and `observableEventsList()` at the call site — the top pane always shows `observableEventsList()`.

---

### Change 3 — Simplify `queryDetailView()` (remove macOS/iOS duplication)

**Current state:** two near-identical blocks separated by `#if os(macOS)` / `#else`:
- macOS: `GeometryReader { VStack { editor.frame(h*0.5) … results.frame(h*0.5) } }`
- iOS:   `VStack { editor.frame(maxHeight:.infinity) … results.frame(maxHeight:.infinity) } .navigationBarTitleDisplayMode(.inline)`

**Replace with** a single `GeometryReader` block that works on both platforms, keeping only the genuinely iOS-specific modifier:

```swift
func queryDetailView() -> some View {
    VStack(alignment: .leading, spacing: 0) {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                QueryEditorView(...)
                    .frame(height: geometry.size.height * 0.5)

                Divider()

                QueryResultsView(...)
                    .frame(height: geometry.size.height * 0.5)
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.bottom, 28)
    #if os(iOS)
        .toolbar {
            appNameToolbarLabel()
            syncToolbarButton()
            closeToolbarButton()
        }
    #endif
}
```

This removes ~20 lines of duplicated code while keeping identical runtime behaviour on both platforms.

---

## What is NOT changing

- `observableDetailSelectedEvent()` — no changes needed, bottom pane stays as-is
- `SidebarViews.swift` — `observeSidebarView()` keeps its `#if os(macOS)` contextMenu / `#else` swipeActions split; those are genuinely platform-different interaction models and will be addressed in the iPad phase
- All toolbar functions in `MainStudioView.swift` — unchanged
- Test files — no logic changes; the refactor is purely structural

---

## Summary of net changes

| What | Before | After |
|------|--------|-------|
| `observeDetailView()` | `VSplitView` + 2 platform blocks | Single `GeometryReader` pattern |
| `observableDetailNoContent()` | Separate function | Deleted; merged into `observableEventsList()` |
| `observableEventsList()` | Handles events only | Handles all 3 states (no observer, no events, table) |
| `queryDetailView()` | 2 near-identical platform blocks | Single `GeometryReader` block |
| Platform guards remaining | Many | Only `#if os(iOS)` for toolbar + `navigationBarTitleDisplayMode` |
