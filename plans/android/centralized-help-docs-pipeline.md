# Centralized Help Documentation Build Pipeline — Plan

## Overview

The six help documentation `.md` files currently exist in two separate places with diverging content:
- **SwiftUI:** `SwiftUI/EdgeStudio/Resources/Help/` — production-quality, authoritative
- **dotnet:** `dotnet/src/EdgeStudio/Assets/Help/` — stub/preview content, out of date

The Android app has no help files at all.

This plan establishes **`docs/help/`** at the repo root as the single source of truth, and adds build-time copy steps to all three platforms so they each automatically get the latest documentation on every build.

---

## Target State

```
docs/help/                         ← Single source of truth (git-tracked)
    query.md
    subscription.md
    logging.md
    observe.md
    appmetrics.md
    querymetrics.md

scripts/
    sync-help-docs.sh              ← Manual sync helper (optional, developer convenience)

SwiftUI/EdgeStudio/Resources/Help/ ← Generated at Xcode build time (gitignored)
    query.md
    subscription.md
    logging.md
    observe.md
    appmetrics.md
    querymetrics.md

dotnet/src/EdgeStudio/Assets/Help/ ← Generated at dotnet build time (gitignored)
    query.md
    subscription.md
    logging.md
    observe.md
    appmetrics.md
    querymetrics.md

android/app/src/main/assets/help/  ← Generated at Gradle build time (gitignored)
    query.md
    subscription.md
    logging.md
    observe.md
    appmetrics.md
    querymetrics.md
```

---

## The Six Help Files

| File | Description | Lines (current) |
|------|-------------|----------------|
| `query.md` | DQL reference, indexes, execution modes, Inspector features | 124 |
| `subscription.md` | Subscriptions, Peers List, Presence Viewer, transport config | 52 |
| `logging.md` | SDK log levels, log viewer, log files, import/export | 112 |
| `observe.md` | Observer concepts, adding/activating, reading events | 47 |
| `appmetrics.md` | Process resources, storage breakdown, collection sizes | 68 |
| `querymetrics.md` | EXPLAIN analysis, Prometheus export, execution time | 66 |

---

## Phase 1 — Create Central Location

### Step 1.1 — Create `docs/help/` directory

Create the directory and move the authoritative SwiftUI `.md` files there:

```bash
mkdir -p docs/help
cp SwiftUI/EdgeStudio/Resources/Help/query.md       docs/help/
cp SwiftUI/EdgeStudio/Resources/Help/subscription.md docs/help/
cp SwiftUI/EdgeStudio/Resources/Help/logging.md      docs/help/
cp SwiftUI/EdgeStudio/Resources/Help/observe.md      docs/help/
cp SwiftUI/EdgeStudio/Resources/Help/appmetrics.md   docs/help/
cp SwiftUI/EdgeStudio/Resources/Help/querymetrics.md docs/help/
```

These files become the canonical versions. The original SwiftUI copies will be overwritten by the build pipeline going forward.

### Step 1.2 — Add platform copies to `.gitignore`

Add to the **repo-root `.gitignore`** (create or update):
```
# Help docs — generated at build time from docs/help/
SwiftUI/EdgeStudio/Resources/Help/*.md
dotnet/src/EdgeStudio/Assets/Help/*.md
android/app/src/main/assets/help/
```

> **Developer note:** After adding to `.gitignore`, run `git rm --cached` on the existing tracked files to untrack them. New developers will have the files generated on first build.

### Step 1.3 — Create `scripts/sync-help-docs.sh`

A convenience script for developers who want to manually sync (useful before running Xcode without a full build):

```bash
#!/usr/bin/env bash
# Copies docs/help/*.md to all platform asset locations.
# Run from the repo root: ./scripts/sync-help-docs.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/docs/help"

echo "Syncing help docs from $SRC"

# SwiftUI
SWIFT_DEST="$REPO_ROOT/SwiftUI/EdgeStudio/Resources/Help"
mkdir -p "$SWIFT_DEST"
cp "$SRC"/*.md "$SWIFT_DEST/"
echo "  ✓ SwiftUI: $SWIFT_DEST"

# dotnet
DOTNET_DEST="$REPO_ROOT/dotnet/src/EdgeStudio/Assets/Help"
mkdir -p "$DOTNET_DEST"
cp "$SRC"/*.md "$DOTNET_DEST/"
echo "  ✓ dotnet:  $DOTNET_DEST"

# Android
ANDROID_DEST="$REPO_ROOT/android/app/src/main/assets/help"
mkdir -p "$ANDROID_DEST"
cp "$SRC"/*.md "$ANDROID_DEST/"
echo "  ✓ Android: $ANDROID_DEST"

echo "Done."
```

Make executable: `chmod +x scripts/sync-help-docs.sh`

---

## Phase 2 — Android Gradle Copy Task

### `android/app/build.gradle.kts`

Add a copy task that runs before `preBuild`:

```kotlin
val syncHelpDocs by tasks.registering(Copy::class) {
    description = "Copies help markdown files from docs/help/ into assets/help/"
    from(rootProject.file("../../docs/help"))
    into(layout.projectDirectory.dir("src/main/assets/help"))
    include("*.md")
}

tasks.named("preBuild") {
    dependsOn(syncHelpDocs)
}
```

> **Important:** `rootProject.file("../../docs/help")` assumes the Gradle root is `android/` (which it is — `android/settings.gradle.kts` is the root). The path `../../docs/help` goes from `android/` → `../` (repo root) → `docs/help`. Verify with `println(rootProject.projectDir)` if needed.

**Also register the assets directory** (defensive, ensures Gradle knows about it):

```kotlin
android {
    // ...existing config...
    sourceSets {
        getByName("main") {
            assets.srcDirs("src/main/assets")
        }
    }
}
```

> The `assets/help/` directory will be created by the copy task if it doesn't exist.

---

## Phase 3 — SwiftUI Xcode Build Phase

### Add a "Run Script" build phase to Xcode

In Xcode, navigate to the **Edge Studio** target → **Build Phases** → add a **New Run Script Phase** named "Sync Help Docs".

**Script content:**
```bash
#!/bin/bash
# Copies docs/help/*.md from repo root into Resources/Help/ before compilation.

set -e
REPO_ROOT="$(cd "$SRCROOT/../.." && pwd)"
SRC="$REPO_ROOT/docs/help"
DEST="$SRCROOT/EdgeStudio/Resources/Help"

if [ ! -d "$SRC" ]; then
    echo "warning: docs/help/ not found at $SRC — skipping help doc sync"
    exit 0
fi

mkdir -p "$DEST"
cp "$SRC"/*.md "$DEST/"
echo "note: Help docs synced from $SRC to $DEST"
```

**Phase ordering:** Drag this phase to run **before** "Copy Bundle Resources" so the files exist when Xcode tries to bundle them.

**Input files** (optional, for incremental build optimization):
```
$(SRCROOT)/../../docs/help/query.md
$(SRCROOT)/../../docs/help/subscription.md
$(SRCROOT)/../../docs/help/logging.md
$(SRCROOT)/../../docs/help/observe.md
$(SRCROOT)/../../docs/help/appmetrics.md
$(SRCROOT)/../../docs/help/querymetrics.md
```

**Output files:**
```
$(SRCROOT)/EdgeStudio/Resources/Help/query.md
$(SRCROOT)/EdgeStudio/Resources/Help/subscription.md
$(SRCROOT)/EdgeStudio/Resources/Help/logging.md
$(SRCROOT)/EdgeStudio/Resources/Help/observe.md
$(SRCROOT)/EdgeStudio/Resources/Help/appmetrics.md
$(SRCROOT)/EdgeStudio/Resources/Help/querymetrics.md
```

Declaring input/output files allows Xcode to skip this phase when the sources haven't changed (incremental builds).

> **Xcode project file:** The `.md` files are currently referenced in `project.pbxproj` as tracked files. After gitignoring them, run `./scripts/sync-help-docs.sh` once to populate them, then build. Xcode will continue to reference them correctly — they just won't be in git.

---

## Phase 4 — dotnet MSBuild BeforeBuild Target

### `dotnet/src/EdgeStudio/EdgeStudio.csproj`

Add an `ItemGroup` to include help files and a `BeforeBuild` target that copies from the central location:

```xml
<!-- Help docs are generated — copy from docs/help/ at build time -->
<Target Name="SyncHelpDocs" BeforeTargets="Build">
  <PropertyGroup>
    <HelpDocsSource>$(MSBuildProjectDirectory)\..\..\..\docs\help\</HelpDocsSource>
    <HelpDocsDest>$(MSBuildProjectDirectory)\Assets\Help\</HelpDocsDest>
  </PropertyGroup>
  <MakeDir Directories="$(HelpDocsDest)" Condition="!Exists('$(HelpDocsDest)')" />
  <Copy
    SourceFiles="$(HelpDocsSource)query.md;$(HelpDocsSource)subscription.md;$(HelpDocsSource)logging.md;$(HelpDocsSource)observe.md;$(HelpDocsSource)appmetrics.md;$(HelpDocsSource)querymetrics.md"
    DestinationFolder="$(HelpDocsDest)"
    SkipUnchangedFiles="true"
  />
  <Message Text="Help docs synced to $(HelpDocsDest)" Importance="normal" />
</Target>
```

**Also update the `<Content>` itemgroup** to include the generated files as content (so they're bundled in the output):

```xml
<ItemGroup>
  <AvaloniaResource Include="Assets\Help\*.md" />
</ItemGroup>
```

> dotnet/Avalonia uses `AvaloniaResource` for assets bundled with the app. Verify the existing project uses this include pattern (check how `Assets/Help/logging-help.md` etc. are currently included).

---

## Phase 5 — dotnet Content File Consolidation

The dotnet app currently has `.md` files with different names (`logging-help.md`, `query-help.md`, etc.) that are **stub/preview content**. The new pipeline copies the production-quality SwiftUI `.md` files (with standard names like `logging.md`, `query.md`).

### Update dotnet code that reads these files

Any dotnet code that currently reads `logging-help.md`, `query-help.md`, etc. must be updated to read `logging.md`, `query.md`, etc.

Search in dotnet code for asset loading patterns and update file names:
- `logging-help.md` → `logging.md`
- `query-help.md` → `query.md`
- `subscriptions-help.md` → `subscription.md`
- `observers-help.md` → `observe.md`
- `app-metrics-help.md` → `appmetrics.md`
- `query-metrics-help.md` → `querymetrics.md`

The old stub files (`*-help.md`) can be removed once the code is updated.

---

## Phase 6 — CI/CD Integration

For any CI pipeline (GitHub Actions, etc.), add the sync step before each platform build:

```yaml
# For all three platforms (or per-platform job):
- name: Sync help docs
  run: chmod +x scripts/sync-help-docs.sh && ./scripts/sync-help-docs.sh

# Android builds already handle it via Gradle task — sync script is optional redundancy
# Xcode builds need the Run Script phase (step 3) — no explicit CI step needed if in Xcode
# dotnet builds handle it via MSBuild BeforeBuild target — no explicit CI step needed
```

---

## New Files Summary

| File | Purpose |
|------|---------|
| `docs/help/query.md` | Central source of truth (moved from SwiftUI) |
| `docs/help/subscription.md` | Central source of truth |
| `docs/help/logging.md` | Central source of truth |
| `docs/help/observe.md` | Central source of truth |
| `docs/help/appmetrics.md` | Central source of truth |
| `docs/help/querymetrics.md` | Central source of truth |
| `scripts/sync-help-docs.sh` | Developer convenience sync script |

## Modified Files Summary

| File | Change |
|------|--------|
| `.gitignore` (repo root) | Ignore the platform-specific copies of help docs |
| `android/app/build.gradle.kts` | Add `syncHelpDocs` copy task + `sourceSets` assets config |
| `dotnet/src/EdgeStudio/EdgeStudio.csproj` | Add `SyncHelpDocs` MSBuild target + `AvaloniaResource` include |
| `SwiftUI/Edge Debug Helper.xcodeproj` | Add "Sync Help Docs" Run Script build phase |
| dotnet source files | Update asset file name references (`*-help.md` → `*.md`) |

---

## Implementation Order

1. Create `docs/help/` and copy the 6 SwiftUI `.md` files there
2. Create `scripts/sync-help-docs.sh` and make it executable
3. Update `.gitignore` at repo root
4. **Android:** Add Gradle copy task to `build.gradle.kts`
5. **SwiftUI:** Add Xcode Run Script build phase
6. **dotnet:** Add MSBuild `SyncHelpDocs` target to `.csproj`
7. Update dotnet code that references old `*-help.md` filenames
8. Untrack old files from git: `git rm --cached SwiftUI/EdgeStudio/Resources/Help/*.md dotnet/src/EdgeStudio/Assets/Help/*.md`
9. Run `./scripts/sync-help-docs.sh` to populate all platform locations
10. Build all three platforms and verify help files are bundled

---

## Verification

### Android
```bash
cd android && ./gradlew assembleDebug
# Verify files were copied:
ls android/app/src/main/assets/help/
```

### SwiftUI
- Build in Xcode → check Build Log for "Help docs synced" message
- Verify `SwiftUI/EdgeStudio/Resources/Help/*.md` are present before linking step

### dotnet
```bash
cd dotnet && dotnet build
# Verify files in output:
ls dotnet/src/EdgeStudio/bin/Debug/*/Assets/Help/
```

### Content validation
- All six `.md` files are identical across all three platform locations
- The content matches `docs/help/*.md`

---

## Developer Workflow After This Change

```
# After clone:
./scripts/sync-help-docs.sh     # populates all platform asset folders

# During development (editing docs):
# 1. Edit the file in docs/help/
# 2. Run sync script OR just build — each platform's build copies automatically
# 3. Commit the docs/help/ change

# To verify which version is deployed:
git log -- docs/help/query.md   # source history
```

---

## Notes on Edge Cases

**First-time build after clone:**
The `docs/help/` files exist in git. Each platform's build system copies them automatically on the first build. No manual step required for CI or fresh developer setup.

**Content that is platform-specific:**
Some help text references macOS-specific paths (`~/Library/Application Support/...`, `Finder`, `iPadOS swipe left`). These are acceptable for now — the docs describe the SwiftUI version's behavior. Future work can add platform-specific sections to each doc file if needed.

**Adding a new help file:**
1. Add the file to `docs/help/`
2. Add it to the Xcode "Input files" and "Output files" declarations
3. Add it to the dotnet `<Copy SourceFiles="...">` list
4. The Android Gradle task uses `include("*.md")` so it picks up new files automatically
