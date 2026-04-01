# Fix Broken Toasts and Add Database Init Error Dialog — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix silent toast notifications and show a modal error dialog when database initialization fails (e.g., invalid Database ID).

**Architecture:** Two independent fixes — (1) bind the existing `SukiToastHost` XAML to the DI-managed `ISukiToastManager` so toasts actually display, and (2) add a `SukiDialogHost` + `IDialogService` abstraction so `MainWindowViewModel` can show a blocking modal error dialog on database init failure instead of a transient toast.

**Tech Stack:** C# / .NET 10.0, Avalonia UI, SukiUI 6.0.3 (dialogs + toasts), xUnit + Moq + FluentAssertions

**Working directory:** `dotnet/src/` (all paths relative to this unless noted)

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `EdgeStudio/Views/MainWindow.axaml` | Modify | Add `Manager` binding to toast host, add dialog host |
| `EdgeStudio/Views/MainWindow.axaml.cs` | Modify | Add `DialogManager` property resolved from DI |
| `EdgeStudio/App.axaml.cs` | Modify | Register `ISukiDialogManager` and `IDialogService` in DI |
| `EdgeStudio.Shared/Services/IDialogService.cs` | Create | Platform-agnostic dialog service interface |
| `EdgeStudio/Services/SukiDialogService.cs` | Create | SukiUI implementation of `IDialogService` |
| `EdgeStudio/ViewModels/MainWindowViewModel.cs` | Modify | Inject `IDialogService`, use modal dialog for init failures |
| `EdgeStudioTests/DialogServiceTests.cs` | Create | Unit tests for `SukiDialogService` |

---

### Task 1: Fix Toast Host Binding

**Files:**
- Modify: `EdgeStudio/Views/MainWindow.axaml:22-24`

- [ ] **Step 1: Bind the toast host Manager property**

In `EdgeStudio/Views/MainWindow.axaml`, change:

```xml
    <!-- Toast notification host -->
    <suki:SukiWindow.Hosts>
        <suki:SukiToastHost />
    </suki:SukiWindow.Hosts>
```

To:

```xml
    <!-- Toast notification host -->
    <suki:SukiWindow.Hosts>
        <suki:SukiToastHost Manager="{Binding ToastManager, RelativeSource={RelativeSource AncestorType=suki:SukiWindow}}"/>
    </suki:SukiWindow.Hosts>
```

`MainWindow.axaml.cs` already has a public `ToastManager` property (line 27) that resolves from DI. The `RelativeSource` binding connects the XAML host to it.

- [ ] **Step 2: Build to verify**

Run:
```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```
Expected: Build succeeded, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add EdgeStudio/Views/MainWindow.axaml
git commit -m "fix(dotnet): bind SukiToastHost to DI-managed toast manager

Toast notifications were silently dropped because the XAML host used its
own default manager instead of the ISukiToastManager registered in DI."
```

---

### Task 2: Register ISukiDialogManager in DI

**Files:**
- Modify: `EdgeStudio/App.axaml.cs:153-158`

- [ ] **Step 1: Add ISukiDialogManager registration**

In `EdgeStudio/App.axaml.cs`, find the toast manager registration block (around line 153):

```csharp
        // Register toast service for notifications
        services.AddSingleton<SukiUI.Toasts.ISukiToastManager>(provider =>
        {
            return new SukiUI.Toasts.SukiToastManager();
        });
        services.AddSingleton<IToastService, SukiToastService>();
```

Add immediately after:

```csharp
        // Register dialog service for modal error dialogs
        services.AddSingleton<SukiUI.Dialogs.ISukiDialogManager>(provider =>
        {
            return new SukiUI.Dialogs.SukiDialogManager();
        });
```

- [ ] **Step 2: Build to verify**

Run:
```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```
Expected: Build succeeded, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add EdgeStudio/App.axaml.cs
git commit -m "feat(dotnet): register ISukiDialogManager in DI container"
```

---

### Task 3: Add SukiDialogHost to MainWindow

**Files:**
- Modify: `EdgeStudio/Views/MainWindow.axaml:21-24`
- Modify: `EdgeStudio/Views/MainWindow.axaml.cs:27-36`

- [ ] **Step 1: Add DialogManager property to MainWindow.cs**

In `EdgeStudio/Views/MainWindow.axaml.cs`, add a `DialogManager` property next to the existing `ToastManager` property. Find:

```csharp
    /// <summary>
    /// Toast manager for displaying notifications
    /// </summary>
    public ISukiToastManager ToastManager { get; }

    public MainWindow()
    {
        // Get the toast manager from the service provider
        ToastManager = App.ServiceProvider?.GetService(typeof(ISukiToastManager)) as ISukiToastManager
            ?? new SukiToastManager();

        InitializeComponent();
        ConfigurePlatformSpecificStyles();
    }
```

Replace with:

```csharp
    /// <summary>
    /// Toast manager for displaying notifications
    /// </summary>
    public ISukiToastManager ToastManager { get; }

    /// <summary>
    /// Dialog manager for displaying modal dialogs
    /// </summary>
    public SukiUI.Dialogs.ISukiDialogManager DialogManager { get; }

    public MainWindow()
    {
        // Get the toast manager from the service provider
        ToastManager = App.ServiceProvider?.GetService(typeof(ISukiToastManager)) as ISukiToastManager
            ?? new SukiToastManager();

        // Get the dialog manager from the service provider
        DialogManager = App.ServiceProvider?.GetService(typeof(SukiUI.Dialogs.ISukiDialogManager)) as SukiUI.Dialogs.ISukiDialogManager
            ?? new SukiUI.Dialogs.SukiDialogManager();

        InitializeComponent();
        ConfigurePlatformSpecificStyles();
    }
```

- [ ] **Step 2: Add SukiDialogHost to XAML**

In `EdgeStudio/Views/MainWindow.axaml`, find:

```xml
    <!-- Toast notification host -->
    <suki:SukiWindow.Hosts>
        <suki:SukiToastHost Manager="{Binding ToastManager, RelativeSource={RelativeSource AncestorType=suki:SukiWindow}}"/>
    </suki:SukiWindow.Hosts>
```

Replace with:

```xml
    <!-- Toast and dialog notification hosts -->
    <suki:SukiWindow.Hosts>
        <suki:SukiToastHost Manager="{Binding ToastManager, RelativeSource={RelativeSource AncestorType=suki:SukiWindow}}"/>
        <suki:SukiDialogHost Manager="{Binding DialogManager, RelativeSource={RelativeSource AncestorType=suki:SukiWindow}}"/>
    </suki:SukiWindow.Hosts>
```

- [ ] **Step 3: Build to verify**

Run:
```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```
Expected: Build succeeded, 0 errors.

- [ ] **Step 4: Commit**

```bash
git add EdgeStudio/Views/MainWindow.axaml EdgeStudio/Views/MainWindow.axaml.cs
git commit -m "feat(dotnet): add SukiDialogHost to MainWindow for modal dialogs"
```

---

### Task 4: Create IDialogService Interface

**Files:**
- Create: `EdgeStudio.Shared/Services/IDialogService.cs`

- [ ] **Step 1: Create the interface**

Create `EdgeStudio.Shared/Services/IDialogService.cs`:

```csharp
namespace EdgeStudio.Shared.Services;

/// <summary>
/// Service for displaying modal dialogs to the user.
/// Used for errors that require acknowledgment before continuing.
/// </summary>
public interface IDialogService
{
    /// <summary>
    /// Displays a modal error dialog that the user must dismiss.
    /// </summary>
    /// <param name="title">The dialog title</param>
    /// <param name="message">The error message to display</param>
    void ShowError(string title, string message);
}
```

- [ ] **Step 2: Build to verify**

Run:
```bash
cd dotnet/src && dotnet build EdgeStudio.Shared/EdgeStudio.Shared.csproj --verbosity minimal
```
Expected: Build succeeded, 0 errors.

- [ ] **Step 3: Commit**

```bash
git add EdgeStudio.Shared/Services/IDialogService.cs
git commit -m "feat(dotnet): add IDialogService interface for modal error dialogs"
```

---

### Task 5: Create SukiDialogService Implementation and Tests

**Files:**
- Create: `EdgeStudio/Services/SukiDialogService.cs`
- Create: `EdgeStudioTests/DialogServiceTests.cs`
- Modify: `EdgeStudio/App.axaml.cs`

- [ ] **Step 1: Write the failing tests**

Create `EdgeStudioTests/DialogServiceTests.cs`:

```csharp
using EdgeStudio.Services;
using EdgeStudio.Shared.Services;
using FluentAssertions;
using Moq;
using SukiUI.Dialogs;
using Xunit;

namespace EdgeStudioTests;

public class DialogServiceTests
{
    private readonly Mock<ISukiDialogManager> _mockDialogManager;
    private readonly IDialogService _dialogService;

    public DialogServiceTests()
    {
        _mockDialogManager = new Mock<ISukiDialogManager>();
        _dialogService = new SukiDialogService(_mockDialogManager.Object);
    }

    [Fact]
    public void Constructor_NullDialogManager_ShouldThrow()
    {
        // Act
        var act = () => new SukiDialogService(null!);

        // Assert
        act.Should().Throw<ArgumentNullException>();
    }

    [Fact]
    public void ShowError_ShouldCallTryShowDialogOnManager()
    {
        // Arrange
        _mockDialogManager
            .Setup(m => m.TryShowDialog(It.IsAny<ISukiDialog>()))
            .Returns(true);

        // Act
        _dialogService.ShowError("Test Title", "Test message");

        // Assert
        _mockDialogManager.Verify(
            m => m.TryShowDialog(It.IsAny<ISukiDialog>()),
            Times.Once);
    }
}
```

- [ ] **Step 2: Build tests to verify they fail**

Run:
```bash
cd dotnet/src && dotnet build EdgeStudioTests/EdgeStudioTests.csproj --verbosity minimal
```
Expected: Build FAILS — `SukiDialogService` does not exist yet.

- [ ] **Step 3: Create SukiDialogService implementation**

Create `EdgeStudio/Services/SukiDialogService.cs`:

```csharp
using Avalonia.Threading;
using EdgeStudio.Shared.Services;
using SukiUI.Dialogs;
using SukiUI.Enums;
using System;

namespace EdgeStudio.Services;

/// <summary>
/// Dialog service implementation using SukiUI's dialog system.
/// Ensures all dialog operations are executed on the UI thread.
/// </summary>
public class SukiDialogService : IDialogService
{
    private readonly ISukiDialogManager _dialogManager;

    public SukiDialogService(ISukiDialogManager dialogManager)
    {
        _dialogManager = dialogManager ?? throw new ArgumentNullException(nameof(dialogManager));
    }

    public void ShowError(string title, string message)
    {
        DispatchToUI(() =>
        {
            var builder = _dialogManager.CreateDialog();
            builder.SetType(NotificationType.Error);
            builder.SetTitle(title);
            builder.SetContent(message);
            builder.AddActionButton("OK", _ => { }, dismissOnClick: true);
            builder.TryShow();
        });
    }

    private static void DispatchToUI(Action action)
    {
        if (Dispatcher.UIThread.CheckAccess())
        {
            action();
        }
        else
        {
            Dispatcher.UIThread.Post(action);
        }
    }
}
```

- [ ] **Step 4: Register in DI**

In `EdgeStudio/App.axaml.cs`, find the line you added in Task 2:

```csharp
        services.AddSingleton<SukiUI.Dialogs.ISukiDialogManager>(provider =>
        {
            return new SukiUI.Dialogs.SukiDialogManager();
        });
```

Add immediately after:

```csharp
        services.AddSingleton<IDialogService, SukiDialogService>();
```

Note: `IDialogService` is in `EdgeStudio.Shared.Services` — ensure the `using` directive is present at the top of `App.axaml.cs`. It should already be there since `IToastService` is in the same namespace.

- [ ] **Step 5: Build and run tests**

Run:
```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity minimal
```
Expected: Build succeeded. All tests pass (including the 2 new ones).

- [ ] **Step 6: Commit**

```bash
git add EdgeStudio/Services/SukiDialogService.cs EdgeStudioTests/DialogServiceTests.cs EdgeStudio/App.axaml.cs
git commit -m "feat(dotnet): add SukiDialogService for modal error dialogs

Implements IDialogService using SukiUI's dialog system. Shows error-type
modal dialogs with an OK button that requires user dismissal."
```

---

### Task 6: Use Dialog in MainWindowViewModel for Init Failures

**Files:**
- Modify: `EdgeStudio/ViewModels/MainWindowViewModel.cs:28-41, 244-279`

- [ ] **Step 1: Add IDialogService to constructor**

In `EdgeStudio/ViewModels/MainWindowViewModel.cs`, find the field declarations (around line 28):

```csharp
        private readonly IQrCodeService _qrCodeService;
        private readonly ILogCaptureService _logCaptureService;
```

Add after:

```csharp
        private readonly IDialogService _dialogService;
```

Find the constructor parameters (around line 38):

```csharp
            ILogCaptureService logCaptureService,
            IToastService? toastService = null)
```

Change to:

```csharp
            ILogCaptureService logCaptureService,
            IDialogService dialogService,
            IToastService? toastService = null)
```

Find the constructor body assignments (around line 51):

```csharp
            _logCaptureService = logCaptureService ?? throw new ArgumentNullException(nameof(logCaptureService));
```

Add after:

```csharp
            _dialogService = dialogService ?? throw new ArgumentNullException(nameof(dialogService));
```

Add the using directive at the top of the file if not already present:

```csharp
using EdgeStudio.Shared.Services;
```

(This should already be there since `IToastService` is in the same namespace.)

- [ ] **Step 2: Replace ShowError calls with dialog in InitializeSelectedDatabaseAsync**

In `EdgeStudio/ViewModels/MainWindowViewModel.cs`, find the `!success` path (around line 258-265):

```csharp
                if (!success)
                {
                    ShowError("Could not initialize database. Please check your configuration and try again.");
                    // Clear selection to stay on database listing view
                    _selectedDatabase = null;
                    OnPropertyChanged(nameof(SelectedDatabase));
                    OnPropertyChanged(nameof(HasSelectedDatabase));
                }
```

Replace with:

```csharp
                if (!success)
                {
                    _dialogService.ShowError("Database Initialization Failed",
                        "Could not initialize database. Please check your configuration and try again.");
                    // Clear selection to stay on database listing view
                    _selectedDatabase = null;
                    OnPropertyChanged(nameof(SelectedDatabase));
                    OnPropertyChanged(nameof(HasSelectedDatabase));
                }
```

Find the `catch` block (around line 267-274):

```csharp
            catch (Exception ex)
            {
                ShowError($"Failed to initialize database: {ex.Message}");
                // Clear selection to stay on database listing view
                _selectedDatabase = null;
                OnPropertyChanged(nameof(SelectedDatabase));
                OnPropertyChanged(nameof(HasSelectedDatabase));
            }
```

Replace with:

```csharp
            catch (Exception ex)
            {
                _dialogService.ShowError("Database Initialization Failed",
                    $"Failed to open database: {ex.Message}\n\nCheck your Database ID and other settings, then try again.");
                // Clear selection to stay on database listing view
                _selectedDatabase = null;
                OnPropertyChanged(nameof(SelectedDatabase));
                OnPropertyChanged(nameof(HasSelectedDatabase));
            }
```

- [ ] **Step 3: Build and run tests**

Run:
```bash
cd dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity minimal
```
Expected: Build succeeded. All tests pass.

- [ ] **Step 4: Commit**

```bash
git add EdgeStudio/ViewModels/MainWindowViewModel.cs
git commit -m "fix(dotnet): show modal error dialog on database initialization failure

Replaces transient toast notifications with a modal error dialog that
requires user acknowledgment. Covers both the !success and exception
paths in InitializeSelectedDatabaseAsync."
```
