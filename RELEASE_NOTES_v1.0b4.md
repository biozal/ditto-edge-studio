# Edge Studio v1.0 Beta 4

## What's New

### Quickstart Project Downloads (SwiftUI & .NET)

A new **Download Quickstarts** option is now available in the Help menu on both SwiftUI and .NET. This feature downloads the official Ditto quickstart projects directly from GitHub, automatically extracts them, and — when connected to a database — configures `.env` files and edge-server settings with your active credentials.

- **Progress tracking** — A dedicated progress window shows real-time download and extraction status with error handling
- **Project browser** — After download completes, a browser window displays all discovered quickstart projects with their configuration status
- **Smart conflict handling** — Detects existing quickstart folders and offers replace or relocate options
- **Automatic configuration** — Populates database ID, auth token, auth URL, and WebSocket URL across all project `.env` files and edge-server YAML configs

### Embedded MCP Server (.NET)

The .NET version now includes a built-in **Model Context Protocol (MCP) server** with 15 tools, matching the SwiftUI implementation. AI agents and tools like Claude Code can connect to Edge Studio and interact with Ditto databases directly.

- Supports SSE transport for real-time communication
- Configurable via the new **Settings window** with a simple on/off toggle
- Includes server status indicator and logging

### Presence Viewer (.NET)

A full **Presence Viewer** has been added to the .NET version, providing a visual graph of the Ditto mesh network topology.

- **Interactive graph** — SkiaSharp-based rendering with zoom and pan controls
- **Animated transitions** — Smooth node appearance, disappearance, and repositioning with per-node opacity and scale animations
- **BFS ring layout** — Automatic layout engine that arranges peers in concentric rings based on network distance
- **Real-time updates** — Live connection count tracking with properly normalized transport type reporting
- **Last Updated timestamp** — Shows when presence data was last refreshed

### JSON Data Import (.NET)

The .NET version now supports **importing JSON data** into Ditto collections.

- Import window accessible from the toolbar
- Batch DQL insertion for efficient data loading
- Input validation with comprehensive error handling
- Full unit test coverage for the import service

### Observer Improvements (.NET)

The observer experience in the .NET version has been significantly enhanced:

- **Redesigned detail view** — Replaced custom detail pane with integrated JSON and Table result views using shared components
- **Filtering** — ComboBox-based event type filtering with visual filter indicators
- **Pagination** — Added pagination to both the event list and event detail panes
- **Raw/Table toggle** — Switch between raw JSON and structured table views for event data
- **Bug fixes** — Fixed column headers, card clickability, and event data refresh timing

### Help Menu & Documentation (.NET)

- Wired Help menu with a documentation window and direct link to the Ditto website
- Settings window redesigned to match the SwiftUI version layout with proper theme support

---

## Bug Fixes

### SwiftUI
- Fixed extraction hang caused by pipe buffer deadlock when downloading quickstarts — switched to `nullDevice` for process output
- Fixed quickstart notification listener not triggering when a database was already open
- Fixed KVO lifetime and error handling consistency in QuickstartDownloadService
- Resolved actor isolation and unnecessary `await` warnings for Swift 6.2 strict concurrency

### .NET
- Fixed SSE endpoint routing and added startup logging for the MCP server
- Fixed connection count updates from the presence graph observer
- Normalized connection type casing in transport statistics
- Fixed disappearing node rendering during fade-out animations
- Improved peer spacing in the network layout engine to prevent node overlap
- Fixed collection listing order and logging sequence
- Fixed session invalidation and close flow race conditions with diagnostic logging
- Added session-based cancellation to SystemRepository observers
- Fixed Settings window text readability using SukiUI theme resources
- Fixed Windows build compatibility and asset handling

---

## Technical Improvements

- Added closing transition state to prevent race conditions during database disconnection
- Session-based cancellation for SystemRepository observers ensures clean teardown
- Diagnostic logging added throughout the close flow for easier troubleshooting

---

**Full Changelog**: `v1.0b3...v1.0b4`
