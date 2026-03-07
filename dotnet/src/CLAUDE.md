# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Avalonia version of Edge Studio.

## ⚠️ CRITICAL DEVELOPMENT RULES

### Rule 1: Always Compile After Every Change

**MANDATORY: You MUST compile after EVERY code change to verify nothing broke.**

```bash
# After ANY code change, immediately run:
dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

**Why this is critical:**
- Catches syntax errors immediately (XAML, C#)
- Prevents cascading errors from broken code
- Validates dependencies and references
- Ensures the project remains in a buildable state

**When to compile:**
- After editing any .cs file
- After editing any .axaml file
- After adding/removing files
- After modifying project references
- After updating NuGet packages

**If the build fails, you MUST fix it before proceeding with any other changes.**

### Rule 2: Always Check Avalonia Documentation First

**ALWAYS CHECK AVALONIA DOCUMENTATION FIRST** before implementing any Avalonia-specific features or controls. Do NOT assume solutions based on other frameworks (WPF, WinForms, etc.) will work the same way in Avalonia.

**Official Avalonia Documentation:** https://docs.avaloniaui.net/

When working with Avalonia controls or features:
1. ✅ **FIRST**: Search the Avalonia documentation for the specific control or feature
2. ✅ **THEN**: Implement the solution following Avalonia's documented approach
3. ❌ **NEVER**: Assume WPF/WinForms patterns will work the same way

## Other Platform Versions

This repository contains multiple platform implementations of Edge Studio. The other versions are located at the **repository root**:

| Platform | Location | Framework |
|----------|----------|-----------|
| **SwiftUI** (macOS/iPadOS) | `SwiftUI/` | Swift / SwiftUI — see root `CLAUDE.md` |
| **Android** | `android/` | Kotlin / Jetpack Compose — see root `CLAUDE.md` |
| **.NET / Avalonia** (this project) | `dotnet/` | C# / Avalonia UI |

## Project Overview

Edge Studio Avalonia is a cross-platform desktop application for querying and managing Ditto databases. This is the Avalonia UI implementation of the same functionality found in the SwiftUI and Android versions of the application, providing native performance on Windows, Linux, and macOS platforms.

**Application Name:** Edge Studio
**Framework:** Avalonia UI (.NET 10.0) with Material Design
**Platform:** Windows, Linux, and macOS Desktop

## Development Environment Setup

### Prerequisites
- Visual Studio 2022 or later with .NET desktop development workload, OR
- JetBrains Rider, OR
- VS Code with C# Dev Kit extension
- .NET 10.0 SDK
- Windows 10/11, Linux, or macOS 15+ development environment

### Build Environment
```bash
# Restore NuGet packages
dotnet restore

# Build the solution with test validation
dotnet build && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --no-build

# Build in Release configuration with test validation
dotnet build -c Release && dotnet test EdgeStudioTests/EdgeStudioTests.csproj -c Release --no-build

# Run the application
dotnet run --project EdgeStudio/EdgeStudio.csproj
```

## Build Commands

### Command Line (dotnet CLI)
**IMPORTANT:** All builds must run tests and validate no new warnings are introduced.

```bash
# Clean the solution
dotnet clean

# Build Debug configuration with test validation
dotnet build --verbosity normal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --no-build

# Build Release configuration with test validation
dotnet build -c Release --verbosity normal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj -c Release --no-build

# Run the application
dotnet run --project EdgeStudio/EdgeStudio.csproj

# Run tests only
dotnet test EdgeStudioTests/EdgeStudioTests.csproj

# Run tests with detailed output
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --logger "console;verbosity=detailed"

# Publish for Windows
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -r win-x64 --self-contained

# Publish for Linux
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -r linux-x64 --self-contained
```

### IDE Integration
- **Visual Studio**: Open `EdgeStudio.sln`
- **JetBrains Rider**: Open `EdgeStudio.sln` 
- **VS Code**: Open folder and use C# Dev Kit

## Architecture

### Dependency Injection Requirements
**IMPORTANT**: All ViewModels, Services, and Repositories MUST be:
1. **Registered in the DI container** (App.axaml.cs)
2. **Resolved through dependency injection** - never instantiated directly with `new`
3. **Lazy loaded** as needed for performance
4. **Properly scoped**:
   - Singleton for app-wide services (DittoManager, Repositories)
   - Transient for ViewModels that need fresh instances
   - Scoped where appropriate for request-based services

### Project Structure
Located in the `src/` directory:

**Solution Files:**
- **EdgeStudio.sln**: Solution file containing both main project and tests
- **CLAUDE.md**: Project documentation and guidance
- **designs/**: UI design screenshots and mockups

**EdgeStudio Project:**
- **EdgeStudio/EdgeStudio.csproj**: Main project file with Avalonia, Material.Avalonia, AvaloniaEdit, and Ditto SDK dependencies
- **EdgeStudio/Program.cs**: Application entry point
- **EdgeStudio/App.axaml / App.axaml.cs**: Application setup with Material Design theming and dependency injection
- **EdgeStudio/ViewLocator.cs**: MVVM view location logic
- **EdgeStudio/.env**: Embedded environment configuration (not committed to git)
- **EdgeStudio/.env.sample**: Sample configuration file

**Data Layer:**
- **EdgeStudio/Data/IDittoManager.cs**: Interface defining core Ditto database operations
- **EdgeStudio/Data/DittoManager.cs**: Implementation of Ditto database connection and management
- **EdgeStudio/Data/ISystemService.cs**: System-level service interface
- **EdgeStudio/Data/SystemService.cs**: System-level service implementation
- **EdgeStudio/Data/Repositories/**:
  - `IDatabaseRepository.cs`: Database repository interface
  - `DittoDatabaseRepository.cs`: Ditto-specific repository with Avalonia threading integration
  - `ISubscriptionRepository.cs`: Subscription repository interface
  - `DittoSubscriptionRepository.cs`: Ditto subscription management

**Models:**
- **EdgeStudio/Models/DittoDatabaseConfig.cs**: Record type for database configuration with JSON serialization
- **EdgeStudio/Models/DatabaseFormModel.cs**: ObservableObject for form data binding and validation
- **EdgeStudio/Models/DittoDatabaseSubscription.cs**: Subscription configuration model
- **EdgeStudio/Models/SubscriptionFormModel.cs**: Subscription form data binding model
- **EdgeStudio/Models/NavigationItem.cs**: Navigation menu item model
- **EdgeStudio/Models/NavigationItemViewModel.cs**: Navigation item view model
- **EdgeStudio/Models/SyncStatusInfo.cs**: Synchronization status information model

**ViewModels (MVVM):**
- **EdgeStudio/ViewModels/ViewModelBase.cs**: Base class for all ViewModels
- **EdgeStudio/ViewModels/MainWindowViewModel.cs**: Main application ViewModel with async database initialization
- **EdgeStudio/ViewModels/EdgeStudioViewModel.cs**: Database workspace ViewModel
- **EdgeStudio/ViewModels/NavigationViewModel.cs**: Navigation bar and menu management
- **EdgeStudio/ViewModels/QueryViewModel.cs**: Query execution and history ✅ Implemented
- **EdgeStudio/ViewModels/SubscriptionViewModel.cs**: Real-time subscription management ✅ Implemented
- **EdgeStudio/ViewModels/SubscriptionDetailsViewModel.cs**: Individual subscription details
- **EdgeStudio/ViewModels/CollectionsViewModel.cs**: Collections listing and management
- **EdgeStudio/ViewModels/IndexViewModel.cs**: Index management
- **EdgeStudio/ViewModels/ObserversViewModel.cs**: Observer/subscription monitoring
- **EdgeStudio/ViewModels/FavoritesViewModel.cs**: Favorite queries management
- **EdgeStudio/ViewModels/HistoryViewModel.cs**: Query history management
- **EdgeStudio/ViewModels/ToolsViewModel.cs**: Database tools and utilities

**Views:**
- **EdgeStudio/Views/**:
  - `MainWindow.axaml / MainWindow.axaml.cs`: Main application window with navigation logic
  - `LoadingWindow.axaml / LoadingWindow.axaml.cs`: Application startup loading window
  - `DatabaseListingView.axaml / DatabaseListingView.axaml.cs`: Material Design database listing with cards
  - `DatabaseFormWindow.axaml / DatabaseFormWindow.axaml.cs`: Database configuration form dialog
  - `EdgeStudioView.axaml / EdgeStudioView.axaml.cs`: Database workspace view with Material Design styling
  - `SubscriptionFormWindow.axaml / SubscriptionFormWindow.axaml.cs`: Subscription configuration form dialog
- **EdgeStudio/Views/Navigation/**:
  - `NavigationBar.axaml / NavigationBar.axaml.cs`: Navigation sidebar component
- **EdgeStudio/Views/Workspaces/**:
  - `QueryView.axaml / QueryView.axaml.cs`: Query editor and execution workspace
  - `SubscriptionListingView.axaml / SubscriptionListingView.axaml.cs`: Subscriptions list view
  - `SubscriptionDetailsView.axaml / SubscriptionDetailsView.axaml.cs`: Subscription details and documents
  - `CollectionsListingView.axaml / CollectionsListingView.axaml.cs`: Collections browser
  - `IndexListingView.axaml / IndexListingView.axaml.cs`: Database indexes view
  - `ObserverListingView.axaml / ObserverListingView.axaml.cs`: Observer list view
  - `ObserverDetailView.axaml / ObserverDetailView.axaml.cs`: Observer details view
  - `FavoritesListingView.axaml / FavoritesListingView.axaml.cs`: Favorite queries view
  - `HistoryListingView.axaml / HistoryListingView.axaml.cs`: Query history view
  - `ToolsListingView.axaml / ToolsListingView.axaml.cs`: Tools menu view
  - `ToolsDetailView.axaml / ToolsDetailView.axaml.cs`: Tool detail view

**Services:**
- **EdgeStudio/Services/INavigationService.cs**: Navigation service interface
- **EdgeStudio/Services/NavigationService.cs**: Navigation service implementation

**Messages (for inter-component communication):**
- **EdgeStudio/Messages/CloseDatabaseRequestedMessage.cs**: Database close request message
- **EdgeStudio/Messages/DatabaseFormMessages.cs**: Database form related messages
- **EdgeStudio/Messages/SubscriptionFormMessages.cs**: Subscription form related messages
- **EdgeStudio/Messages/ListingItemSelectedMessage.cs**: Item selection messages
- **EdgeStudio/Messages/NavigationChangedMessage.cs**: Navigation change messages

**Helpers:**
- **EdgeStudio/Helpers/EnvFileReader.cs**: Environment configuration file reader with embedded resource support

**Exceptions:**
- **EdgeStudio/AppExceptions.cs**: Application-specific exception definitions

**Test Project:**
- **EdgeStudioTests/EdgeStudioTests.csproj**: xUnit test project with Avalonia.Headless.XUnit, Moq, and FluentAssertions
- **EdgeStudioTests/UnitTest1.cs**: Basic test infrastructure (to be expanded)

### Current Implementation Status
- **Cross-Platform UI**: ✅ Implemented with Avalonia UI (Windows, Linux, macOS)
- **Material Design**: ✅ Implemented with Material.Avalonia theming
- **Data Layer**: ✅ Fully implemented with Ditto SDK integration and Avalonia threading
- **MVVM Architecture**: ✅ Complete with async operations and proper data binding
- **Navigation System**: ✅ View switching with loading states and error handling
- **Messaging System**: ✅ Inter-component communication using CommunityToolkit.Mvvm
- **Dependency Injection**: ✅ Microsoft.Extensions.DependencyInjection integration
- **Services Layer**: ✅ Navigation and system services implemented
- **Configuration**: ✅ Environment file reader with embedded resource support
- **Query Editor**: ✅ Implemented with AvaloniaEdit
- **Subscriptions**: ✅ Real-time subscription management and monitoring
- **Database Management**: ✅ Collections, indexes, and observers
- **Testing Framework**: ✅ xUnit with Avalonia.Headless.XUnit for UI testing
- **Build System**: ✅ Cross-platform build and publish support

## Configuration Requirements

### Application Configuration
Configuration follows the same pattern as the WPF version:
- Ditto application ID
- Authentication token  
- Authentication endpoint URL
- WebSocket endpoint URL
- HTTP API endpoint and key

### Configuration Sources
1. **Embedded .env file**: Primary configuration source (embedded as resource)
2. **Development fallback**: Hard-coded development configuration when .env is unavailable
3. **Environment variables**: Can override embedded configuration

### Configuration Example (.env file)
```env
DITTO_APP_ID=your-app-id
DITTO_AUTH_TOKEN=your-auth-token
DITTO_AUTH_URL=https://your-auth-endpoint.com
DITTO_HTTP_API_URL=https://your-api-endpoint.com
DITTO_HTTP_API_KEY=your-api-key
DITTO_MODE=online
DITTO_ALLOW_UNTRUSTED_CERTS=false
```

## Key Features

### Cross-Platform Functionality
- **Windows, Linux, and macOS Support**: Native performance on all platforms
- **Material Design UI**: Consistent, modern interface across platforms
- **Fluent theming**: Supports system light/dark theme switching
- **Native file dialogs**: Platform-appropriate file operations

### Core Database Features  
- Multi-app connection management with local storage
- Query execution with history and favorites
- Real-time subscriptions and observables
- Presence viewer and peer management
- Disk usage monitoring
- Import/export functionality
- Permissions health checking

### Avalonia-Specific Features
- **Cross-platform deployment**: Single codebase for Windows, Linux, and macOS
- **Material Design theming**: Indigo and Pink color scheme with light/dark support
- **XAML Hot Reload**: Development-time UI updates
- **Native performance**: No browser overhead compared to Electron alternatives

## Platform Requirements

### Runtime Requirements
- **Windows**: Windows 10 version 1809 or later, Windows 11
- **Linux**: Modern Linux distributions with X11 or Wayland (Debian 9+, Ubuntu 16.04+, Fedora 30+)
- **macOS**: macOS 15+ (Sequoia or later)
- **.NET 10.0 Runtime**: Cross-platform runtime

### Development Requirements
- .NET 10.0 SDK
- Platform-specific development tools:
  - **Windows**: Visual Studio 2022+ or VS Code
  - **Linux**: JetBrains Rider, VS Code, or command line tools
  - **macOS**: Xcode 16.0+ (for development), JetBrains Rider, or VS Code

## Dependencies

### Core Avalonia Packages
```xml
<!-- UI Framework -->
<PackageReference Include="Avalonia" Version="11.3.9" />
<PackageReference Include="Avalonia.Desktop" Version="11.3.9" />
<PackageReference Include="Avalonia.Themes.Fluent" Version="11.3.9" />
<PackageReference Include="Avalonia.Fonts.Inter" Version="11.3.9" />
<PackageReference Include="Avalonia.Diagnostics" Version="11.3.9" />
<PackageReference Include="AvaloniaUI.DiagnosticsSupport" Version="2.1.1" />

<!-- Material Design -->
<PackageReference Include="Material.Avalonia" Version="3.13.3" />

<!-- Code Editor -->
<PackageReference Include="AvaloniaEdit" Version="0.10.12" />
```

### Business Logic Dependencies
```xml
<!-- MVVM Framework -->
<PackageReference Include="CommunityToolkit.Mvvm" Version="8.4.0" />

<!-- Ditto SDK -->
<PackageReference Include="Ditto" Version="4.13.0" />

<!-- Dependency Injection -->
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="10.0.0" />
<PackageReference Include="Microsoft.Extensions.Configuration" Version="10.0.0" />
<PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="10.0.0" />

<!-- Security Fix -->
<PackageReference Include="System.Text.RegularExpressions" Version="4.3.1" />

<!-- JSON Handling -->
<PackageReference Include="System.Text.Json" Version="10.0.0" />
```

### Testing Dependencies
```xml
<!-- xUnit Testing Framework -->
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.0.1" />
<PackageReference Include="xunit" Version="2.9.3" />
<PackageReference Include="xunit.runner.visualstudio" Version="3.1.5" />
<PackageReference Include="coverlet.collector" Version="6.0.4" />

<!-- Avalonia Testing -->
<PackageReference Include="Avalonia.Headless.XUnit" Version="11.3.9" />
<PackageReference Include="Avalonia.Themes.Fluent" Version="11.3.9" />

<!-- Ditto SDK for Testing -->
<PackageReference Include="Ditto" Version="4.13.0" />

<!-- Mocking and Assertions -->
<PackageReference Include="Moq" Version="4.20.72" />
<PackageReference Include="FluentAssertions" Version="8.8.0" />
```

## MVVM Pattern Implementation

### ViewModels
- **ViewModelBase**: ✅ Implemented - base class for all ViewModels
- **MainWindowViewModel**: ✅ Implemented - orchestrates main window state with async database operations
- **EdgeStudioViewModel**: ✅ Implemented - manages database workspace state
- **NavigationViewModel**: ✅ Implemented - navigation menu and routing
- **QueryViewModel**: ✅ Implemented - query execution and history
- **SubscriptionViewModel**: ✅ Implemented - real-time subscription management
- **CollectionsViewModel**: ✅ Implemented - collections browsing
- **IndexViewModel**: ✅ Implemented - index management
- **ObserversViewModel**: ✅ Implemented - observer monitoring
- **FavoritesViewModel**: ✅ Implemented - favorite queries
- **HistoryViewModel**: ✅ Implemented - query history
- **ToolsViewModel**: ✅ Implemented - database tools

### Data Binding
- Uses CommunityToolkit.Mvvm source generators for property change notifications
- Implements ICommand pattern with RelayCommand for user actions
- Uses ObservableCollection for dynamic UI lists
- Async operations with proper loading state management

## Threading and Cross-Platform Considerations

### UI Thread Management
- Uses `Avalonia.Threading.Dispatcher.UIThread.InvokeAsync()` for cross-thread UI updates
- Implements async/await patterns for non-blocking operations
- Uses Task.Run for CPU-intensive operations
- Background operations properly marshaled to UI thread

### Cross-Platform File Handling
- Platform-agnostic path handling using `Path.Combine()`
- Cross-platform application data directories
- Embedded resource loading for configuration files

## Testing

### Testing Framework
- **xUnit**: Primary testing framework (preferred for Avalonia projects)
- **Avalonia.Headless.XUnit**: Avalonia-specific UI testing framework
- **Moq**: Dependency mocking framework
- **FluentAssertions**: Enhanced assertion library

### Test Structure
- **EdgeStudioTests/**: Test project with xUnit and Avalonia testing infrastructure
- **Unit Tests**: Isolated component testing with mocked dependencies
- **Integration Tests**: End-to-end testing with real Avalonia UI components
- **Headless UI Tests**: UI logic testing without rendering

### Test Execution
```bash
# Run all tests
dotnet test EdgeStudioTests/EdgeStudioTests.csproj

# Run tests with detailed output
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --logger "console;verbosity=detailed"

# Run headless UI tests
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "Category=UI"
```

## Troubleshooting

### Build Issues
- **Platform targeting**: Ensure project targets correct platforms (Windows/Linux/macOS)
- **Package compatibility**: Verify all NuGet packages support .NET 10.0
- **Missing dependencies**: Run `dotnet restore` to restore packages

### Runtime Issues
- **Linux display**: Ensure X11 or Wayland is properly configured
- **macOS**: Ensure macOS 15+ (Sequoia) and proper Xcode installation for development
- **Font rendering**: Inter font package provides cross-platform font consistency
- **File permissions**: Ensure application data directory is writable

### Material.Avalonia Issues
- **Theming**: Uses MaterialTheme element in App.axaml, not StyleInclude
- **Assembly reference**: Requires `xmlns:themes="clr-namespace:Material.Styles.Themes;assembly=Material.Styles"`
- **Color schemes**: Supports PrimaryColor and SecondaryColor customization

## Deployment

### Cross-Platform Publishing
```bash
# Self-contained Windows executable
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -r win-x64 --self-contained -o ./publish/win-x64/

# Self-contained Linux executable
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -r linux-x64 --self-contained -o ./publish/linux-x64/

# Self-contained macOS executable (Intel)
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -r osx-x64 --self-contained -o ./publish/osx-x64/

# Self-contained macOS executable (Apple Silicon)
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -r osx-arm64 --self-contained -o ./publish/osx-arm64/

# Framework-dependent (smaller, requires .NET runtime installed)
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -o ./publish/framework-dependent/
```

### Distribution
- **Windows**: Executable with optional installer creation
- **Linux**: AppImage, Flatpak, or native package distribution
- **macOS**: Application bundle (.app) creation, DMG installer, or Homebrew
- **Cross-platform**: Framework-dependent deployment for environments with .NET runtime

## Performance Optimizations

### Avalonia-Specific Optimizations
- **Compiled bindings**: Enabled by default for better performance
- **Control virtualization**: For large data sets in lists
- **Async loading**: Non-blocking UI during database initialization
- **Memory management**: Proper disposal of Ditto resources

### Cross-Platform Considerations
- **Startup time**: Async application initialization with loading window
- **Memory usage**: Efficient data binding and resource cleanup
- **UI responsiveness**: Background thread usage for database operations

## UI Development Guidelines

### **CRITICAL: Theme System Compliance**
**ALL UI changes MUST follow the established Material Design theme system. NEVER use hard-coded colors, backgrounds, or styling.**

#### Required Practices:
- ✅ **USE**: `{DynamicResource MaterialSurfaceBrush}`, `{DynamicResource MaterialPrimaryBrush}`, etc.
- ❌ **NEVER**: Hard-coded colors like `Background="White"`, `Foreground="Black"`, `Background="#FFFFFF"`
- ✅ **USE**: Material Design theme resources for proper light/dark mode support
- ❌ **NEVER**: Fixed opacity values that break theme transparency
- ✅ **TEST**: Always verify UI changes work in both light AND dark modes
- ❌ **NEVER**: Assume one theme mode - the app must support system theme switching

#### Theme Resources Available:
```xml
<!-- Backgrounds -->
{DynamicResource MaterialSurfaceBrush}
{DynamicResource MaterialCardBackgroundBrush} 
{DynamicResource MaterialBackgroundBrush}

<!-- Text and Foregrounds -->
{DynamicResource MaterialBodyBrush}
{DynamicResource MaterialPrimaryForegroundBrush}

<!-- Accents and Borders -->
{DynamicResource MaterialPrimaryBrush}
{DynamicResource MaterialDividerBrush}
```

#### Testing Requirements:
1. **Theme Testing**: Every UI change must be tested in both light and dark system themes
2. **Contrast Verification**: Ensure readability in all theme modes
3. **Transparency Respect**: Don't break theme transparency with hard-coded opacity values

**Violation of theme system guidelines is considered a critical error.**

#### Recent Theme Fixes Applied:
**Critical fixes that were required to maintain light/dark mode compatibility:**

1. **DatabaseFormWindow Mode Buttons** (EdgeStudio/Views/DatabaseFormWindow.axaml:16-28):
   - **Issue**: Text was unreadable in light mode due to improper foreground color usage
   - **Fix**: Replaced `MaterialOnSurfaceBrush`/`MaterialOnPrimaryBrush` with `MaterialBodyBrush` 
   - **Lesson**: `MaterialBodyBrush` provides consistent text contrast across both themes
   - **Solution**: Removed custom ControlTemplate, used `MaterialBodyBrush` for both checked/unchecked states

2. **EdgeStudioView Top Toolbar** (EdgeStudio/Views/EdgeStudioView.axaml:24-28):
   - **Issue**: Toolbar background and Close button unreadable in light mode
   - **Fix**: Changed from `MaterialPrimaryBrush` to `MaterialSurfaceBrush` background
   - **Solution**: Simplified Close button to use default Material button styling

3. **Navigation Bar Icons** (EdgeStudio/Views/Navigation/NavigationBar.axaml:23-34):
   - **Issue**: Navigation buttons had unwanted borders in light mode
   - **Fix**: Created custom ControlTemplate that properly inherits theme styling
   - **Solution**: Used transparent backgrounds with proper hover states

4. **Database Cards** (EdgeStudio/App.axaml:46-48, EdgeStudio/Views/DatabaseListingView.axaml):
   - **Issue**: Hard-coded colors breaking light mode display
   - **Fix**: Replaced `#3A3A3A` with `{DynamicResource MaterialCardBackgroundBrush}`
   - **Solution**: Added `MaterialBodyBrush` foreground to all TextBlock elements

#### **ABSOLUTE REQUIREMENTS - NO EXCEPTIONS:**
- ⚠️ **NEVER BREAK LIGHT/DARK MODE COMPATIBILITY** - This is completely unacceptable
- 🔍 **ALWAYS TEST BOTH THEMES** - Every UI change must work in light AND dark modes
- 🚫 **ZERO HARDCODED COLORS** - Use Material theme resources exclusively
- ✅ **FOLLOW EXISTING PATTERNS** - Examine how other working buttons/elements are styled
- 📝 **USE MaterialBodyBrush FOR TEXT** - Provides automatic contrast adjustment

#### Common Theme Resource Patterns:
```xml
<!-- Standard text foreground (auto-adjusts for theme) -->
<TextBlock Foreground="{DynamicResource MaterialBodyBrush}"/>

<!-- Button with proper theme integration -->
<Button Classes="material-button" Content="Save"/>

<!-- Primary accent for selected states -->
<TextBlock Foreground="{DynamicResource MaterialPrimaryBrush}"/>

<!-- Surface backgrounds for cards/panels -->
<Border Background="{DynamicResource MaterialSurfaceBrush}"/>
```

## Key Differences from WPF Version

### Framework Changes
1. **UI Framework**: WPF → Avalonia UI for cross-platform support
2. **Threading**: `Application.Current.Dispatcher` → `Avalonia.Threading.Dispatcher.UIThread`
3. **Window lifecycle**: `OnClosing(CancelEventArgs)` → `OnClosed(EventArgs)`
4. **Material Design**: Different implementation using Material.Avalonia vs WPF Material Design
5. **Theme System**: **MANDATORY** use of Material.Avalonia theme resources instead of hard-coded values

### Enhanced Features
1. **Cross-platform support**: Windows + Linux (WPF was Windows-only)
2. **Modern theming**: Material.Avalonia with **automatic light/dark mode switching**
3. **Better testing**: xUnit + Avalonia.Headless.XUnit vs MSTest
4. **Improved performance**: Native compilation and better memory management
5. **System theme integration**: Automatic detection and following of OS dark/light mode

### Architecture Improvements
1. **Async initialization**: Proper async/await throughout the application
2. **Better separation**: Enhanced MVVM with dependency injection
3. **Error handling**: Improved error states and user feedback
4. **Configuration**: Embedded resource configuration with fallbacks
5. **Theme compliance**: All UI elements use dynamic theme resources for consistency

## Future Enhancements

### Planned Features
- **Data visualization**: Charts and graphs for query results
- **Plugin architecture**: Extensible functionality
- **Advanced theming**: Custom color schemes and themes beyond Indigo/Pink
- **Enhanced offline mode**: Advanced offline database capabilities and sync management
- **Export options**: Additional data export formats (CSV, JSON, Excel)
- **Query performance profiling**: Query execution time analysis and optimization suggestions

### Cross-Platform Enhancements
- **Mobile platforms**: Avalonia mobile platform support (iOS, Android)
- **Package managers**: Expanded package manager integration:
  - **Windows**: WinGet, Chocolatey, Microsoft Store
  - **Linux**: APT, YUM/DNF, Snap, Flatpak
  - **macOS**: Homebrew, MacPorts
- **Native ARM64**: Optimized ARM64 builds for Apple Silicon and ARM-based Linux devices

## Notes

This Avalonia implementation provides comprehensive database management functionality for Ditto with full cross-platform support. The application runs natively on Windows, Linux, and macOS with modern Material Design theming and a consistent user experience across all platforms.

### Key Achievements:
- **✅ Full Cross-Platform Support**: Native performance on Windows 10/11, Linux (Debian 9+, Ubuntu 16.04+, Fedora 30+), and macOS 15+
- **✅ Modern Architecture**: Complete MVVM implementation with dependency injection, messaging, and service layers
- **✅ Feature Complete**: All core database operations including queries, subscriptions, collections, indexes, and observers
- **✅ Production Ready**: Built with .NET 10.0, comprehensive error handling, and Material Design theming with light/dark mode support

The project follows Avalonia best practices and uses the recommended xUnit testing framework for better compatibility with the Avalonia ecosystem. The codebase is structured for maintainability with clear separation of concerns across Data, Services, ViewModels, Views, and Models layers.