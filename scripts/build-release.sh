#!/bin/bash

# Edge Debug Helper - Simple Release Build Script
# This script builds the release version with proper code signing and creates a DMG

set -e  # Exit on error

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XCODE_PROJECT="${PROJECT_DIR}/SwiftUI/Edge Debug Helper.xcodeproj"
SCHEME="Edge Studio"
CONFIGURATION="Release"
BUILD_DIR="${PROJECT_DIR}/build/Release"
APP_NAME="Edge Debug Helper.app"
DEVELOPER_ID="Developer ID Application: Aaron LaBeau (E3FRN9JNGJ)"
TEAM_ID="E3FRN9JNGJ"

echo -e "${GREEN}Building Edge Debug Helper (Release)...${NC}"

# Clean and build with proper code signing
xcodebuild clean build \
    -project "${XCODE_PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "platform=macOS,arch=arm64" \
    CONFIGURATION_BUILD_DIR="${BUILD_DIR}" \
    CODE_SIGN_IDENTITY="${DEVELOPER_ID}" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="${TEAM_ID}"

echo -e "${GREEN}✓ Build complete!${NC}"

# Re-sign embedded frameworks with Developer ID
echo -e "${YELLOW}Re-signing embedded frameworks...${NC}"

# Find and re-sign all frameworks
for framework in "${BUILD_DIR}/${APP_NAME}/Contents/Frameworks"/*.framework; do
    if [ -d "$framework" ]; then
        echo "  Signing $(basename "$framework")"
        codesign --force --sign "${DEVELOPER_ID}" \
            --timestamp \
            --options runtime \
            "$framework"
    fi
done

# Re-sign the app bundle
echo -e "${YELLOW}Re-signing app bundle...${NC}"
codesign --force --deep --sign "${DEVELOPER_ID}" \
    --timestamp \
    --options runtime \
    --entitlements "${PROJECT_DIR}/SwiftUI/Edge Debug Helper/Edge_Studio.entitlements" \
    "${BUILD_DIR}/${APP_NAME}"

# Verify signature
echo -e "${YELLOW}Verifying signature...${NC}"
codesign --verify --verbose=2 "${BUILD_DIR}/${APP_NAME}"

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Code signing verified!${NC}"
else
    echo -e "${RED}✗ Code signing verification failed!${NC}"
    exit 1
fi

# Get version from the built app
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "${BUILD_DIR}/${APP_NAME}/Contents/Info.plist" 2>/dev/null || echo "0.2.4")

echo -e "${GREEN}✓ Detected version: ${VERSION}${NC}"

# Create DMG with Applications symlink
echo -e "${YELLOW}Creating DMG...${NC}"

# Create temporary directory for DMG contents
DMG_TEMP="${PROJECT_DIR}/build/dmg_temp"
mkdir -p "${DMG_TEMP}"

# Copy app to temp directory
cp -R "${BUILD_DIR}/${APP_NAME}" "${DMG_TEMP}/"

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

echo -e "${GREEN}✓ DMG created!${NC}"
echo ""
echo -e "Version:      ${VERSION}"
echo -e "App location: ${BUILD_DIR}/${APP_NAME}"
echo -e "DMG location: ${DMG_PATH}"
echo ""
echo -e "${GREEN}Code Signing:${NC}"
echo -e "  Identity: ${DEVELOPER_ID}"
echo -e "  Team ID:  ${TEAM_ID}"
echo ""
echo -e "To test: open \"${BUILD_DIR}/${APP_NAME}\""
echo -e "To distribute: Upload \"${DMG_PATH}\" to GitHub Releases"
echo ""
echo -e "${YELLOW}Note:${NC} This DMG is signed but NOT notarized."
echo -e "      For notarization, use: ./build-and-notarize.sh"
