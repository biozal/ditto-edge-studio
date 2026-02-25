# Fix: Observer Events Table — Use ResultTableViewer Pattern

## Status
READY TO IMPLEMENT

## Summary

Stop fighting custom layout. Create a dedicated `ObserverEventsTableView` component that
mirrors the **proven, working structure** of `ResultTableViewer`. Both share the same
`GeometryReader → ScrollView → LazyVStack(pinnedViews:) → Section { header / rows }` layout.
`ResultTableViewer` works because it has one line our custom table was always missing.

---

## Root Cause — The Missing Line

Compare the two implementations:

**`ResultTableViewer.macOSTableView` (works correctly):**
```swift
GeometryReader { geometry in
    ScrollView([.horizontal, .vertical]) {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section { /* rows */ } header: { /* header */ }
        }
        .frame(minHeight: geometry.size.height, alignment: .top)  // ← THE KEY LINE
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

**`observableEventsTable()` (original, had gap):**
```swift
GeometryReader { geo in
    ScrollView([.horizontal, .vertical]) {
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section { /* rows */ } header: { /* header */ }
        }
        // ← MISSING: .frame(minHeight: geo.size.height, alignment: .top)
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

`.frame(minHeight: geometry.size.height, alignment: .top)` on the `LazyVStack` pins the content
to the top of the scroll view's frame. Without it, the `LazyVStack` only occupies the height of
its rendered rows. When `pinnedViews: [.sectionHeaders]` is active, the section header renders
at the scroll view's safe-area-offset origin rather than at the content origin, producing the
visible gap between the header and the first row.

Every previous fix attempt (removing GeometryReader, removing pinnedViews, contentMargins, fixed
header above ScrollView) worked around symptoms of this missing line rather than fixing the
actual cause.

---

## Why Create a New Component (not fix inline)

The current `observableEventsTable()` in `DetailViews.swift` has been patched multiple times and
now has a non-standard structure (VStack-above-ScrollView, fixedSize, contentMargins). It differs
from the working `ResultTableViewer` pattern.

Creating `ObserverEventsTableView` as a standalone component:
- Uses the **exact same proven structure** as `ResultTableViewer`
- Is typed for `[DittoObserveEvent]` (ResultTableViewer can't be reused directly — it parses JSON)
- Moves table rendering out of the 900-line `DetailViews.swift` extension
- Matches the project's pattern of reusable components in `Components/`

---

## Implementation

### New file: `SwiftUI/Edge Debug Helper/Components/ObserverEventsTableView.swift`

Must be created via XcodeWrite to be added to the correct build target.

Structure mirrors `ResultTableViewer.macOSTableView` exactly:

```swift
import SwiftUI

struct ObserverEventsTableView: View {
    let events: [DittoObserveEvent]
    @Binding var selectedEventId: String?

    private let columnDefs: [(header: String, width: CGFloat)] = [
        ("Time", 180), ("Count", 70), ("Inserted", 80),
        ("Updated", 80), ("Deleted", 70), ("Moves", 70)
    ]

    var body: some View {
        #if os(macOS)
        macOSTable
        #else
        iOSTable
        #endif
    }

    // MARK: - macOS

    #if os(macOS)
    private var macOSTable: some View {
        GeometryReader { geometry in
            ScrollView([.horizontal, .vertical]) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                            let isSelected = selectedEventId == event.id
                            let values = rowValues(for: event)
                            HStack(spacing: 0) {
                                ForEach(columnDefs.indices, id: \.self) { colIdx in
                                    if colIdx > 0 { Divider() }
                                    Text(values[colIdx])
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)
                                        .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 8)
                                }
                                Divider()
                            }
                            .frame(minWidth: geometry.size.width)
                            .background(
                                isSelected
                                    ? Color.accentColor.opacity(0.2)
                                    : (index % 2 == 0
                                        ? Color(NSColor.textBackgroundColor)
                                        : Color(NSColor.controlBackgroundColor).opacity(0.3))
                            )
                            .onTapGesture {
                                selectedEventId = isSelected ? nil : event.id
                            }
                        }
                    } header: {
                        HStack(spacing: 0) {
                            ForEach(columnDefs.indices, id: \.self) { colIdx in
                                if colIdx > 0 { Divider() }
                                Text(columnDefs[colIdx].header)
                                    .font(.system(.headline, design: .monospaced))
                                    .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                                    .background(Color(NSColor.windowBackgroundColor))
                            }
                            Divider()
                        }
                        .frame(minWidth: geometry.size.width)
                        .background(Color(NSColor.windowBackgroundColor))
                    }
                }
                .frame(minHeight: geometry.size.height, alignment: .top)  // ← THE FIX
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - iOS

    #if os(iOS)
    private var iOSTable: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        let isSelected = selectedEventId == event.id
                        let values = rowValues(for: event)
                        HStack(spacing: 0) {
                            ForEach(columnDefs.indices, id: \.self) { colIdx in
                                if colIdx > 0 { Divider() }
                                Text(values[colIdx])
                                    .font(.system(.body, design: .monospaced))
                                    .lineLimit(1)
                                    .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 8)
                            }
                            Divider()
                        }
                        .background(
                            isSelected
                                ? Color.accentColor.opacity(0.2)
                                : (index % 2 == 0
                                    ? Color(UIColor.systemBackground)
                                    : Color(UIColor.secondarySystemBackground).opacity(0.3))
                        )
                        .onTapGesture {
                            selectedEventId = isSelected ? nil : event.id
                        }
                    }
                } header: {
                    HStack(spacing: 0) {
                        ForEach(columnDefs.indices, id: \.self) { colIdx in
                            if colIdx > 0 { Divider() }
                            Text(columnDefs[colIdx].header)
                                .font(.system(.headline, design: .monospaced))
                                .frame(width: columnDefs[colIdx].width, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(Color(UIColor.systemBackground))
                        }
                        Divider()
                    }
                    .background(Color(UIColor.systemBackground))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    #endif

    // MARK: - Helpers

    private func rowValues(for event: DittoObserveEvent) -> [String] {
        [
            event.eventTime,
            "\(event.data.count)",
            "\(event.insertIndexes.count)",
            "\(event.updatedIndexes.count)",
            "\(event.deletedIndexes.count)",
            "\(event.movedIndexes.count)"
        ]
    }
}
```

### Changes to `DetailViews.swift`

**Replace `observableEventsTable(containerWidth:)`** with a simple call to the new component.

The `containerWidth` parameter is no longer needed since the component uses its own
GeometryReader (same as `ResultTableViewer`).

In `observableEventsList(containerWidth:)`:
```swift
// BEFORE
} else {
    observableEventsTable(containerWidth: containerWidth)
}

// AFTER
} else {
    ObserverEventsTableView(
        events: pagedObservableEvents,
        selectedEventId: $viewModel.selectedEventId
    )
}
```

Remove the entire `observableEventsTable(containerWidth:)` function.

Also clean up the now-unnecessary `containerWidth` threading through the call chain:
- `observableEventsList(containerWidth:)` → back to `observableEventsList()`
- `observeDetailView()` → back to `observableEventsList()` (no argument)

---

## Files to Change

| File | Action |
|------|--------|
| `Components/ObserverEventsTableView.swift` | **Create** (via XcodeWrite) |
| `Views/StudioView/Details/DetailViews.swift` | **Edit** — remove `observableEventsTable`, revert `containerWidth` threading, use new component |

---

## Verification

1. Build macOS and iOS (both must succeed)
2. Open Observers tab → select an active observer with events
3. Verify:
   - Column header (Time, Count, …) appears **immediately below** the pagination bar Divider — no gap
   - First data row is **directly under** the column header — no gap between header and rows
   - Column header **pins** to the top while scrolling down through many events
   - Alternating row backgrounds and selection highlight work
   - Horizontal scroll works (rows extend beyond screen width)
4. Open Query tab — verify `ResultTableViewer` is unaffected
5. Verify AppMetrics and QueryMetrics are unaffected
