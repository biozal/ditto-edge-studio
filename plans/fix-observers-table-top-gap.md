# Fix: Observer Events Table Top Gap

## Status
APPROVED — ready to implement

## Problem
The observer events table (`observableEventsTable()`) has a ~100pt blank gap between
the pagination bar and the table header/rows.

## Root Cause (Confirmed by Code Research)

### The Smoking Gun

| Detail view | `.navigationTitle()` on content? | Has raw `ScrollView`? | Gap? |
|---|---|---|---|
| `queryDetailView()` | ❌ none | ✅ yes (inside TabView) | no gap |
| `AppMetricsDetailView` | ❌ none | ✅ yes (plain ScrollView, line 18) | **no gap** |
| `QueryMetricsDetailView` | ❌ none | ✅ yes (List + ScrollView, line 121) | **no gap** |
| `syncTabsDetailView()` | ❌ none | ✅ yes (List) | no gap |
| `observeDetailView()` | ✅ `.navigationTitle("Observer Events")` | ✅ yes | **100pt GAP** |

`AppMetricsDetailView` uses a **plain, unwrapped `ScrollView`** with no `.ignoresSafeArea`,
no `TabView` wrapper — and **no gap**. This single fact disproves the safe-area-content-inset
theory that was previously pursued.

### The Actual Cause

On macOS 26 with `.navigationSplitViewStyle(.prominentDetail)` and Liquid Glass, setting
`.navigationTitle()` on the **detail view content** (rather than on the `NavigationSplitView`
itself) triggers an **in-content large title section**. SwiftUI injects this transparent
(glass-effect) section at the top of the first `ScrollView` in the subtree. It takes ~100pt
of space and looks exactly like a blank gap.

The pagination bar (`HStack`) is ABOVE the `ScrollView` in the VStack, so it is unaffected.
Only the `ScrollView` inside `observableEventsTable()` gets the injection.

### Why ALL Other Detail Views Work

Every other detail view (`queryDetailView`, `AppMetricsDetailView`, `QueryMetricsDetailView`,
`syncTabsDetailView`) does NOT set `.navigationTitle()` on its content. They inherit the
NavigationSplitView-level `.navigationTitle(viewModel.selectedApp.name)`. No injection
occurs, so their `ScrollView`s render without a gap.

## Why Previous Fixes Failed

1. **`alignment: .top` on frames**: Irrelevant — the gap is injected SwiftUI content
   inside the ScrollView, unreachable by frame alignment.

2. **Moving `.navigationTitle("Observer Events")`**: Moved within the same detail view
   subtree, so macOS 26 still found a `.navigationTitle` and still injected the large title.

3. **`.contentMargins(.top, 0, for: .scrollContent)`**: Adjusts explicit padding markers.
   The injected large title is a SwiftUI subview, not a margin — unaffected.

4. **`.ignoresSafeArea(.container, edges: .top)` on the ScrollView**: Removes safe-area
   content insets on the underlying scroll view. The gap is NOT a content inset — it is
   an injected SwiftUI view. `.ignoresSafeArea` has zero effect on it.

## Fix

**File:** `SwiftUI/Edge Debug Helper/Views/StudioView/Details/DetailViews.swift`

### Change 1 — Remove `.navigationTitle()` from macOS (line ~653)

Wrap the existing `.navigationTitle("Observer Events")` in `#if os(iOS)` so macOS
no longer triggers the large title injection. iOS keeps the title for its navigation stack.

```swift
// BEFORE
.navigationTitle("Observer Events")
#if os(iOS)
    .navigationBarTitleDisplayMode(.inline)
    ...
#endif

// AFTER
#if os(iOS)
    .navigationTitle("Observer Events")
    .navigationBarTitleDisplayMode(.inline)
    ...
#endif
```

### Change 2 — Remove `.ignoresSafeArea(.container, edges: .top)` from `observableEventsTable()`

This modifier was added based on the now-disproved safe-area theory. It has no effect
and should be removed to leave the code clean.

```swift
// BEFORE
ScrollView([.horizontal, .vertical]) {
    LazyVStack(...) { ... }
}
.ignoresSafeArea(.container, edges: .top)

// AFTER
ScrollView([.horizontal, .vertical]) {
    LazyVStack(...) { ... }
}
```

## Verification
1. Build macOS + iOS
2. Open Observers tab → table header should appear immediately below the pagination
   bar divider with zero gap
3. Verify query tab still works (not affected by this change)
4. Verify iOS/iPad layout is still correct
5. Verify AppMetrics and QueryMetrics views still render correctly (sanity check)
