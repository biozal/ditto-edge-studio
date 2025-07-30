# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ditto Edge Studio is a cross-platform development tool for working with Ditto databases. It consists of:
- **SwiftUI App** (macOS/iPadOS): Main GUI application for querying and managing Ditto databases
- **Rust CLI** (in development): Command-line interface for Edge Studio

## Build Commands

### SwiftUI (macOS/iPadOS)
```bash
# Build the app
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Debug build

# Run tests
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" test

# Build for release
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" -scheme "Edge Studio" -configuration Release archive
```

### Rust CLI

Review CLAUDE.md file in the rust directory.

```bash
# Build debug
cd rust && cargo build

# Build release
cd rust && cargo build --release

# Run tests
cd rust && cargo test

# Run the CLI
cd rust && cargo run --bin edge-studio
```

## Architecture

### SwiftUI App Structure
- **DittoManager**: Core service managing Ditto SDK operations, split into modules:
  - `DittoManager.swift`: Base configuration and initialization
  - `DittoManager_Lifecycle.swift`: Connection management and sync controls
  - `DittoManager_Query.swift`: Query execution and results handling
  - `DittoManager_Subscription.swift`: Real-time subscription management
  - `DittoManager_Observable.swift`: Observe event handling
  - `DittoManager_LocalSubscription.swift`: Local database subscriptions
  
- **Views**:
  - `MainStudioView.swift`: Primary interface with tabs for different functionalities
  - `ContentView.swift`: App selection and initial setup
  - Query editor and results viewer components
  
- **Models**: Data structures for app configs, subscriptions, and query results

### Configuration Requirements
The app requires a `dittoConfig.plist` file in the SwiftUI project root with:
- `appId`: Ditto application ID
- `authToken`: Authentication token
- `authUrl`: Authentication endpoint
- `websocketUrl`: WebSocket endpoint
- `httpApiUrl`: HTTP API endpoint
- `httpApiKey`: HTTP API key

### Key Features
- Multi-app connection management
- Query execution with history and favorites
- Real-time subscriptions and observables
- Presence viewer and peer management
- Disk usage monitoring
- Import/export functionality

### Security Entitlements
The macOS app requires:
- Network client/server access
- Bluetooth access for P2P
- File system read/write for user-selected files
- App sandbox enabled