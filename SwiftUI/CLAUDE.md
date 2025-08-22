# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Edge Debug Helper is a comprehensive development toolset for working with Ditto databases. The project contains two main applications:
- **SwiftUI App** (macOS/iPadOS): Production-ready GUI for querying and managing Ditto databases
- **Rust/Tauri App** (in development): Cross-platform desktop application built with Tauri, React, and TypeScript

Note: The "Edge Bot" (codename Grimlock) mentioned in documentation refers to future CLI functionality, but currently the rust folder contains a Tauri desktop application.

## Build Commands

### SwiftUI (macOS/iPadOS)
```bash
# Build the app
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug build

# Run tests
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" test

# Build for release
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Release archive

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
  
- **Views** (`Views/` folder):
  - `ContentView.swift`: Root view with app selection
  - `MainStudioView.swift`: Primary tabbed interface
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
- macOS 15+ with Xcode 16.0+
- iPadOS 18.0+
- App sandbox enabled with entitlements for network, Bluetooth, and file access

### Tauri
- Node.js and npm for frontend development
- Rust 1.84.0+ with Cargo
- Platform-specific build requirements for Tauri