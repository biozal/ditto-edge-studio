# VSplitView + Inspector Layout Fix

## Problem Summary

**Issue**: In MainStudioView, when the Inspector opens, the Sidebar disappears and only the VSplitView (query editor + results) remains visible.

**Root Cause**: The VSplitView children have `.frame(maxWidth: .infinity)` modifiers (lines 1081, 1091 in MainStudioView.swift), which create rigid width constraints that conflict with the Inspector's width requirements. When NavigationSplitView can't satisfy all constraints, it hides the Sidebar as a "compromise."

**Screenshot**: See `/Users/labeaaa/Developer/ditto-edge-studio/screens/edge-studio-broke.png`

## Solution

Remove `.frame(maxWidth: .infinity)` from VSplitView children and only apply `.frame(maxWidth: .infinity, maxHeight: .infinity)` to the detail view container.

### Working POC

A complete working proof-of-concept has been created:
```
/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/POC/NavigationSplitViewWithVSplitViewPOC.swift
```

This POC demonstrates:
- ✅ NavigationSplitView with Sidebar + Detail + Inspector
- ✅ VSplitView in the detail view with resizable divider
- ✅ All three panes work together without breaking
- ✅ Inspector can open/close without hiding sidebar
- ✅ VSplitView divider remains draggable
- ✅ No constraint loop errors

### How to Test the POC

1. Open the project in Xcode
2. Open `NavigationSplitViewWithVSplitViewPOC.swift`
3. Click the "Preview" button or run in simulator
4. Verify all success criteria:
   - Sidebar visible with 4 menu items
   - Click "Collections" to see VSplitView
   - Drag the horizontal divider between editor/results
   - Click inspector toggle button (top-right)
   - Verify sidebar REMAINS VISIBLE when inspector opens
   - Click queries in inspector History/Favorites tabs
   - Verify sidebar auto-switches to Collections but stays visible
   - Resize window from 800px to 1400px
   - Verify no console errors

## The Critical Pattern

### ❌ BROKEN PATTERN (Current MainStudioView.swift)

```swift
func queryDetailView() -> some View {
    return VStack(alignment: .leading) {
        VSplitView {
            QueryEditorView(...)
                .frame(maxWidth: .infinity)    // ❌ Creates rigid constraint

            QueryResultsView(...)
                .frame(maxWidth: .infinity)    // ❌ Creates rigid constraint
        }
    }
    .padding(.bottom, 28)
}
```

**Why this breaks:**
- Each VSplitView child demands infinite width
- NavigationSplitView sees: "Detail needs infinite width + Inspector needs 250-500px"
- NavigationSplitView's solution: Hide sidebar to free up space
- Result: Sidebar disappears when inspector opens

### ✅ WORKING PATTERN (POC)

```swift
func queryDetailView() -> some View {
    return VStack(alignment: .leading, spacing: 0) {
        VSplitView {
            QueryEditorView(...)
                // ✅ No .frame(maxWidth: .infinity)

            QueryResultsView(...)
                // ✅ No .frame(maxWidth: .infinity)
        }
        // ✅ VSplitView has no frame modifiers
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ Only on container
    .padding(.bottom, 28)
}
```

**Why this works:**
- Container has `.frame(maxWidth: .infinity)` = "use available space"
- VSplitView has NO width constraints = "fit in parent's space"
- VSplitView children have NO width constraints = "fit in VSplitView's space"
- Result: Clean constraint chain, no conflicts, all panes visible

## Fix Instructions for MainStudioView.swift

### Step 1: Fix queryDetailView() function

**Location**: Lines 1069-1116 in `/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI/Edge Debug Helper/Views/MainStudioView.swift`

**Change**:
```swift
// BEFORE (lines 1069-1116)
func queryDetailView() -> some View {
    return VStack(alignment: .leading) {
        #if os(macOS)
            VSplitView {
                //top half
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isQueryExecuting,
                    onExecuteQuery: executeQuery
                )
                .frame(maxWidth: .infinity)    // ❌ REMOVE THIS LINE

                //bottom half
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults,
                    onGetLastQuery: { viewModel.selectedQuery },
                    onInsertQuery: { dql in
                        viewModel.selectedQuery = dql
                    }
                )
                .frame(maxWidth: .infinity)    // ❌ REMOVE THIS LINE
            }
        #else
            // ... iOS code stays the same ...
        #endif
    }
    .padding(.bottom, 28)  // Keep this
}

// AFTER (FIXED)
func queryDetailView() -> some View {
    return VStack(alignment: .leading, spacing: 0) {
        #if os(macOS)
            VSplitView {
                //top half
                QueryEditorView(
                    queryText: $viewModel.selectedQuery,
                    executeModes: $viewModel.executeModes,
                    selectedExecuteMode: $viewModel.selectedExecuteMode,
                    isLoading: $viewModel.isQueryExecuting,
                    onExecuteQuery: executeQuery
                )
                // ✅ No .frame(maxWidth: .infinity) here

                //bottom half
                QueryResultsView(
                    jsonResults: $viewModel.jsonResults,
                    onGetLastQuery: { viewModel.selectedQuery },
                    onInsertQuery: { dql in
                        viewModel.selectedQuery = dql
                    }
                )
                // ✅ No .frame(maxWidth: .infinity) here
            }
        #else
            // ... iOS code stays the same ...
        #endif
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)  // ✅ ADD THIS LINE
    .padding(.bottom, 28)
}
```

### Step 2: Verify other detail views

Check that other detail views (syncTabsDetailView, observeDetailView, dittoToolsDetailView) also follow this pattern. They should have `.frame(maxWidth: .infinity, maxHeight: .infinity)` on their containers if they contain complex layouts.

### Step 3: Test the fix

After making the changes:

1. Build and run the app
2. Open an app in MainStudioView
3. Select "Collections" in sidebar
4. Verify VSplitView shows query editor and results
5. Drag the VSplitView divider - should resize smoothly
6. Click inspector toggle button (top-right)
7. **VERIFY**: Sidebar REMAINS VISIBLE ✅
8. **VERIFY**: VSplitView divider still draggable ✅
9. Click queries in inspector History/Favorites
10. **VERIFY**: Sidebar auto-switches but stays visible ✅
11. **VERIFY**: No console errors ✅

### Step 4: Run tests

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/SwiftUI
./run_ui_tests.sh
```

Ensure all tests pass after the fix.

## Technical Explanation

### Why .frame(maxWidth: .infinity) Causes Problems

When you apply `.frame(maxWidth: .infinity)` to a view, you're telling SwiftUI:
- "This view wants to be as wide as possible"
- "Give me the maximum available width"

In a NavigationSplitView with Inspector:
- Sidebar needs: 200-300px (fixed range)
- Inspector needs: 250-500px (fixed range)
- Detail needs: Whatever's left

If Detail's children each have `.frame(maxWidth: .infinity)`:
- VSplitView child 1: "I want infinite width"
- VSplitView child 2: "I want infinite width"
- NavigationSplitView: "I can't give infinite width to Detail AND show Inspector"
- NavigationSplitView's solution: Hide Sidebar to free up space

### Why Container-Only .frame() Works

When only the container has `.frame(maxWidth: .infinity, maxHeight: .infinity)`:
- Container: "I'll use whatever space you give me"
- VSplitView: "I'll fit in my parent's space"
- VSplitView children: "I'll fit in VSplitView's space"
- NavigationSplitView: "Perfect! I can allocate: Sidebar (250) + Detail (flex) + Inspector (350)"
- Result: All panes visible, clean constraint chain

### Key Principle

**Flexibility should decrease as you go deeper in the view hierarchy:**
1. Detail view container: Flexible (`.frame(maxWidth: .infinity)`)
2. VSplitView: Adapts to parent (no frame modifier)
3. VSplitView children: Adapt to VSplitView (no frame modifier)

## Additional Resources

- **Working POC**: `SwiftUI/POC/NavigationSplitViewWithVSplitViewPOC.swift`
- **Reference POC**: `SwiftUI/POC/NavigationSplitViewInspectorTest.swift` (without VSplitView)
- **Screenshot of Issue**: `screens/edge-studio-broke.png`

## Success Criteria

After applying the fix, verify:
- [ ] Sidebar visible when inspector is open
- [ ] VSplitView divider can be dragged to resize panes
- [ ] Inspector can open/close without breaking layout
- [ ] Sidebar can be resized by dragging edge
- [ ] Inspector can be resized by dragging edge
- [ ] Switching between sidebar items works
- [ ] No constraint loop errors in console
- [ ] Works at window sizes from 800px to 1400px wide
- [ ] All UI tests pass

## Notes

This fix applies the same pattern that was successfully used in `NavigationSplitViewInspectorTest.swift`, extended to work with VSplitView. The key insight is that frame modifiers with `.infinity` should only be applied to the outermost container in the detail view, not to individual children.
