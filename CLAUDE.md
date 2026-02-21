# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Plans

All plans should be stored in the plans folder.  If you are told to create a plan for a new feature or bug fix, you should create a plan in the plans folder and name it with the feature or bug fix.  The plan should be a markdown file and should be named with the feature or bug fix.  Research should also go in this folder but approved research implementations should be in stored in the docs folder.

## Project Overview

Edge Debug Helper is a comprehensive SwiftUI application for macOS and iPadOS, providing a production-ready GUI for querying and managing Ditto databases.

## Ditto SDK Version

**CRITICAL: This project is migrating to Ditto SDK v5.**

### Terminology Changes (v5)

In Ditto SDK v5, the terminology has changed:
- **Old term:** "Ditto App" (or "App")
- **New term:** "Ditto Database" (or "Database")

**Throughout this codebase:**
- When we refer to a "Ditto App", we actually mean a **Ditto Database**
- The model `DittoConfigForDatabase` represents a database configuration (formerly known as app config)
- Each "database" in the UI represents a separate Ditto database instance with its own configuration
## Screenshots

From time to time to debug or design new features screenshots or design mock ups will always be stored in the screens folder of the repository.  If you are told
there is a screenshot named and then a filename always asssume it's in the screens folder.

## File Management with Xcode MCP Server

**CRITICAL WORKFLOW REQUIREMENT: When adding or modifying files in this project, ALWAYS use the Xcode MCP server.**

### Why Use Xcode MCP Server

The Xcode MCP server ensures proper integration with the Xcode project structure:
- Automatically adds new files to the correct build targets
- Maintains proper file references in the `.xcodeproj` structure
- Prevents "file not in target" compilation errors
- Handles File System Synchronized directories correctly
- Updates `project.pbxproj` with proper membership settings

### When to Use Xcode MCP Server

Use the Xcode MCP server for:
- ✅ Creating new Swift files (Views, ViewModels, Utilities, etc.)
- ✅ Creating new test files (unit tests, UI tests)
- ✅ Adding new resource files (images, fonts, plists)
- ✅ Moving or renaming files within the project
- ✅ Any operation that modifies the Xcode project structure

### How to Use

Before creating or modifying files that need to be part of the Xcode project:

1. **Check available Xcode MCP tools:**
   ```
   Use ToolSearch to find xcode-related tools
   ```

2. **Use appropriate Xcode MCP commands** for file operations instead of standard file tools

3. **Verify the file appears in Xcode** after creation/modification

### Standard File Operations vs. Xcode Operations

| Operation | Use Standard Tools | Use Xcode MCP Server |
|-----------|-------------------|---------------------|
| Read existing files | ✅ Read tool | - |
| Edit existing files | ✅ Edit tool | - |
| Create documentation (`.md` files) | ✅ Write tool | - |
| Create Swift source files | ❌ | ✅ Xcode MCP |
| Create test files | ❌ | ✅ Xcode MCP |
| Add resources to bundle | ❌ | ✅ Xcode MCP |
| Move files in project | ❌ | ✅ Xcode MCP |

**Important:** Only use the Xcode MCP server for files that need to be compiled or bundled with the app. Documentation, scripts, and configuration files outside the Xcode project can use standard file tools.

## Testing Requirements

> **MANDATORY: Before starting any implementation plan, READ [`docs/TESTING.md`](docs/TESTING.md) in full. All rules in that file MUST be followed without exception.**

Full testing documentation: **[`docs/TESTING.md`](docs/TESTING.md)**

### Quick Reference

- All new code requires tests (minimum 80% coverage for new code)
- Unit/integration tests: Swift Testing (`import Testing`) — **NOT XCTest**
- UI tests only: XCTest/XCUITest (no Swift Testing alternative exists)
- Follow AAA pattern (Arrange-Act-Assert) in all tests
- Use `TestHelpers.setupFreshDatabase()` for test isolation
- Tests must compile and run in Xcode — no exceptions
- Tests must pass before merging any changes

**For complete rules, patterns, and examples: [`docs/TESTING.md`](docs/TESTING.md)**

## Code Quality Tools

**CRITICAL: This project uses automated tools to detect unused code, enforce code quality, and maintain consistent style.**

### Tool Overview

| Tool | Purpose | When to Run | Configuration File |
|------|---------|-------------|-------------------|
| **Periphery** | Detects unused Swift code | Monthly or before releases | `.periphery.yml` |
| **SwiftLint** | Enforces style and detects issues | During development | `.swiftlint.yml` |
| **SwiftFormat** | Auto-formats code | Before committing | `.swiftformat` |

### Installation (Required for Contributors)

All tools installed via Homebrew:

```bash
# Install all three tools
brew install peripheryapp/periphery/periphery
brew install swiftlint
brew install swiftformat

# Verify installations
periphery version  # Should show 2.21.2+
swiftlint version  # Should show 0.63.2+
swiftformat --version  # Should show 0.59.1+
```

### Periphery - Unused Code Detection

**What it does:**
- Scans entire project to find unused Swift code
- Detects unused classes, structs, enums, protocols, functions, properties
- Analyzes build graph to understand actual usage patterns
- Generates reports of dead code candidates

**When to run:**
- Monthly code cleanup sessions
- Before major releases
- When preparing for refactoring
- After removing features

**How to run:**

```bash
# Standard scan (from project root)
cd /Users/labeaaa/Developer/ditto-edge-studio
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --format xcode

# Save report to file
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --format xcode > periphery-report.txt

# Generate baseline (track new unused code only)
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --baseline .periphery_baseline.json
```

**Configuration (`.periphery.yml`):**
- Excludes test files and generated code
- Retains `@main`, `@objc`, and other special attributes
- Configured for app targets (not framework/library)

**Understanding results:**
- Periphery lists file path, line number, and type/name of unused code
- Verify before deleting - some code may be used via runtime reflection or dynamic lookups
- SwiftUI views with no direct references may still be used via navigation

**Common false positives:**
- SwiftUI view initializers
- Protocol requirements in protocol definitions
- Code used via Objective-C runtime
- Entry points (`@main`, `@NSApplicationMain`)

### SwiftLint - Code Quality & Style

**What it does:**
- Enforces Swift style guidelines (based on Swift.org and community standards)
- Detects code smells and potential bugs
- Finds unused imports, variables, and closures
- Warns about force unwraps, force casts, and overly complex code

**When to run:**
- During active development (continuously)
- Before committing changes
- As part of code review process
- Can be integrated into Xcode build phase

**How to run:**

```bash
# Lint entire project
swiftlint lint

# Lint and auto-fix issues
swiftlint lint --fix

# Lint specific directory
swiftlint lint --path "SwiftUI/Edge Debug Helper/"

# Strict mode (treat warnings as errors)
swiftlint lint --strict

# Generate HTML report
swiftlint lint --reporter html > swiftlint-report.html
```

**Xcode Integration:**

Add a "Run Script" build phase to show SwiftLint warnings in Xcode:

```bash
# Build Phase Script:
if which swiftlint >/dev/null; then
  swiftlint
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

**Configuration (`.swiftlint.yml`):**
- Enables unused code detection rules
- Custom rules for project-specific patterns
- Excludes generated files (`FontAwesomeIcons.swift`)
- Excludes POC/experimental code

**Key enabled rules:**
- `unused_import` - Detects unused import statements
- `unused_declaration` - Finds unused functions/variables
- `unused_optional_binding` - Unused variables in if-let/guard-let
- `force_unwrapping` - Warns about `!` force unwraps
- `sorted_imports` - Enforces alphabetical import order

**Custom rules:**
- `todos_fixmes` - Warns about TODO/FIXME comments
- `no_print_statements` - Detects print() calls (use proper logging)

### SwiftFormat - Code Formatting

**What it does:**
- Automatically formats Swift code for consistency
- Enforces indentation, spacing, brace style
- Organizes imports and removes redundancies
- Makes code style uniform across the project

**When to run:**
- Before committing changes
- After pulling code from others
- When refactoring or restructuring code
- Can be run automatically via pre-commit hook

**How to run:**

```bash
# Format entire project
swiftformat .

# Format specific directory
swiftformat "SwiftUI/Edge Debug Helper/"

# Dry run (show what would change without modifying files)
swiftformat --verbose --dryrun .

# Format and show changes
swiftformat --verbose .
```

**Configuration (`.swiftformat`):**
- Swift 6.2 syntax
- 4-space indentation
- 150-character line width
- Inline commas and semicolons
- Removes redundant `self`

**Pre-commit hook (optional):**

Create `.git/hooks/pre-commit`:
```bash
#!/bin/sh
swiftformat --verbose .
git add -u
```

Make executable: `chmod +x .git/hooks/pre-commit`

### Best Practices for Using These Tools

**Daily Development:**
1. SwiftLint runs automatically if integrated into Xcode build phase
2. Run `swiftlint lint --fix` before committing to auto-correct issues
3. Review SwiftLint warnings and address high-priority ones

**Weekly/Sprint:**
1. Run SwiftFormat on modified files: `swiftformat "path/to/modified/files"`
2. Ensure all SwiftLint warnings are addressed before merging PRs

**Monthly/Major Releases:**
1. Run Periphery scan to identify unused code: `periphery scan ...`
2. Review Periphery report and create tickets for removal candidates
3. Verify test coverage before removing code flagged by Periphery

**Before Committing:**
```bash
# Recommended pre-commit checks
swiftlint lint --fix  # Auto-fix style issues
swiftformat .         # Format code
swiftlint lint        # Final check for remaining issues
```

**CI/CD Integration (Future):**

Add to GitHub Actions or CI pipeline:
```yaml
- name: SwiftLint
  run: swiftlint lint --strict

- name: Periphery
  run: periphery scan --format github-actions --fail-on-unused
```

### Tool Output Examples

**Periphery output:**
```
/path/to/File.swift:42:6: warning: Struct 'UnusedStruct' is unused
/path/to/File.swift:58:10: warning: Function 'unusedFunction()' is unused
```

**SwiftLint output:**
```
/path/to/File.swift:12:5: warning: Unused Import Violation: 'Foundation' is imported but not used
/path/to/File.swift:45:20: warning: Force Unwrapping Violation: Avoid using ! to force unwrap
```

**SwiftFormat output:**
```
1/245 files updated:
  /path/to/File.swift
```

### Troubleshooting

**Periphery scan fails or hangs:**
- Ensure Xcode project builds successfully first
- Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Check `.periphery.yml` excludes paths are correct
- Run with `--verbose` flag for debugging

**SwiftLint too strict:**
- Adjust rules in `.swiftlint.yml`
- Disable specific rules with `disabled_rules:`
- Use inline comments to suppress warnings: `// swiftlint:disable:next rule_name`

**SwiftFormat changes too aggressive:**
- Review `.swiftformat` configuration
- Use `--dryrun` to preview changes before applying
- Disable specific rules with `--disable rule_name`

### When NOT to Use These Tools

**Don't rely solely on automated tools for:**
- Architectural decisions (tools can't judge if code *should* exist)
- Performance optimization (tools don't measure runtime performance)
- Security audits (tools catch obvious issues, not all vulnerabilities)
- User experience issues (tools don't test UI/UX quality)

**Always combine automated tools with:**
- Manual code review
- Unit and UI testing
- Performance profiling
- User testing and feedback

### Further Reading

- **Periphery Documentation:** https://github.com/peripheryapp/periphery
- **SwiftLint Rules Reference:** https://realm.github.io/SwiftLint/rule-directory.html
- **SwiftFormat Rules Reference:** https://github.com/nicklockwood/SwiftFormat/blob/main/Rules.md
- **Swift Style Guide:** https://google.github.io/swift/

### Periphery Scanning Results Summary

**Last Full Scan:** February 17, 2026
**Total Unused Declarations Found:** 0
**Removed in Initial Cleanup:** 0 (clean codebase)
**Baseline Created:** February 17, 2026

**Scan Statistics:**
- **Files Analyzed:** 80 Swift files
- **Lines of Code:** ~22,015 lines
- **Scan Duration:** ~3 minutes
- **Tool Version:** Periphery 2.21.2

**Result Interpretation:**

The "no unused code" result is **accurate and expected** for this SwiftUI-based project:
- SwiftUI's dynamic view construction makes static analysis challenging
- Recent architecture refactoring (Font Awesome integration, repository optimization) removed legacy code
- Active development with comprehensive testing validates code usage
- Conservative retainers (SwiftUIRetainer, XCTestRetainer) mark most code as "potentially used"

**Common False Positives (Already Handled):**
- SwiftUI View structs used via @ViewBuilder - Retained by SwiftUIRetainer
- Protocol requirements in protocol definitions - Retained by ProtocolConformanceReferenceBuilder
- @objc declarations - Retained by configuration (`retain_objc_accessible: true`)
- Test code - Excluded via `report_exclude: [".*Tests\\.swift"]`
- Generated code - Excluded via `report_exclude: ["FontAwesomeIcons\\.swift"]`
- POC/experimental code - Excluded via `report_exclude: ["POC/.*"]`

**Baseline Tracking:**
- Baseline file: `.periphery_baseline.json` (gitignored)
- Baseline snapshot: `reports/periphery/baselines/periphery-baseline-20260217.json`
- Future scans will only show **new** unused code since baseline

**Next Scheduled Scan:** First Monday of each month

**Detailed Report:** See `reports/periphery/UNUSED_CODE_REPORT_2026-02-17.md` for comprehensive analysis.

## Logging Framework

**CRITICAL: This project uses CocoaLumberjack for file-based logging with user-viewable logs for debugging and GitHub issue support.**

### Why CocoaLumberjack?

Edge Debug Helper uses [CocoaLumberjack](https://github.com/CocoaLumberjack/CocoaLumberjack) for comprehensive logging:

- ✅ **File-based logging**: All logs written to files with automatic rotation
- ✅ **User accessibility**: Logs can be viewed in-app and exported for GitHub issues
- ✅ **Automatic rotation**: Keeps last 7 days, 5MB max per file
- ✅ **Performance**: Asynchronous logging, doesn't block UI
- ✅ **Thread-safe**: Safe for concurrent access across actors
- ✅ **macOS native**: Full support for macOS, iOS, tvOS, watchOS, visionOS

### Installation (Required)

**The project requires CocoaLumberjack to build.** Add it via Swift Package Manager:

1. Open `Edge Debug Helper.xcodeproj` in Xcode
2. Go to **File → Add Package Dependencies...**
3. Enter URL: `https://github.com/CocoaLumberjack/CocoaLumberjack`
4. Select version: **Latest** (3.8.5+)
5. Add to target: **Edge Debug Helper**

### Usage

The project provides a centralized `LoggingService` (`Utilities/LoggingService.swift`) with a global `Log` accessor:

```swift
// Import not needed - Log is globally available

// Debug (development only)
Log.debug("Detailed debug information")

// Info (general information)
Log.info("Starting operation")

// Warning (non-critical issues)
Log.warning("Missing optional configuration")

// Error (failures, exceptions)
Log.error("Operation failed: \(error.localizedDescription)")
```

**DO NOT use `print()` statements** - All logging must use the `Log` API for proper file logging and user support.

### Log File Location

Logs are automatically saved to:
```
~/Library/Logs/io.ditto.EdgeStudio/
```

**Log rotation:**
- Daily rotation (24-hour rolling)
- Maximum 7 log files kept
- 5MB maximum per file
- Old logs automatically deleted

### Retrieving Logs (for User Support)

```swift
// Get all log files
let logFiles = Log.getAllLogFiles()

// Get combined log content
let logContent = Log.getCombinedLogs()

// Get logs directory path
let logsDir = Log.getLogsDirectory()

// Export logs to specific location
try Log.exportLogs(to: destinationURL)

// Clear all logs (privacy/reset)
Log.clearAllLogs()
```

### Future Feature: Log Viewer

Planned feature for users to:
- View logs in-app
- Copy logs to clipboard
- Export logs as attachment for GitHub issues
- Clear logs for privacy

See `LoggingService.swift` for implementation details and future log viewer UI examples.

### Log Levels by Build Configuration

**Debug builds:**
- All log levels enabled (debug, info, warning, error)
- Console output to Xcode
- File logging enabled

**Release builds:**
- Info, warning, error only (debug disabled)
- No console output
- File logging enabled

### Best Practices

1. **Use appropriate log levels:**
   - `debug()` - Temporary debugging, verbose details
   - `info()` - Normal operations, state changes
   - `warning()` - Recoverable issues, missing optional data
   - `error()` - Failures, exceptions, critical issues

2. **Include context:**
   ```swift
   // ❌ Bad
   Log.error("Failed")

   // ✅ Good
   Log.error("Failed to load database '\(dbName)': \(error.localizedDescription)")
   ```

3. **Don't log sensitive data:**
   - No authentication tokens
   - No user passwords
   - No personally identifiable information (PII)

4. **Use descriptive messages:**
   - Logs should be understandable without code context
   - Include operation name, resource identifiers, error details

### Troubleshooting

**Build error: "No such module 'CocoaLumberjack'"**
- Verify CocoaLumberjack is added via Swift Package Manager
- Clean build: `rm -rf ~/Library/Developer/Xcode/DerivedData`
- Rebuild project

**Logs not appearing:**
- Check `~/Library/Logs/io.ditto.EdgeStudio/` directory exists
- Verify `LoggingService.shared` is initialized (happens automatically)
- Check Console.app for any initialization errors

**Too many log files:**
- Log rotation is automatic (7 days, 5MB max)
- Use `Log.clearAllLogs()` to manually clear all logs

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
  - `DittoManager_LocalSubscription.swift`: Local database subscriptions for database state
  - `DittoManager_DittoAppConfig.swift`: Database configuration management (uses DittoConfigForDatabase model)
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
  - `ContentView.swift`: Root view with database selection
  - `MainStudioView.swift`: Primary interface with navigation sidebar and detail views
    - Sync detail view uses native TabView with three tabs: Peers List, Presence Viewer, Settings
    - Tab selection persists when navigating between menu items
    - Threading optimizations for cleanup operations using TaskGroup
  - `DatabaseEditorView.swift`: Database configuration editor (uses DittoConfigForDatabase model)
  - **Tabs/**: Tab-specific views like `ObserversTabView.swift`
  - **Tools/**: Utility views (presence, disk usage, peers, permissions)
  
- **Components** (`Components/` folder): Reusable UI components
  - Query editor and results viewers
  - Database and subscription cards/lists
  - Pagination controls and secure input fields
  - `DatabaseCard.swift`: Card component for displaying database configurations
  - `NoDatabaseConfigurationView.swift`: Empty state when no databases are configured
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
- Multi-database connection management with local storage (using DittoConfigForDatabase model)
- Query execution with history and favorites
- Real-time subscriptions and observables
- Connection status bar with real-time transport-level monitoring (WebSocket, Bluetooth, P2P WiFi, Access Point)
- Presence viewer and peer management
- Disk usage monitoring
- Import/export functionality
- Permissions health checking
- Font Debug window for visualizing all Font Awesome icons (Help menu → Font Debug or ⌘⇧D)

## UI Patterns

### Picker Navigation Consistency

**CRITICAL: Sidebar and Inspector navigation MUST use identical Picker implementation.**

Both use this exact pattern:

```swift
HStack {
    Spacer()
    Picker("", selection: $selectedItem) {
        ForEach(items) { item in
            item.image  // 48pt SF Symbol
                .tag(item)
        }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .liquidGlassToolbar()
    .accessibilityIdentifier("NavigationSegmentedPicker") // or "InspectorSegmentedPicker"
    Spacer()
}
.padding(.horizontal, 12)
.padding(.vertical, 6)
```

**Standards:**
- Navigation icons: **48pt** SF Symbols only (not Font Awesome)
- Picker height: **Auto-sized** (no fixed height constraint - allows picker to grow with icon size)
- Picker alignment: **Centered** using HStack with Spacers
- Both use MenuItem struct with `systemIcon: String`
- Both use `.accessibilityIdentifier()` for UI tests
- If styling changes in one, MUST change in the other

**Menu Items:**
- Sidebar: Subscriptions (arrow.trianglehead.2.clockwise.rotate.90), Collections (macpro.gen2), Observer (eye)
- Inspector: History (clock), Favorites (bookmark)

**MenuItem Structure:**
```swift
struct MenuItem: Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    var systemIcon: String  // SF Symbol name

    @ViewBuilder
    var image: some View {
        Image(systemName: systemIcon)
            .font(.system(size: 48))
    }
}
```

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

## App Launch and Navigation Flow

**CRITICAL: Understanding this flow is required for writing UI tests.**

### Complete Navigation Flow

```
App Launch (Ditto_Edge_StudioApp.swift)
  ↓
ContentView (root view)
  ├─ State: isMainStudioViewPresented = false (initially)
  ├─ onAppear: loadApps() - loads database configurations (DittoConfigForDatabase models)
  │
  ├──→ DATABASE LIST SCREEN (when isMainStudioViewPresented = false)
  │    │
  │    ├─ Component: DatabaseList
  │    │  └─ Accessibility ID: "DatabaseList" (macOS only)
  │    │
  │    ├─ Loading State: ProgressView("Loading Database Configs...")
  │    ├─ Empty State: NoDatabaseConfigurationView (component)
  │    │
  │    └─ Normal State: List of database cards
  │       ├─ Each card: DatabaseCard component
  │       ├─ Accessibility ID: "AppCard_{name}" (macOS only, legacy naming)
  │       └─ User taps card →
  │          ├─ showMainStudio(dittoDatabase) called
  │          ├─ selectedDittoConfigForDatabase = dittoDatabase
  │          ├─ hydrateDittoSelectedDatabase() - async setup
  │          └─ isMainStudioViewPresented = true
  │             ↓
  │             (ContentView re-renders)
  │             ↓
  └──→ MAINSTUDIOVIEW SCREEN (when isMainStudioViewPresented = true)
       │
       ├─ Toolbar (top)
       │  ├─ Sync toggle button
       │  ├─ Close button → returns to database list
       │  └─ Inspector toggle (ID: "Toggle Inspector")
       │
       ├─ Sidebar (left panel, 200-300px)
       │  ├─ NavigationSegmentedPicker (ID: "NavigationSegmentedPicker")
       │  └─ Menu Items: Subscriptions | Collections | Observer
       │
       ├─ Detail Area (center panel)
       │  ├─ Collections: QueryEditor (50%) + QueryResults (50%)
       │  ├─ Observer: ObserverEventsList + EventDetail
       │  └─ Subscriptions: Sync tabs (Peers/Presence/Settings)
       │
       ├─ Inspector (right panel, 250-500px, optional)
       │  ├─ InspectorSegmentedPicker (ID: "InspectorSegmentedPicker")
       │  └─ Tabs: History | Favorites
       │
       └─ Status Bar (bottom)
          └─ ConnectionStatusBar (sync status, peer count)
```

### Accessibility Identifiers for UI Testing

| Element | Identifier | Platform | Purpose |
|---------|-----------|----------|---------|
| **Add Database Button** | `"AddDatabaseButton"` | Both | **ContentView indicator** - CRITICAL for test verification |
| Database List Container | `"DatabaseList"` | macOS only | Root container for database cards |
| Individual Database Card | `"AppCard_{name}"` | macOS only | Each selectable database (legacy "App" naming) |
| Sidebar Navigation Picker | `"NavigationSegmentedPicker"` | Both | Sidebar menu switcher |
| Inspector Toggle Button | `"Toggle Inspector"` | Both | Show/hide inspector |
| Inspector Navigation Picker | `"InspectorSegmentedPicker"` | Both | Inspector menu |

**Note:** Some accessibility identifiers use legacy "App" naming (e.g., `"AppCard_{name}"`) but these refer to database configurations.

## Testing

See **[`docs/TESTING.md`](docs/TESTING.md)** for all testing documentation.

### Test File Locations
- Unit tests: `SwiftUI/EdgeStudioUnitTests/`
- Integration tests: `SwiftUI/EdgeStudioIntegrationTests/`
- UI tests: `SwiftUI/Edge Debugg Helper UITests/Ditto_Edge_StudioUITests.swift`

### Quick Commands

```bash
# Run all tests
xcodebuild test -project "SwiftUI/Edge Debug Helper.xcodeproj" \
                -scheme "Edge Studio" \
                -destination "platform=macOS,arch=arm64"

# Run specific target
xcodebuild test ... -only-testing:EdgeStudioUnitTests
```

### UI Test Setup
1. Copy `SwiftUI/Edge Debug Helper/testDatabaseConfig.plist.example` to `testDatabaseConfig.plist`
2. Add real test credentials to the plist file
3. Tests auto-load databases when launched with `UI-TESTING` argument

## Platform Requirements

- macOS 26.0 with Xcode 26.0+ with Swift 6.2
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
