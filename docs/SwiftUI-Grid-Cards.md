# SwiftUI Grid Cards — Layout Reference

Reference for card-grid layouts used in Edge Studio. Covers `GridItem` strategies, when to use each approach, and project-specific conventions.

---

## `GridItem(.adaptive(minimum:maximum:))`

The recommended approach for card grids in this app. SwiftUI calculates the number of columns automatically based on available width — no `GeometryReader`, no breakpoints, no `@State`.

### How the column-count algorithm works

Given `minimum: M`, `maximum: X`, and available width `W`:
1. Maximum columns = `floor(W / M)`
2. Each column gets `(W - totalSpacing) / columns` width
3. If a column's computed width exceeds `maximum`, SwiftUI adds another column

### Code example

```swift
LazyVGrid(
    columns: [GridItem(.adaptive(minimum: 300, maximum: 520))],
    spacing: 16
) {
    ForEach(items) { item in
        MyCard(item: item)
    }
}
.padding(.horizontal)
```

### Column counts at `minimum: 300`

| Device / Context                  | Available width | Columns |
|-----------------------------------|-----------------|---------|
| iPhone SE (320pt)                 | ~288pt          | 1       |
| iPhone 15 (393pt)                 | ~361pt          | 1       |
| iPad mini portrait (744pt)        | ~712pt          | 2       |
| iPad mini landscape (1024pt)      | ~992pt          | 3       |
| iPad Pro 12.9" portrait (1024pt)  | ~992pt          | 3       |
| Mac detail pane (~900pt)          | ~868pt          | 2–3     |

Columns reflow automatically on rotation and Split View resizes.

### When to add `maximum`

Use `maximum` to cap how wide cards grow on very large screens. Without it, a single card in a wide Mac window would stretch to fill the whole pane.

```swift
// Peer / database cards — cap at 520pt so they don't become unreadable
columns: [GridItem(.adaptive(minimum: 300, maximum: 520))]

// Database listing on iOS — let cards fill the column naturally
columns: [GridItem(.adaptive(minimum: 300))]
```

---

## `GridItem(.flexible())`

Produces exactly N equally-wide columns regardless of available width. Useful when you always want a fixed count.

```swift
// Always 2 columns — does NOT adapt to narrow screens
columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
```

**Avoid for card grids.** On iPhone (393pt) with 2 flexible columns, each column is ~172pt — too narrow for cards with rich content. Use `.adaptive` instead.

---

## Other Layout APIs — Quick Reference

| API | Use when |
|-----|----------|
| `Grid` | Small static grids where you control every row/cell explicitly |
| `ViewThatFits` | Pick between horizontal and vertical layouts based on space |
| `AnyLayout` | Switch between layout strategies at runtime with animation |
| `.containerRelativeFrame` | Size a child relative to its scroll container |
| `GeometryReader` | **Last resort only.** Breaks layout composability and triggers re-renders. Use `.adaptive` or `.containerRelativeFrame` instead. |

---

## Decision Matrix

| Scenario | Recommended API |
|----------|----------------|
| Cards that should adapt to screen width | `GridItem(.adaptive(minimum:maximum:))` |
| Always 2 columns on all screen sizes | `GridItem(.flexible())` with count: 2 |
| Horizontal stack that wraps | `ViewThatFits` + nested `HStack`/`VStack` |
| Read parent width for non-layout logic | `.containerRelativeFrame` or environment values |
| Legacy manual column-count calculation | Replace with `.adaptive` |

---

## Project-Specific Guidance

### Minimum widths in this codebase

| View | `minimum` | `maximum` | Notes |
|------|-----------|-----------|-------|
| `ConnectedPeersView` peer grid | 460 | 520 | Max 2 cols on iPad Pro; 1 col on iPhone/iPad mini |
| `ConnectedPeersView` network interface grid | 460 | 520 | Same grid, same constraint |
| `ContentView` database listing (iOS) | 300 | — | Cards expand to fill column naturally |

### Which views use which API

- **`ConnectedPeersView`** — `GridItem(.adaptive(minimum: 460, maximum: 520))` for both peer and network-interface grids
- **`ContentView` (iOS)** — `GridItem(.adaptive(minimum: 300))` inside `ScrollView` + `LazyVGrid`
- **`DatabaseListPanel` (macOS)** — single-column `List` in a 340pt-wide panel; grid is unnecessary

### `GeometryReader` anti-pattern

The original `ConnectedPeersView` used:

```swift
// BEFORE — do not use
@State private var columnCount = 2
GeometryReader { geometry in
    LazyVGrid(columns: Array(repeating: .flexible(), count: columnCount)) { ... }
        .onChange(of: geometry.size.width) { _, w in updateColumnCount(for: w) }
}

private func updateColumnCount(for width: CGFloat) {
    columnCount = width < 900 ? 2 : 3
}
```

Problems:
- Always returns 2 columns on iPhone (393pt < 900pt) → cards ~172pt wide
- Extra `@State` + `onChange` re-renders on every resize
- `GeometryReader` expands to fill all available space, breaking layout composability
- Hardcoded breakpoint doesn't account for padding or orientation

**Replacement:**

```swift
// AFTER — adaptive, no GeometryReader
LazyVGrid(
    columns: [GridItem(.adaptive(minimum: 300, maximum: 520))],
    spacing: 16
) { ... }
```

SwiftUI handles all breakpoints, orientations, and Split View widths automatically.
