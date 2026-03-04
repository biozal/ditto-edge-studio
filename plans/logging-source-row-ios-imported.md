# Plan: Hide "Imported" Source Tab on iOS

**File**: `SwiftUI/Edge Debug Helper/Views/Logging/LoggingDetailView.swift`

---

## Problem

`sourceRow` iterates `SourceTab.allCases` which includes `.imported`. On iOS the
"Import External Logs…" button already lives inside a `#if os(macOS)` block in
`footerRow`, so the tab would select a source that can never be populated. The
Imported option must not render at all on iOS.

---

## What Needs to Change (one file, three touch-points)

### 1 — Add `visibleSourceTabs` computed property

Placed just above `sourceRow`, after the existing `maxDisplayedEntries` constant:

```swift
/// Source tabs visible in the current platform.
/// The Imported tab is macOS-only because log file import uses a macOS file picker.
private var visibleSourceTabs: [SourceTab] {
    #if os(macOS)
    return SourceTab.allCases
    #else
    return [.dittoSDK, .application]
    #endif
}
```

### 2 — Update `sourceRow` to use `visibleSourceTabs`

Two changes inside `sourceRow`:

**a)** Change `ForEach(SourceTab.allCases, ...)` → `ForEach(visibleSourceTabs, ...)`

**b)** Fix the divider guard to use `visibleSourceTabs.last` instead of
`SourceTab.allCases.last`, so no trailing divider appears after "App Logs" on iOS:

```swift
// Before
if tab != SourceTab.allCases.last {

// After
if tab != visibleSourceTabs.last {
```

### 3 — Wrap the imported-label / clear-button section in `#if os(macOS)`

The inline label+clear-button that shows the imported filename is only reachable
when the Imported tab is active. Guard it so it doesn't compile dead code on iOS:

```swift
#if os(macOS)
if !capture.importedLabel.isEmpty {
    Text("[\(capture.importedLabel)]") ...
    Button { capture.clearImported() } label: { ... }
}
#endif
```

---

## What Does NOT Change

- `SourceTab` enum keeps all three cases — the switch statements in
  `activeSourceEntries`, `filterRow`, and `footerRow` remain exhaustive.
- `filterRow` already guards the Component picker behind
  `selectedSource == .dittoSDK || selectedSource == .imported` — this can't
  trigger on iOS because `.imported` is never selectable.
- `footerRow` import button is already inside `#if os(macOS)`.
- No new files, no model changes, no test changes required.

---

## Build Verification

Both platforms must pass after the change:

```bash
# macOS
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
  -configuration Debug -destination "platform=macOS,arch=arm64" build

# iOS
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" \
  -configuration Debug -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" build
```
