#!/bin/bash
#
# Helper script to add PresenceVisualizer files to Xcode project
# This provides the commands needed, but manual verification in Xcode is recommended
#

set -e

echo "📦 Adding PresenceVisualizer files to Xcode project..."
echo ""

PROJECT_DIR="/Users/labeaaa/Developer/ditto-edge-studio/SwiftUI"
PROJECT_FILE="$PROJECT_DIR/Edge Debug Helper.xcodeproj"

# Check if project exists
if [ ! -d "$PROJECT_FILE" ]; then
    echo "❌ Error: Xcode project not found at $PROJECT_FILE"
    exit 1
fi

echo "✅ Found Xcode project"
echo ""
echo "⚠️  IMPORTANT: This script shows the files that need to be added."
echo "   For safety, please add them manually via Xcode:"
echo ""
echo "   1. Open: open \"$PROJECT_FILE\""
echo "   2. In Xcode Project Navigator, right-click 'Components' folder"
echo "   3. Select 'Add Files to Edge Debug Helper...'"
echo "   4. Add these 4 files:"
echo ""
echo "      ✓ FloatingSquaresLayer.swift"
echo "      ✓ PixelPhoneTexture.swift"
echo "      ✓ MobilePhoneNode.swift"
echo "      ✓ PresenceVisualizerScene.swift"
echo ""
echo "   5. In the dialog, ensure:"
echo "      ✓ 'Copy items if needed' is checked"
echo "      ✓ 'Create groups' is selected"
echo "      ✓ 'Edge Studio' target is checked"
echo ""
echo "   6. Remove old HelloWorldScene.swift reference if still present"
echo ""
echo "Files to add are located in:"
ls -1 "$PROJECT_DIR/Edge Debug Helper/Components/"*Layer.swift "$PROJECT_DIR/Edge Debug Helper/Components/"*Texture.swift "$PROJECT_DIR/Edge Debug Helper/Components/"MobilePhoneNode.swift "$PROJECT_DIR/Edge Debug Helper/Components/"PresenceVisualizerScene.swift 2>/dev/null || true
echo ""
echo "After adding files, build the project:"
echo "  cd SwiftUI"
echo "  xcodebuild -project \"Edge Debug Helper.xcodeproj\" -scheme \"Edge Studio\" -destination \"platform=macOS,arch=arm64\" build"
echo ""
echo "📖 See PRESENCE_VISUALIZER_IMPLEMENTATION.md for detailed instructions"
