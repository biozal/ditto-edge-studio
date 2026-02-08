# NavigationSplitView + Inspector Constraint Loop Fix - Verification Guide

## Status: ✅ FIX APPLIED - PENDING MANUAL VALIDATION

**Date:** 2026-02-07
**Issue:** Sidebar disappears when opening inspector while viewing Collections (with VSplitView)
**Root Cause:** Rigid minimum width constraints causing constraint loop crashes
**Solution:** Remove rigid constraints, use flexible frame modifiers only on containers

---

## Research Summary

### POC Files Created and Validated

1. **NavigationSplitViewInspectorTest.swift** (465 lines)
   - Tests 3-pane layout without VSplitView
   - Validates inspector interaction patterns
   - Shows correct use of columnVisibility binding

2. **NavigationSplitViewWithVSplitViewPOC.swift** (692 lines) ⭐ **PRIMARY POC**
   - Demonstrates EXACT pattern needed for MainStudioView
   - Includes VSplitView with resizable divider
   - Comprehensive testing checklist (lines 462-691)
   - **KEY FINDING:** VSplitView children must NOT have `.frame(maxWidth: .infinity)` modifiers

### The Critical Pattern Difference

#### ❌ BROKEN PATTERN (What Was Causing Crashes)
```swift
VSplitView {
    QueryEditorView(...)
        .frame(maxWidth: .infinity)    // ❌ Creates rigid constraint conflict

    QueryResultsView(...)
        .frame(maxWidth: .infinity)    // ❌ Creates rigid constraint conflict
}
```

**Problem:** Each VSplitView child demands infinite width, but NavigationSplitView needs to allocate space for sidebar + detail + inspector. When constraints can't be satisfied, sidebar is hidden as a "compromise."

#### ✅ WORKING PATTERN (Applied to MainStudioView)
```swift
VStack(alignment: .leading, spacing: 0) {
    VSplitView {
        QueryEditorView(...)
            // ✅ No frame modifiers

        QueryResultsView(...)
            // ✅ No frame modifiers
    }
    // ✅ VSplitView has no frame modifiers
}
.frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ Only on container
```

**Solution:** Only the detail view CONTAINER has flexible frame modifiers. VSplitView and its children inherit their sizing from the container, creating a clean constraint chain.

---

## Fix Applied to MainStudioView.swift

### Changes Made

**File:** `SwiftUI/Edge Debug Helper/Views/MainStudioView.swift`

#### Change 1: Removed Rigid Detail View Constraints (Lines 154-164)
```swift
// BEFORE (Crashed):
} detail: {
    switch viewModel.selectedMenuItem.name {
    case "Collections":
        queryDetailView()
            .frame(minWidth: 400)  // ❌ REMOVED
    // ... other cases with .frame(minWidth: 400) removed
    }
}

// AFTER (Fixed):
} detail: {
    switch viewModel.selectedMenuItem.name {
    case "Collections":
        queryDetailView()  // ✅ No rigid constraints
    case "Observer":
        observeDetailView()
    case "Ditto Tools":
        dittoToolsDetailView()
    default:
        syncTabsDetailView()
    }
}
```

#### Change 2: Ensured Container Has Flexible Frame (Lines 1069-1116)
```swift
func queryDetailView() -> some View {
    return VStack(alignment: .leading) {
        VSplitView {
            QueryEditorView(...)  // ✅ No .frame(maxWidth: .infinity)
            QueryResultsView(...) // ✅ No .frame(maxWidth: .infinity)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ Only on container
    .padding(.bottom, 28)
}
```

---

## Manual Verification Checklist

### Test Scenario 1: Basic Inspector Toggle
1. ☐ Select "Collections" in sidebar
2. ☐ Verify VSplitView shows query editor (top) and results (bottom)
3. ☐ Drag the VSplitView horizontal divider - should resize smoothly
4. ☐ Click inspector toggle button (top-right toolbar)
5. ☐ **CRITICAL:** Verify sidebar REMAINS VISIBLE on left side
6. ☐ **CRITICAL:** Verify VSplitView divider still draggable
7. ☐ Inspector opens on right side
8. ☐ All three panes visible: Sidebar | VSplitView | Inspector
9. ☐ No console errors (check Xcode console)

### Test Scenario 2: Inspector Query Click (Critical Use Case)
1. ☐ Start with "Subscriptions" selected in sidebar
2. ☐ Open inspector
3. ☐ Click "History" tab in inspector
4. ☐ Click any query in the history list
5. ☐ **CRITICAL:** Sidebar auto-switches to Collections AND remains visible
6. ☐ **CRITICAL:** Detail view changes to show Collections VSplitView
7. ☐ **CRITICAL:** Inspector remains visible and functional
8. ☐ Query loads into editor
9. ☐ No layout breaks

### Test Scenario 3: Console Verification
1. ☐ Open Xcode console (⌘⇧Y)
2. ☐ Perform above scenarios
3. ☐ **CRITICAL:** NO "Update Constraints in Window pass" errors
4. ☐ NO Auto Layout warnings
5. ☐ Clean console output

---

## Expected Behavior

### Before Fix (Broken)
- ❌ Opening inspector while viewing Collections caused sidebar to disappear
- ❌ Clicking query in inspector crashed app or broke layout
- ❌ Console showed constraint loop errors

### After Fix (Expected)
- ✅ Opening inspector keeps sidebar visible
- ✅ Clicking query in inspector smoothly switches views
- ✅ Console clean, no errors
- ✅ Three-pane layout stable

---

## Reference Files

- **Primary POC:** `SwiftUI/POC/NavigationSplitViewWithVSplitViewPOC.swift` (lines 145-219, 462-691)
- **Fix Documentation:** `SwiftUI/POC/VSPLITVIEW_INSPECTOR_FIX.md`
- **Screenshot Test:** `SwiftUI/Edge Debugg Helper UITests/Ditto_Edge_StudioUITests.swift` (lines 262-374)
