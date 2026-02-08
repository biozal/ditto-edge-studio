# Quick Reference: NavigationSplitView + Inspector + VSplitView

## The Problem

When using VSplitView inside NavigationSplitView's detail view with an Inspector, the sidebar disappears when the inspector opens.

## The Solution

Remove `.frame(maxWidth: .infinity)` from VSplitView children and only apply it to the detail view container.

## Code Pattern

### ❌ WRONG (Causes sidebar to disappear)

```swift
NavigationSplitView {
    // Sidebar
    sidebarView()
} detail: {
    VStack {
        VSplitView {
            TopView()
                .frame(maxWidth: .infinity)    // ❌ BAD

            BottomView()
                .frame(maxWidth: .infinity)    // ❌ BAD
        }
    }
}
.inspector(isPresented: $showInspector) {
    inspectorView()
}
```

### ✅ CORRECT (All panes work together)

```swift
NavigationSplitView {
    // Sidebar
    sidebarView()
        .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 300)
} detail: {
    VStack {
        VSplitView {
            TopView()
                // ✅ No frame modifier

            BottomView()
                // ✅ No frame modifier
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ Only on container
}
.inspector(isPresented: $showInspector) {
    inspectorView()
        .inspectorColumnWidth(min: 250, ideal: 350, max: 500)
}
```

## Rule of Thumb

**Only the outermost container in the detail view should have `.frame(maxWidth: .infinity, maxHeight: .infinity)`**

**Never apply `.frame(maxWidth: .infinity)` to:**
- Individual VSplitView children
- Individual HSplitView children
- Views directly inside split views

**The container's frame modifier cascades flexibility down the view hierarchy naturally.**

## Testing Checklist

After making changes, verify:
- [ ] Sidebar visible when inspector is open
- [ ] VSplitView divider can be dragged
- [ ] Inspector can toggle without breaking layout
- [ ] No console errors
- [ ] Works at 800px - 1400px window width

## Files

- **Working POC**: `SwiftUI/POC/NavigationSplitViewWithVSplitViewPOC.swift`
- **Detailed Fix**: `SwiftUI/POC/VSPLITVIEW_INSPECTOR_FIX.md`
- **Visual Comparison**: `SwiftUI/POC/LAYOUT_COMPARISON.md`
- **This Reference**: `SwiftUI/POC/QUICK_REFERENCE.md`

## Fix for MainStudioView

In `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Views/MainStudioView.swift`:

**Lines 1081 and 1091**: Remove `.frame(maxWidth: .infinity)`

**Line 1116**: Add `.frame(maxWidth: .infinity, maxHeight: .infinity)` before `.padding(.bottom, 28)`

Done.
