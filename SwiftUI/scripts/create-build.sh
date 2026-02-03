#!/bin/bash

# Create a temporary directory for DMG contents
mkdir -p ../dmg_temp

# Copy the app to the temporary directory
cp -R "Edge Debug Helper.app" ../dmg_temp/

# Create a symbolic link to Applications folder
ln -s /Applications ../dmg_temp/Applications

# Get the version from the tag
VERSION="0.2.4"

hdiutil create -volname "Edge Debug Helper $VERSION" \
          -srcfolder ../dmg_temp \
          -ov -format UDZO \
          "Edge Debug Helper $VERSION.dmg"
          
# Clean up
rm -rf ../dmg_temp