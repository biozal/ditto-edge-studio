# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Avalonia version of Edge Studio.

## Project Overview

Edge Studio Avalonia is a cross-platform desktop application for querying and managing Ditto databases. This is the Avalonia UI implementation of the same functionality found in the WPF and other versions of the application, providing native performance on Windows and Linux platforms.

**Application Name:** Edge Studio  
**Framework:** Avalonia UI (.NET 9.0) with Material Design  
**Platform:** Windows and Linux Desktop

## Development Environment Setup

### Prerequisites
- Visual Studio 2022 or later with .NET desktop development workload, OR
- JetBrains Rider, OR  
- VS Code with C# Dev Kit extension
- .NET 9.0 SDK
- Windows 10/11 or Linux development environment

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
Located in the `avalonia/` directory:

**Solution Files:**
- **EdgeStudio.sln**: Solution file containing both main project and tests
- **CLAUDE.md**: Project documentation and guidance

**EdgeStudio Project:**
- **EdgeStudio/EdgeStudio.csproj**: Main project file with Avalonia, Material.Avalonia, AvaloniaEdit, and Ditto SDK dependencies
- **EdgeStudio/App.axaml / App.axaml.cs**: Application entry point with Material Design theming and dependency injection
- **EdgeStudio/ViewLocator.cs**: MVVM view location logic

**Data Layer:**
- **EdgeStudio/Data/IDittoManager.cs**: Interface defining core Ditto database operations
- **EdgeStudio/Data/DittoManager.cs**: Implementation of Ditto database connection and management
- **EdgeStudio/Data/Repositories/**:
  - `IDatabaseRepository.cs`: Database repository interface
  - `DittoDatabaseRepository.cs`: Ditto-specific repository with Avalonia threading integration

**Models:**
- **EdgeStudio/Models/DittoDatabaseConfig.cs**: Record type for database configuration with JSON serialization
- **EdgeStudio/Models/DatabaseFormModel.cs**: ObservableObject for form data binding and validation

**ViewModels (MVVM):**
- **EdgeStudio/ViewModels/MainWindowViewModel.cs**: Main application ViewModel with async database initialization
- **EdgeStudio/ViewModels/EdgeStudioViewModel.cs**: Database workspace ViewModel

**Views:**
- **EdgeStudio/Views/**:
  - `MainWindow.axaml / MainWindow.axaml.cs`: Main application window with navigation logic
  - `LoadingWindow.axaml / LoadingWindow.axaml.cs`: Application startup loading window
  - `DatabaseListingView.axaml / DatabaseListingView.axaml.cs`: Material Design database listing with cards
  - `EdgeStudioView.axaml / EdgeStudioView.axaml.cs`: Database workspace view with Material Design styling

**Helpers:**
- **EdgeStudio/Helpers/EnvFileReader.cs**: Environment configuration file reader with embedded resource support

**Test Project:**
- **EdgeStudioTests/EdgeStudioTests.csproj**: xUnit test project with Avalonia.Headless.XUnit, Moq, and FluentAssertions
- **EdgeStudioTests/UnitTest1.cs**: Basic test infrastructure (to be expanded)

### Current Implementation Status
- **Cross-Platform UI**: ✅ Implemented with Avalonia UI
- **Material Design**: ✅ Implemented with Material.Avalonia theming
- **Data Layer**: ✅ Fully ported from WPF with Avalonia threading adaptations
- **MVVM Architecture**: ✅ Complete with async operations and proper data binding
- **Navigation System**: ✅ View switching with loading states and error handling
- **Dependency Injection**: ✅ Microsoft.Extensions.DependencyInjection integration
- **Configuration**: ✅ Environment file reader with embedded resource support
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
- **Windows and Linux Support**: Native performance on both platforms
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
- **Cross-platform deployment**: Single codebase for Windows and Linux
- **Material Design theming**: Indigo and Pink color scheme with light/dark support
- **XAML Hot Reload**: Development-time UI updates
- **Native performance**: No browser overhead compared to Electron alternatives

## Platform Requirements

### Runtime Requirements
- **Windows**: Windows 10 version 1809 or later, Windows 11
- **Linux**: Modern Linux distributions with X11 or Wayland
- **.NET 9.0 Runtime**: Cross-platform runtime

### Development Requirements
- .NET 9.0 SDK
- Platform-specific development tools:
  - **Windows**: Visual Studio 2022+ or VS Code
  - **Linux**: JetBrains Rider, VS Code, or command line tools

## Dependencies

### Core Avalonia Packages
```xml
<!-- UI Framework -->
<PackageReference Include="Avalonia" Version="11.3.4" />
<PackageReference Include="Avalonia.Desktop" Version="11.3.4" />
<PackageReference Include="Avalonia.Themes.Fluent" Version="11.3.4" />
<PackageReference Include="Avalonia.Fonts.Inter" Version="11.3.4" />

<!-- Material Design -->
<PackageReference Include="Material.Avalonia" Version="3.7.3" />

<!-- Code Editor -->
<PackageReference Include="AvaloniaEdit" Version="0.10.12" />
```

### Business Logic Dependencies
```xml
<!-- MVVM Framework -->
<PackageReference Include="CommunityToolkit.Mvvm" Version="8.4.0" />

<!-- Ditto SDK -->
<PackageReference Include="Ditto" Version="4.12.0" />

<!-- Dependency Injection -->
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="9.0.0" />
<PackageReference Include="Microsoft.Extensions.Configuration" Version="9.0.0" />
<PackageReference Include="Microsoft.Extensions.Configuration.Json" Version="9.0.0" />

<!-- JSON Handling -->
<PackageReference Include="System.Text.Json" Version="9.0.0" />
```

### Testing Dependencies
```xml
<!-- xUnit Testing Framework -->
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="17.8.0" />
<PackageReference Include="xunit" Version="2.8.2" />
<PackageReference Include="xunit.runner.visualstudio" Version="2.8.2" />

<!-- Avalonia Testing -->
<PackageReference Include="Avalonia.Headless.XUnit" Version="11.3.4" />

<!-- Mocking and Assertions -->
<PackageReference Include="Moq" Version="4.20.72" />
<PackageReference Include="FluentAssertions" Version="7.0.0" />
```

## MVVM Pattern Implementation

### ViewModels
- **MainWindowViewModel**: ✅ Implemented - orchestrates main window state with async database operations
- **EdgeStudioViewModel**: ✅ Implemented - manages database workspace state
- **ConnectionViewModel**: Planned - enhanced connection management
- **QueryViewModel**: Planned - query execution and history
- **SubscriptionViewModel**: Planned - real-time subscription management

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
- **Platform targeting**: Ensure project targets correct platforms (Windows/Linux only)
- **Package compatibility**: Verify all NuGet packages support .NET 9.0
- **Missing dependencies**: Run `dotnet restore` to restore packages

### Runtime Issues
- **Linux display**: Ensure X11 or Wayland is properly configured
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

# Framework-dependent (smaller, requires .NET runtime installed)
dotnet publish EdgeStudio/EdgeStudio.csproj -c Release -o ./publish/framework-dependent/
```

### Distribution
- **Windows**: Executable with optional installer creation
- **Linux**: AppImage, Flatpak, or native package distribution
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
- **Query editor**: AvaloniaEdit integration for DQL queries
- **Data visualization**: Charts and graphs for query results
- **Plugin architecture**: Extensible functionality
- **Advanced theming**: Custom color schemes and themes
- **Offline mode**: Enhanced offline database capabilities

### Cross-Platform Enhancements
- **macOS support**: Potential future expansion
- **Mobile platforms**: Avalonia mobile platform support
- **ARM64 support**: Native ARM64 compilation for better performance
- **Package managers**: Linux package manager integration

## Notes

This Avalonia implementation provides the same core functionality as the WPF version while adding cross-platform support and modern Material Design theming. The application maintains architectural compatibility with the WPF version while leveraging Avalonia's cross-platform capabilities and enhanced performance characteristics.

The project follows Avalonia best practices and uses the recommended xUnit testing framework for better compatibility with the Avalonia ecosystem. All WPF-specific code has been successfully adapted to use Avalonia equivalents while maintaining full functionality.