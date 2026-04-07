# SukiUI Replacement — EdgeStudio.UI Library

**Date:** 2026-04-07
**Status:** Design Approved
**Target:** Avalonia 12

---

## Context

Edge Studio's .NET/Avalonia app currently depends on SukiUI 6.0.3, which is tied to Avalonia 11 with no Avalonia 12 support planned. SukiUI is integrated across 47+ locations in the codebase, providing window chrome, card components, theming, toast notifications, and modal dialogs. Replacing SukiUI with a custom library unblocks the Avalonia 12 migration and its significant performance improvements.

## Decisions

- **Target Avalonia 12 directly** — no Avalonia 11 compatibility shim. Avalonia 12's `WindowDrawnDecorations` and improved theming simplify the replacement.
- **Standalone class library** — new `EdgeStudio.UI` project, referenced by `EdgeStudio`. Clean separation, testable in isolation.
- **Follow OS theme** — no runtime theme switching. App uses system light/dark preference with Ditto brand accent colors always.
- **Native window chrome on all platforms** — no custom title bar. Settings/Help buttons move to menu bar.
- **Liquid glass visual style** — acrylic/blur materials inspired by macOS 26 liquid glass, with graceful degradation on Linux.
- **Toasts positioned top-right** — slide-in from right, fade-out on dismiss.

---

## 1. Project Structure

```
dotnet/src/EdgeStudio.UI/
├── EdgeStudio.UI.csproj          # net10.0, Avalonia 12
├── Themes/
│   ├── StudioTheme.axaml         # Main theme resource dictionary
│   └── DittoBrushes.axaml        # Brand color resources (light + dark variants)
├── Controls/
│   ├── GlassCard.cs              # Liquid glass card control
│   ├── ToastHost.axaml/.cs       # Toast overlay container
│   ├── ToastItem.axaml/.cs       # Individual toast notification
│   ├── DialogHost.axaml/.cs      # Modal dialog overlay
│   └── DialogItem.axaml/.cs      # Dialog content container
└── Services/
    ├── ToastManager.cs           # IToastService implementation
    └── DialogManager.cs          # IDialogService implementation
```

`EdgeStudio.UI.csproj` depends on Avalonia 12 core packages only. No SukiUI. No app-specific code.

---

## 2. Theme System

### StudioTheme.axaml

Loaded in `App.axaml` replacing `<suki:SukiTheme />`:

```xml
<!-- Remove -->
<suki:SukiTheme />

<!-- Add -->
<studio:StudioTheme />
```

`App.axaml` uses `RequestedThemeVariant="Default"` so the app follows the OS light/dark setting automatically via Avalonia's built-in behavior. No runtime switching code.

### DittoBrushes.axaml

Theme-variant-aware resource dictionary defining:

| Resource Key | Replaces | Purpose |
|---|---|---|
| `StudioCardBackground` | `SukiCardBackground` | Semi-transparent card background, different tints for light/dark |
| `StudioLowText` | `SukiLowText` | Muted text color |
| `StudioPopupShadow` | `SukiPopupShadow` | Elevation shadow |
| `StudioAccent` | (new) | Ditto brand yellow `#F0D830` |
| `StudioAccentDark` | (new) | Ditto dark `#2A292A` |

### Deleted Code

- `SukiTheme.GetInstance()` and all `SukiColorTheme` registration (~15 lines in App.axaml.cs)
- `OnColorThemeChanged` callback in MainWindow.axaml.cs
- `UpdateBackgroundStyle()` method
- `SukiBackgroundStyle` enum usage

---

## 3. GlassCard Control

**Inherits:** `ContentControl`

**Visual design:**
- Translucent background with blur via `ExperimentalAcrylicBorder` (macOS/Windows), fallback to semi-transparent solid + `BoxShadow` on Linux
- Acrylic material: `TintOpacity=0.75`, `MaterialOpacity=0.3`, tint from `StudioCardBackground`
- Default `CornerRadius=8`, settable as styled property
- Subtle 1px top-edge highlight border for liquid glass depth cue

**Styled properties:**
- `CornerRadius` (CornerRadius, default 8)
- `IsInteractive` (bool, default false)

**Pseudo-classes (when `IsInteractive=true`):**
- `:pointerover` — slight background brightness increase
- `:pressed` — subtle scale-down (0.98) and brightness decrease

**Default template structure:**
```
ExperimentalAcrylicBorder
  └── Border (highlight edge)
       └── ContentPresenter
```

**API compatibility:** `ContextMenu` and `Tapped` event come free from `ContentControl`/`InputElement` base classes. Existing XAML using these features works without changes beyond namespace.

**Estimated size:** ~150-200 lines

---

## 4. Toast System

### ToastManager (implements IToastService)

- `ActiveToasts` — `ObservableCollection<ToastItemData>` of visible toasts
- Each `Show*` method creates a `ToastItemData` record with title, message, severity, duration
- Auto-dismiss via `DispatcherTimer` per toast
- Click-to-dismiss on all toasts
- Maximum 5 visible — oldest dismissed when limit exceeded
- UI thread marshaling built-in

**Durations:** Error=5s, Warning=4s, Info=4s, Success=3s

**DI registration:**
```csharp
services.AddSingleton<ToastManager>();
services.AddSingleton<IToastService>(sp => sp.GetRequiredService<ToastManager>());
```

`ToastManager` is both the `IToastService` implementation (ViewModels) and the data source for `ToastHost` (view). Single class, dual role.

### ToastHost (control)

- `ItemsControl` overlay positioned top-right, fixed width ~350px
- Binds to `ToastManager.ActiveToasts`
- Slide-in from right, fade-out on dismiss (Avalonia `Animation` API)
- `Manager` dependency property for binding

### ToastItem (control)

- `GlassCard`-styled container for visual consistency
- Left color stripe: red (error), green (success), amber (warning), blue (info)
- Title (bold), message text, close button
- Clickable to dismiss

**Estimated size:** ~300 lines total

---

## 5. Dialog System

### DialogManager (implements IDialogService)

- `CurrentDialog` — observable property (single dialog at a time)
- `IsOpen` — boolean for backdrop visibility
- `ShowError(title, message)` sets `CurrentDialog` and `IsOpen=true`
- Dismiss clears both
- UI thread marshaling built-in

**DI registration:**
```csharp
services.AddSingleton<DialogManager>();
services.AddSingleton<IDialogService>(sp => sp.GetRequiredService<DialogManager>());
```

**Note:** `IDialogService` currently only defines `ShowError`. No speculative expansion — add methods when needed.

### DialogHost (control)

- Full-window overlay `Grid` with semi-transparent backdrop (`#40000000`)
- Backdrop click dismisses (same as OK)
- Centers a single `DialogItem`
- Fade-in backdrop, scale-in dialog card animation
- `Manager` dependency property for binding

### DialogItem (control)

- `GlassCard` container
- Severity icon (Material.Icons)
- Title, message, OK button
- Max width ~450px, centered

**Estimated size:** ~250 lines total

---

## 6. Window Migration

### All 15 Windows

| Change | From | To |
|--------|------|----|
| XAML root element | `<suki:SukiWindow>` | `<Window>` |
| Code-behind base | `: SukiWindow` | `: Window` |
| `BackgroundStyle` | Remove | (deleted) |
| `xmlns:suki` | Remove | (deleted) |

### MainWindow Specifically

**Remove:**
- `<suki:SukiWindow.Hosts>` section
- `<suki:SukiWindow.RightWindowTitleBarControls>` section
- All `using SukiUI.*` imports (6 total)
- `ToastManager`/`DialogManager` properties from code-behind
- `SukiBackgroundStyle` logic
- `SukiTheme.GetInstance()` and theme change callback

**Add:**
- Toast/dialog hosts as overlay layers in the main content Grid:
```xml
<Grid>
    <!-- Existing app content -->
    <studio:ToastHost Manager="{Binding ToastManager}" />
    <studio:DialogHost Manager="{Binding DialogManager}" />
</Grid>
```
- `MainWindowViewModel` gets `ToastManager` and `DialogManager` via DI and exposes them for binding

**Title bar buttons (Settings, Help):**
- Move to app menu bar (already exists on macOS; add for Windows/Linux)

### Styles Migration

| File | Change |
|------|--------|
| `GlassCardStyles.axaml` | `suki\|GlassCard` → `studio\|GlassCard` |
| `WrapPanelStyles.axaml` | Remove `suki:WrapPanelExtensions.AnimatedScroll` |
| `CompletionWindowStyles.axaml` | `SukiCardBackground` → `StudioCardBackground`, `SukiPopupShadow` → `StudioPopupShadow`, remove `suki:BiggestItemListBoxConverter` (replace with simple inline converter in EdgeStudio.UI or remove if unused) |

### App.axaml.cs Cleanup

- Remove `SukiTheme.GetInstance()` and `SukiColorTheme` registration
- Replace 4 toast/dialog DI registrations with new ones
- Remove `using SukiUI` and `using SukiUI.Models`

### Package Reference

```xml
<!-- Remove from EdgeStudio.csproj -->
<PackageReference Include="SukiUI" Version="6.0.3" />

<!-- Add -->
<ProjectReference Include="..\EdgeStudio.UI\EdgeStudio.UI.csproj" />
```

---

## 7. Testing Strategy

### Unit Tests (EdgeStudio.UI)

**GlassCard:**
- Renders without error
- `IsInteractive=true` adds `:pointerover` pseudo-class on pointer enter
- `IsInteractive=false` does not respond to pointer events
- `CornerRadius` applies correctly
- Content renders via `ContentPresenter`

**ToastManager:**
- `ShowError/Success/Warning/Info` each add a toast to `ActiveToasts`
- Auto-dismiss removes toast after specified duration
- Max 5 toasts — oldest removed when exceeded
- Thread-safe — calls from background thread don't throw

**DialogManager:**
- `ShowError` sets `CurrentDialog` and `IsOpen=true`
- Dismiss clears `CurrentDialog` and `IsOpen=false`
- Only one dialog at a time — second call replaces first

**Theme:**
- `StudioTheme` loads without errors
- Brand color resources resolve in both light and dark variants

### Integration Tests

- Build for all target platforms (Windows, macOS, Linux)
- Toast notifications appear and auto-dismiss
- Error dialog displays and dismisses
- GlassCard renders in database listing, subscription listing, and empty states
- Light/dark follows OS setting

### Framework

Existing xUnit + `Avalonia.Headless.XUnit`. GlassCard and theme tests use headless rendering. Toast/dialog manager tests are pure logic — no UI needed.

---

## 8. Files Modified (Complete List)

### New Files (EdgeStudio.UI)
- `EdgeStudio.UI.csproj`
- `Themes/StudioTheme.axaml`
- `Themes/DittoBrushes.axaml`
- `Controls/GlassCard.cs`
- `Controls/ToastHost.axaml` + `.cs`
- `Controls/ToastItem.axaml` + `.cs`
- `Controls/DialogHost.axaml` + `.cs`
- `Controls/DialogItem.axaml` + `.cs`
- `Services/ToastManager.cs`
- `Services/DialogManager.cs`

### Modified Files (EdgeStudio)
- `EdgeStudio.csproj` — remove SukiUI, add EdgeStudio.UI reference
- `App.axaml` — replace SukiTheme with StudioTheme
- `App.axaml.cs` — replace DI registrations, remove theme code
- `Views/MainWindow.axaml` — remove SukiWindow, hosts, title bar controls; add overlay hosts
- `Views/MainWindow.axaml.cs` — remove SukiUI imports, theme callbacks, manager properties
- `Views/Database/DatabaseFormWindow.axaml` + `.cs`
- `Views/Database/IndexFormWindow.axaml` + `.cs`
- `Views/Database/ObserverFormWindow.axaml` + `.cs`
- `Views/Database/SubscriptionFormWindow.axaml` + `.cs`
- `Views/Database/QrCodeDisplayWindow.axaml` + `.cs`
- `Views/Database/QrCodeImportWindow.axaml` + `.cs`
- `Views/Database/DatabaseListingView.axaml` — GlassCard namespace
- `Views/Settings/PreferencesWindow.axaml` + `.cs`
- `Views/Settings/TransportSettingsWindow.axaml` + `.cs`
- `Views/AttachmentPickerWindow.axaml` + `.cs`
- `Views/DeleteAttachmentWindow.axaml` + `.cs`
- `Views/StudioView/ImportDataWindow.axaml` + `.cs`
- `Views/Help/UserGuideWindow.axaml` + `.cs`
- `Views/Help/QuickstartBrowserWindow.axaml` + `.cs`
- `Views/Help/QuickstartProgressWindow.axaml` + `.cs`
- `Views/StudioView/Sidebar/SubscriptionListingView.axaml` — GlassCard namespace
- `Views/StudioView/Sidebar/ObserverListingView.axaml` — GlassCard namespace
- `Views/StudioView/Inspector/TableResultsView.axaml` — GlassCard namespace + resource keys
- `Views/StudioView/Inspector/IndexesToolView.axaml` — GlassCard namespace
- `Views/StudioView/Inspector/FavoritesToolView.axaml` — GlassCard namespace
- `Views/StudioView/Inspector/HistoryToolView.axaml` — GlassCard namespace
- `Styles/GlassCardStyles.axaml` — namespace
- `Styles/WrapPanelStyles.axaml` — remove AnimatedScroll, namespace
- `Styles/CompletionWindowStyles.axaml` — resource key names

### Deleted Files
- `Services/SukiDialogService.cs`
- `Services/SukiToastService.cs`

### Test Files
- New unit tests in `EdgeStudioTests/` for GlassCard, ToastManager, DialogManager, StudioTheme
