# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with the Windows Presentation Framework (WPF) version of Edge Studio.

## Project Overview

Edge Studio WPF is a Windows desktop application for querying and managing Ditto databases. This is the Windows Presentation Framework implementation of the same functionality found in the SwiftUI and Rust/Tauri versions of the application.

**Application Name:** Edge Studio  
**Framework:** WPF (.NET 9.0)  
**Platform:** Windows Desktop

## Development Environment Setup

### Prerequisites
- Visual Studio 2022 or later with .NET desktop development workload
- .NET 9.0 SDK
- Windows 10/11 development environment

### Build Environment
```bash
# Restore NuGet packages
dotnet restore

# Build the solution
dotnet build EdgeStudio.sln

# Build in Release configuration
dotnet build EdgeStudio.sln -c Release

# Run the application
dotnet run --project EdgeStudio/EdgeStudio.csproj
```

## Build Commands

### Command Line (dotnet CLI)
```bash
# Clean the solution
dotnet clean

# Build Debug configuration
dotnet build

# Build Release configuration
dotnet build -c Release

# Run the application
dotnet run

# Run tests (when available)
dotnet test

# Publish for Windows
dotnet publish -c Release -r win-x64 --self-contained
```

### Visual Studio
- Open `EdgeStudio.sln` in Visual Studio
- Build: `Ctrl+Shift+B` or Build → Build Solution
- Run: `F5` (Debug) or `Ctrl+F5` (Without Debugging)
- Clean: Build → Clean Solution

## Architecture

### Project Structure
Located in the `wpf/` directory:

**Solution Files:**
- **EdgeStudio.sln**: Visual Studio solution file
- **CLAUDE.md**: Project documentation and guidance

**EdgeStudio Project:**
- **EdgeStudio/EdgeStudio.csproj**: Main project file defining dependencies and build configuration
- **EdgeStudio/App.xaml / App.xaml.cs**: Application entry point and global resources
- **EdgeStudio/AssemblyInfo.cs**: Assembly metadata and versioning
- **EdgeStudio/AppExceptions.cs**: Global exception handling

**Data Layer:**
- **EdgeStudio/Data/DittoManager.cs**: Core Ditto database connection manager
- **EdgeStudio/Data/Repositories/**:
  - `IDatabaseRepository.cs`: Database repository interface
  - `DittoDatabaseRepository.cs`: Ditto-specific database repository implementation

**Models:**
- **EdgeStudio/Models/DittoDatabaseConfig.cs**: Configuration model for Ditto database connections

**ViewModels (MVVM):**
- **EdgeStudio/ViewModels/MainWindowViewModel.cs**: Main window view model

**Views:**
- **EdgeStudio/Views/**:
  - `MainWindow.xaml / MainWindow.xaml.cs`: Main application window
  - `LoadingWindow.xaml / LoadingWindow.xaml.cs`: Loading/splash screen
- **EdgeStudio/MainWindow.xaml.cs**: Legacy main window (moved to Views folder)

**Themes:**
- **EdgeStudio/Themes/**:
  - `DarkTheme.xaml`: Dark theme resource dictionary
  - `LightTheme.xaml`: Light theme resource dictionary

**Helpers:**
- **EdgeStudio/Helpers/**:
  - `EnvFileReader.cs`: Environment file configuration reader
  - `ThemeHelper.cs`: Theme management utilities

**Test Project:**
- **EdgeStudioTests/EdgeStudioTests.csproj**: Test project configuration
- **EdgeStudioTests/Test1.cs**: Sample test file
- **EdgeStudioTests/MSTestSettings.cs**: MSTest configuration

### Current Implementation Status
- **Data Layer**: ✅ Implemented
  - DittoManager service for database connections
  - Repository pattern with interface-based design
  - Configuration model for database settings

- **MVVM Architecture**: ✅ Partially Implemented
  - MainWindowViewModel for main window data binding
  - Separation of Views into dedicated folder
  - Repository pattern for data access

- **UI Framework**: ✅ Implemented
  - Theme system with light/dark mode support
  - Loading window for application startup
  - Main window structure in place

- **Configuration**: ✅ Implemented
  - Environment file reader for configuration
  - Ditto database configuration model

- **Testing**: ✅ Initialized
  - MSTest framework configured
  - Test project structure in place

## Configuration Requirements

### Application Configuration
Will require configuration similar to SwiftUI version:
- Ditto application ID
- Authentication token
- Authentication endpoint URL
- WebSocket endpoint URL
- HTTP API endpoint and key

Configuration storage options:
- App.config / appsettings.json for static configuration
- User settings for per-user configuration
- Secure storage for sensitive credentials

## Key Features (Planned)

### Core Functionality
- Multi-app connection management with Windows credential storage
- Query execution with history and favorites
- Real-time subscriptions and observables
- Presence viewer and peer management
- Disk usage monitoring
- Import/export functionality
- Permissions health checking

### Windows-Specific Features
- Windows notifications integration
- System tray support for background operation
- Native Windows theming (Light/Dark mode)
- Windows Hello for secure credential storage

## Testing

### Unit Tests
- **EdgeStudioTests**: MSTest-based test project
- Use MSTest framework for unit testing
- Mock Ditto dependencies for isolated testing
- Run tests: `dotnet test EdgeStudioTests/EdgeStudioTests.csproj`

### Integration Tests
- Test actual Ditto connections
- Verify query execution and results
- Test subscription mechanisms

### Test Structure
- **EdgeStudioTests/MSTestSettings.cs**: MSTest configuration and settings
- **EdgeStudioTests/Test1.cs**: Sample test implementation

## Platform Requirements

### Runtime Requirements
- Windows 10 version 1809 or later
- Windows 11
- .NET 9.0 Windows Desktop Runtime

### Development Requirements
- Visual Studio 2022 or later
- .NET 9.0 SDK
- Windows SDK

## Dependencies

### NuGet Packages (to be added)
```xml
<!-- Core WPF packages -->
<PackageReference Include="CommunityToolkit.Mvvm" Version="*" />
<PackageReference Include="Microsoft.Extensions.DependencyInjection" Version="*" />
<PackageReference Include="Microsoft.Extensions.Configuration" Version="*" />

<!-- UI enhancements -->
<PackageReference Include="ModernWpfUI" Version="*" />
<PackageReference Include="AvalonEdit" Version="*" /> <!-- For code editor -->

<!-- Data and networking -->
<PackageReference Include="Newtonsoft.Json" Version="*" />
<PackageReference Include="System.Reactive" Version="*" />

<!-- Ditto SDK (when available) -->
<!-- <PackageReference Include="Ditto" Version="*" /> -->
```

## MVVM Pattern Implementation

### ViewModels
- **MainWindowViewModel**: Currently implemented - orchestrates main window state
- **ConnectionViewModel**: Planned - manages Ditto connections
- **QueryViewModel**: Planned - handles query execution
- **SubscriptionViewModel**: Planned - manages subscriptions
- **ObservableViewModel**: Planned - handles observable events

### Data Binding
- Use INotifyPropertyChanged or CommunityToolkit.Mvvm
- Implement ICommand for user actions
- Use ObservableCollection for dynamic lists

## Threading Considerations

### UI Thread Management
- Use Dispatcher for UI updates from background threads
- Implement async/await patterns for non-blocking operations
- Use Task.Run for CPU-intensive operations

### Background Operations
- Query execution on background threads
- Subscription updates via Dispatcher
- Progress reporting for long-running operations

## Troubleshooting

### Build Issues
- Ensure .NET 9.0 SDK is installed
- Clear bin and obj folders if encountering strange build errors
- Restore NuGet packages: `dotnet restore`

### Runtime Issues
- Check Windows Event Viewer for application errors
- Enable detailed logging for debugging
- Verify Ditto configuration is correct

## Coding Standards

### Naming Conventions
- PascalCase for public members and types
- camelCase for private fields (with underscore prefix optional)
- XAML x:Name uses PascalCase

### XAML Best Practices
- Use data binding instead of code-behind when possible
- Define resources in appropriate scope
- Use styles and templates for consistent UI

### C# Best Practices
- Use async/await for asynchronous operations
- Implement IDisposable for resource cleanup
- Use dependency injection for testability

## Future Enhancements

### Planned Features
- Plugin architecture for extensibility
- Custom query templates
- Data visualization components
- Export to multiple formats (CSV, JSON, Excel)
- Batch operations support

### Performance Optimizations
- Virtualization for large data sets
- Lazy loading for improved startup time
- Caching for frequently accessed data
- Background indexing for search

## Notes

This is a new WPF implementation of Edge Studio. Development should follow Windows desktop application best practices while maintaining feature parity with the SwiftUI version where applicable.