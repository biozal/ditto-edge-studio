#!/bin/bash

# Run Edge Studio from the .app bundle
# This ensures the proper icon is displayed when launching from Rider

APP_BUNDLE="src/EdgeStudio/bin/Debug/net10.0/EdgeStudio.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: App bundle not found at $APP_BUNDLE"
    echo "Please build the project first."
    exit 1
fi

echo "Launching Edge Studio from app bundle..."
open "$APP_BUNDLE"
