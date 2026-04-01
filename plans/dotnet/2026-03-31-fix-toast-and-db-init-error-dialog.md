# Fix Broken Toasts and Add Database Initialization Error Dialog

**Date:** 2026-03-31
**Status:** Approved

## Problem

1. **Toast notifications are completely broken.** The `SukiToastHost` in `MainWindow.axaml` has no `Manager` binding. The `SukiToastService` queues toasts to a DI-managed `ISukiToastManager` instance, but the XAML host uses its own internal default manager. Every `ShowError()`, `ShowSuccess()`, etc. call across the entire app is silently dropped.

2. **Invalid Database ID shows no user-facing error.** When a user creates a database config with an invalid Database ID (not a valid UUID), `Ditto.OpenAsync()` throws an exception. The catch block in `MainWindowViewModel.InitializeSelectedDatabaseAsync` calls `ShowError()` which would show a 5-second toast — but due to bug #1, it never appears. Even with working toasts, a transient notification is too subtle for a configuration error requiring user action.

## Solution

### Part 1: Fix Toast Host Binding

**File:** `EdgeStudio/Views/MainWindow.axaml`

Change:
```xml
<suki:SukiToastHost />
```
To:
```xml
<suki:SukiToastHost Manager="{Binding ToastManager, RelativeSource={RelativeSource AncestorType=suki:SukiWindow}}"/>
```

`MainWindow.cs` already resolves the DI `ISukiToastManager` as a public `ToastManager` property (line 32). This binding connects it to the visual host.

This single change fixes all toast notifications app-wide.

### Part 2: Add SukiUI Dialog for Database Init Failures

#### 2a. Register `ISukiDialogManager` in DI

**File:** `EdgeStudio/App.axaml.cs`

Add alongside the existing `ISukiToastManager` registration:
```csharp
services.AddSingleton<SukiUI.Dialogs.ISukiDialogManager>(provider =>
{
    return new SukiUI.Dialogs.SukiDialogManager();
});
```

#### 2b. Add `SukiDialogHost` to MainWindow

**File:** `EdgeStudio/Views/MainWindow.axaml`

Add inside `<suki:SukiWindow.Hosts>` alongside the toast host:
```xml
<suki:SukiDialogHost Manager="{Binding DialogManager, RelativeSource={RelativeSource AncestorType=suki:SukiWindow}}"/>
```

**File:** `EdgeStudio/Views/MainWindow.axaml.cs`

Add a public `DialogManager` property that resolves from DI (same pattern as `ToastManager`):
```csharp
public ISukiDialogManager DialogManager { get; }
```

Initialize in the parameterless constructor from `App.ServiceProvider`.

#### 2c. Create Dialog Service

**File:** `EdgeStudio.Shared/Services/IDialogService.cs` (new)
```csharp
public interface IDialogService
{
    void ShowError(string title, string message);
}
```

**File:** `EdgeStudio/Services/SukiDialogService.cs` (new)

Implementation that uses `ISukiDialogManager`:
```csharp
public class SukiDialogService : IDialogService
{
    private readonly ISukiDialogManager _dialogManager;

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
}
```

Note: SukiUI v6.0.3 uses `SukiDialogBuilder` with `SetType(NotificationType)`, `SetTitle()`, `SetContent()`, `AddActionButton()`, and `TryShow()`. The `NotificationType` enum is at `SukiUI.Enums.NotificationType` with values including `Error`.

Register in DI as singleton.

#### 2d. Use Dialog in MainWindowViewModel

**File:** `EdgeStudio/ViewModels/MainWindowViewModel.cs`

Inject `IDialogService` via constructor.

Replace both error paths in `InitializeSelectedDatabaseAsync`:

- `!success` path (line 258): Show dialog with message "Could not initialize database. Please check your configuration and try again."
- `catch` path (line 267): Show dialog with message "Failed to open database: {ex.Message}\n\nCheck your Database ID and other settings, then try again."

Both paths already correctly clear `_selectedDatabase` and revert to the listing view.

### Part 3: Testing

**File:** `EdgeStudioTests/DialogServiceTests.cs` (new)

- Test that `ShowError` calls `ISukiDialogManager.CreateDialog()` with correct parameters
- Mock `ISukiDialogManager` using Moq
- Follow existing `NavigationServiceTests` pattern

## Files Changed

| File | Change |
|------|--------|
| `EdgeStudio/Views/MainWindow.axaml` | Add `Manager` binding to toast host, add dialog host |
| `EdgeStudio/Views/MainWindow.axaml.cs` | Add `DialogManager` property |
| `EdgeStudio/App.axaml.cs` | Register `ISukiDialogManager` and `IDialogService` in DI |
| `EdgeStudio.Shared/Services/IDialogService.cs` | New interface |
| `EdgeStudio/Services/SukiDialogService.cs` | New implementation |
| `EdgeStudio/ViewModels/MainWindowViewModel.cs` | Inject `IDialogService`, replace `ShowError` with dialog in init failure paths |
| `EdgeStudioTests/DialogServiceTests.cs` | New tests |
