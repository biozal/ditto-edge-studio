#!/bin/bash

# Build macOS .app bundle for Edge Studio
# This script creates a proper macOS application bundle with icon support

set -e

# Configuration
APP_NAME="Edge Studio"
BUNDLE_ID="com.costoda.edgestudionet"
VERSION="1.0.0"
PROJECT_DIR="src/EdgeStudio"
PUBLISH_DIR="publish/osx-app"
APP_DIR="$PUBLISH_DIR/$APP_NAME.app"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ]; then
    RID="osx-arm64"
else
    RID="osx-x64"
fi

echo "Building Edge Studio for macOS ($RID)..."

# Clean previous build
rm -rf "$PUBLISH_DIR"

# Publish the app
echo "Publishing .NET application..."
dotnet publish "$PROJECT_DIR/EdgeStudio.csproj" \
    -c Release \
    -r "$RID" \
    --self-contained \
    -p:PublishSingleFile=false \
    -o "$PUBLISH_DIR/temp"

# Create .app bundle structure
echo "Creating .app bundle structure..."
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable and dependencies
echo "Copying application files..."
cp -r "$PUBLISH_DIR/temp/"* "$APP_DIR/Contents/MacOS/"

# Copy Info.plist
echo "Copying Info.plist..."
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/"

# Copy icon
echo "Copying application icon..."
if [ -f "$PROJECT_DIR/Assets/EdgeStudio.icns" ]; then
    cp "$PROJECT_DIR/Assets/EdgeStudio.icns" "$APP_DIR/Contents/Resources/"
    echo "✓ Icon copied successfully"
else
    echo "⚠ Warning: EdgeStudio.icns not found"
fi

# Create PkgInfo file
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

# Make executable
chmod +x "$APP_DIR/Contents/MacOS/EdgeStudio"

# Clean up temp directory
rm -rf "$PUBLISH_DIR/temp"

# Set icon attribute (tells macOS to use the custom icon)
if [ -f "$APP_DIR/Contents/Resources/EdgeStudio.icns" ]; then
    # This command associates the icon with the app bundle
    sips -i "$APP_DIR/Contents/Resources/EdgeStudio.icns" > /dev/null 2>&1 || true
    DeRez -only icns "$APP_DIR/Contents/Resources/EdgeStudio.icns" > /tmp/icns.rsrc 2>/dev/null || true
    Rez -append /tmp/icns.rsrc -o "$APP_DIR"$'/Contents/\r' 2>/dev/null || true
    SetFile -a C "$APP_DIR" 2>/dev/null || true
    rm /tmp/icns.rsrc 2>/dev/null || true
fi

echo ""
echo "✓ Build complete!"
echo "Application bundle: $APP_DIR"
echo ""
echo "To run the app:"
echo "  open \"$APP_DIR\""
echo ""
echo "To install to Applications:"
echo "  cp -r \"$APP_DIR\" /Applications/"
echo ""
