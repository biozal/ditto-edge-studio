# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when worki:wng with code in this repository.

## Project Overview

Edge Debug Helper is a comprehensive SwiftUI application for macOS and iPadOS, providing a production-ready GUI for querying and managing Ditto databases.
## Screenshots

From time to time to debug or design new features screenshots or design mock ups will always be stored in the screens folder of the repository.  If you are told
there is a screenshot named and then a filename always asssume it's in the screens folder.

## Testing Requirements

**CRITICAL RULE: All tests MUST be runnable in Xcode.**

- Tests must be properly configured to compile and run in the Xcode test target
- Tests must NOT be moved to temporary directories or locations outside the project
- If tests produce warnings about being in the wrong target, fix the Xcode project configuration (using `membershipExceptions` in project.pbxproj for File System Synchronized targets)
- Tests that cannot be run in Xcode are not acceptable and the configuration must be fixed
- Use Swift Testing framework (`import Testing`) for all new tests, not XCTest

## Development Environment Setup

### Xcode Version Requirements
This project requires **Xcode 26.2** (or later) with Swift 6.2 for proper dependency compatibility.

**To verify your Xcode version:**
```bash
# Verify Xcode version
xcode-select -p
xcodebuild -version
xcrun swift --version
```

### Build Environment Clean-up
If experiencing Swift version compatibility issues:
```bash
# Clear derived data to force fresh dependency compilation
rm -rf ~/Library/Developer/Xcode/DerivedData

# Clean and rebuild project
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" clean
```

## Build Commands

### SwiftUI (macOS/iPadOS)
```bash
# Build the app (ARM64 only to avoid multiple destination warnings)
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug -destination "platform=macOS,arch=arm64" build

# Run tests
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -destination "platform=macOS,arch=arm64" test

# Build for release
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Release -destination "platform=macOS,arch=arm64" archive

# Export for distribution (requires exportOptions.plist)
xcodebuild -exportArchive -archivePath <path-to-archive> -exportPath <output-path> -exportOptionsPlist SwiftUI/exportOptions.plist
```

## Architecture

### SwiftUI App Structure
Located in the `SwiftUI/` directory:

- **DittoManager** (`Data/` folder): Core service layer split into functional modules:
  - `DittoManager.swift`: Base initialization and shared state
  - `DittoManager_Lifecycle.swift`: Connection management and sync controls
  - `DittoManager_Query.swift`: Query execution and results handling
  - `DittoManager_Subscription.swift`: Real-time subscription management
  - `DittoManager_Observable.swift`: Observe event handling
  - `DittoManager_LocalSubscription.swift`: Local database subscriptions for app state
  - `DittoManager_DittoAppConfig.swift`: App configuration management
  - `DittoManager_Import.swift`: Data import functionality

- **QueryService** (`Data/QueryService.swift`): Query execution service with enhanced features:
  - Local and HTTP query execution
  - Commit ID tracking for mutated documents
  - Returns both document IDs and commit IDs for mutations

- **Repositories** (`Data/Repositories/` folder): Actor-based data repositories with threading optimizations:
  - `SubscriptionsRepository.swift`: Real-time subscription management
  - `HistoryRepository.swift`: Query history tracking with observer pattern
  - `FavoritesRepository.swift`: Favorite queries management
  - `ObservableRepository.swift`: Observable events management with diffing
  - `CollectionsRepository.swift`: Collections data management
  - `SystemRepository.swift`: System metrics and health monitoring, including sync status and connection transport statistics
  - All repositories use Task.detached(priority: .utility) for cleanup operations to prevent threading priority inversions
  
- **Views** (`Views/` folder):
  - `ContentView.swift`: Root view with app selection
  - `MainStudioView.swift`: Primary interface with navigation sidebar and detail views
    - Sync detail view uses native TabView with three tabs: Peers List, Presence Viewer, Settings
    - Tab selection persists when navigating between menu items
    - Threading optimizations for cleanup operations using TaskGroup
  - `AppEditorView.swift`: App configuration editor
  - **Tabs/**: Tab-specific views like `ObserversTabView.swift`
  - **Tools/**: Utility views (presence, disk usage, peers, permissions)
  
- **Components** (`Components/` folder): Reusable UI components
  - Query editor and results viewers
  - App and subscription cards/lists
  - Pagination controls and secure input fields
  - `ConnectedPeersView.swift`: Extracted sync status view showing connected peers (used in Peers List tab)
  - `PresenceViewerTab.swift`: Wrapper for DittoPresenceViewer with connection handling
  - `TransportConfigView.swift`: Placeholder for future transport configuration settings

## Configuration Requirements
Requires `dittoConfig.plist` in `SwiftUI/Edge Debug Helper/` with:
- `appId`: Ditto application ID
- `authToken`: Authentication token
- `authUrl`: Authentication endpoint
- `websocketUrl`: WebSocket endpoint
- `httpApiUrl`: HTTP API endpoint
- `httpApiKey`: HTTP API key

## Key Features
- Multi-app connection management with local storage
- Query execution with history and favorites
- Real-time subscriptions and observables
- Connection status bar with real-time transport-level monitoring (WebSocket, Bluetooth, P2P WiFi, Access Point)
- Presence viewer and peer management
- Disk usage monitoring
- Import/export functionality
- Permissions health checking
- Font Debug window for visualizing all Font Awesome icons (Help menu → Font Debug or ⌘⇧D)

## Font Awesome Icons

### Icon System
The app uses Font Awesome 7 Pro for all icons instead of SF Symbols for better cross-platform consistency and design flexibility.

**Key Files:**
- `Utilities/FontAwesome.swift` - Icon alias enums and helper functions
- `Utilities/FontAwesomeIcons.swift` - Auto-generated enum with 4,245 icons
- `Views/Tools/FontDebugWindow.swift` - Debug window showing all icons in use
- `generate_icons.swift` - Script to regenerate icons from font files

**Icon Categories:**
- **PlatformIcon**: OS icons (Linux, macOS, Android, iOS, Windows)
- **ConnectivityIcon**: Network/transport icons (WiFi, Bluetooth, Ethernet, etc.)
- **SystemIcon**: System UI icons (Link, Info, Clock, Gear, Question, SDK)
- **NavigationIcon**: Navigation controls (Chevrons, Play, Refresh, Sync)
- **ActionIcon**: User actions (Plus, Download, Copy, Close)
- **DataIcon**: Data display (Code, Table, Database, Layers)
- **StatusIcon**: Status indicators (Check, Info, Warning, Question)
- **UIIcon**: Interface elements (Star, Eye, Clock, Nodes)

### Adding New Icons

**CRITICAL: When adding a new icon to any category, you MUST update the Font Debug Window.**

1. **Add icon to FontAwesome.swift:**
   ```swift
   enum NavigationIcon {
       static let newIcon: FAIcon = .icon_f123  // fa-icon-name
   }
   ```

2. **Update FontDebugWindow.swift** in the `allIcons` computed property:
   ```swift
   // Navigation Icons section
   icons.append(contentsOf: [
       // ... existing icons ...
       IconDebugInfo(icon: NavigationIcon.newIcon, aliasName: "NavigationIcon.newIcon",
                    category: "Navigation Icons", unicode: "f123",
                    fontFamily: "FontAwesome7Pro-Solid"),
   ])
   ```

3. **Use the icon in views:**
   ```swift
   FontAwesomeText(icon: NavigationIcon.newIcon, size: 14)
   ```

**Finding Unicode Values:**
- Use Font Book.app to inspect font glyphs
- Check Font Awesome website (fontawesome.com)
- Search FontAwesomeIcons.swift for icon codes
- Unicode format in Swift: `\u{XXXX}` (e.g., `\u{f2f1}`)

**Font Families:**
- `FontAwesome7Pro-Solid` (900 weight) - Most icons (3,725 icons)
- `FontAwesome7Pro-Regular` (400 weight) - Lighter variant of Solid icons
- `FontAwesome7Pro-Light` (300 weight) - Light weight for subtle UI elements
- `FontAwesome7Pro-Thin` (100 weight) - Thinnest weight for large icons or minimal designs
- `FontAwesome7Brands-Regular` - Brand/platform icons (526 icons)

### Font Weights

The app supports multiple font weights for the same icon unicode value using the `WeightedFAIcon` system.

**When to Use Different Weights:**
- **Solid (900)**: Default weight for most icons, provides best visibility at small sizes
- **Regular (400)**: Lighter appearance, better for large icons (64pt+) or when visual weight needs to be reduced
- **Light (300)**: Very subtle appearance, ideal for toolbar icons and non-primary actions
- **Thin (100)**: Extremely light weight, best for very large icons (80pt+) or minimalist designs

**Creating Weighted Icons:**
```swift
// In icon alias enums
enum DataIcon {
    static let database: FAIcon = .icon_f1c0                      // Solid (default)
    static let databaseRegular: WeightedFAIcon = WeightedFAIcon(.icon_f1c0, weight: .regular)
}

enum NavigationIcon {
    static let sync: FAIcon = .icon_f2f1                          // Solid (default)
    static let syncLight: WeightedFAIcon = WeightedFAIcon(.icon_f2f1, weight: .light)
}
```

**Usage Examples:**
```swift
// Solid database icon (default) for small size
FontAwesomeText(icon: DataIcon.database, size: 14)

// Regular database icon for large size (less visual weight)
FontAwesomeText(icon: DataIcon.databaseRegular, size: 64)

// Light sync icon for toolbar (subtle appearance)
FontAwesomeText(icon: NavigationIcon.syncLight, size: 20)
```

**Current Weighted Variants:**
- `DataIcon.databaseRegular` - Database icon in Regular (400) weight
- `DataIcon.databaseThin` - Database icon in Thin (100) weight (used for main screen)
- `NavigationIcon.syncLight` - Sync/rotate icon in Light (300) weight
- `ActionIcon.circleXmarkLight` - Close icon in Light (300) weight

### Font Debug Window
Access via **Help → Font Debug** or **⌘⇧D**

Features:
- Visual display of all 47+ icons currently in use (including weighted variants)
- Search by alias name or unicode value
- Category filtering (8 categories)
- Copy icon alias names to clipboard
- Shows: icon rendering, alias name, unicode value, font family, font weight

**Purpose:** Quick reference for developers and visual verification that all icons render correctly. The weight column shows which font weight each icon uses (Solid 900, Regular 400, Light 300, or Brands).

## Testing

- Unit tests in `Edge Debug Helper Tests/`
- UI tests in `Edge Debugg Helper UITests/`
- Run with: `xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" test`

## Platform Requirements

- macOS 15+ with Xcode 26.2+ or Xcode 16.5+ with Swift 6.2
- iPadOS 18.0+
- App sandbox enabled with entitlements for network, Bluetooth, and file access

## Threading and Performance Optimizations

### Threading Priority Inversion Prevention
The SwiftUI app includes comprehensive threading optimizations to prevent priority inversions during Ditto sync operations:

- **DittoManager**: All sync start/stop operations use `Task.detached(priority: .utility)` to run on appropriate background queues
- **Repository Cleanup**: All repository `stopObserver()` methods use background tasks to prevent blocking the main UI thread
- **MainStudioView**: App cleanup operations are separated into UI state updates (main thread) and heavy operations (background queues using TaskGroup)

These optimizations eliminate threading warnings like "Thread running at User-initiated quality-of-service class waiting on a lower QoS thread running at Default quality-of-service class."

### QueryService Enhancements
The QueryService now provides enhanced mutation tracking:
- Returns document IDs for all mutated documents
- Includes commit ID information for better change tracking
- Supports both local Ditto queries and HTTP API queries
- Format: `"Document ID: [id]"` followed by `"Commit ID: [commit_id]"`

## Troubleshooting

### Swift Version Compatibility Issues
If you encounter "module compiled with Swift 6.2 cannot be imported by the Swift 6.1.2 compiler" errors:

1. **Ensure Xcode 26.2+ is active**:
   ```bash
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. **Clean build environment**:
   ```bash
   rm -rf ~/Library/Developer/Xcode/DerivedData
   xcodebuild clean
   ```

3. **Verify Swift version alignment**:
   ```bash
   xcrun swift --version  # Should show Swift 6.2
   ```

### Build Issues
- Use ARM64-only builds to avoid multiple destination warnings
- Ensure Xcode 26.2+ is active for Swift 6.2 compatibility
- Clean derived data if dependencies seem out of sync
