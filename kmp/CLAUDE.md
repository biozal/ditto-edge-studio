# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Kotlin Multiplatform (KMP) codebase in this repository.

## Project Overview

This is a Kotlin Multiplatform (KMP) application for Ditto Edge Studio, focusing on desktop and tablet platforms:
- **Windows**: Native Windows desktop application
- **macOS**: Native macOS desktop application  
- **Linux**: Native Linux desktop application
- **Tablet**: Tablet-optimized UI for iPadOS and Android tablets

The application provides a cross-platform GUI for querying and managing Ditto databases using Compose Multiplatform for the UI layer.

## Development Environment Setup

### Prerequisites
- JDK 17 or later
- Kotlin 2.1.0+
- Gradle 8.0+
- Platform-specific requirements:
  - **macOS**: Xcode Command Line Tools
  - **Windows**: Visual Studio Build Tools
  - **Linux**: GCC/Clang toolchain

### Ditto SDK Setup
The project uses Ditto SDK v5 for Kotlin. Documentation: https://docs.ditto.live/sdk/v5/install-guides/kotlin

## Build Commands

### Common Tasks
```bash
# Build all platforms
./gradlew build

# Run desktop application (auto-detects platform)
./gradlew run

# Run tests
./gradlew test

# Clean build
./gradlew clean
```

### Platform-Specific Builds
```bash
# macOS
./gradlew packageDmg

# Windows
./gradlew packageMsi

# Linux (AppImage)
./gradlew packageAppImage

# Distribution packages for all platforms
./gradlew packageDistributionForCurrentOS
```

## Architecture

### Project Structure
```
kmp/
├── composeApp/       # Main application module
│   ├── src/
│   │   ├── commonMain/    # Common code for all platforms
│   │   │   ├── kotlin/com/edgestudio/
│   │   │   │   ├── ui/
│   │   │   │   │   ├── theme/         # Material 3 theme system
│   │   │   │   │   │   ├── Theme.kt   # Light/Dark color schemes
│   │   │   │   │   │   ├── Typography.kt # Typography system
│   │   │   │   │   │   └── ThemeManager.kt # Theme state management
│   │   │   │   │   └── components/    # Reusable UI components
│   │   │   │   │       └── ThemeToggle.kt # Theme switching controls
│   │   │   │   ├── App.kt            # Main app composable
│   │   │   │   ├── Greeting.kt       # Demo functionality
│   │   │   │   └── Platform.kt       # Platform abstractions
│   │   ├── jvmMain/       # Desktop JVM code
│   │   │   └── main.kt    # Desktop entry point
│   │   ├── androidMain/   # Android-specific code
│   │   └── iosMain/       # iOS-specific code
├── gradle/           # Gradle configuration
└── build.gradle.kts  # Build configuration
```

### Key Components
- **Compose Multiplatform UI**: Cross-platform UI framework
- **Material 3 Design System**: Modern theming with light/dark mode support
- **Ditto SDK Integration**: Database sync and query capabilities
- **Platform-specific implementations**: Native features per platform
- **Theme Management**: Reactive theme switching (Light/Dark/System)

## Configuration

### Ditto Configuration
Configure Ditto SDK credentials and endpoints:
- App ID
- Authentication token
- Sync endpoints
- HTTP API configuration

### Build Configuration
Key Gradle properties:
- `compose.version`: Compose Multiplatform version
- `kotlin.version`: Kotlin version
- `ditto.version`: Ditto SDK version

### macOS Entitlements Configuration
The project includes entitlements files for proper macOS permissions:

#### Entitlements Files
- `composeApp/entitlements.plist`: Main app entitlements
- `composeApp/runtime-entitlements.plist`: JVM runtime entitlements

#### Required Permissions
The app requests the following macOS permissions:
- **App Sandbox**: Required for App Store distribution
- **File Access**: Read/write for user-selected files
- **Network**: Client and server permissions for Ditto sync
- **Bluetooth**: Required for Ditto peer-to-peer sync
- **JVM Runtime**: JIT compilation and memory management

#### Team ID Configuration
Before building for distribution:
1. Replace `TEAMID` in `entitlements.plist` with your Apple Developer Team ID
2. Verify bundle ID matches your provisioning profile

The entitlements are automatically applied during the build process via the Gradle configuration in `composeApp/build.gradle.kts`.

## Key Features
- Cross-platform Ditto database management
- Query editor with syntax highlighting
- Real-time sync monitoring
- Collection browser
- Peer management
- Data import/export
- **Material 3 Design System** with custom Ditto branding
- **Light/Dark/System theme support** with smooth transitions
- **Responsive UI** optimized for desktop and tablet form factors

## Testing
```bash
# Unit tests
./gradlew test

# Integration tests
./gradlew integrationTest

# UI tests (platform-specific)
./gradlew uiTest
```

## Platform-Specific Considerations

### Desktop (Windows/macOS/Linux)
- Full keyboard and mouse support
- Window management
- File system access for import/export
- Native menu bars

### Tablet
- Touch-optimized UI
- Responsive layouts
- Gesture support
- Split-view compatibility

## Dependencies
Key dependencies managed in `build.gradle.kts`:
- Compose Multiplatform
- Ditto SDK for Kotlin
- Kotlinx Coroutines
- Kotlinx Serialization

## Troubleshooting

### Common Issues
1. **Gradle sync failures**: Ensure JDK 17+ is configured
2. **Compose rendering issues**: Update graphics drivers
3. **Ditto connection issues**: Verify network permissions and credentials
4. **Platform build errors**: Install required platform toolchains

### Known Build Issues
- ~~**Compose Compiler compatibility**: Previously experiencing `generateFunctionKeyMetaAnnotations=true` unsupported plugin option error with Kotlin 2.1.0 and Compose Multiplatform 1.8.2.~~ **RESOLVED**: Updated to Kotlin 2.2.0 and Compose Multiplatform 1.8.2
- ~~**Skiko native library loading**: Previously experiencing `UnsatisfiedLinkError` with RenderNodeContext native methods.~~ **RESOLVED**: Fixed with Compose Multiplatform 1.8.2 stable version
- **Desktop packaging works**: The macOS entitlements configuration is validated and working correctly - `./gradlew packageDmg --dry-run` succeeds
- **Build Status**: ✅ JVM compilation and runtime execution successful with current version combination

### Debug Commands
```bash
# Verbose Gradle output
./gradlew build --info

# Gradle daemon status
./gradlew --status

# Clear Gradle cache
./gradlew clean build --refresh-dependencies
```

## Development Guidelines
- Use Kotlin idioms and coroutines for async operations
- Follow Material Design 3 guidelines for UI
- Implement platform-specific features using expect/actual mechanism
- Maintain separation between UI and business logic
- Use dependency injection for testability

### Build Validation Rule
**CRITICAL**: After making any changes to the codebase, configuration files, or dependencies, you MUST run a build to validate that the changes don't break the project:

```bash
./gradlew build
```

This ensures:
- Code compiles successfully across all platforms
- Dependencies are resolved correctly
- Configuration changes are valid
- No regressions are introduced

### Running the Application
For the desktop JVM version:
```bash
./gradlew jvmRun -DmainClass=com.edgestudio.MainKt
```

**Note**: The explicit `-DmainClass` parameter is required for proper execution.

## Performance Optimization
- Lazy loading for large datasets
- Efficient state management with Compose
- Background processing for Ditto sync operations
- Memory-efficient data structures for query results

## Release Process
1. Update version in `gradle.properties`
2. Build release packages for all platforms
3. Sign packages with appropriate certificates
4. Test on target platforms
5. Create distribution artifacts

## Important Notes
- This is a proof-of-concept (POC) implementation for KMP support
- Focus on desktop platforms first, then extend to tablets
- Maintain API compatibility with existing SwiftUI and Tauri versions
- Prioritize Ditto SDK integration and performance