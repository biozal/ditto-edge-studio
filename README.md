# Ditto Edge Studio 
Ditto Edge Studio is a set of tools and an application that allows you to create a local Ditto Database based on a database registered in the Ditto Portal and use the Ditto SDK to query information in the Ditto Edge Server, local Edge Server, or P2P with other devices sharing the same DatabaseId.

**Key Features:**
- Multi-app connection management with local storage
- Real-time query execution with history and favorites
- Active subscriptions and observables management
- Connection status bar with transport-level statistics
- Presence viewer and peer management
- Disk usage monitoring and permissions health checking
- Import/export functionality 

## Requirements

### Ditto Portal Account:
- You need a Ditto Portal account.  You can sign up for a free account at [Ditto Portal](https://portal.ditto.live/create-account?_gl=1*gkhgpr*_gcl_au*MTE4OTI1ODI0OS4xNzQ3MzEzNTc4*_ga*MTM3NDExNTUyOS4xNzMzMTQ4MTc5*_ga_D8PMW3CCL2*czE3NTAzNTA2MjYkbzE2MyRnMCR0MTc1MDM1MDYyNyRqNTkkbDAkaDA.).

### App Requirements
- A Mac with MacOS 26.0 or higher installed
- An iPad with OS 26.0  or higher installed

### Build REquirements
- Xcode 26.2 or higher installed
- [SwiftLint](https://github.com/realm/SwiftLint) Installed
- [Swiftformat](https://github.com/swiftlang/swift-format) Installed
- [Periphery](https://github.com/peripheryapp/periphery) Installed

Note: The SwiftUI app is only officially supports MacOS and iPadOS.  While it will build and run on iOS, it has not been tested on iOS and there are known issues with the SwiftUI app on iOS.


## Getting Started from Source

## Development Tools

Edge Debug Helper uses industry-standard code quality tools to maintain code health and detect unused code. These tools help catch issues early and keep the codebase clean.

### Quick Start

```bash
# Install all tools
brew install swiftlint swiftformat peripheryapp/periphery/periphery

# Run quick quality check
swiftlint lint
swiftformat .
```

### Installed Tools

| Tool | Purpose | Integration | Documentation |
|------|---------|-------------|---------------|
| **SwiftFormat** | Auto-formatting | Xcode build phase | [Guide](docs/CODE_QUALITY_GUIDE.md#swiftformat) |
| **SwiftLint** | Style & quality rules | Xcode build phase | [Guide](docs/CODE_QUALITY_GUIDE.md#swiftlint) |
| **Periphery** | Unused code detection | Manual (weekly) | [Guide](docs/CODE_QUALITY_GUIDE.md#periphery) |

### Xcode Integration

Both SwiftFormat and SwiftLint are integrated into the build process:
- **SwiftFormat** runs first - automatically formats code
- **SwiftLint** runs second - shows violations as warnings in Xcode

**To add both tools to your build:**
1. Open project in Xcode
2. Target → Build Phases → "+" → New Run Script Phase (add 2 phases)
3. First: "SwiftFormat" phase (formats code)
4. Second: "SwiftLint" phase (checks code)
5. Add scripts (see [CODE_QUALITY_GUIDE.md](docs/CODE_QUALITY_GUIDE.md#build-phase-scripts))

### Configuration Files

All tools are configured via dotfiles in the project root:
- `.periphery.yml` - Periphery configuration
- `.swiftlint.yml` - SwiftLint rules and exclusions
- `.swiftformat` - SwiftFormat style rules

### Common Commands

```bash
# SwiftLint
swiftlint lint              # Check violations
swiftlint lint --fix        # Auto-fix where possible

# SwiftFormat
swiftformat .               # Format all files
swiftformat --lint .        # Check formatting only

# Periphery
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio"
```

### Recommended Workflow

1. **Every build** - SwiftFormat and SwiftLint run automatically (Xcode integration)
2. **Weekly** - Run Periphery to find unused code
3. **Before releases** - Run all tools with `--strict` flags

**With build integration, you don't need to remember to format or lint - it happens automatically!**

### Complete Documentation

📖 **See [docs/CODE_QUALITY_GUIDE.md](docs/CODE_QUALITY_GUIDE.md) for:**
- Detailed installation and configuration
- Xcode build phase setup
- Per-file rule overrides
- CI/CD integration examples
- Troubleshooting guide
- Best practices

**Also see CLAUDE.md** for AI-specific code quality guidance.

## Logging Framework

Edge Debug Helper uses **CocoaLumberjack** for file-based logging with user-viewable logs.

### Installation (Required)

Add CocoaLumberjack via Swift Package Manager in Xcode:
1. **File → Add Package Dependencies...**
2. URL: `https://github.com/CocoaLumberjack/CocoaLumberjack`
3. Version: **Latest** (3.8.5+)

### Usage

```swift
// Use the global Log accessor (import not needed)
Log.debug("Debug information")
Log.info("General information")
Log.warning("Non-critical issue")
Log.error("Failure or exception")

// DO NOT use print() - use Log instead
```

### Features

- ✅ **File-based**: All logs written to files automatically
- ✅ **Rotation**: Keeps last 7 days, 5MB max per file
- ✅ **User export**: Future feature for GitHub issue attachments
- ✅ **Performance**: Asynchronous, doesn't block UI
- ✅ **Location**: `~/Library/Logs/io.ditto.EdgeStudio/`

### Retrieving Logs

```swift
// Get all log files
let logFiles = Log.getAllLogFiles()

// Get combined content
let content = Log.getCombinedLogs()

// Export to location
try Log.exportLogs(to: url)
```

See **CLAUDE.md** for complete logging documentation, best practices, and future log viewer feature.

## ⚠️ DISCLAIMER

**THIS SOFTWARE IS PROVIDED "AS-IS" WITHOUT WARRANTY OF ANY KIND.**

This tool is **NOT** officially supported by Ditto or the author. It is provided as a community resource for development and debugging purposes only.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

By using this software, you acknowledge and agree that:
- There is no official support from Ditto or the author
- The software may contain bugs or incomplete features
- You use this software at your own risk
- No warranty of any kind is provided
- The authors are not liable for any damages resulting from use of this software

For official Ditto support and documentation, please visit [Ditto Documentation](https://docs.ditto.live/).


