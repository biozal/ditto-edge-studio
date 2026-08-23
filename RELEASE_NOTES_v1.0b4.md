# Edge Studio v1.0 Beta 4

## What's New

### Quickstart Project Downloads (SwiftUI)

A new **Download Quickstarts** option is now available in the Help menu. This feature downloads the official Ditto quickstart projects directly from GitHub, automatically extracts them, and — when connected to a database — configures `.env` files and edge-server settings with your active credentials.

- **Progress tracking** — A dedicated progress window shows real-time download and extraction status with error handling
- **Project browser** — After download completes, a browser window displays all discovered quickstart projects with their configuration status
- **Smart conflict handling** — Detects existing quickstart folders and offers replace or relocate options
- **Automatic configuration** — Populates database ID, auth token, auth URL, and WebSocket URL across all project `.env` files and edge-server YAML configs

---

## Bug Fixes

### SwiftUI
- Fixed extraction hang caused by pipe buffer deadlock when downloading quickstarts — switched to `nullDevice` for process output
- Fixed quickstart notification listener not triggering when a database was already open
- Fixed KVO lifetime and error handling consistency in QuickstartDownloadService
- Resolved actor isolation and unnecessary `await` warnings for Swift 6.2 strict concurrency

---

## Technical Improvements

- Added closing transition state to prevent race conditions during database disconnection
- Session-based cancellation for SystemRepository observers ensures clean teardown
- Diagnostic logging added throughout the close flow for easier troubleshooting

---

**Full Changelog**: `v1.0b3...v1.0b4`
