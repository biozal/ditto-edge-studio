# JetBrains Rider Setup for macOS with Proper Icon

## Problem
When debugging from Rider, the app launches with a generic folder icon instead of the custom Edge Studio icon.

## Solution
The project now automatically creates a proper `.app` bundle during build with the correct icon.

## Using Rider with the Correct Icon

### Option 1: Use the "Edge Studio (Debug with Icon)" Run Configuration (Recommended)

1. Open the project in Rider
2. Look for the run configuration dropdown (top-right toolbar)
3. Select **"Edge Studio (Debug with Icon)"**
4. Click the Debug or Run button
5. The app will launch with the proper Edge Studio icon! ✅

This configuration:
- Automatically builds the project first
- Launches the app from the `.app` bundle using `open` command
- Displays the correct icon in Dock, Finder, and App Switcher

### Option 2: Use the ".NET Project" Run Configuration

1. Select **"Edge Studio (macOS)"** from the run configurations
2. Click Run/Debug
3. The app will run from inside the bundle structure

### What Happens Automatically

Every time you build the project (Debug or Release), a post-build event:
1. ✅ Creates `EdgeStudio.app` bundle in the output directory
2. ✅ Copies all files to `Contents/MacOS/`
3. ✅ Copies `EdgeStudio.icns` icon to `Contents/Resources/`
4. ✅ Copies `Info.plist` with app metadata
5. ✅ Sets proper permissions

### Debugging Notes

**Note**: When using "Debug with Icon" configuration, attaching the debugger might not work automatically since the app is launched via `open` command. For full debugging support:

1. Use the regular Rider debug configuration (may show folder icon but debugger works)
2. Or manually attach the debugger after launch:
   - Run > Attach to Process
   - Find "EdgeStudio" in the list
   - Click Attach

### Manual Launch (Alternative)

You can also launch the app manually from terminal:
```bash
# After building in Rider
open src/EdgeStudio/bin/Debug/net10.0/EdgeStudio.app
```

## Troubleshooting

### Icon Not Showing?
1. Make sure you've built the project at least once after these changes
2. Check that `EdgeStudio.app` exists in `src/EdgeStudio/bin/Debug/net10.0/`
3. Verify the icon file is present:
   ```bash
   ls -la src/EdgeStudio/bin/Debug/net10.0/EdgeStudio.app/Contents/Resources/
   ```

### Can't Find Run Configuration?
The run configurations are in `.run/` folder. Rider should detect them automatically. If not:
1. Right-click on `.run/` folder in Project view
2. Verify the XML files are there
3. Restart Rider if needed

### Still Shows Folder Icon?
If launching directly from Rider's default configuration:
- This is expected behavior when running the executable directly
- Use one of the custom run configurations above instead
- The icon will display correctly when using the `.app` bundle

## For Production Builds

For release builds and distribution:
```bash
./build-macos-app.sh
```
This creates a production-ready app bundle in `publish/osx-app/Edge Studio.app`
