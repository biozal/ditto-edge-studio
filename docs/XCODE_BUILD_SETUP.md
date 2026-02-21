# Xcode Build Integration - Quick Setup Guide

**Time Required:** 10 minutes
**Benefit:** Automatic code formatting and quality checks on every build

---

## Overview

This guide will help you add **SwiftFormat** and **SwiftLint** to your Xcode build process. Once configured, these tools will run automatically on every build, ensuring consistent code quality.

**What you'll get:**
- ✅ Automatic code formatting (SwiftFormat)
- ✅ Real-time violation warnings in Xcode (SwiftLint)
- ✅ No need to remember to format before committing
- ✅ Team consistency enforced automatically

### ⚠️ Important: Xcode 15+ Sandbox Configuration

**CRITICAL**: Xcode 15+ requires disabling user script sandboxing for SwiftFormat to work.

**How to Configure:**
1. Select the **Edge Debug Helper** target
2. Go to **Build Settings** tab
3. Search for: **"User Script Sandboxing"**
4. Set **ENABLE_USER_SCRIPT_SANDBOXING** to **NO**

**Why**: SwiftFormat needs write access to format source files. The sandbox prevents this.

**Status in this project:** ✅ Already configured (ENABLE_USER_SCRIPT_SANDBOXING = NO)

**Cross-Platform Note**: These scripts work on both Intel and Apple Silicon Macs by using `which` instead of hardcoded paths like `/opt/homebrew/bin/`.

---

## Step 1: Open Project in Xcode

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio
open "SwiftUI/Edge Debug Helper.xcodeproj"
```

---

## Step 2: Add SwiftFormat Build Phase

**Purpose:** Automatically formats code before compilation

1. In Xcode, select the **"Edge Debug Helper"** project (blue icon) in the navigator
2. Select the **"Edge Debug Helper"** target
3. Go to the **"Build Phases"** tab
4. Click the **"+"** button at the top left
5. Select **"New Run Script Phase"**

### Configure SwiftFormat Phase

1. **Name the phase:**
   - Double-click "Run Script" to rename it to: **SwiftFormat**

2. **Add the script:**
   Click in the script text area and paste:
   ```bash
   export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
   cd "${PROJECT_DIR}/.."

   if which swiftformat >/dev/null; then
     if [ -d "SwiftUI/Edge Debug Helper" ]; then
       swiftformat "SwiftUI/Edge Debug Helper" --config .swiftformat --quiet || true
     fi
   else
     echo "warning: SwiftFormat not installed, download from https://github.com/nicklockwood/SwiftFormat"
   fi
   ```

3. **Add Input Files:**
   - Expand **"Input Files"** section
   - Click **"+"** button
   - Add: `$(SRCROOT)/../.swiftformat`

4. **Configure Settings:**
   - ☑️ Check **"Based on dependency analysis"**
   - ☐ Uncheck **"For install builds only"** (we want it to run on all builds)

5. **Position the phase:**
   - Drag the "SwiftFormat" phase to be **right after "Dependencies"**
   - It should be **before "Compile Sources"**

---

## Step 3: Add SwiftLint Build Phase

**Purpose:** Check code quality and show violations as warnings

1. Click the **"+"** button again
2. Select **"New Run Script Phase"**

### Configure SwiftLint Phase

1. **Name the phase:**
   - Double-click "Run Script" to rename it to: **SwiftLint**

2. **Add the script:**
   Click in the script text area and paste:
   ```bash
   export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
   cd "${PROJECT_DIR}/.."

   if which swiftlint >/dev/null; then
     swiftlint lint --config .swiftlint.yml --quiet || true
   else
     echo "warning: SwiftLint not installed, download from https://github.com/realm/SwiftLint"
   fi
   ```

3. **Add Input Files:**
   - Expand **"Input Files"** section
   - Click **"+"** button
   - Add: `$(SRCROOT)/../.swiftlint.yml`

4. **Configure Settings:**
   - ☑️ Check **"Based on dependency analysis"**
   - ☐ Uncheck **"For install builds only"**

5. **Position the phase:**
   - Drag the "SwiftLint" phase to be **right after "SwiftFormat"**
   - It should be **before "Compile Sources"**

---

## Step 4: Verify Build Phase Order

Your Build Phases should now look like this:

```
1. Dependencies (built-in)
2. SwiftFormat ← Your new phase
3. SwiftLint ← Your new phase
4. Compile Sources (built-in)
5. Copy Bundle Resources (built-in)
... other phases
```

**Why this order matters:**
1. **SwiftFormat** runs first to format all code
2. **SwiftLint** runs second to check the formatted code
3. **Compile Sources** runs third to build the formatted, linted code

---

## Step 5: Test the Integration

1. **Build the project** (⌘B or Product → Build)

2. **Check the build log:**
   - Open **Report Navigator** (⌘9)
   - Click the latest build
   - Expand "Build Edge Debug Helper"
   - You should see:
     ```
     SwiftFormat
     SwiftLint
     ```

3. **Verify SwiftLint warnings appear:**
   - You should see 7 warnings for "multiple closures with trailing closure"
   - These show up as yellow warnings in the Issue Navigator (⌘5)
   - Click any warning to jump to the code

4. **Verify SwiftFormat is running:**
   - Make a formatting change (e.g., add extra spaces)
   - Build (⌘B)
   - SwiftFormat should automatically fix the formatting
   - The file will be updated with proper formatting

---

## Expected Results

### Build Output

You should see output like:
```
⚙️  SwiftFormat
Formatting 78 files...
✓ Done in 1.2 seconds

⚙️  SwiftLint
Linting Swift files...
⚠️  Found 7 violations, 0 serious
```

### In Xcode Editor

- **Yellow warnings** appear inline for SwiftLint violations
- **Click warnings** to jump to the issue
- **Code automatically formats** when you build
- **Hover over warnings** to see violation details

---

## Troubleshooting

### "SwiftFormat not installed" warning

**Solution:**
```bash
brew install swiftformat
```

Then rebuild the project.

### "SwiftLint not installed" warning

**Solution:**
```bash
brew install swiftlint
```

Then rebuild the project.

### Build phase doesn't run

**Check:**
1. Is the phase enabled? (checkbox on left should be checked)
2. Is it positioned before "Compile Sources"?
3. Does the script have execute permissions? (should be automatic)
4. Check Build Log for output (⌘9 → select build → expand)

### No warnings appear in Xcode

**Check:**
1. SwiftLint is running (check build log)
2. .swiftlint.yml config file exists in project root
3. Issue Navigator is open (⌘5)
4. Build was successful (errors prevent warnings from showing)

### SwiftFormat changes files unexpectedly

**This is normal behavior!** SwiftFormat is designed to automatically format your code. If you don't like a formatting change:

1. Update `.swiftformat` configuration
2. Rebuild to reformat all files
3. See [CODE_QUALITY_GUIDE.md](CODE_QUALITY_GUIDE.md#swiftformat) for options

### Builds are slower

**Expected:** Build times increase by 2-5 seconds
- SwiftFormat: ~1-2 seconds
- SwiftLint: ~1-3 seconds

**To speed up:**
- Enable "Based on dependency analysis" (already done)
- Both tools only run on changed files in incremental builds

---

## Advanced Configuration

### Disable for Specific Build Configurations

If you want to skip formatting/linting for Debug builds:

1. Edit build phase script to check configuration:
   ```bash
   # Only run in Release builds
   if [ "${CONFIGURATION}" = "Release" ]; then
     if which swiftformat >/dev/null; then
       swiftformat "${PROJECT_DIR}/.." --config "${PROJECT_DIR}/../.swiftformat"
     fi
   fi
   ```

### Treat Warnings as Errors

To fail builds on SwiftLint violations:

**Option 1:** Add to SwiftLint script
```bash
swiftlint lint --config "${PROJECT_DIR}/../.swiftlint.yml" --strict
```

**Option 2:** Xcode build settings
1. Target → Build Settings
2. Search: "Treat Warnings as Errors"
3. Set to: **Yes**

### Custom Rules Per Target

To use different rules for tests:

1. Create `.swiftlint-tests.yml` in project root
2. Modify SwiftLint script:
   ```bash
   if [[ "${TARGET_NAME}" == *"Tests" ]]; then
     CONFIG_FILE="${PROJECT_DIR}/../.swiftlint-tests.yml"
   else
     CONFIG_FILE="${PROJECT_DIR}/../.swiftlint.yml"
   fi

   swiftlint lint --config "${CONFIG_FILE}"
   ```

---

## Verification Checklist

After setup, verify everything works:

- [ ] SwiftFormat phase appears in Build Phases
- [ ] SwiftLint phase appears in Build Phases
- [ ] Both phases are positioned before "Compile Sources"
- [ ] Both phases have Input Files configured
- [ ] Both phases have "Based on dependency analysis" checked
- [ ] Project builds successfully (⌘B)
- [ ] SwiftFormat output appears in build log
- [ ] SwiftLint output appears in build log
- [ ] 7 SwiftLint warnings appear in Issue Navigator (⌘5)
- [ ] Can click warnings to jump to code
- [ ] Code automatically formats when building

---

## Next Steps

Once build integration is working:

1. **Review remaining violations:**
   - Open Issue Navigator (⌘5)
   - Address or suppress style preference warnings as needed

2. **Configure team settings:**
   - Commit `.swiftlint.yml` and `.swiftformat` to git
   - Ensure all team members have tools installed
   - Document any team-specific rule customizations

3. **Set up git hooks (optional):**
   - See [CODE_QUALITY_GUIDE.md](CODE_QUALITY_GUIDE.md#cicd-integration)
   - Adds pre-commit quality checks

4. **Run Periphery weekly:**
   ```bash
   periphery scan --project "SwiftUI/Edge Debug Helper.xcodeproj" \
                  --schemes "Edge Studio"
   ```

---

## Summary

**You've successfully integrated code quality tools into Xcode!**

✅ **SwiftFormat** automatically formats code on every build
✅ **SwiftLint** shows violations as warnings in Xcode
✅ No manual formatting needed before commits
✅ Team consistency enforced automatically

**Build times:** Expect 2-5 second increase per build (worth it for automatic quality!)

For complete documentation, see [docs/CODE_QUALITY_GUIDE.md](CODE_QUALITY_GUIDE.md)

---

**Setup Time:** 10 minutes
**Maintenance:** Zero (runs automatically)
**Benefit:** Consistent, high-quality code on every build! 🚀
