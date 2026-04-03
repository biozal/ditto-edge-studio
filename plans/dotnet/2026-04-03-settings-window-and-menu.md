# Settings Window & Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cross-platform Settings window with an MCP Server toggle (off by default), wire it to the Preferences menu on macOS and a new Settings menu item on Windows/Linux.

**Architecture:** Create a `PreferencesWindow` (SukiWindow) with a `PreferencesViewModel` following the existing `TransportSettingsWindow` pattern. Settings are persisted in a new `app_settings` table in the existing encrypted SQLite database via a new `ISettingsRepository`. The macOS "Preferences..." menu in `App.axaml` gets a click handler; Windows/Linux get a "Settings..." item in the Edit menu of `MainWindow.axaml`. The MCP toggle writes `mcpServerEnabled` and `mcpServerPort` to the database — Plan B (MCP Server) reads these values to start/stop.

**Tech Stack:** C# / Avalonia UI / SukiUI / SQLite (existing encrypted DB) / CommunityToolkit.Mvvm

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `dotnet/src/EdgeStudio.Shared/Data/ISettingsRepository.cs` | Create | Interface for reading/writing app settings |
| `dotnet/src/EdgeStudio.Shared/Data/SqliteSettingsRepository.cs` | Create | SQLite-backed implementation with `app_settings` table |
| `dotnet/src/EdgeStudio/ViewModels/PreferencesViewModel.cs` | Create | ViewModel for the preferences window with MCP toggle |
| `dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml` | Create | XAML layout for the preferences window |
| `dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml.cs` | Create | Code-behind with ViewModel constructor |
| `dotnet/src/EdgeStudio/App.axaml` | Modify (line 15) | Add Click handler to "Preferences..." menu item |
| `dotnet/src/EdgeStudio/App.axaml.cs` | Modify | Add PreferencesMenuItem_Click handler |
| `dotnet/src/EdgeStudio/Views/MainWindow.axaml` | Modify (Edit menu) | Add "Settings..." item for Windows/Linux |
| `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs` | Modify | Add Settings_Click handler |
| `dotnet/src/EdgeStudio/App.axaml.cs` | Modify (DI) | Register ISettingsRepository and PreferencesViewModel |
| `dotnet/src/EdgeStudioTests/SettingsRepositoryTests.cs` | Create | Tests for settings persistence |
| `dotnet/src/EdgeStudioTests/PreferencesViewModelTests.cs` | Create | Tests for ViewModel logic |

---

### Task 1: Create ISettingsRepository and SqliteSettingsRepository

**Files:**
- Create: `dotnet/src/EdgeStudio.Shared/Data/ISettingsRepository.cs`
- Create: `dotnet/src/EdgeStudio.Shared/Data/SqliteSettingsRepository.cs`

- [ ] **Step 1: Create the interface**

Create `dotnet/src/EdgeStudio.Shared/Data/ISettingsRepository.cs`:

```csharp
namespace EdgeStudio.Shared.Data;

public interface ISettingsRepository
{
    Task InitializeAsync();
    Task<string?> GetAsync(string key);
    Task SetAsync(string key, string value);
    Task<bool> GetBoolAsync(string key, bool defaultValue = false);
    Task SetBoolAsync(string key, bool value);
    Task<int> GetIntAsync(string key, int defaultValue = 0);
    Task SetIntAsync(string key, int value);
}
```

- [ ] **Step 2: Create the SQLite implementation**

Create `dotnet/src/EdgeStudio.Shared/Data/SqliteSettingsRepository.cs`:

```csharp
using Microsoft.Data.Sqlite;

namespace EdgeStudio.Shared.Data;

public class SqliteSettingsRepository : ISettingsRepository
{
    private readonly ILocalDatabaseService _db;

    public SqliteSettingsRepository(ILocalDatabaseService db)
    {
        _db = db;
    }

    public async Task InitializeAsync()
    {
        await using var connection = _db.CreateOpenConnection();
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY NOT NULL,
                value TEXT NOT NULL
            )
            """;
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task<string?> GetAsync(string key)
    {
        await using var connection = _db.CreateOpenConnection();
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = "SELECT value FROM app_settings WHERE key = @key";
        cmd.Parameters.AddWithValue("@key", key);
        var result = await cmd.ExecuteScalarAsync();
        return result as string;
    }

    public async Task SetAsync(string key, string value)
    {
        await using var connection = _db.CreateOpenConnection();
        await using var cmd = connection.CreateCommand();
        cmd.CommandText = """
            INSERT INTO app_settings (key, value) VALUES (@key, @value)
            ON CONFLICT(key) DO UPDATE SET value = @value
            """;
        cmd.Parameters.AddWithValue("@key", key);
        cmd.Parameters.AddWithValue("@value", value);
        await cmd.ExecuteNonQueryAsync();
    }

    public async Task<bool> GetBoolAsync(string key, bool defaultValue = false)
    {
        var value = await GetAsync(key);
        return value != null ? value == "true" : defaultValue;
    }

    public async Task SetBoolAsync(string key, bool value)
    {
        await SetAsync(key, value ? "true" : "false");
    }

    public async Task<int> GetIntAsync(string key, int defaultValue = 0)
    {
        var value = await GetAsync(key);
        return value != null && int.TryParse(value, out var result) ? result : defaultValue;
    }

    public async Task SetIntAsync(string key, int value)
    {
        await SetAsync(key, value.ToString());
    }
}
```

- [ ] **Step 3: Build to verify compilation**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio.Shared/EdgeStudio.Shared.csproj --verbosity minimal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio.Shared/Data/ISettingsRepository.cs dotnet/src/EdgeStudio.Shared/Data/SqliteSettingsRepository.cs
git commit -m "feat(dotnet): add ISettingsRepository with SQLite key-value settings storage"
```

---

### Task 2: Write Tests for SettingsRepository

**Files:**
- Create: `dotnet/src/EdgeStudioTests/SettingsRepositoryTests.cs`

- [ ] **Step 1: Create tests**

Create `dotnet/src/EdgeStudioTests/SettingsRepositoryTests.cs`:

```csharp
using System;
using System.IO;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using FluentAssertions;
using Moq;
using Microsoft.Data.Sqlite;
using Xunit;

namespace EdgeStudioTests;

public class SettingsRepositoryTests : IDisposable
{
    private readonly string _dbPath;
    private readonly Mock<ILocalDatabaseService> _mockDb;
    private readonly SqliteSettingsRepository _repo;

    public SettingsRepositoryTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"test_settings_{Guid.NewGuid()}.db");
        _mockDb = new Mock<ILocalDatabaseService>();
        _mockDb.Setup(x => x.CreateOpenConnection()).Returns(() =>
        {
            var conn = new SqliteConnection($"Data Source={_dbPath}");
            conn.Open();
            return conn;
        });
        _repo = new SqliteSettingsRepository(_mockDb.Object);
    }

    public void Dispose()
    {
        if (File.Exists(_dbPath))
            File.Delete(_dbPath);
    }

    [Fact]
    public async Task InitializeAsync_CreatesAppSettingsTable()
    {
        await _repo.InitializeAsync();

        await using var conn = _mockDb.Object.CreateOpenConnection();
        await using var cmd = conn.CreateCommand();
        cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'";
        var result = await cmd.ExecuteScalarAsync();
        result.Should().Be("app_settings");
    }

    [Fact]
    public async Task GetAsync_ReturnsNull_WhenKeyDoesNotExist()
    {
        await _repo.InitializeAsync();
        var result = await _repo.GetAsync("nonexistent");
        result.Should().BeNull();
    }

    [Fact]
    public async Task SetAsync_And_GetAsync_RoundTrip()
    {
        await _repo.InitializeAsync();
        await _repo.SetAsync("testKey", "testValue");
        var result = await _repo.GetAsync("testKey");
        result.Should().Be("testValue");
    }

    [Fact]
    public async Task SetAsync_OverwritesExistingValue()
    {
        await _repo.InitializeAsync();
        await _repo.SetAsync("key", "first");
        await _repo.SetAsync("key", "second");
        var result = await _repo.GetAsync("key");
        result.Should().Be("second");
    }

    [Fact]
    public async Task GetBoolAsync_ReturnsDefault_WhenKeyMissing()
    {
        await _repo.InitializeAsync();
        var result = await _repo.GetBoolAsync("missing", defaultValue: true);
        result.Should().BeTrue();
    }

    [Fact]
    public async Task SetBoolAsync_And_GetBoolAsync_RoundTrip()
    {
        await _repo.InitializeAsync();
        await _repo.SetBoolAsync("mcpServerEnabled", true);
        var result = await _repo.GetBoolAsync("mcpServerEnabled");
        result.Should().BeTrue();
    }

    [Fact]
    public async Task GetIntAsync_ReturnsDefault_WhenKeyMissing()
    {
        await _repo.InitializeAsync();
        var result = await _repo.GetIntAsync("port", defaultValue: 65269);
        result.Should().Be(65269);
    }

    [Fact]
    public async Task SetIntAsync_And_GetIntAsync_RoundTrip()
    {
        await _repo.InitializeAsync();
        await _repo.SetIntAsync("mcpServerPort", 8080);
        var result = await _repo.GetIntAsync("mcpServerPort");
        result.Should().Be(8080);
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~SettingsRepositoryTests" --logger "console;verbosity=detailed"
```

Expected: All 8 tests pass.

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudioTests/SettingsRepositoryTests.cs
git commit -m "test(dotnet): add tests for SqliteSettingsRepository"
```

---

### Task 3: Create PreferencesViewModel

**Files:**
- Create: `dotnet/src/EdgeStudio/ViewModels/PreferencesViewModel.cs`

- [ ] **Step 1: Create the ViewModel**

Create `dotnet/src/EdgeStudio/ViewModels/PreferencesViewModel.cs`:

```csharp
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Shared.Data;

namespace EdgeStudio.ViewModels;

public partial class PreferencesViewModel : ViewModelBase
{
    private readonly ISettingsRepository _settings;

    [ObservableProperty]
    private bool _isMcpServerEnabled;

    [ObservableProperty]
    private int _mcpServerPort = 65269;

    [ObservableProperty]
    private string _statusMessage = string.Empty;

    public PreferencesViewModel(ISettingsRepository settings, IToastService toastService)
        : base(toastService)
    {
        _settings = settings;
    }

    public async Task LoadSettingsAsync()
    {
        IsMcpServerEnabled = await _settings.GetBoolAsync("mcpServerEnabled", defaultValue: false);
        McpServerPort = await _settings.GetIntAsync("mcpServerPort", defaultValue: 65269);
    }

    [RelayCommand]
    private async Task SaveSettingsAsync()
    {
        try
        {
            if (McpServerPort < 1024 || McpServerPort > 65535)
            {
                StatusMessage = "Port must be between 1024 and 65535.";
                return;
            }

            await _settings.SetBoolAsync("mcpServerEnabled", IsMcpServerEnabled);
            await _settings.SetIntAsync("mcpServerPort", McpServerPort);

            StatusMessage = "Settings saved.";
            ShowSuccess("Settings saved successfully.");
        }
        catch (System.Exception ex)
        {
            StatusMessage = $"Failed to save: {ex.Message}";
            ShowError($"Failed to save settings: {ex.Message}");
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/PreferencesViewModel.cs
git commit -m "feat(dotnet): add PreferencesViewModel with MCP server settings"
```

---

### Task 4: Write Tests for PreferencesViewModel

**Files:**
- Create: `dotnet/src/EdgeStudioTests/PreferencesViewModelTests.cs`

- [ ] **Step 1: Create tests**

Create `dotnet/src/EdgeStudioTests/PreferencesViewModelTests.cs`:

```csharp
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Services;
using EdgeStudio.ViewModels;
using FluentAssertions;
using Moq;
using Xunit;

namespace EdgeStudioTests;

public class PreferencesViewModelTests
{
    private readonly Mock<ISettingsRepository> _mockSettings;
    private readonly Mock<IToastService> _mockToast;
    private readonly PreferencesViewModel _vm;

    public PreferencesViewModelTests()
    {
        _mockSettings = new Mock<ISettingsRepository>();
        _mockToast = new Mock<IToastService>();
        _vm = new PreferencesViewModel(_mockSettings.Object, _mockToast.Object);
    }

    [Fact]
    public async Task LoadSettingsAsync_LoadsValuesFromRepository()
    {
        _mockSettings.Setup(s => s.GetBoolAsync("mcpServerEnabled", false))
            .ReturnsAsync(true);
        _mockSettings.Setup(s => s.GetIntAsync("mcpServerPort", 65269))
            .ReturnsAsync(9090);

        await _vm.LoadSettingsAsync();

        _vm.IsMcpServerEnabled.Should().BeTrue();
        _vm.McpServerPort.Should().Be(9090);
    }

    [Fact]
    public async Task LoadSettingsAsync_UsesDefaults_WhenNoSettingsExist()
    {
        _mockSettings.Setup(s => s.GetBoolAsync("mcpServerEnabled", false))
            .ReturnsAsync(false);
        _mockSettings.Setup(s => s.GetIntAsync("mcpServerPort", 65269))
            .ReturnsAsync(65269);

        await _vm.LoadSettingsAsync();

        _vm.IsMcpServerEnabled.Should().BeFalse();
        _vm.McpServerPort.Should().Be(65269);
    }

    [Fact]
    public async Task SaveSettingsCommand_PersistsValues()
    {
        _vm.IsMcpServerEnabled = true;
        _vm.McpServerPort = 8080;

        await _vm.SaveSettingsCommand.ExecuteAsync(null);

        _mockSettings.Verify(s => s.SetBoolAsync("mcpServerEnabled", true), Times.Once);
        _mockSettings.Verify(s => s.SetIntAsync("mcpServerPort", 8080), Times.Once);
    }

    [Fact]
    public async Task SaveSettingsCommand_RejectsInvalidPort()
    {
        _vm.McpServerPort = 80; // Below 1024

        await _vm.SaveSettingsCommand.ExecuteAsync(null);

        _mockSettings.Verify(s => s.SetBoolAsync(It.IsAny<string>(), It.IsAny<bool>()), Times.Never);
        _vm.StatusMessage.Should().Contain("Port must be between");
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~PreferencesViewModelTests" --logger "console;verbosity=detailed"
```

**Note:** The test may need adjustment depending on how `IToastService` is referenced. Check the using statements — it may be in `EdgeStudio.Shared.Services` or `EdgeStudio.Services`. Match whatever the codebase uses. The implementer should check `ViewModelBase` constructor to determine the correct `IToastService` namespace and interface.

Expected: All 4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudioTests/PreferencesViewModelTests.cs
git commit -m "test(dotnet): add tests for PreferencesViewModel"
```

---

### Task 5: Create PreferencesWindow (XAML + Code-Behind)

**Files:**
- Create: `dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml`
- Create: `dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml.cs`

- [ ] **Step 1: Create the XAML file**

Create `dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml`:

```xml
<suki:SukiWindow xmlns="https://github.com/avaloniaui"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
                 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
                 xmlns:vm="using:EdgeStudio.ViewModels"
                 xmlns:suki="using:SukiUI.Controls"
                 mc:Ignorable="d"
                 d:DesignWidth="460"
                 d:DesignHeight="320"
                 x:Class="EdgeStudio.Views.Settings.PreferencesWindow"
                 x:DataType="vm:PreferencesViewModel"
                 x:CompileBindings="True"
                 Title="Edge Studio Settings"
                 Width="460"
                 SizeToContent="Height"
                 MaxHeight="500"
                 WindowStartupLocation="CenterOwner"
                 CanResize="False"
                 BackgroundStyle="Flat">

    <Grid RowDefinitions="*,Auto">

        <!-- Settings content -->
        <StackPanel Grid.Row="0" Margin="24,16,24,8" Spacing="16">

            <!-- MCP Server Section -->
            <TextBlock Text="MCP Server" FontSize="18" FontWeight="SemiBold" />

            <StackPanel Spacing="8">
                <ToggleSwitch IsChecked="{Binding IsMcpServerEnabled}"
                              Content="Enable MCP Server"
                              OnContent="Running"
                              OffContent="Disabled" />

                <StackPanel Orientation="Horizontal" Spacing="8"
                            IsVisible="{Binding IsMcpServerEnabled}">
                    <TextBlock Text="Port:" VerticalAlignment="Center" />
                    <NumericUpDown Value="{Binding McpServerPort}"
                                   Minimum="1024"
                                   Maximum="65535"
                                   FormatString="0"
                                   Width="120" />
                </StackPanel>

                <TextBlock Text="The MCP server allows AI assistants like Claude Code to interact with your Ditto databases. It listens on localhost only."
                           TextWrapping="Wrap"
                           FontSize="12"
                           Opacity="0.6" />
            </StackPanel>

        </StackPanel>

        <!-- Footer: status + buttons -->
        <StackPanel Grid.Row="1" Margin="24,4,24,16" Spacing="8">

            <TextBlock Text="{Binding StatusMessage}"
                       FontSize="12"
                       Opacity="0.7"
                       IsVisible="{Binding StatusMessage, Converter={x:Static StringConverters.IsNotNullOrEmpty}}" />

            <Grid ColumnDefinitions="*,Auto">
                <Button Content="Close"
                        Classes="Flat"
                        Click="Close_Click" />
                <Button Grid.Column="1"
                        Content="Save"
                        Command="{Binding SaveSettingsCommand}" />
            </Grid>
        </StackPanel>

    </Grid>

</suki:SukiWindow>
```

- [ ] **Step 2: Create the code-behind file**

Create `dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml.cs`:

```csharp
using Avalonia.Interactivity;
using EdgeStudio.ViewModels;
using SukiUI.Controls;

namespace EdgeStudio.Views.Settings;

public partial class PreferencesWindow : SukiWindow
{
    public PreferencesWindow()
    {
        InitializeComponent();
    }

    public PreferencesWindow(PreferencesViewModel vm) : this()
    {
        DataContext = vm;
    }

    private void Close_Click(object? sender, RoutedEventArgs e) => Close();
}
```

- [ ] **Step 3: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml dotnet/src/EdgeStudio/Views/Settings/PreferencesWindow.axaml.cs
git commit -m "feat(dotnet): add PreferencesWindow with MCP server toggle"
```

---

### Task 6: Register in DI and Wire Menu Items

**Files:**
- Modify: `dotnet/src/EdgeStudio/App.axaml` (line 15)
- Modify: `dotnet/src/EdgeStudio/App.axaml.cs` (DI registration + menu handler)
- Modify: `dotnet/src/EdgeStudio/Views/MainWindow.axaml` (Edit menu)
- Modify: `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs` (Settings handler)

- [ ] **Step 1: Add Click handler to macOS Preferences menu in App.axaml**

In `dotnet/src/EdgeStudio/App.axaml`, change line 15 from:

```xml
<NativeMenuItem Header="Preferences…" Gesture="Meta+," />
```

To:

```xml
<NativeMenuItem Header="Preferences…" Gesture="Meta+," Click="PreferencesMenuItem_Click" />
```

- [ ] **Step 2: Add "Settings..." to Edit menu in MainWindow.axaml for Windows/Linux**

In `dotnet/src/EdgeStudio/Views/MainWindow.axaml`, find the Edit menu section and add a Settings item with a separator before it. Find:

```xml
<NativeMenuItem Header="Edit">
    <NativeMenu>
```

Add at the end of the Edit NativeMenu children (before the closing `</NativeMenu>`):

```xml
<NativeMenuItemSeparator />
<NativeMenuItem Header="Settings…" Click="Settings_Click" />
```

- [ ] **Step 3: Register ISettingsRepository and PreferencesViewModel in DI**

In `dotnet/src/EdgeStudio/App.axaml.cs`, in the `InitializeDependencyInjectionAsync()` method, add after the other repository registrations:

```csharp
// Settings repository
var settingsRepo = new SqliteSettingsRepository(localDatabaseService);
await settingsRepo.InitializeAsync();
services.AddSingleton<ISettingsRepository>(settingsRepo);
```

And in the ViewModel registrations section:

```csharp
services.AddTransient<PreferencesViewModel>();
```

Add the required using at the top of the file:

```csharp
using EdgeStudio.Shared.Data;
```

- [ ] **Step 4: Add PreferencesMenuItem_Click handler in App.axaml.cs**

In `dotnet/src/EdgeStudio/App.axaml.cs`, add a new method (e.g., after `AboutMenuItem_Click`):

```csharp
private async void PreferencesMenuItem_Click(object? sender, EventArgs e)
{
    if (_serviceProvider == null) return;

    var vm = _serviceProvider.GetRequiredService<PreferencesViewModel>();
    await vm.LoadSettingsAsync();

    var window = new Views.Settings.PreferencesWindow(vm);

    if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop && desktop.MainWindow != null)
        window.ShowDialog(desktop.MainWindow);
    else
        window.Show();
}
```

Add the required using if not present:

```csharp
using Microsoft.Extensions.DependencyInjection;
```

- [ ] **Step 5: Add Settings_Click handler in MainWindow.axaml.cs**

In `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs`, add:

```csharp
private async void Settings_Click(object? sender, EventArgs e)
{
    var vm = App.ServiceProvider?.GetService(typeof(PreferencesViewModel)) as PreferencesViewModel;
    if (vm == null) return;

    await vm.LoadSettingsAsync();
    var window = new Settings.PreferencesWindow(vm);
    window.ShowDialog(this);
}
```

Add the required using:

```csharp
using EdgeStudio.ViewModels;
```

- [ ] **Step 6: Build and run full test suite**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj
```

- [ ] **Step 7: Commit**

```bash
git add dotnet/src/EdgeStudio/App.axaml dotnet/src/EdgeStudio/App.axaml.cs dotnet/src/EdgeStudio/Views/MainWindow.axaml dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs
git commit -m "feat(dotnet): wire Settings menu items and register DI for preferences"
```

---

### Task 7: Manual Verification

- [ ] **Step 1: Run the app on macOS**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet run --project EdgeStudio/EdgeStudio.csproj
```

Verify:
1. **Edge Studio > Preferences...** (Cmd+,) opens the Settings window
2. MCP Server toggle is OFF by default
3. Toggling ON reveals the port field (default 65269)
4. Save persists values — close and reopen to verify
5. Port validation rejects values below 1024

- [ ] **Step 2: Verify Edit > Settings... appears**

On macOS the Edit menu should show "Settings..." at the bottom. On Windows/Linux this would be the primary way to access settings.

- [ ] **Step 3: Verify both themes**

Switch system theme (light/dark) and confirm the settings window renders correctly in both.
