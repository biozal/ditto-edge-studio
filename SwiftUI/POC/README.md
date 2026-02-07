# Three-Pane Layout POC

## Purpose
This proof-of-concept demonstrates how to create an Xcode-like 3-pane layout:
- **Left**: Sidebar with navigation
- **Center**: Main detail/content view
- **Right**: Inspector panel (like Xcode's inspector)

## Key Finding
SwiftUI's `.inspector()` modifier is the correct solution for creating a right-side panel that mimics Xcode's inspector behavior.

## Files
- `ThreePaneLayoutPOC.swift` - Complete POC implementation with comments

## How to Test

### Option 1: Quick Preview in Xcode
1. Open `ThreePaneLayoutPOC.swift` in Xcode
2. Use the Canvas preview (⌥⌘↵)
3. The preview is configured with a reasonable window size (1200x800)

### Option 2: Standalone App (Recommended for full testing)
1. Create a new macOS App target in Xcode:
   - File → New → Target
   - Choose "App" template
   - Name it "ThreePanePOC"
   - Platform: macOS

2. Replace the ContentView with:
   ```swift
   import SwiftUI

   @main
   struct ThreePanePOCApp: App {
       var body: some Scene {
           WindowGroup {
               ThreePaneLayoutPOC()
           }
       }
   }
   ```

3. Add `ThreePaneLayoutPOC.swift` to the target
4. Run the app (⌘R)

### Option 3: Integrate into Edge Debug Helper (Temporary)
1. Add a menu item or keyboard shortcut to show the POC
2. Present it as a new window or replace MainStudioView temporarily

## What to Test

### Layout Verification
- [ ] Three distinct panes visible
- [ ] Inspector appears on the RIGHT side (not middle)
- [ ] Toolbar button toggles inspector visibility
- [ ] Inspector is resizable by dragging the divider
- [ ] Inspector width constrained to min=250, ideal=350, max=500

### Interaction Testing
- [ ] Sidebar items selectable
- [ ] Detail view responds to sidebar selection
- [ ] Inspector tabs (History, Favorites, Settings) switchable
- [ ] Inspector content updates per tab
- [ ] Inspector state persists when changing sidebar items

### Adaptive Behavior (Optional - iPad testing)
- [ ] Inspector becomes a sheet in compact width
- [ ] Toggle button works in all size classes

## Key Questions to Answer
1. ✅ Does this match Xcode's inspector behavior?
2. ✅ Is the inspector positioned on the RIGHT as expected?
3. ✅ Can we easily move History and Favorites to the inspector?
4. ✅ Will this integrate well with MainStudioView?
5. ✅ Is the inspector resizable and user-friendly?

## Integration Plan (If POC succeeds)
See the main implementation plan in the plan file.

## SwiftUI Version Requirements
- macOS 14+ (Sonoma)
- iOS 17+

Edge Debug Helper targets macOS 15+ and iPadOS 18+, so we're good! ✅
