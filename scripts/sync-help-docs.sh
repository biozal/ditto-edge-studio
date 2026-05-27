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
SWIFT_DEST="$REPO_ROOT/SwiftUI/EdgeStudio/Resources/Help"
mkdir -p "$SWIFT_DEST"
cp "$SRC"/*.md "$SWIFT_DEST/"
echo "  ✓ SwiftUI: $SWIFT_DEST"

# Android
ANDROID_DEST="$REPO_ROOT/android/app/src/main/assets/help"
mkdir -p "$ANDROID_DEST"
cp "$SRC"/*.md "$ANDROID_DEST/"
echo "  ✓ Android: $ANDROID_DEST"

# Note: the dotnet/Avalonia target is archived (see ReleaseNotes / CLAUDE.md).
# It is intentionally not synced anymore. The historic files remain under
# dotnet/src/EdgeStudio/Assets/Help/ for git history only.

echo "Done."
