# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Edge Debug Helper is a comprehensive development toolset for working with Ditto databases. The project contains two main applications:
- **SwiftUI App** (macOS/iPadOS): Production-ready GUI for querying and managing Ditto databases
- **Rust/Tauri App** (in development): Cross-platform desktop application built with Tauri, React, and TypeScript

Note: The "Edge Bot" (codename Grimlock) mentioned in documentation refers to future CLI functionality, but currently the rust folder contains a Tauri desktop application.

## Development Environment Setup

### Xcode Version Requirements
This project requires **Xcode 26.0 beta** (or later) with Swift 6.2 for proper dependency compatibility.

**To switch to Xcode beta:**
```bash
# Switch active developer tools to Xcode beta
sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer

# Verify the switch worked
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

### Rust/Tauri Application
```bash
# Development mode (starts Vite dev server + Tauri)
cd rust && npm run tauri dev

# Build frontend only
cd rust && npm run build

# Build Tauri application for production
cd rust && npm run tauri build

# Run frontend dev server only
cd rust && npm run dev

# Install dependencies
cd rust && npm install

# Build Rust backend only
cd rust/src-tauri && cargo build
cd rust/src-tauri && cargo build --release
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
  - `SystemRepository.swift`: System metrics and health monitoring
  - All repositories use Task.detached(priority: .utility) for cleanup operations to prevent threading priority inversions
  
- **Views** (`Views/` folder):
  - `ContentView.swift`: Root view with app selection
  - `MainStudioView.swift`: Primary tabbed interface with threading optimizations for cleanup operations
  - `AppEditorView.swift`: App configuration editor
  - **Tabs/**: Tab-specific views like `ObserversTabView.swift`
  - **Tools/**: Utility views (presence, disk usage, peers, permissions)
  
- **Components** (`Components/` folder): Reusable UI components
  - Query editor and results viewers
  - App and subscription cards/lists
  - Pagination controls and secure input fields

### Rust/Tauri App Structure
Located in the `rust/` directory:

- **Frontend** (React/TypeScript):
  - `src/App.tsx`: Main React application
  - `src/main.tsx`: Application entry point
  - Uses Vite for bundling and development
  
- **Backend** (Rust/Tauri):
  - `src-tauri/src/main.rs`: Application entry point
  - `src-tauri/src/lib.rs`: Core Tauri application with command handlers
  - `src-tauri/tauri.conf.json`: Tauri configuration
  - Currently implements basic IPC with `greet` command example

## Configuration Requirements

### SwiftUI App
Requires `dittoConfig.plist` in `SwiftUI/Edge Debug Helper/` with:
- `appId`: Ditto application ID
- `authToken`: Authentication token
- `authUrl`: Authentication endpoint
- `websocketUrl`: WebSocket endpoint
- `httpApiUrl`: HTTP API endpoint
- `httpApiKey`: HTTP API key

### Tauri App
Configuration in `rust/src-tauri/tauri.conf.json`:
- Product name: `ditto-edge-studio`
- Identifier: `com.costoda.ditto-edge-studio`
- Dev server: `http://localhost:1420`
- Frontend dist: `../dist`

## Key Features

### SwiftUI App
- Multi-app connection management with local storage
- Query execution with history and favorites
- Real-time subscriptions and observables
- Presence viewer and peer management
- Disk usage monitoring
- Import/export functionality
- Permissions health checking

### Tauri App (in development)
- Cross-platform desktop application
- React-based UI with Tauri backend
- IPC communication between frontend and Rust backend

## Testing

### SwiftUI
- Unit tests in `Edge Debug Helper Tests/`
- UI tests in `Edge Debugg Helper UITests/`
- Run with: `xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" test`

### Tauri/Rust
- Rust tests: `cd rust/src-tauri && cargo test`
- TypeScript/React tests: Not yet configured

## Platform Requirements

### SwiftUI
- macOS 15+ with Xcode 26.0+ (beta) or Xcode 16.5+ with Swift 6.2
- iPadOS 18.0+
- App sandbox enabled with entitlements for network, Bluetooth, and file access

### Tauri
- Node.js and npm for frontend development
- Rust 1.84.0+ with Cargo
- Platform-specific build requirements for Tauri

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

1. **Switch to Xcode beta** (recommended):
   ```bash
   sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer
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
- Ensure Xcode beta is active for Swift 6.2 compatibility
- Clean derived data if dependencies seem out of sync
