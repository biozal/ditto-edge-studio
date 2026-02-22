# Plan: Fix Observer Events Table on iPhone (Horizontal Scrolling)

## Context

On iPhone, `observableEventsTable()` uses SwiftUI's native `Table` component. On iPhone (compact width), `Table` collapses to a single-column list showing only "Time" — no horizontal scrolling. This is intentional Apple behavior but wrong for this use case.

The fix is **Option A: replace `Table` with a custom `ScrollView([.horizontal, .vertical])` + `LazyVStack` implementation on all platforms**, matching the pattern already used by `ResultTableViewer`.

---

## Why Not Reuse `ResultTableViewer` Directly?

Research confirmed `ResultTableViewer` cannot be reused without significant conversion overhead:

| Issue | Detail |
|-------|--------|
| **Type mismatch** | `ResultTableViewer` takes `@Binding var resultText: [String]` (JSON strings). The events table works with `[DittoObserveEvent]` (typed Swift structs). |
| **Conversion overhead** | Converting 6 summary fields (eventTime, data.count, insertIndexes.count, etc.) to JSON strings, only to have `TableResultsParser` re-parse them back into columns, is wasteful. |
| **Private methods** | `iPadOSTableView()` and `macOSTableView()` are private — can't be called externally. |
| **Parser mismatch** | `TableResultsParser` is built for arbitrary JSON documents. The events table has exactly 6 known fixed columns — doesn't need dynamic key extraction. |

**Best approach: copy the ScrollView pattern directly into `observableEventsTable()` in `DetailViews.swift`.** No new file needed — it's a private helper that's only used in one place.

---

## What to Copy from `ResultTableViewer`

The structural pattern to replicate (from `ResultTableViewer.iPadOSTableView`):

```swift
ScrollView([.horizontal, .vertical]) {
    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
        Section {
            // data rows: ForEach with HStack of fixed-width cells
        } header: {
            // sticky column header row: HStack of fixed-width headers
        }
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

Key details to carry over:
- `ScrollView([.horizontal, .vertical])` — explicit both-axis scrolling
- `pinnedViews: [.sectionHeaders]` — column headers stick while scrolling vertically
- Fixed column widths on each cell (forces total row width > screen width → horizontal scroll)
- Alternating row background colors
- `Divider()` between cells for column separators

---

## Implementation

### File to Modify
`SwiftUI/Edge Debug Helper/Views/StudioView/Details/DetailViews.swift`

### Change: Replace `observableEventsTable()`

Remove the existing `@ViewBuilder` `Table`-based implementation entirely. Replace with a custom `ScrollView` implementation.

**Column widths** (chosen for content — summary integers are narrow, timestamp needs space):

| Column | Width | Content |
|--------|-------|---------|
| Time | 180pt | ISO timestamp `"2026-02-21T10:30:45Z"` |
| Count | 70pt | Integer |
| Inserted | 80pt | Integer (longer header) |
| Updated | 80pt | Integer |
| Deleted | 70pt | Integer |
| Moves | 70pt | Integer |

Total row width ≈ 550pt — wider than any iPhone screen (max ~430pt), guaranteeing horizontal scroll is triggered.

**Row selection:** `onTapGesture` to toggle `viewModel.selectedEventId` (matches the existing `selectionBinding` behavior). Highlight selected row with `.accentColor.opacity(0.2)` background. Unselected rows use alternating `systemBackground` / `secondarySystemBackground` stripes.

**New `observableEventsTable()` implementation:**

```swift
@ViewBuilder
private func observableEventsTable() -> some View {
    let columnDefs: [(header: String, width: CGFloat)] = [
        ("Time", 180), ("Count", 70), ("Inserted", 80),
        ("Updated", 80), ("Deleted", 70), ("Moves", 70)
    ]

    ScrollView([.horizontal, .vertical]) {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            Section {
                ForEach(Array(pagedObservableEvents.enumerated()), id: \.element.id) { index, event in
                    let isSelected = viewModel.selectedEventId == event.id
                    let values = [
                        event.eventTime,
                        "\(event.data.count)",
                        "\(event.insertIndexes.count)",
                        "\(event.updatedIndexes.count)",
                        "\(event.deletedIndexes.count)",
                        "\(event.movedIndexes.count)"
                    ]
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
                    }
                    .background(
                        isSelected
                            ? Color.accentColor.opacity(0.2)
                            : (index % 2 == 0
                                ? Color(PlatformColor.systemBackground)
                                : Color(PlatformColor.secondarySystemBackground).opacity(0.3))
                    )
                    .onTapGesture {
                        viewModel.selectedEventId = isSelected ? nil : event.id
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
                            .background(Color(PlatformColor.systemBackground))
                    }
                }
                .background(Color(PlatformColor.systemBackground))
            }
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
```

Note: `PlatformColor` needs to be `NSColor` on macOS and `UIColor` on iOS — use a `#if os(macOS)` typealias or write the conditional inline.

**Alternative to avoid `#if` for background colors**: use `Color(uiColor:)` on iOS and `Color(nsColor:)` on macOS, or simply use SwiftUI semantic colors:
- `Color(.systemBackground)` and `Color(.secondarySystemBackground)` work on iOS.
- On macOS, use `Color(NSColor.textBackgroundColor)` and `Color(NSColor.controlBackgroundColor)`.
- Wrap in `#if os(macOS)` / `#else` the same way `ResultTableViewer` already does (lines 117-118 and 197-198 of `ResultTableViewer.swift`).

---

## What Does NOT Change

- `pagedObservableEvents` computed property — same data source
- `viewModel.selectedEventId` — selection state unchanged
- Pagination controls in `observableEventsList()` — unchanged
- Everything else in `DetailViews.swift` — unchanged

---

## Files Modified

| File | Change |
|------|--------|
| `SwiftUI/Edge Debug Helper/Views/StudioView/Details/DetailViews.swift` | Replace `observableEventsTable()` body: remove `Table`+`TableColumn`, add `ScrollView([.horizontal,.vertical])` + `LazyVStack` with pinned section header |

---

## Verification

1. Build: `xcodebuild -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" build`
2. **iPhone simulator**: Observer tab → activate observer → verify all 6 columns visible by swiping left; tap a row to select it, verify bottom pane updates
3. **iPad simulator**: Verify all 6 columns visible, horizontal scroll works, row selection works
4. **macOS**: Verify all 6 columns visible, horizontal scroll works, row selection works
5. No regressions: pagination, event selection, and bottom detail pane unaffected
