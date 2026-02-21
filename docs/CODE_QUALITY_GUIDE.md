# Code Quality Tools Guide

**Last Updated:** 2026-02-16

This guide covers all code quality tools configured for the Edge Debug Helper project, including installation, configuration, Xcode integration, and best practices.

---

## Table of Contents

1. [Overview](#overview)
2. [Tools Summary](#tools-summary)
3. [SwiftLint](#swiftlint)
4. [SwiftFormat](#swiftformat)
5. [Periphery](#periphery)
6. [Xcode Integration](#xcode-integration)
7. [Configuration Files](#configuration-files)
8. [Per-File Overrides](#per-file-overrides)
9. [CI/CD Integration](#cicd-integration)
10. [Best Practices](#best-practices)
11. [Troubleshooting](#troubleshooting)

---

## Overview

The project uses three main code quality tools:

| Tool | Purpose | When to Run |
|------|---------|-------------|
| **SwiftLint** | Style & quality rules | Every build (auto) |
| **SwiftFormat** | Auto-formatting | Before commit (manual) |
| **Periphery** | Unused code detection | Weekly/before release |

---

## Tools Summary

### SwiftLint
- **Purpose:** Enforce Swift style and conventions
- **Speed:** Fast (2-5 seconds)
- **Integration:** Xcode build phase
- **Configuration:** `.swiftlint.yml`
- **Actions:** Reports warnings/errors

### SwiftFormat
- **Purpose:** Automatically format code
- **Speed:** Fast (1-3 seconds)
- **Integration:** Manual or git hook
- **Configuration:** `.swiftformat`
- **Actions:** Modifies files

### Periphery
- **Purpose:** Find unused code
- **Speed:** Slow (30-60 seconds)
- **Integration:** Manual only
- **Configuration:** `.periphery.yml`
- **Actions:** Reports unused code

---

## SwiftLint

### Installation

```bash
brew install swiftlint
```

**Verify installation:**
```bash
swiftlint version
# Expected: 0.63.2 or later
```

### Basic Usage

```bash
# Lint all Swift files
swiftlint lint

# Auto-fix violations where possible
swiftlint lint --fix

# Lint specific file
swiftlint lint --path SwiftUI/Edge\ Debug\ Helper/Views/ContentView.swift

# Show only errors (no warnings)
swiftlint lint --strict

# Generate report
swiftlint lint --reporter json > swiftlint_report.json
```

### Cross-Platform Compatibility

**Intel vs Apple Silicon Macs**

Homebrew installs to different locations:
- **Apple Silicon (M1/M2/M3)**: `/opt/homebrew/bin/`
- **Intel (x86_64)**: `/usr/local/bin/`

**Best Practice**: Use `which swiftformat` instead of hardcoded paths.

**Build Script Pattern**:
```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if which swiftformat >/dev/null; then
  swiftformat .
else
  echo "warning: SwiftFormat not installed"
fi
```

**Why**: PATH-based lookup works on both architectures. Hardcoded paths fail on the other platform.

### Xcode Integration (Recommended)

#### Sandbox Configuration (Xcode 15+)

**CRITICAL for SwiftFormat**: Xcode 15+ introduced User Script Sandboxing which prevents build scripts from modifying source files.

**Required Setting:**
```
ENABLE_USER_SCRIPT_SANDBOXING = NO
```

**How to Set:**
1. Select target in Xcode
2. Build Settings tab
3. Search: "User Script Sandboxing"
4. Change to: **NO**

**Impact**: Without this setting, SwiftFormat cannot format files during builds. Errors are silently hidden if scripts use `2>/dev/null`.

**Security Note**: Disabling sandbox is safe for trusted build scripts. SwiftFormat/SwiftLint are open-source, widely-used tools.

#### Add SwiftLint to Build Process

1. Open project in Xcode
2. Select **Edge Debug Helper** project → **Edge Debug Helper** target
3. Go to **Build Phases** tab
4. Click **"+"** → **"New Run Script Phase"**
5. Name it **"SwiftLint"** (drag to top, after Dependencies)
6. Add this script:

```bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "${PROJECT_DIR}/.."

if which swiftlint >/dev/null; then
  swiftlint lint --config .swiftlint.yml --quiet || true
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

7. **Input Files:** Add `$(SRCROOT)/../.swiftlint.yml`
8. Check **"Based on dependency analysis"** for faster builds
9. Build project (⌘B) - violations now appear as Xcode warnings!

**Benefits:**
- ✅ Real-time feedback in Xcode editor
- ✅ Violations show as warnings/errors
- ✅ Click to jump to issue
- ✅ Runs automatically on every build

### Configuration

Edit `.swiftlint.yml` in project root:

```yaml
# Enable/disable rules
disabled_rules:
  - line_length          # Allow long lines
  - identifier_name      # Allow short variable names

opt_in_rules:
  - empty_count          # Prefer isEmpty over count == 0
  - unused_import        # Remove unused imports

# Customize rule parameters
line_length:
  warning: 150
  error: 200

# Exclude paths
excluded:
  - Pods
  - DerivedData
  - .build
```

### Common Rules

| Rule | Description | Autofix |
|------|-------------|---------|
| `force_unwrapping` | Avoid `!` force unwraps | ❌ |
| `unused_optional_binding` | Use `!= nil` instead of `let _ =` | ✅ |
| `trailing_whitespace` | Remove trailing spaces | ✅ |
| `unused_import` | Remove unused imports | ✅ |
| `redundant_optional_initialization` | Remove `= nil` for optionals | ✅ |

### Per-File Rule Overrides

**Disable rule for entire file:**
```swift
// swiftlint:disable force_unwrapping
class MyClass {
    let value = dict["key"]!  // Allowed
}
// swiftlint:enable force_unwrapping
```

**Disable rule for single line:**
```swift
let value = dict["key"]! // swiftlint:disable:this force_unwrapping
```

**Disable multiple rules:**
```swift
// swiftlint:disable force_unwrapping force_cast
let value = dict["key"]! as! String
// swiftlint:enable force_unwrapping force_cast
```

**Disable next line:**
```swift
// swiftlint:disable:next force_unwrapping
let value = dict["key"]!
```

### Treating Warnings as Errors

**Option 1: SwiftLint config**
```yaml
# .swiftlint.yml
strict: true  # Treat all violations as errors
```

**Option 2: Xcode build settings**
1. Target → Build Settings
2. Search for "Treat Warnings as Errors"
3. Set to **"Yes"**

**Option 3: Specific rules only**
```yaml
# .swiftlint.yml
force_unwrapping:
  severity: error  # This rule fails builds
```

---

## SwiftFormat

### Installation

```bash
brew install swiftformat
```

**Verify:**
```bash
swiftformat --version
# Expected: 0.59.1 or later
```

### Basic Usage

```bash
# Format entire project
swiftformat .

# Format specific directory
swiftformat SwiftUI/Edge\ Debug\ Helper/

# Preview changes without modifying
swiftformat --dryrun .

# Format and show which files changed
swiftformat --verbose .
```

### Configuration

Edit `.swiftformat` in project root:

```
# Indentation
--indent 4
--tabwidth 4
--indentcase false

# Spacing
--trimwhitespace always
--insertlines enabled
--removelines enabled

# Wrapping
--maxwidth 150
--wraparguments before-first
--wrapcollections before-first

# Organization
--importgrouping testable-bottom
--stripunusedargs closure-only

# Excluded files
--exclude Pods,DerivedData,.build
```

### Xcode Integration (Recommended)

**Add SwiftFormat to Build Process:**

SwiftFormat should run as part of your build to ensure consistent formatting automatically.

1. Open project in Xcode
2. Select **Edge Debug Helper** project → **Edge Debug Helper** target
3. Go to **Build Phases** tab
4. Click **"+"** → **"New Run Script Phase"**
5. Name it **"SwiftFormat"** (place after SwiftLint)
6. Add script:

```bash
# Run SwiftFormat if installed
if which swiftformat >/dev/null; then
  swiftformat "${PROJECT_DIR}/.." --config "${PROJECT_DIR}/../.swiftformat"
else
  echo "warning: SwiftFormat not installed, download from https://github.com/nicklockwood/SwiftFormat"
fi
```

7. **Input Files:** Add `$(SRCROOT)/../.swiftformat`
8. Check **"Based on dependency analysis"** for faster builds

**Benefits:**
- ✅ Automatic formatting on every build
- ✅ No need to remember to format before committing
- ✅ Team consistency enforced automatically
- ✅ Files are always properly formatted

**Note:** SwiftFormat modifies your source files during the build. This is intentional and ensures all code follows the same style guidelines.

### Common Formatting Options

| Option | Description | Default |
|--------|-------------|---------|
| `--indent` | Spaces per indent | 4 |
| `--maxwidth` | Max line length | 150 |
| `--wraparguments` | How to wrap function args | `preserve` |
| `--stripunusedargs` | Remove unused closure args | `closure-only` |
| `--importgrouping` | Group imports | `alphabetized` |

---

## Periphery

### Installation

```bash
brew install peripheryapp/periphery/periphery
```

**Verify:**
```bash
periphery version
# Expected: 2.21.2 or later
```

### Basic Usage

```bash
# Scan for unused code
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --format xcode

# Save to file
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --format json > periphery_report.json

# Scan specific targets only
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio" \
               --targets "Edge Debug Helper"
```

### Configuration

Edit `.periphery.yml` in project root:

```yaml
project: SwiftUI/Edge Debug Helper.xcodeproj
schemes:
  - Edge Studio
targets:
  - Edge Debug Helper

# Skip test files
report_exclude:
  - ".*Tests\\.swift$"
  - ".*UITests\\.swift$"

# Skip generated code
  - ".*\\.generated\\.swift$"
```

### When to Run Periphery

- ✅ **Weekly** - Regular maintenance
- ✅ **Before major releases** - Clean up before shipping
- ✅ **After large refactors** - Find newly unused code
- ❌ **Not on every build** - Too slow (30-60 seconds)

### Understanding Results

**Periphery finds:**
- Unused classes, structs, enums
- Unused functions, methods, properties
- Unused parameters
- Unused imports

**Example output:**
```
warning: Class 'OldViewModel' is unused
  --> SwiftUI/Edge Debug Helper/ViewModels/OldViewModel.swift:10:7
```

### False Positives

Periphery may report false positives for:
- `@IBOutlet` and `@IBAction` (used by Interface Builder)
- SwiftUI views (used by reflection)
- Protocol methods (used by conformance)

**Suppress false positives:**
```swift
// periphery:ignore
class IntentionallyUnusedClass {
    // Used by dependency injection
}
```

---

## Xcode Integration

### Build Phase Order

Recommended order for Run Script phases:

1. **Dependencies** (built-in)
2. **SwiftFormat** ← Run first (formats code before compilation)
3. **SwiftLint** ← Run second (check formatted code for violations)
4. **Compile Sources** (built-in)
5. **Copy Bundle Resources** (built-in)

**Why this order:**
- SwiftFormat runs first to ensure consistent formatting
- SwiftLint runs second to check the formatted code
- Both run before compilation to catch issues early

### Build Phase Scripts

#### 1. SwiftFormat Phase (Run First)

**Name:** SwiftFormat
**Script:**
```bash
# Run SwiftFormat if installed
if which swiftformat >/dev/null; then
  swiftformat "${PROJECT_DIR}/.." --config "${PROJECT_DIR}/../.swiftformat"
else
  echo "warning: SwiftFormat not installed, download from https://github.com/nicklockwood/SwiftFormat"
fi
```

**Input Files:**
```
$(SRCROOT)/../.swiftformat
```

**Settings:**
- ☑️ Based on dependency analysis
- ☐ For install builds only (run on all builds)

#### 2. SwiftLint Phase (Run Second)

**Name:** SwiftLint
**Script:**
```bash
# Run SwiftLint if installed
if which swiftlint >/dev/null; then
  swiftlint lint --config "${PROJECT_DIR}/../.swiftlint.yml"
else
  echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
fi
```

**Input Files:**
```
$(SRCROOT)/../.swiftlint.yml
```

**Settings:**
- ☑️ Based on dependency analysis
- ☐ For install builds only (run on all builds)

### Xcode Warnings as Errors

**Enable globally:**
1. Target → Build Settings
2. Search: "Treat Warnings as Errors"
3. Set to **"Yes"**

**Enable for specific configurations:**
- Debug: No (faster iteration)
- Release: Yes (ship quality code)

---

## Configuration Files

### .swiftlint.yml

Located at: `/path/to/project/.swiftlint.yml`

**Key sections:**
```yaml
# Disabled rules (turned off)
disabled_rules:
  - line_length
  - identifier_name

# Opt-in rules (explicitly enabled)
opt_in_rules:
  - empty_count
  - unused_import

# Analyzer rules (require compilation)
analyzer_rules:
  - unused_declaration

# Custom rule parameters
line_length:
  warning: 150
  error: 200

# Excluded paths
excluded:
  - Pods
  - DerivedData

# Included paths (if not all files)
included:
  - SwiftUI/Edge Debug Helper
```

### .swiftformat

Located at: `/path/to/project/.swiftformat`

**Key options:**
```
# Indentation
--indent 4
--tabwidth 4

# Line wrapping
--maxwidth 150
--wraparguments before-first

# Organization
--importgrouping testable-bottom
--stripunusedargs closure-only

# Excluded
--exclude Pods,DerivedData
```

### .periphery.yml

Located at: `/path/to/project/.periphery.yml`

**Key settings:**
```yaml
project: SwiftUI/Edge Debug Helper.xcodeproj
schemes:
  - Edge Studio

targets:
  - Edge Debug Helper

report_exclude:
  - ".*Tests\\.swift$"
```

---

## Per-File Overrides

### SwiftLint Per-File Rules

**Disable specific rule for entire file:**
```swift
// swiftlint:disable force_cast

class MyClass {
    let value = object as! String  // Allowed in this file
}
```

**Disable multiple rules:**
```swift
// swiftlint:disable force_cast force_unwrapping

class MyClass {
    let value1 = object as! String
    let value2 = dict["key"]!
}
```

**Disable for code block:**
```swift
// swiftlint:disable force_unwrapping
func legacyMethod() {
    let value = dict["key"]!  // OK
}
// swiftlint:enable force_unwrapping

func newMethod() {
    let value = dict["key"]  // Must handle optional
}
```

### SwiftFormat Per-File Rules

**Disable formatting for file:**
```swift
// swiftformat:disable all

class UnformattedClass {
    var weirdSpacing    =     "preserved"
}
```

**Disable specific rules:**
```swift
// swiftformat:disable wrap
func methodWithLongParameterList(param1: String, param2: Int, param3: Bool, param4: Double) {
    // Line won't be wrapped
}
// swiftformat:enable wrap
```

---

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Code Quality

on: [push, pull_request]

jobs:
  swiftlint:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install SwiftLint
        run: brew install swiftlint
      - name: Run SwiftLint
        run: swiftlint lint --strict

  swiftformat:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install SwiftFormat
        run: brew install swiftformat
      - name: Check formatting
        run: swiftformat --lint .

  periphery:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Periphery
        run: brew install peripheryapp/periphery/periphery
      - name: Scan for unused code
        run: |
          periphery scan \
            --project "SwiftUI/Edge Debug Helper.xcodeproj" \
            --schemes "Edge Studio" \
            --format github-actions
```

### Git Pre-commit Hook

Create `.git/hooks/pre-commit`:

```bash
#!/bin/bash

echo "Running SwiftLint..."
swiftlint lint --strict
if [ $? -ne 0 ]; then
    echo "❌ SwiftLint failed. Fix violations before committing."
    exit 1
fi

echo "Running SwiftFormat..."
swiftformat --lint .
if [ $? -ne 0 ]; then
    echo "⚠️  Code needs formatting. Run: swiftformat ."
    echo "Do you want to format and continue? (y/n)"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        swiftformat .
        git add -u
    else
        exit 1
    fi
fi

echo "✅ All checks passed!"
```

**Make executable:**
```bash
chmod +x .git/hooks/pre-commit
```

---

## Best Practices

### Daily Development

1. **Every Build** (automatic)
   - SwiftLint runs via Xcode build phase
   - Fix violations as you code

2. **Before Committing** (manual)
   ```bash
   # Format code
   swiftformat .

   # Check for violations
   swiftlint lint --strict

   # Stage changes
   git add -u
   git commit
   ```

### Weekly Maintenance

```bash
# Check for unused code
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio"

# Review and remove unused code
# Update .periphery.yml if false positives
```

### Before Releases

```bash
# Full quality check
swiftlint lint --strict
swiftformat --lint .
periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
               --schemes "Edge Studio"

# Fix all violations
swiftlint lint --fix
swiftformat .

# Verify build
xcodebuild -project "SwiftUI/Edge Debug Helper.xcodeproj" \
           -scheme "Edge Studio" \
           -destination "platform=macOS,arch=arm64" \
           clean build
```

### Team Conventions

1. **SwiftLint** - Everyone must pass (zero violations)
2. **SwiftFormat** - Run before committing
3. **Periphery** - Review weekly, fix before releases
4. **Xcode Warnings** - Treat as errors in Release builds

---

## Troubleshooting

### SwiftLint Issues

**"SwiftLint not found" during build**
```bash
# Install SwiftLint
brew install swiftlint

# Verify installation
which swiftlint
# Should output: /opt/homebrew/bin/swiftlint
```

**"Configuration file not found"**
- Check `.swiftlint.yml` exists in project root
- Verify path in build script: `--config "${PROJECT_DIR}/../.swiftlint.yml"`

**"Too many violations"**
```bash
# Fix automatically where possible
swiftlint lint --fix

# Disable problematic rules temporarily
# Edit .swiftlint.yml and add to disabled_rules
```

**Build phase runs but no warnings appear**
- Check build phase order (should be before Compile Sources)
- Check "Show environment variables in build log"
- Look for SwiftLint output in Build Log

### SwiftFormat Issues

**"Formatting breaks code"**
```bash
# Preview changes first
swiftformat --dryrun .

# Format incrementally
swiftformat SwiftUI/Edge\ Debug\ Helper/Views/
swiftformat SwiftUI/Edge\ Debug\ Helper/Models/
```

**"Formatting conflicts with team style"**
- Update `.swiftformat` configuration
- Run on entire codebase: `swiftformat .`
- Commit formatting changes separately

### Periphery Issues

**"False positives"**
```swift
// Add ignore comments
// periphery:ignore
class IntentionallyUnused {
}
```

**"Scan takes too long"**
- Scan specific targets only
- Use `--skip-build` if project already built
- Exclude test targets from `.periphery.yml`

**"Xcode build errors"**
- Ensure project builds successfully first
- Check scheme is shared (needed for command line builds)
- Try cleaning derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`

---

## Quick Reference

### Commands

```bash
# SwiftLint
swiftlint lint              # Check violations
swiftlint lint --fix        # Auto-fix
swiftlint lint --strict     # Fail on warnings

# SwiftFormat
swiftformat .               # Format all files
swiftformat --dryrun .      # Preview changes
swiftformat --lint .        # Check only

# Periphery
periphery scan \
  --project "SwiftUI/Edge Debug Helper.xcodeproj" \
  --schemes "Edge Studio"
```

### Files

- `.swiftlint.yml` - SwiftLint rules
- `.swiftformat` - SwiftFormat options
- `.periphery.yml` - Periphery config

### Links

- [SwiftLint Rules](https://realm.github.io/SwiftLint/rule-directory.html)
- [SwiftFormat Options](https://github.com/nicklockwood/SwiftFormat#options)
- [Periphery Docs](https://github.com/peripheryapp/periphery)

---

## Summary

**Integrated into builds:**
- ✅ SwiftLint (Xcode build phase)

**Run manually:**
- SwiftFormat (before committing)
- Periphery (weekly/before releases)

**Configuration:**
- All tools configured via dotfiles in project root
- Per-file overrides supported
- CI/CD ready

**Support:**
- Full documentation in README.md and CLAUDE.md
- Configuration files committed to repo
- Team conventions established

---

**Last Updated:** 2026-02-16
**Tools Versions:** SwiftLint 0.63.2, SwiftFormat 0.59.1, Periphery 2.21.2
