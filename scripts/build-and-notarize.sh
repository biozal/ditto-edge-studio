#!/bin/bash

# Edge Debug Helper - Build and Notarize Script
# This script builds a release version of the app and submits it for notarization

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_PROJECT="${PROJECT_DIR}/SwiftUI/Edge Debug Helper.xcodeproj"
SCHEME="Edge Studio"
CONFIGURATION="Release"
ARCHIVE_PATH="${PROJECT_DIR}/build/EdgeDebugHelper.xcarchive"
EXPORT_PATH="${PROJECT_DIR}/build/export"
APP_NAME="Edge Debug Helper.app"
BUNDLE_ID="com.costoda.ditto-edge-studio"
DEVELOPER_ID="Developer ID Application: Aaron LaBeau (E3FRN9JNGJ)"

# Apple ID for notarization (you'll need to provide this)
APPLE_ID="${APPLE_ID:-your-apple-id@example.com}"
TEAM_ID="E3FRN9JNGJ"

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   Edge Debug Helper - Release Build       ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""

# Step 1: Clean previous builds
echo -e "${YELLOW}[1/6]${NC} Cleaning previous builds..."
rm -rf "${PROJECT_DIR}/build"
mkdir -p "${PROJECT_DIR}/build"
mkdir -p "${EXPORT_PATH}"

# Step 2: Build Archive
echo -e "${YELLOW}[2/6]${NC} Building archive..."

# Check if xcpretty is available for prettier output
if command -v xcpretty &> /dev/null; then
    xcodebuild archive \
        -project "${XCODE_PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -archivePath "${ARCHIVE_PATH}" \
        -destination "platform=macOS,arch=arm64" \
        CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM="${TEAM_ID}" \
        | xcpretty
else
    xcodebuild archive \
        -project "${XCODE_PROJECT}" \
        -scheme "${SCHEME}" \
        -configuration "${CONFIGURATION}" \
        -archivePath "${ARCHIVE_PATH}" \
        -destination "platform=macOS,arch=arm64" \
        CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
        CODE_SIGN_STYLE=Manual \
        DEVELOPMENT_TEAM="${TEAM_ID}"
fi

echo -e "${GREEN}✓${NC} Archive created successfully"

# Step 3: Export Archive
echo -e "${YELLOW}[3/6]${NC} Exporting archive..."

# Create exportOptions.plist
cat > "${PROJECT_DIR}/build/exportOptions.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${PROJECT_DIR}/build/exportOptions.plist"

echo -e "${GREEN}✓${NC} Export completed successfully"

# Get version from the built app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "${EXPORT_PATH}/${APP_NAME}/Contents/Info.plist" 2>/dev/null || echo "0.2.4")

echo -e "${GREEN}✓${NC} Detected version: ${VERSION}"

# Step 4: Create DMG with Applications symlink (like existing script)
echo -e "${YELLOW}[4/6]${NC} Creating DMG..."

# Create temporary directory for DMG contents
DMG_TEMP="${PROJECT_DIR}/build/dmg_temp"
mkdir -p "${DMG_TEMP}"

# Copy app to temp directory
cp -R "${EXPORT_PATH}/${APP_NAME}" "${DMG_TEMP}/"

# Create Applications symlink for easy installation
ln -s /Applications "${DMG_TEMP}/Applications"

# DMG name with version
DMG_NAME="Edge Debug Helper ${VERSION}.dmg"
DMG_PATH="${PROJECT_DIR}/scripts/${DMG_NAME}"

# Remove existing DMG if present
rm -f "${DMG_PATH}"

# Create DMG
hdiutil create -volname "Edge Debug Helper ${VERSION}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_PATH}"

# Clean up temp directory
rm -rf "${DMG_TEMP}"

echo -e "${GREEN}✓${NC} DMG created: ${DMG_PATH}"

# Step 5: Notarize
echo -e "${YELLOW}[5/6]${NC} Submitting for notarization..."
echo -e "${YELLOW}Note:${NC} You need to have your Apple ID credentials stored in keychain"
echo -e "${YELLOW}      Run: xcrun notarytool store-credentials \"notarytool-profile\" --apple-id ${APPLE_ID} --team-id ${TEAM_ID}${NC}"
echo ""

read -p "Do you want to submit for notarization now? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Submit for notarization
    NOTARIZE_RESPONSE=$(xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "notarytool-profile" \
        --wait)

    echo "$NOTARIZE_RESPONSE"

    # Check if notarization succeeded
    if echo "$NOTARIZE_RESPONSE" | grep -q "status: Accepted"; then
        echo -e "${GREEN}✓${NC} Notarization successful!"

        # Step 6: Staple
        echo -e "${YELLOW}[6/6]${NC} Stapling notarization ticket..."
        xcrun stapler staple "${DMG_PATH}"
        echo -e "${GREEN}✓${NC} Notarization ticket stapled!"
    else
        echo -e "${RED}✗${NC} Notarization failed. Check the output above for details."
        exit 1
    fi
else
    echo -e "${YELLOW}⚠${NC}  Skipping notarization. You can notarize later with:"
    echo -e "    xcrun notarytool submit \"${DMG_PATH}\" --keychain-profile \"notarytool-profile\" --wait"
    echo -e "    xcrun stapler staple \"${DMG_PATH}\""
fi

# Summary
echo ""
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           Build Complete!                  ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "Version:       ${VERSION}"
echo -e "App Location:  ${EXPORT_PATH}/${APP_NAME}"
echo -e "DMG Location:  ${DMG_PATH}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo -e "1. Test the app: open \"${EXPORT_PATH}/${APP_NAME}\""
echo -e "2. If notarization was skipped, run the notarization commands above"
echo -e "3. Upload DMG to GitHub Releases"
echo ""
