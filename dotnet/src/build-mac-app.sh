#!/bin/bash
# Build script for Edge Studio macOS .app bundle

set -e

APP_NAME="Edge Studio"
APP_BUNDLE="./EdgeStudio.app"
PROJECT_PATH="EdgeStudio/EdgeStudio.csproj"

echo "🔨 Building Edge Studio for macOS..."
echo ""

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create bundle directory structure
echo "📁 Creating .app bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Publish the app
echo "⚙️  Publishing application..."
dotnet publish "$PROJECT_PATH" \
  -c Release \
  -r osx-arm64 \
  --self-contained false \
  -o "$APP_BUNDLE/Contents/MacOS" \
  --verbosity minimal

if [ $? -ne 0 ]; then
    echo "❌ Build failed!"
    exit 1
fi

# Copy Info.plist to Contents/
echo "📄 Copying Info.plist..."
cp EdgeStudio/Info.plist "$APP_BUNDLE/Contents/"

# Copy icon to Resources/
echo "🎨 Copying application icon..."
cp EdgeStudio/Assets/EdgeStudio.icns "$APP_BUNDLE/Contents/Resources/"

# Make sure the executable is executable
chmod +x "$APP_BUNDLE/Contents/MacOS/EdgeStudio"

# Create PkgInfo file
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

echo ""
echo "✅ Build complete!"
echo ""
echo "📦 App bundle created at: $(pwd)/$APP_BUNDLE"
echo ""
echo "🚀 To run the app:"
echo "   open \"$APP_BUNDLE\""
echo ""
echo "📥 To install to Applications folder:"
echo "   cp -R \"$APP_BUNDLE\" /Applications/"
echo ""
echo "🧪 To run tests:"
echo "   dotnet test EdgeStudioTests/EdgeStudioTests.csproj"
echo ""
