#!/usr/bin/env bash
# sync-help-docs.sh
# Copies docs/help/*.md to all platform asset locations.
# Run from the repo root: ./scripts/sync-help-docs.sh

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/docs/help"

if [ ! -d "$SRC" ]; then
    echo "Error: docs/help/ not found at $SRC"
    exit 1
fi

echo "Syncing help docs from $SRC"

# SwiftUI
# diskusage.md describes the Android-only Database Metrics screen and is
# unreferenced by any SwiftUI code — excluded here (mirrors the Android-side
# UserGuide.md exclusion below). Android still ships it via StudioNavItem.helpFileName.
SWIFT_DEST="$REPO_ROOT/SwiftUI/EdgeStudio/Resources/Help"
mkdir -p "$SWIFT_DEST"
for f in "$SRC"/*.md; do
    [ "$(basename "$f")" = "diskusage.md" ] && continue
    cp "$f" "$SWIFT_DEST/"
done
rm -f "$SWIFT_DEST/diskusage.md"
echo "  ✓ SwiftUI: $SWIFT_DEST (excluding diskusage.md)"

# Android
# UserGuide.md is macOS/iPadOS-only content (⌘ shortcuts, Settings menu, MCP server)
# and is unreferenced by the Android UI — excluded here and in the Gradle
# syncHelpDocs task (android/app/build.gradle.kts). SwiftUI still ships it.
ANDROID_DEST="$REPO_ROOT/android/app/src/main/assets/help"
mkdir -p "$ANDROID_DEST"
for f in "$SRC"/*.md; do
    [ "$(basename "$f")" = "UserGuide.md" ] && continue
    cp "$f" "$ANDROID_DEST/"
done
rm -f "$ANDROID_DEST/UserGuide.md"
echo "  ✓ Android: $ANDROID_DEST (excluding UserGuide.md)"

echo "Done."
