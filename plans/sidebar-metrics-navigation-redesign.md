# Plan: Sidebar Metrics Navigation Redesign

**Date:** 2026-02-22
**Status:** Draft — awaiting approval
**Screenshot ref:** `screens/ipad-navigation.png`

---

## Problem

1. **Icons/fonts are too large** in the top navigation section of the unified sidebar. On iPadOS, `listStyle(.sidebar)` defaults to `.body` font (17pt), which renders the `Label` icons and text bigger than desired.

2. **Metrics navigation is clunky.** A single "Metrics" item in the top nav opens a sub-view, and then sub-items ("App" / "Query") inside the METRICS sidebar section switch _within_ that view. This two-level indirection is confusing — especially on iOS where the "App" sub-item was hidden entirely.

---

## Goal

- Remove "Metrics" from the top navigation row.
- Add two first-class navigation items **inside the METRICS sidebar section**: **"App Metrics"** and **"Query Metrics"**, each with its own icon, tapping directly to their respective detail views.
- Fix the font/icon size of the top navigation items.

---

## Current Architecture (relevant pieces)

| Location | Role |
|---|---|
| `MainStudioView.swift: buildSidebarItems()` (line 618) | Builds the 4 top-nav `MenuItem` objects |
| `MainStudioView.swift: detail switch` (line 150) | Routes `selectedSidebarMenuItem.name` → detail view |
| `SidebarViews.swift: unifiedSidebarView()` | Renders top nav `Section` + content sections |
| `SidebarViews.swift: metricsRows()` | Renders "App" / "Query" sub-items in the METRICS section |
| `MetricsViews.swift: metricsDetailView()` | Dispatches sub-view based on `selectedMetricsSubItem` string |
| `ViewModel.selectedMetricsSubItem` | Tracks which metrics sub-view is active |

---

## Proposed Changes

### 1. Fix font size — `SidebarViews.swift`

In the top navigation `Section` ForEach, the `Label` currently inherits the default `.body` font from the list. Add an explicit `.font(.subheadline)` to tighten up both the icon and text:

```swift
// BEFORE
Label(item.name, systemImage: item.systemIcon)

// AFTER
Label(item.name, systemImage: item.systemIcon)
    .font(.subheadline)
```

### 2. Remove "Metrics" from top nav — `MainStudioView.swift`

In `buildSidebarItems()`, remove the `Metrics` item entirely. The top nav will have exactly 3 items regardless of `metricsEnabled`:

```swift
// BEFORE
var items: [MenuItem] = [
    MenuItem(id: 1, name: "Subscriptions", systemIcon: "arrow.trianglehead.2.clockwise.rotate.90"),
    MenuItem(id: 2, name: "Query",         systemIcon: "macpro.gen2"),
    MenuItem(id: 3, name: "Observers",     systemIcon: "eye")
]
if metricsEnabled {
    items.append(MenuItem(id: 4, name: "Metrics", systemIcon: "chart.line.uptrend.xyaxis"))
}

// AFTER
let items: [MenuItem] = [
    MenuItem(id: 1, name: "Subscriptions", systemIcon: "arrow.trianglehead.2.clockwise.rotate.90"),
    MenuItem(id: 2, name: "Query",         systemIcon: "macpro.gen2"),
    MenuItem(id: 3, name: "Observers",     systemIcon: "eye")
]
// Metrics items are no longer top-nav items; they live in the METRICS sidebar section
```

### 3. Replace `metricsRows()` with two first-class nav items — `SidebarViews.swift`

Remove the `metricsRows()` helper entirely. Replace the METRICS section body with two buttons that set `selectedSidebarMenuItem` directly, styled identically to the top nav items (including highlight state and `.font(.subheadline)`):

```swift
// Hard-coded metric MenuItems — defined as private let constants in the section
private static let appMetricsItem  = MenuItem(id: 4, name: "App Metrics",   systemIcon: "cpu")
private static let queryMetricsItem = MenuItem(id: 5, name: "Query Metrics", systemIcon: "text.magnifyingglass")
```

METRICS section body becomes:

```swift
Section {
    // App Metrics — both platforms (AppMetricsDetailView shows process section macOS-only)
    Button {
        viewModel.selectedSidebarMenuItem = Self.appMetricsItem
    } label: {
        Label("App Metrics", systemImage: "cpu")
            .font(.subheadline)
    }
    .buttonStyle(.plain)
    .listRowBackground(
        viewModel.selectedSidebarMenuItem == Self.appMetricsItem
            ? Color.accentColor.opacity(0.18)
            : Color.clear
    )

    // Query Metrics — both platforms
    Button {
        viewModel.selectedSidebarMenuItem = Self.queryMetricsItem
    } label: {
        Label("Query Metrics", systemImage: "text.magnifyingglass")
            .font(.subheadline)
    }
    .buttonStyle(.plain)
    .listRowBackground(
        viewModel.selectedSidebarMenuItem == Self.queryMetricsItem
            ? Color.accentColor.opacity(0.18)
            : Color.clear
    )
} header: {
    Text("METRICS")
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
}
```

### 4. Update detail view routing — `MainStudioView.swift`

Replace the `case "Metrics": metricsDetailView()` in the detail switch with direct cases for each metrics item:

```swift
// BEFORE
case "Metrics":
    metricsDetailView()

// AFTER
case "App Metrics":
    AppMetricsDetailView()
case "Query Metrics":
    QueryMetricsDetailView()
```

### 5. Fix the `metricsEnabled` guard — `MainStudioView.swift`

Update the `onChange(of: metricsEnabled)` handler to reset selection when either metrics item is active and metrics get disabled:

```swift
// BEFORE
if !enabled, viewModel.selectedSidebarMenuItem.name == "Metrics" {
    viewModel.selectedSidebarMenuItem = viewModel.sidebarMenuItems[0]
}

// AFTER
if !enabled,
   viewModel.selectedSidebarMenuItem.name == "App Metrics" ||
   viewModel.selectedSidebarMenuItem.name == "Query Metrics" {
    viewModel.selectedSidebarMenuItem = viewModel.sidebarMenuItems[0]
}
```

### 6. Remove dead ViewModel state — `MainStudioView.swift`

The following ViewModel properties are no longer needed once the old sub-item routing is gone:

```swift
// REMOVE:
var selectedMetricsSubItem = "App"
let metricsSubItems: [String] = ["App", "Query"]
```

### 7. Remove `metricsDetailView()` — `MetricsViews.swift`

The entire `MetricsViews.swift` file / `metricsDetailView()` extension becomes dead code. Delete the file (or the function) since routing is now handled directly in the detail switch.

---

## Icon Choices for New Items

| Item | SF Symbol | Rationale |
|---|---|---|
| App Metrics | `cpu` | System/process-level metrics (CPU, memory) |
| Query Metrics | `text.magnifyingglass` | Query explain / search metrics |

Alternative icons to consider:
- App Metrics: `gauge.medium`, `chart.bar`, `bolt.circle`
- Query Metrics: `list.bullet.clipboard`, `tablecells`, `magnifyingglass.circle`

---

## What Stays the Same

- The METRICS section header ("METRICS") stays as a `Section` header
- `metricsEnabled` AppStorage still gates the entire METRICS section
- `AppMetricsDetailView` and `QueryMetricsDetailView` are unchanged
- Both platforms (macOS + iOS/iPad) get both "App Metrics" and "Query Metrics" items
  - `AppMetricsDetailView` already conditionally shows process stats on macOS only; the iOS version shows the query-latency summary section only — this is fine

---

## Files Touched

| File | Change Type |
|---|---|
| `Views/StudioView/SidebarViews.swift` | Font fix + replace `metricsRows()` with two nav items |
| `Views/MainStudioView.swift` | Remove "Metrics" from `buildSidebarItems()`, update detail switch, fix `onChange`, remove dead ViewModel state |
| `Views/StudioView/MetricsViews.swift` | **Delete** (dead code after routing moves inline) |

---

## Build Requirements

After implementation, build for both platforms per CLAUDE.md:

```bash
# macOS
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
           -configuration Debug -destination "platform=macOS,arch=arm64" build

# iPadOS
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
           -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build
```
