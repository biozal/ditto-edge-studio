# Plan: Shared Logging Service + Logging Mode Fix

## Overview

Three problems to solve:
1. `ILoggingService` / `SerilogLoggingService` live in the EdgeStudio UI project — unreachable from the Shared project
2. `DittoManager` and repositories use `System.Diagnostics.Debug.WriteLine` instead of the logging service
3. Opening the Logging screen always resets `DittoLogger.MinimumLogLevel` to `Verbose`, ignoring whatever was set from the database config

---

## Root Cause Analysis

### Problem 1 — Logging classes in wrong project
`ILoggingService` and `SerilogLoggingService` are in `EdgeStudio/Services/` (namespace `EdgeStudio.Services`).
The Shared project (`EdgeStudio.Shared`) cannot reference them, so nothing in Shared can write to the log files.

### Problem 2 — Debug.WriteLine scattered through Shared code
17 total calls:
- `DittoManager.cs` — 6 calls (database close, mesh parameter, transport config details)
- `SystemRepository.cs` — 9 calls (observer callbacks, peer card operations, connection types)
- `CollectionsRepository.cs` — 1 call (collection access error)
- `SqliteSubscriptionRepository.cs` — 1 call (subscription cancel error)

### Problem 3 — Logging mode defaulting to Verbose
Sequence of events:
1. User opens a database → `DittoManager.InitializeDittoSelectedApp` sets `DittoLogger.MinimumLogLevel` from config (e.g., `info`)
2. User navigates to the Logging screen → `LoggingViewModel.OnActivated()` fires
3. `OnActivated` calls `_captureService.StartCapture(SelectedSdkLogLevel)` where `SelectedSdkLogLevel = "verbose"` (hardcoded field initializer, line 41)
4. `DittoLogCaptureService.StartCapture` sets `DittoLogger.MinimumLogLevel = Verbose` — **overrides the config value**
5. UI dropdown shows "verbose" regardless of what was configured

---

## Implementation Plan

### Step 1 — Add Serilog to EdgeStudio.Shared.csproj

Add the same two packages that EdgeStudio.csproj already has:
```xml
<PackageReference Include="Serilog" Version="4.3.1" />
<PackageReference Include="Serilog.Sinks.File" Version="7.0.0" />
```

File: `dotnet/src/EdgeStudio.Shared/EdgeStudio.Shared.csproj`

---

### Step 2 — Create ILoggingService in Shared project

Create `dotnet/src/EdgeStudio.Shared/Services/ILoggingService.cs`:
```csharp
namespace EdgeStudio.Shared.Services;

public interface ILoggingService
{
    void Debug(string message);
    void Info(string message);
    void Warning(string message);
    void Error(string message);
    IReadOnlyList<string> GetLogFilePaths();
    string GetCombinedLogs();
    void ClearAllLogs();
}
```

---

### Step 3 — Create SerilogLoggingService in Shared project

Create `dotnet/src/EdgeStudio.Shared/Services/SerilogLoggingService.cs`:
- Same logic as the current EdgeStudio version
- Namespace changes to `EdgeStudio.Shared.Services`

---

### Step 4 — Delete old logging files from EdgeStudio project

- Delete `dotnet/src/EdgeStudio/Services/ILoggingService.cs`
- Delete `dotnet/src/EdgeStudio/Services/SerilogLoggingService.cs`
- Remove Serilog package references from `EdgeStudio.csproj` (they're now in Shared which EdgeStudio already references)

---

### Step 5 — Update namespace references in EdgeStudio project

Files that import `EdgeStudio.Services` for logging types:
- `EdgeStudio/App.axaml.cs` — DI registration
- `EdgeStudio/ViewModels/LoggingViewModel.cs` — uses `ILoggingService`
- `EdgeStudio/Services/DittoLogCaptureService.cs` — has `using EdgeStudio.Services` (if present)
- Any other file with `using EdgeStudio.Services` that references `ILoggingService`

Change: `using EdgeStudio.Services;` → `using EdgeStudio.Shared.Services;`

The `App.axaml.cs` DI registration line stays the same in logic, just picks up the new type location:
```csharp
services.AddSingleton<ILoggingService, SerilogLoggingService>();
```

---

### Step 6 — Inject ILoggingService into DittoManager

`DittoManager` currently uses a zero-arg implicit constructor. Add an explicit constructor that accepts `ILoggingService?`:

```csharp
public sealed class DittoManager : IDittoManager, IDisposable
{
    private readonly ILoggingService? _logger;

    public DittoManager(ILoggingService? logger = null)
    {
        _logger = logger;
    }
    ...
}
```

Replace Debug.WriteLine calls:
| Current | Replacement |
|---|---|
| `Debug.WriteLine($"Error closing Ditto database: {ex.Message}")` | `_logger?.Error($"Error closing Ditto database: {ex.Message}")` |
| `Debug.WriteLine("=== SETTING system parameter mesh_chooser_max_wlan_clients to 12 ===")` | `_logger?.Info("Setting system parameter mesh_chooser_max_wlan_clients to 12")` |
| `Debug.WriteLine("=== Transport Configuration Applied ===")` | `_logger?.Info("Transport Configuration Applied")` |
| `Debug.WriteLine($"Bluetooth LE: ...")` etc. | `_logger?.Debug($"Bluetooth LE: ...")` etc. |

Update DI registration in `App.axaml.cs`:
```csharp
// Before (implicit construction):
services.AddSingleton<IDittoManager, DittoManager>();

// After (ILoggingService already registered, DI resolves it):
services.AddSingleton<IDittoManager, DittoManager>();
// (No change needed — DI will inject ILoggingService automatically since it's registered)
```

---

### Step 7 — Inject ILoggingService into SystemRepository

`SystemRepository` uses a primary constructor: `SystemRepository(IDittoManager dittoManager)`.

Update to: `SystemRepository(IDittoManager dittoManager, ILoggingService? logger = null)`

Store as `private readonly ILoggingService? _logger;` (from primary constructor parameter or body).

Since primary constructors don't support initializing readonly fields from optional params directly, switch to a regular constructor body or use the primary constructor and store:
```csharp
public sealed class SystemRepository(IDittoManager dittoManager, ILoggingService? logger = null)
{
    // primary constructor params are available as fields in the body
    private readonly ILoggingService? _logger = logger;
    ...
}
```

Replace 9 Debug.WriteLine calls with appropriate `_logger?.Debug/Warning/Error()` calls.

Update DI registration:
```csharp
services.AddSingleton<ISystemRepository, SystemRepository>();
// DI resolves ILoggingService? automatically
```

---

### Step 8 — Inject ILoggingService into CollectionsRepository

`CollectionsRepository` primary constructor: `CollectionsRepository(IDittoManager dittoManager)`

Update to: `CollectionsRepository(IDittoManager dittoManager, ILoggingService? logger = null)`

Replace 1 Debug.WriteLine call with `_logger?.Warning(...)`.

---

### Step 9 — Inject ILoggingService into SqliteSubscriptionRepository

`SqliteSubscriptionRepository` has a traditional constructor:
```csharp
public SqliteSubscriptionRepository(
    ILocalDatabaseService localDatabaseService,
    IDittoManager dittoManager)
```

Add `ILoggingService? logger = null` parameter, store it, replace 1 Debug.WriteLine call.

---

### Step 10 — Fix the Logging Mode Bug

**Two changes:**

**Change A: `DittoLogCaptureService.StartCapture` — stop overriding MinimumLogLevel**

`StartCapture` currently sets `DittoLogger.MinimumLogLevel` from its `minimumLevel` parameter. This is wrong — the level was already set by `DittoManager` from the database config, and `StartCapture` clobbers it.

Remove the log level assignment from `StartCapture`. It should only register the callback:
```csharp
public void StartCapture()
{
    if (_isCapturing) return;
    try
    {
        DittoLogger.CustomLogCallback = OnDittoLog;
        _isCapturing = true;
    }
    catch (Exception ex)
    {
        System.Diagnostics.Debug.WriteLine($"[DittoLogCaptureService] Failed to start capture: {ex.Message}");
    }
}
```

The `minimumLevel` string parameter is removed — DittoManager owns the log level, not the capture service.

**Change B: `LoggingViewModel` — initialize dropdown from actual config**

The `_selectedSdkLogLevel` backing field initializes to `"verbose"` which is wrong.

- Add `IDittoManager` parameter to `LoggingViewModel` constructor
- In the constructor body, read `IDittoManager.SelectedDatabaseConfig?.LogLevel` and set the backing field **directly** (bypassing the `OnSelectedSdkLogLevelChanged` partial method, which would otherwise call `DittoLogger.MinimumLogLevel` again)
- Update `OnActivated` to call `_captureService.StartCapture()` with no argument (since we removed the level parameter)

```csharp
public LoggingViewModel(
    DittoLogCaptureService captureService,
    IDittoManager dittoManager,
    ILoggingService? loggingService = null,
    IToastService? toastService = null)
    : base(toastService)
{
    _captureService = captureService;
    _loggingService = loggingService;
    _captureService.Cleared += OnCaptureServiceCleared;

    // Initialize dropdown from the actual configured level — NOT from a hardcoded default.
    // Set backing field directly to avoid triggering OnSelectedSdkLogLevelChanged,
    // which would re-set DittoLogger.MinimumLogLevel unnecessarily.
    _selectedSdkLogLevel = dittoManager.SelectedDatabaseConfig?.LogLevel ?? "info";

    _pollTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
    _pollTimer.Tick += OnPollTimerTick;
}
```

Update DI registration for LoggingViewModel (DI will inject IDittoManager automatically since it's registered as a singleton):
```csharp
services.AddTransient<LoggingViewModel>();
// No changes needed — DI resolves IDittoManager automatically
```

**Also fix `DittoLogCaptureService`'s remaining Debug.WriteLine:**
Replace the `System.Diagnostics.Debug.WriteLine` in `StartCapture`'s catch block — since this class is in the EdgeStudio (not Shared) project, inject `ILoggingService?` into it as well.

---

### Step 11 — Build Verification

After each group of changes, compile immediately:

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio.sln --verbosity minimal
```

Fix any compile errors before proceeding to the next step.

---

### Step 12 — Run Tests

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --logger "console;verbosity=detailed"
```

Verify all existing tests pass. Add or update tests if any test mocks `DittoManager`, `SystemRepository`, `CollectionsRepository`, or `SqliteSubscriptionRepository` (since constructor signatures change).

---

## File Change Summary

| File | Change |
|---|---|
| `EdgeStudio.Shared/EdgeStudio.Shared.csproj` | Add Serilog + Serilog.Sinks.File packages |
| `EdgeStudio.Shared/Services/ILoggingService.cs` | **NEW** — moved from EdgeStudio project |
| `EdgeStudio.Shared/Services/SerilogLoggingService.cs` | **NEW** — moved from EdgeStudio project |
| `EdgeStudio/Services/ILoggingService.cs` | **DELETE** |
| `EdgeStudio/Services/SerilogLoggingService.cs` | **DELETE** |
| `EdgeStudio/EdgeStudio.csproj` | Remove Serilog packages (now in Shared) |
| `EdgeStudio/App.axaml.cs` | Update `using` for ILoggingService/SerilogLoggingService |
| `EdgeStudio.Shared/Data/DittoManager.cs` | Add ILoggingService? param, replace 6 Debug.WriteLine |
| `EdgeStudio.Shared/Data/Repositories/SystemRepository.cs` | Add ILoggingService? param, replace 9 Debug.WriteLine |
| `EdgeStudio.Shared/Data/Repositories/CollectionsRepository.cs` | Add ILoggingService? param, replace 1 Debug.WriteLine |
| `EdgeStudio.Shared/Data/Repositories/SqliteSubscriptionRepository.cs` | Add ILoggingService? param, replace 1 Debug.WriteLine |
| `EdgeStudio/Services/DittoLogCaptureService.cs` | Remove level param from StartCapture, inject ILoggingService? for its own Debug.WriteLine |
| `EdgeStudio/ViewModels/LoggingViewModel.cs` | Add IDittoManager param, init `_selectedSdkLogLevel` from config, call StartCapture() with no args |

---

## Risk Notes

- **Optional parameters with DI**: Using `ILoggingService? logger = null` on constructors means DI will inject it if registered (which it is), and null if not. This is safe.
- **Primary constructors with stored fields**: C# 12 primary constructors allow capturing params as fields using `= param` assignment. SystemRepository and CollectionsRepository may need slight adjustments to store the logger field.
- **Serilog in Shared**: Serilog is cross-platform (.NET Standard), so adding it to the Shared project works for all consumers (Avalonia app + any future console app).
- **Removing Serilog from EdgeStudio.csproj**: EdgeStudio references EdgeStudio.Shared, so Serilog becomes a transitive dependency — no build impact. However, to keep the project graph clean, explicitly removing it from EdgeStudio.csproj is preferred. If there are any `using Serilog` statements in EdgeStudio-only files (unlikely, since SerilogLoggingService is moving), those would break.
- **Test project**: If tests mock `DittoManager`, `SystemRepository`, etc. using Moq, the constructor changes may require mock setup updates. Check `EdgeStudioTests` for any affected test files.
