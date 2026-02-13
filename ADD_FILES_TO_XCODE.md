# Adding Phase 1 Files to Xcode Project

## Issue

The Xcode MCP server is not currently available in this environment, so files created in Phase 1 need to be added to the Xcode project manually or via script.

## Option 1: Manual Addition in Xcode (Recommended)

1. **Open project in Xcode:**
   ```bash
   open "SwiftUI/Edge Debug Helper.xcodeproj"
   ```

2. **Remove old PresenceViewerSK.swift reference:**
   - In Xcode Navigator, find old `PresenceViewerSK.swift` in `Components/` folder (will show in red)
   - Right-click → Delete → "Remove Reference"

3. **Add new PresenceViewer folder:**
   - Right-click on `Components` folder in Xcode
   - Choose "Add Files to 'Edge Debug Helper'..."
   - Navigate to `Components/PresenceViewer/` folder
   - Select the folder
   - ✅ Check "Create groups"
   - ✅ Select "Edge Debug Helper" target
   - Click "Add"

4. **Add Sprites folder (with moved files):**
   - Right-click on `Components` folder in Xcode
   - Choose "Add Files to 'Edge Debug Helper'..."
   - Navigate to `Components/Sprites/` folder
   - Select the folder
   - ✅ Check "Create groups"
   - ✅ Select "Edge Debug Helper" target
   - Click "Add"

5. **Add Textures folder (with moved files):**
   - Right-click on `Components` folder in Xcode
   - Choose "Add Files to 'Edge Debug Helper'..."
   - Navigate to `Components/Textures/` folder
   - Select the folder
   - ✅ Check "Create groups"
   - ✅ Select "Edge Debug Helper" target
   - Click "Add"

6. **Clean and build:**
   ```bash
   xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" clean
   xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" build
   ```

## Option 2: Using plutil/PlistBuddy (Advanced)

This would require directly editing the `.xcodeproj/project.pbxproj` file, which is complex and error-prone. Not recommended.

## Why Xcode MCP Server Wasn't Available

The Xcode MCP server needs to be configured separately. To enable it for future use:

1. Check if Xcode MCP server is installed
2. Configure MCP server connection in Claude Code settings
3. Restart Claude Code to pick up the new MCP server

## Verification After Adding Files

Once files are added, verify by running:

```bash
cd SwiftUI
xcodebuild -project "Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" build
```

Expected result: Build should succeed with no errors.

---

**Status:** Waiting for manual file addition in Xcode
**Next:** After files are added, ready to proceed to Phase 2
