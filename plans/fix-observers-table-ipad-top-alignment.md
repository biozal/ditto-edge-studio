# Fix: Observer Events Table — iPad Top Alignment & Container Fill

## Status
READY TO IMPLEMENT

## Problem

On iPad, the **top pane** of `observeDetailView()` (the observer events table) is not aligned
to the top of its container and does not fill the available height. The **bottom pane**
(selected event detail / `ResultTableViewer`) works correctly.

---

## Root Cause

`ObserverEventsTableView.iOSTable` has no `GeometryReader` and no
`.frame(minHeight:, alignment: .top)` on its `LazyVStack`. Without a `minHeight` anchor
the `LazyVStack` sizes itself to fit its content (which may be just a few rows). The
`ScrollView` then places this undersized stack at whatever vertical position SwiftUI chooses,
rather than pinning it to the top and filling the frame.

### Why the bottom pane works

`ResultTableViewer.iPadOSTableView` also lacks a `GeometryReader`, but it is placed inside
a `TabView` by `QueryResultsView.tabLayout` on iPad (regular size class). The `TabView`
gives each child an isolated, properly-filled layout context so `.frame(maxWidth: .infinity,
maxHeight: .infinity)` actually fills the tab — the `ScrollView` + `LazyVStack` expand to fill.

### Why the macOS observer table works

`ObserverEventsTableView.macOSTable` uses:
```swift
GeometryReader { geometry in
    ScrollView([.horizontal, .vertical]) {
        LazyVStack(...) { ... }
            .frame(minHeight: geometry.size.height, alignment: .top)  // ← the key line
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
```

The `GeometryReader` measures the allocated frame (50% of the outer GR height from
`observeDetailView()`). `.frame(minHeight: geometry.size.height, alignment: .top)` forces
the `LazyVStack` to be at least that tall, so data rows start immediately at the top and
the `ScrollView` fills the full pane.

### The fix

Add the same `GeometryReader` + `.frame(minHeight:, alignment: .top)` to `iOSTable`,
mirroring the macOS implementation exactly.

---

## File to Change

`SwiftUI/Edge Debug Helper/Components/ObserverEventsTableView.swift`

---

## Change — Add GeometryReader to iOS table

Replace the current `iOSTable` body (the plain `ScrollView`) with a `GeometryReader`
wrapper that mirrors the macOS version, using iOS colors.

```swift
// BEFORE
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
                            .lineLimit(1)
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

// AFTER
#if os(iOS)
private var iOSTable: some View {
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
                                .lineLimit(1)
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
            .frame(minHeight: geometry.size.height, alignment: .top)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
#endif
```

**What changed:** Added `GeometryReader { geometry in ... }` wrapper around the `ScrollView`,
and added `.frame(minHeight: geometry.size.height, alignment: .top)` on the `LazyVStack`.
All row/header content is unchanged.

---

## Why This Works

`observeDetailView()` allocates `.frame(height: geometry.size.height * 0.5)` to the top pane.
The new inner `GeometryReader` measures that allocated height. The `LazyVStack` is then forced
to be at least that tall, so:
1. The first row (or column header) appears immediately at the top of the pane.
2. The `ScrollView` fills the full allocated height rather than collapsing to content size.

This is identical to how the macOS observer table and the macOS query results table work.
The pattern is safe to nest with the outer `GeometryReader` in `observeDetailView()` — the
macOS observer table already nests these without issues.

---

## Files to Change

| File | Change |
|------|--------|
| `Components/ObserverEventsTableView.swift` | Wrap `iOSTable` ScrollView in `GeometryReader`; add `.frame(minHeight:, alignment: .top)` to `LazyVStack` |

No changes to `DetailViews.swift` or any other file.

---

## Verification

1. Build for iOS: `xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build`
2. Build for macOS: `xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build`
3. On iPad simulator: open a database → Observers → activate an observer with events
4. Verify top pane:
   - Column header (Time, Count, Inserted, …) is **immediately** at the top with no gap ✅
   - Table fills the full 50% top pane height ✅
   - Column headers are on one line (no wrapping) ✅
   - Data rows are alternating background colors ✅
   - Selecting a row highlights it ✅
5. Verify bottom pane still works correctly (no regression) ✅
6. On macOS: verify no change to appearance ✅
