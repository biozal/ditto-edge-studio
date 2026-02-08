# POC Directory: NavigationSplitView + Inspector + VSplitView

## Overview

This directory contains proof-of-concept implementations demonstrating proper layout patterns for SwiftUI's NavigationSplitView with Inspector and VSplitView.

## Latest POC: VSplitView + Inspector Fix

**NavigationSplitViewWithVSplitViewPOC.swift** (691 lines) - **MOST IMPORTANT**

This POC solves the critical layout issue where the Sidebar disappears when Inspector opens in MainStudioView.

**Problem**: VSplitView children with `.frame(maxWidth: .infinity)` create constraint conflicts
**Solution**: Only apply `.frame(maxWidth: .infinity, maxHeight: .infinity)` to the detail view container

**Documentation**:
- `VSPLITVIEW_INSPECTOR_FIX.md` - Detailed fix instructions for MainStudioView
- `LAYOUT_COMPARISON.md` - Visual comparison of broken vs. working patterns
- `QUICK_REFERENCE.md` - One-page quick reference guide

## Other POCs

### NavigationSplitViewInspectorTest.swift
Earlier POC demonstrating NavigationSplitView + Inspector (without VSplitView). Validates the basic pattern of view switching triggered from inspector clicks.

### ThreePaneLayoutPOC.swift
Original exploration of three-pane layout using `.inspector()` modifier.

## The Solution (TL;DR)

### Problem
In MainStudioView, when Inspector opens, the Sidebar disappears. This is caused by `.frame(maxWidth: .infinity)` on VSplitView children creating rigid constraints that conflict with Inspector width requirements.

### Solution
Remove `.frame(maxWidth: .infinity)` from VSplitView children and only apply `.frame(maxWidth: .infinity, maxHeight: .infinity)` to the detail view container.

**Before (Broken)**:
```swift
VSplitView {
    QueryEditorView(...).frame(maxWidth: .infinity)    // ❌ Remove
    QueryResultsView(...).frame(maxWidth: .infinity)   // ❌ Remove
}
```

**After (Fixed)**:
```swift
VStack {
    VSplitView {
        QueryEditorView(...)  // ✅ No frame modifier
        QueryResultsView(...) // ✅ No frame modifier
    }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ Only on container
```

## How to Use This POC

### Step 1: Test the Working POC
1. Open `NavigationSplitViewWithVSplitViewPOC.swift` in Xcode
2. Run in Preview or simulator
3. Test all functionality:
   - Click sidebar items
   - Toggle inspector open/closed
   - Drag VSplitView divider
   - Click queries in inspector
   - Resize window from 800px to 1400px
4. Verify all three panes work together ✅

### Step 2: Review Documentation
1. Read `LAYOUT_COMPARISON.md` - Visual diagrams showing why it breaks and how to fix it
2. Read `VSPLITVIEW_INSPECTOR_FIX.md` - Step-by-step fix instructions
3. Keep `QUICK_REFERENCE.md` handy for future reference

### Step 3: Apply the Fix to MainStudioView
1. Open `SwiftUI/Edge Debug Helper/Views/MainStudioView.swift`
2. Find `queryDetailView()` function (lines 1069-1116)
3. Remove `.frame(maxWidth: .infinity)` from lines 1081 and 1091
4. Add `.frame(maxWidth: .infinity, maxHeight: .infinity)` at line 1116 (before `.padding(.bottom, 28)`)
5. Build and test

### Step 4: Verify the Fix
1. Run the app
2. Select Collections in sidebar
3. Toggle inspector open/closed
4. Verify sidebar STAYS VISIBLE ✅
5. Run tests: `cd SwiftUI && ./run_ui_tests.sh`

## Success Criteria

The fix works when:
- [ ] Sidebar remains visible when inspector is open
- [ ] VSplitView divider can be dragged to resize panes
- [ ] Inspector can toggle without breaking layout
- [ ] No constraint loop errors in console
- [ ] Layout works at window widths 800px - 1400px
- [ ] All UI tests pass

## Key Principle

**Only the outermost container in the detail view should have `.frame(maxWidth: .infinity, maxHeight: .infinity)`**

Never apply `.frame(maxWidth: .infinity)` to individual children inside split views. The container's frame modifier cascades flexibility down the view hierarchy naturally.

## Files in This Directory

- `NavigationSplitViewWithVSplitViewPOC.swift` - **Complete working POC** (691 lines)
- `VSPLITVIEW_INSPECTOR_FIX.md` - **Detailed fix instructions**
- `LAYOUT_COMPARISON.md` - **Visual diagrams and analysis**
- `QUICK_REFERENCE.md` - **One-page quick reference**
- `NavigationSplitViewInspectorTest.swift` - Earlier POC without VSplitView
- `ThreePaneLayoutPOC.swift` - Original layout exploration
- `README.md` - This file

## References

- **Issue Screenshot**: `/Users/labeaaa/Developer/ditto-edge-studio/screens/edge-studio-broke.png`
- **MainStudioView**: `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Views/MainStudioView.swift`
