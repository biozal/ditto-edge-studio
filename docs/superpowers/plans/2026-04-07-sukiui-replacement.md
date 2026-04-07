# SukiUI Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace SukiUI 6.0.3 with a custom EdgeStudio.UI class library targeting Avalonia 12, unblocking the Avalonia 12 migration.

**Architecture:** New `EdgeStudio.UI` class library containing GlassCard control, toast/dialog overlay systems, and theme resources. The main `EdgeStudio` project swaps its SukiUI dependency for a project reference to `EdgeStudio.UI`. All 15 SukiWindow subclasses become standard Avalonia `Window`. Toast/dialog services are reimplemented behind existing `IToastService`/`IDialogService` interfaces with zero ViewModel changes.

**Tech Stack:** .NET 10.0, Avalonia 12, CommunityToolkit.Mvvm, xUnit + Avalonia.Headless.XUnit + Moq + FluentAssertions

**Spec:** `docs/superpowers/specs/2026-04-07-sukiui-replacement-design.md`

---

## File Structure

### New Files (EdgeStudio.UI library)

| File | Responsibility |
|------|---------------|
| `dotnet/src/EdgeStudio.UI/EdgeStudio.UI.csproj` | Project file targeting net10.0 + Avalonia 12 |
| `dotnet/src/EdgeStudio.UI/Themes/StudioTheme.axaml` | Root theme resource dictionary (replaces `<suki:SukiTheme />`) |
| `dotnet/src/EdgeStudio.UI/Themes/DittoBrushes.axaml` | Theme-variant-aware brushes replacing SukiUI dynamic resources |
| `dotnet/src/EdgeStudio.UI/Controls/GlassCard.cs` | Liquid glass card control with IsInteractive property |
| `dotnet/src/EdgeStudio.UI/Controls/GlassCard.axaml` | Default template/styles for GlassCard |
| `dotnet/src/EdgeStudio.UI/Controls/ToastHost.axaml` + `.cs` | Overlay container for toast notifications (top-right) |
| `dotnet/src/EdgeStudio.UI/Controls/ToastItem.axaml` + `.cs` | Individual toast notification control |
| `dotnet/src/EdgeStudio.UI/Services/ToastManager.cs` | `IToastService` implementation + toast data source |
| `dotnet/src/EdgeStudio.UI/Services/ToastItemData.cs` | Record for toast state (title, message, severity, id) |
| `dotnet/src/EdgeStudio.UI/Controls/DialogHost.axaml` + `.cs` | Modal dialog overlay with backdrop |
| `dotnet/src/EdgeStudio.UI/Controls/DialogItem.axaml` + `.cs` | Dialog content container |
| `dotnet/src/EdgeStudio.UI/Services/DialogManager.cs` | `IDialogService` implementation + confirmation dialog support |
| `dotnet/src/EdgeStudio.UI/Services/DialogItemData.cs` | Record for dialog state |

### Modified Files (EdgeStudio app)

| File | Change |
|------|--------|
| `dotnet/src/EdgeStudio/EdgeStudio.csproj` | Remove SukiUI package, add EdgeStudio.UI project reference |
| `dotnet/src/EdgeStudio/App.axaml` | Replace `<suki:SukiTheme />` with `<studio:StudioTheme />` |
| `dotnet/src/EdgeStudio/App.axaml.cs` | Replace DI registrations, remove `SetupDittoThemes()` |
| `dotnet/src/EdgeStudio/Views/MainWindow.axaml` | `Window` base, remove Hosts/TitleBar, add toast/dialog overlays |
| `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs` | Remove SukiUI imports, theme callbacks, direct DialogManager usage |
| 14 other `*.axaml` + `*.axaml.cs` window files | `SukiWindow` → `Window`, remove `BackgroundStyle`, remove `xmlns:suki` |
| 7 view files with GlassCard | `suki:GlassCard` → `studio:GlassCard` |
| `Styles/GlassCardStyles.axaml` | Update namespace selector |
| `Styles/WrapPanelStyles.axaml` | Remove `AnimatedScroll`, update namespace |
| `Styles/CompletionWindowStyles.axaml` | Replace SukiUI resource keys |

### Deleted Files

| File | Reason |
|------|--------|
| `dotnet/src/EdgeStudio/Services/SukiDialogService.cs` | Replaced by `DialogManager` |
| `dotnet/src/EdgeStudio/Services/SukiToastService.cs` | Replaced by `ToastManager` |

### Test Files

| File | What it tests |
|------|--------------|
| `dotnet/src/EdgeStudioTests/ToastManagerTests.cs` | ToastManager: show, auto-dismiss, max limit, thread safety |
| `dotnet/src/EdgeStudioTests/DialogManagerTests.cs` | DialogManager: show, dismiss, single dialog constraint |
| `dotnet/src/EdgeStudioTests/GlassCardTests.cs` | GlassCard: render, interactive states, corner radius |

---

## Task 1: Create EdgeStudio.UI Project

**Files:**
- Create: `dotnet/src/EdgeStudio.UI/EdgeStudio.UI.csproj`
- Modify: `dotnet/src/EdgeStudio.sln`

- [ ] **Step 1: Create the project directory**

```bash
mkdir -p /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src/EdgeStudio.UI
```

- [ ] **Step 2: Create EdgeStudio.UI.csproj**

Create `dotnet/src/EdgeStudio.UI/EdgeStudio.UI.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <LangVersion>14</LangVersion>
    <RootNamespace>EdgeStudio.UI</RootNamespace>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Avalonia" Version="11.3.13" />
    <PackageReference Include="Avalonia.Themes.Fluent" Version="11.3.13" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\EdgeStudio.Shared\EdgeStudio.Shared.csproj" />
  </ItemGroup>

</Project>
```

> **Note:** We start with Avalonia 11.3.13 (matching the current app) so the project compiles and integrates immediately. The version bump to Avalonia 12 is a separate task outside this plan. The controls we build here use standard Avalonia APIs that exist in both 11 and 12.

- [ ] **Step 3: Add project to solution**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet sln EdgeStudio.sln add EdgeStudio.UI/EdgeStudio.UI.csproj
```

- [ ] **Step 4: Verify it builds**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio.UI/EdgeStudio.UI.csproj
```

Expected: Build succeeded. 0 Errors.

- [ ] **Step 5: Commit**

```bash
git add dotnet/src/EdgeStudio.UI/EdgeStudio.UI.csproj dotnet/src/EdgeStudio.sln
git commit -m "feat(dotnet): add EdgeStudio.UI class library project"
```

---

## Task 2: Create Theme System (StudioTheme + DittoBrushes)

**Files:**
- Create: `dotnet/src/EdgeStudio.UI/Themes/StudioTheme.axaml`
- Create: `dotnet/src/EdgeStudio.UI/Themes/DittoBrushes.axaml`

- [ ] **Step 1: Create Themes directory**

```bash
mkdir -p /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src/EdgeStudio.UI/Themes
```

- [ ] **Step 2: Create DittoBrushes.axaml**

Create `dotnet/src/EdgeStudio.UI/Themes/DittoBrushes.axaml`:

```xml
<ResourceDictionary xmlns="https://github.com/avaloniaui"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

    <!-- Theme-variant-aware resources (light/dark) -->
    <ResourceDictionary.ThemeDictionaries>

        <ResourceDictionary x:Key="Light">
            <!-- Card background: semi-transparent light surface -->
            <Color x:Key="StudioCardBackgroundColor">#CCF1F0EA</Color>
            <SolidColorBrush x:Key="StudioCardBackground" Color="{StaticResource StudioCardBackgroundColor}" />

            <!-- Low-contrast text -->
            <Color x:Key="StudioLowTextColor">#99000000</Color>
            <SolidColorBrush x:Key="StudioLowText" Color="{StaticResource StudioLowTextColor}" />

            <!-- Glass border highlight -->
            <Color x:Key="StudioGlassHighlightColor">#40FFFFFF</Color>
            <SolidColorBrush x:Key="StudioGlassHighlight" Color="{StaticResource StudioGlassHighlightColor}" />

            <!-- Glass card hover state -->
            <Color x:Key="StudioCardHoverColor">#D9F1F0EA</Color>
            <SolidColorBrush x:Key="StudioCardHover" Color="{StaticResource StudioCardHoverColor}" />
        </ResourceDictionary>

        <ResourceDictionary x:Key="Dark">
            <!-- Card background: semi-transparent dark surface -->
            <Color x:Key="StudioCardBackgroundColor">#CC2A292A</Color>
            <SolidColorBrush x:Key="StudioCardBackground" Color="{StaticResource StudioCardBackgroundColor}" />

            <!-- Low-contrast text -->
            <Color x:Key="StudioLowTextColor">#99FFFFFF</Color>
            <SolidColorBrush x:Key="StudioLowText" Color="{StaticResource StudioLowTextColor}" />

            <!-- Glass border highlight -->
            <Color x:Key="StudioGlassHighlightColor">#20FFFFFF</Color>
            <SolidColorBrush x:Key="StudioGlassHighlight" Color="{StaticResource StudioGlassHighlightColor}" />

            <!-- Glass card hover state -->
            <Color x:Key="StudioCardHoverColor">#D92A292A</Color>
            <SolidColorBrush x:Key="StudioCardHover" Color="{StaticResource StudioCardHoverColor}" />
        </ResourceDictionary>

    </ResourceDictionary.ThemeDictionaries>

    <!-- Popup shadow (invariant) -->
    <BoxShadows x:Key="StudioPopupShadow">0 4 12 0 #40000000</BoxShadows>

    <!-- Card shadow for GlassCard -->
    <BoxShadows x:Key="StudioCardShadow">0 2 8 0 #30000000</BoxShadows>

    <!-- Toast severity colors -->
    <SolidColorBrush x:Key="StudioToastError" Color="#D93025" />
    <SolidColorBrush x:Key="StudioToastSuccess" Color="#34A853" />
    <SolidColorBrush x:Key="StudioToastWarning" Color="#F9AB00" />
    <SolidColorBrush x:Key="StudioToastInfo" Color="#4285F4" />

</ResourceDictionary>
```

- [ ] **Step 3: Create StudioTheme.axaml**

Create `dotnet/src/EdgeStudio.UI/Themes/StudioTheme.axaml`:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:controls="using:EdgeStudio.UI.Controls">

    <Styles.Resources>
        <ResourceDictionary>
            <ResourceDictionary.MergedDictionaries>
                <ResourceInclude Source="avares://EdgeStudio.UI/Themes/DittoBrushes.axaml" />
            </ResourceDictionary.MergedDictionaries>
        </ResourceDictionary>
    </Styles.Resources>

    <!-- GlassCard default styles are included from the control's theme -->
    <StyleInclude Source="avares://EdgeStudio.UI/Controls/GlassCard.axaml" />
    <StyleInclude Source="avares://EdgeStudio.UI/Controls/ToastItem.axaml" />
    <StyleInclude Source="avares://EdgeStudio.UI/Controls/ToastHost.axaml" />
    <StyleInclude Source="avares://EdgeStudio.UI/Controls/DialogHost.axaml" />
    <StyleInclude Source="avares://EdgeStudio.UI/Controls/DialogItem.axaml" />

</Styles>
```

> **Note:** The StyleIncludes will fail to resolve until we create the control files in subsequent tasks. That's expected — we'll verify the build after all controls exist.

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio.UI/Themes/
git commit -m "feat(dotnet): add StudioTheme and DittoBrushes resource dictionaries"
```

---

## Task 3: Create GlassCard Control

**Files:**
- Create: `dotnet/src/EdgeStudio.UI/Controls/GlassCard.cs`
- Create: `dotnet/src/EdgeStudio.UI/Controls/GlassCard.axaml`
- Test: `dotnet/src/EdgeStudioTests/GlassCardTests.cs`

- [ ] **Step 1: Create Controls directory**

```bash
mkdir -p /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src/EdgeStudio.UI/Controls
```

- [ ] **Step 2: Write GlassCard tests**

Create `dotnet/src/EdgeStudioTests/GlassCardTests.cs`:

```csharp
using Avalonia.Controls;
using Avalonia.Headless.XUnit;
using Avalonia.Input;
using EdgeStudio.UI.Controls;
using FluentAssertions;

namespace EdgeStudioTests;

public class GlassCardTests
{
    [AvaloniaFact]
    public void GlassCard_DefaultCornerRadius_ShouldBe8()
    {
        var card = new GlassCard();
        card.CornerRadius.TopLeft.Should().Be(8);
    }

    [AvaloniaFact]
    public void GlassCard_IsInteractive_DefaultFalse()
    {
        var card = new GlassCard();
        card.IsInteractive.Should().BeFalse();
    }

    [AvaloniaFact]
    public void GlassCard_SetCornerRadius_ShouldApply()
    {
        var card = new GlassCard { CornerRadius = new Avalonia.CornerRadius(12) };
        card.CornerRadius.TopLeft.Should().Be(12);
    }

    [AvaloniaFact]
    public void GlassCard_ContentPresenter_ShouldRenderContent()
    {
        var card = new GlassCard
        {
            Content = new TextBlock { Text = "Test" }
        };

        card.Content.Should().NotBeNull();
        card.Content.Should().BeOfType<TextBlock>();
    }
}
```

- [ ] **Step 3: Add EdgeStudio.UI project reference to test project**

Add to `dotnet/src/EdgeStudioTests/EdgeStudioTests.csproj` in the `<ItemGroup>` with project references:

```xml
<ProjectReference Include="..\EdgeStudio.UI\EdgeStudio.UI.csproj" />
```

- [ ] **Step 4: Run tests to verify they fail**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~GlassCardTests" --verbosity normal
```

Expected: Build failure — `GlassCard` type does not exist yet.

- [ ] **Step 5: Create GlassCard.cs**

Create `dotnet/src/EdgeStudio.UI/Controls/GlassCard.cs`:

```csharp
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;

namespace EdgeStudio.UI.Controls;

public class GlassCard : ContentControl
{
    public static readonly StyledProperty<bool> IsInteractiveProperty =
        AvaloniaProperty.Register<GlassCard, bool>(nameof(IsInteractive), defaultValue: false);

    public static readonly new StyledProperty<CornerRadius> CornerRadiusProperty =
        AvaloniaProperty.Register<GlassCard, CornerRadius>(nameof(CornerRadius), defaultValue: new CornerRadius(8));

    public bool IsInteractive
    {
        get => GetValue(IsInteractiveProperty);
        set => SetValue(IsInteractiveProperty, value);
    }

    public new CornerRadius CornerRadius
    {
        get => GetValue(CornerRadiusProperty);
        set => SetValue(CornerRadiusProperty, value);
    }

    protected override void OnPointerEntered(PointerEventArgs e)
    {
        base.OnPointerEntered(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pointerover", true);
        }
    }

    protected override void OnPointerExited(PointerEventArgs e)
    {
        base.OnPointerExited(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pointerover", false);
            PseudoClasses.Set(":pressed", false);
        }
    }

    protected override void OnPointerPressed(PointerPressedEventArgs e)
    {
        base.OnPointerPressed(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pressed", true);
        }
    }

    protected override void OnPointerReleased(PointerReleasedEventArgs e)
    {
        base.OnPointerReleased(e);
        if (IsInteractive)
        {
            PseudoClasses.Set(":pressed", false);
        }
    }
}
```

- [ ] **Step 6: Create GlassCard.axaml (default template)**

Create `dotnet/src/EdgeStudio.UI/Controls/GlassCard.axaml`:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:controls="using:EdgeStudio.UI.Controls">

    <Style Selector="controls|GlassCard">
        <Setter Property="Background" Value="{DynamicResource StudioCardBackground}" />
        <Setter Property="Padding" Value="12" />
        <Setter Property="Template">
            <ControlTemplate>
                <Border CornerRadius="{TemplateBinding CornerRadius}"
                        Background="{TemplateBinding Background}"
                        BoxShadow="{DynamicResource StudioCardShadow}"
                        ClipToBounds="True">
                    <!-- Top highlight border for glass depth cue -->
                    <Border BorderBrush="{DynamicResource StudioGlassHighlight}"
                            BorderThickness="0,1,0,0"
                            Padding="{TemplateBinding Padding}">
                        <ContentPresenter Content="{TemplateBinding Content}"
                                          ContentTemplate="{TemplateBinding ContentTemplate}"
                                          HorizontalContentAlignment="{TemplateBinding HorizontalContentAlignment}"
                                          VerticalContentAlignment="{TemplateBinding VerticalContentAlignment}" />
                    </Border>
                </Border>
            </ControlTemplate>
        </Setter>
    </Style>

    <!-- Hover state for interactive cards -->
    <Style Selector="controls|GlassCard:pointerover">
        <Setter Property="Background" Value="{DynamicResource StudioCardHover}" />
    </Style>

    <!-- Pressed state for interactive cards -->
    <Style Selector="controls|GlassCard:pressed">
        <Setter Property="RenderTransform">
            <ScaleTransform ScaleX="0.98" ScaleY="0.98" />
        </Setter>
    </Style>

</Styles>
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~GlassCardTests" --verbosity normal
```

Expected: All 4 tests pass.

- [ ] **Step 8: Commit**

```bash
git add dotnet/src/EdgeStudio.UI/Controls/GlassCard.cs dotnet/src/EdgeStudio.UI/Controls/GlassCard.axaml dotnet/src/EdgeStudioTests/GlassCardTests.cs dotnet/src/EdgeStudioTests/EdgeStudioTests.csproj
git commit -m "feat(dotnet): add GlassCard control with tests"
```

---

## Task 4: Create Toast System

**Files:**
- Create: `dotnet/src/EdgeStudio.UI/Services/ToastItemData.cs`
- Create: `dotnet/src/EdgeStudio.UI/Services/ToastManager.cs`
- Create: `dotnet/src/EdgeStudio.UI/Controls/ToastItem.axaml` + `.cs`
- Create: `dotnet/src/EdgeStudio.UI/Controls/ToastHost.axaml` + `.cs`
- Test: `dotnet/src/EdgeStudioTests/ToastManagerTests.cs`

- [ ] **Step 1: Write ToastManager tests**

Create `dotnet/src/EdgeStudioTests/ToastManagerTests.cs`:

```csharp
using EdgeStudio.UI.Services;
using FluentAssertions;

namespace EdgeStudioTests;

public class ToastManagerTests
{
    [Fact]
    public void ShowError_ShouldAddToastToActiveToasts()
    {
        var manager = new ToastManager();
        manager.ShowError("Something failed");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Title.Should().Be("Error");
        manager.ActiveToasts[0].Message.Should().Be("Something failed");
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Error);
    }

    [Fact]
    public void ShowSuccess_ShouldAddToastWithCorrectSeverity()
    {
        var manager = new ToastManager();
        manager.ShowSuccess("Done!");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Success);
    }

    [Fact]
    public void ShowWarning_ShouldAddToastWithCorrectSeverity()
    {
        var manager = new ToastManager();
        manager.ShowWarning("Watch out");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Warning);
    }

    [Fact]
    public void ShowInfo_ShouldAddToastWithCorrectSeverity()
    {
        var manager = new ToastManager();
        manager.ShowInfo("FYI");
        manager.ActiveToasts.Should().HaveCount(1);
        manager.ActiveToasts[0].Severity.Should().Be(ToastSeverity.Info);
    }

    [Fact]
    public void ShowError_WithCustomTitle_ShouldUseCustomTitle()
    {
        var manager = new ToastManager();
        manager.ShowError("msg", "Custom Title");
        manager.ActiveToasts[0].Title.Should().Be("Custom Title");
    }

    [Fact]
    public void MaxFiveToasts_ShouldRemoveOldestWhenExceeded()
    {
        var manager = new ToastManager();
        for (int i = 0; i < 6; i++)
        {
            manager.ShowInfo($"Toast {i}");
        }

        manager.ActiveToasts.Should().HaveCount(5);
        manager.ActiveToasts[0].Message.Should().Be("Toast 1");
    }

    [Fact]
    public void DismissToast_ShouldRemoveFromActiveToasts()
    {
        var manager = new ToastManager();
        manager.ShowError("msg");
        var toastId = manager.ActiveToasts[0].Id;

        manager.Dismiss(toastId);

        manager.ActiveToasts.Should().BeEmpty();
    }

    [Fact]
    public void DismissToast_WithInvalidId_ShouldNotThrow()
    {
        var manager = new ToastManager();
        var act = () => manager.Dismiss(Guid.NewGuid());
        act.Should().NotThrow();
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~ToastManagerTests" --verbosity normal
```

Expected: Build failure — types do not exist yet.

- [ ] **Step 3: Create Services directory and ToastItemData.cs**

```bash
mkdir -p /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src/EdgeStudio.UI/Services
```

Create `dotnet/src/EdgeStudio.UI/Services/ToastItemData.cs`:

```csharp
namespace EdgeStudio.UI.Services;

public enum ToastSeverity
{
    Error,
    Success,
    Warning,
    Info
}

public record ToastItemData(
    Guid Id,
    string Title,
    string Message,
    ToastSeverity Severity,
    TimeSpan Duration);
```

- [ ] **Step 4: Create ToastManager.cs**

Create `dotnet/src/EdgeStudio.UI/Services/ToastManager.cs`:

```csharp
using System.Collections.ObjectModel;
using Avalonia.Threading;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.UI.Services;

public class ToastManager : IToastService
{
    private const int MaxToasts = 5;

    public ObservableCollection<ToastItemData> ActiveToasts { get; } = new();

    public void ShowError(string message, string? title = null)
    {
        AddToast(title ?? "Error", message, ToastSeverity.Error, TimeSpan.FromSeconds(5));
    }

    public void ShowSuccess(string message, string? title = null)
    {
        AddToast(title ?? "Success", message, ToastSeverity.Success, TimeSpan.FromSeconds(3));
    }

    public void ShowWarning(string message, string? title = null)
    {
        AddToast(title ?? "Warning", message, ToastSeverity.Warning, TimeSpan.FromSeconds(4));
    }

    public void ShowInfo(string message, string? title = null)
    {
        AddToast(title ?? "Information", message, ToastSeverity.Info, TimeSpan.FromSeconds(4));
    }

    public void Dismiss(Guid toastId)
    {
        DispatchToUI(() =>
        {
            var toast = ActiveToasts.FirstOrDefault(t => t.Id == toastId);
            if (toast != null)
            {
                ActiveToasts.Remove(toast);
            }
        });
    }

    private void AddToast(string title, string message, ToastSeverity severity, TimeSpan duration)
    {
        DispatchToUI(() =>
        {
            var toast = new ToastItemData(Guid.NewGuid(), title, message, severity, duration);

            while (ActiveToasts.Count >= MaxToasts)
            {
                ActiveToasts.RemoveAt(0);
            }

            ActiveToasts.Add(toast);
            StartAutoDismiss(toast);
        });
    }

    private void StartAutoDismiss(ToastItemData toast)
    {
        var timer = new DispatcherTimer { Interval = toast.Duration };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            Dismiss(toast.Id);
        };
        timer.Start();
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

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~ToastManagerTests" --verbosity normal
```

Expected: All 8 tests pass.

- [ ] **Step 6: Create ToastItem control**

Create `dotnet/src/EdgeStudio.UI/Controls/ToastItem.cs`:

```csharp
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using EdgeStudio.UI.Services;

namespace EdgeStudio.UI.Controls;

public class ToastItem : TemplatedControl
{
    public static readonly StyledProperty<string> TitleProperty =
        AvaloniaProperty.Register<ToastItem, string>(nameof(Title), defaultValue: "");

    public static readonly StyledProperty<string> MessageProperty =
        AvaloniaProperty.Register<ToastItem, string>(nameof(Message), defaultValue: "");

    public static readonly StyledProperty<ToastSeverity> SeverityProperty =
        AvaloniaProperty.Register<ToastItem, ToastSeverity>(nameof(Severity), defaultValue: ToastSeverity.Info);

    public string Title
    {
        get => GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public string Message
    {
        get => GetValue(MessageProperty);
        set => SetValue(MessageProperty, value);
    }

    public ToastSeverity Severity
    {
        get => GetValue(SeverityProperty);
        set => SetValue(SeverityProperty, value);
    }
}
```

Create `dotnet/src/EdgeStudio.UI/Controls/ToastItem.axaml`:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:controls="using:EdgeStudio.UI.Controls">

    <Style Selector="controls|ToastItem">
        <Setter Property="Template">
            <ControlTemplate>
                <Border Background="{DynamicResource StudioCardBackground}"
                        CornerRadius="8"
                        BoxShadow="{DynamicResource StudioPopupShadow}"
                        Padding="0"
                        Margin="0,0,0,8"
                        ClipToBounds="True">
                    <Grid ColumnDefinitions="4,*,Auto">
                        <!-- Severity color stripe -->
                        <Border Grid.Column="0" CornerRadius="8,0,0,8"
                                Name="SeverityStripe" />

                        <!-- Content -->
                        <StackPanel Grid.Column="1" Margin="12,10" Spacing="4">
                            <TextBlock Text="{TemplateBinding Title}"
                                       FontWeight="SemiBold"
                                       FontSize="13" />
                            <TextBlock Text="{TemplateBinding Message}"
                                       Foreground="{DynamicResource StudioLowText}"
                                       FontSize="12"
                                       TextWrapping="Wrap" />
                        </StackPanel>

                        <!-- Close button -->
                        <Button Grid.Column="2"
                                Content="&#x2715;"
                                Background="Transparent"
                                BorderThickness="0"
                                Padding="8"
                                Margin="0,4,4,0"
                                VerticalAlignment="Top"
                                FontSize="11"
                                Name="CloseButton" />
                    </Grid>
                </Border>
            </ControlTemplate>
        </Setter>
    </Style>

    <!-- Severity stripe colors -->
    <Style Selector="controls|ToastItem /template/ Border#SeverityStripe">
        <Setter Property="Background" Value="{DynamicResource StudioToastInfo}" />
    </Style>
    <Style Selector="controls|ToastItem[Severity=Error] /template/ Border#SeverityStripe">
        <Setter Property="Background" Value="{DynamicResource StudioToastError}" />
    </Style>
    <Style Selector="controls|ToastItem[Severity=Success] /template/ Border#SeverityStripe">
        <Setter Property="Background" Value="{DynamicResource StudioToastSuccess}" />
    </Style>
    <Style Selector="controls|ToastItem[Severity=Warning] /template/ Border#SeverityStripe">
        <Setter Property="Background" Value="{DynamicResource StudioToastWarning}" />
    </Style>

</Styles>
```

- [ ] **Step 7: Create ToastHost control**

Create `dotnet/src/EdgeStudio.UI/Controls/ToastHost.cs`:

```csharp
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using EdgeStudio.UI.Services;

namespace EdgeStudio.UI.Controls;

public class ToastHost : TemplatedControl
{
    public static readonly StyledProperty<ToastManager?> ManagerProperty =
        AvaloniaProperty.Register<ToastHost, ToastManager?>(nameof(Manager));

    public ToastManager? Manager
    {
        get => GetValue(ManagerProperty);
        set => SetValue(ManagerProperty, value);
    }
}
```

Create `dotnet/src/EdgeStudio.UI/Controls/ToastHost.axaml`:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:controls="using:EdgeStudio.UI.Controls">

    <Style Selector="controls|ToastHost">
        <Setter Property="HorizontalAlignment" Value="Right" />
        <Setter Property="VerticalAlignment" Value="Top" />
        <Setter Property="Width" Value="350" />
        <Setter Property="Margin" Value="0,16,16,0" />
        <Setter Property="IsHitTestVisible" Value="False" />
        <Setter Property="Template">
            <ControlTemplate>
                <ItemsControl ItemsSource="{Binding Manager.ActiveToasts, RelativeSource={RelativeSource TemplatedParent}}"
                              IsHitTestVisible="True">
                    <ItemsControl.ItemTemplate>
                        <DataTemplate>
                            <controls:ToastItem Title="{Binding Title}"
                                                Message="{Binding Message}"
                                                Severity="{Binding Severity}" />
                        </DataTemplate>
                    </ItemsControl.ItemTemplate>
                </ItemsControl>
            </ControlTemplate>
        </Setter>
    </Style>

</Styles>
```

- [ ] **Step 8: Verify build**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio.UI/EdgeStudio.UI.csproj
```

Expected: Build succeeded.

- [ ] **Step 9: Run all tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~ToastManagerTests" --verbosity normal
```

Expected: All 8 tests pass.

- [ ] **Step 10: Commit**

```bash
git add dotnet/src/EdgeStudio.UI/Services/ dotnet/src/EdgeStudio.UI/Controls/ToastItem.cs dotnet/src/EdgeStudio.UI/Controls/ToastItem.axaml dotnet/src/EdgeStudio.UI/Controls/ToastHost.cs dotnet/src/EdgeStudio.UI/Controls/ToastHost.axaml dotnet/src/EdgeStudioTests/ToastManagerTests.cs
git commit -m "feat(dotnet): add toast notification system with tests"
```

---

## Task 5: Create Dialog System

**Files:**
- Create: `dotnet/src/EdgeStudio.UI/Services/DialogItemData.cs`
- Create: `dotnet/src/EdgeStudio.UI/Services/DialogManager.cs`
- Create: `dotnet/src/EdgeStudio.UI/Controls/DialogItem.axaml` + `.cs`
- Create: `dotnet/src/EdgeStudio.UI/Controls/DialogHost.axaml` + `.cs`
- Test: `dotnet/src/EdgeStudioTests/DialogManagerTests.cs`

- [ ] **Step 1: Write DialogManager tests**

Create `dotnet/src/EdgeStudioTests/DialogManagerTests.cs`:

```csharp
using EdgeStudio.UI.Services;
using FluentAssertions;

namespace EdgeStudioTests;

public class DialogManagerTests
{
    [Fact]
    public void ShowError_ShouldSetCurrentDialogAndIsOpen()
    {
        var manager = new DialogManager();
        manager.ShowError("Error Title", "Something broke");

        manager.CurrentDialog.Should().NotBeNull();
        manager.CurrentDialog!.Title.Should().Be("Error Title");
        manager.CurrentDialog.Message.Should().Be("Something broke");
        manager.IsOpen.Should().BeTrue();
    }

    [Fact]
    public void Dismiss_ShouldClearCurrentDialogAndIsOpen()
    {
        var manager = new DialogManager();
        manager.ShowError("Title", "Message");

        manager.Dismiss();

        manager.CurrentDialog.Should().BeNull();
        manager.IsOpen.Should().BeFalse();
    }

    [Fact]
    public void ShowError_WhenDialogAlreadyOpen_ShouldReplaceIt()
    {
        var manager = new DialogManager();
        manager.ShowError("First", "First message");
        manager.ShowError("Second", "Second message");

        manager.CurrentDialog!.Title.Should().Be("Second");
    }

    [Fact]
    public void ShowConfirmation_ShouldReturnTrueWhenConfirmed()
    {
        var manager = new DialogManager();
        var task = manager.ShowConfirmationAsync("Confirm?", "Are you sure?", "Yes", "No");

        manager.CurrentDialog.Should().NotBeNull();
        manager.IsOpen.Should().BeTrue();

        // Simulate user clicking confirm
        manager.CurrentDialog!.Buttons[0].Callback();

        task.IsCompleted.Should().BeTrue();
        task.Result.Should().BeTrue();
        manager.IsOpen.Should().BeFalse();
    }

    [Fact]
    public void ShowConfirmation_ShouldReturnFalseWhenCancelled()
    {
        var manager = new DialogManager();
        var task = manager.ShowConfirmationAsync("Confirm?", "Are you sure?", "Yes", "No");

        // Simulate user clicking cancel
        manager.CurrentDialog!.Buttons[1].Callback();

        task.IsCompleted.Should().BeTrue();
        task.Result.Should().BeFalse();
    }

    [Fact]
    public void InitialState_ShouldHaveNoDialogAndNotOpen()
    {
        var manager = new DialogManager();
        manager.CurrentDialog.Should().BeNull();
        manager.IsOpen.Should().BeFalse();
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~DialogManagerTests" --verbosity normal
```

Expected: Build failure — types do not exist yet.

- [ ] **Step 3: Create DialogItemData.cs**

Create `dotnet/src/EdgeStudio.UI/Services/DialogItemData.cs`:

```csharp
namespace EdgeStudio.UI.Services;

public record DialogButton(string Label, Action Callback);

public record DialogItemData(
    string Title,
    string Message,
    DialogSeverity Severity,
    List<DialogButton> Buttons);

public enum DialogSeverity
{
    Error,
    Warning,
    Info
}
```

- [ ] **Step 4: Create DialogManager.cs**

Create `dotnet/src/EdgeStudio.UI/Services/DialogManager.cs`:

```csharp
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Avalonia.Threading;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.UI.Services;

public class DialogManager : IDialogService, INotifyPropertyChanged
{
    private DialogItemData? _currentDialog;
    private bool _isOpen;

    public DialogItemData? CurrentDialog
    {
        get => _currentDialog;
        private set
        {
            _currentDialog = value;
            OnPropertyChanged();
        }
    }

    public bool IsOpen
    {
        get => _isOpen;
        private set
        {
            _isOpen = value;
            OnPropertyChanged();
        }
    }

    public void ShowError(string title, string message)
    {
        DispatchToUI(() =>
        {
            CurrentDialog = new DialogItemData(
                title,
                message,
                DialogSeverity.Error,
                new List<DialogButton>
                {
                    new("OK", Dismiss)
                });
            IsOpen = true;
        });
    }

    public Task<bool> ShowConfirmationAsync(
        string title,
        string message,
        string confirmLabel = "OK",
        string cancelLabel = "Cancel")
    {
        var tcs = new TaskCompletionSource<bool>();
        DispatchToUI(() =>
        {
            CurrentDialog = new DialogItemData(
                title,
                message,
                DialogSeverity.Warning,
                new List<DialogButton>
                {
                    new(confirmLabel, () =>
                    {
                        Dismiss();
                        tcs.TrySetResult(true);
                    }),
                    new(cancelLabel, () =>
                    {
                        Dismiss();
                        tcs.TrySetResult(false);
                    })
                });
            IsOpen = true;
        });
        return tcs.Task;
    }

    public void Dismiss()
    {
        DispatchToUI(() =>
        {
            CurrentDialog = null;
            IsOpen = false;
        });
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
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

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~DialogManagerTests" --verbosity normal
```

Expected: All 6 tests pass.

- [ ] **Step 6: Create DialogItem control**

Create `dotnet/src/EdgeStudio.UI/Controls/DialogItem.cs`:

```csharp
using Avalonia;
using Avalonia.Controls.Primitives;

namespace EdgeStudio.UI.Controls;

public class DialogItem : TemplatedControl
{
    public static readonly StyledProperty<string> TitleProperty =
        AvaloniaProperty.Register<DialogItem, string>(nameof(Title), defaultValue: "");

    public static readonly StyledProperty<string> MessageProperty =
        AvaloniaProperty.Register<DialogItem, string>(nameof(Message), defaultValue: "");

    public string Title
    {
        get => GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public string Message
    {
        get => GetValue(MessageProperty);
        set => SetValue(MessageProperty, value);
    }
}
```

Create `dotnet/src/EdgeStudio.UI/Controls/DialogItem.axaml`:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:controls="using:EdgeStudio.UI.Controls">

    <Style Selector="controls|DialogItem">
        <Setter Property="Template">
            <ControlTemplate>
                <Border Background="{DynamicResource StudioCardBackground}"
                        CornerRadius="12"
                        BoxShadow="{DynamicResource StudioPopupShadow}"
                        MaxWidth="450"
                        MinWidth="300"
                        Padding="24">
                    <StackPanel Spacing="16">
                        <TextBlock Text="{TemplateBinding Title}"
                                   FontWeight="Bold"
                                   FontSize="16" />
                        <TextBlock Text="{TemplateBinding Message}"
                                   TextWrapping="Wrap"
                                   Foreground="{DynamicResource StudioLowText}"
                                   FontSize="14" />
                        <ItemsControl Name="ButtonHost"
                                      HorizontalAlignment="Right">
                            <ItemsControl.ItemsPanel>
                                <ItemsPanelTemplate>
                                    <StackPanel Orientation="Horizontal" Spacing="8" />
                                </ItemsPanelTemplate>
                            </ItemsControl.ItemsPanel>
                        </ItemsControl>
                    </StackPanel>
                </Border>
            </ControlTemplate>
        </Setter>
    </Style>

</Styles>
```

- [ ] **Step 7: Create DialogHost control**

Create `dotnet/src/EdgeStudio.UI/Controls/DialogHost.cs`:

```csharp
using Avalonia;
using Avalonia.Controls;
using Avalonia.Controls.Primitives;
using Avalonia.Input;
using EdgeStudio.UI.Services;

namespace EdgeStudio.UI.Controls;

public class DialogHost : TemplatedControl
{
    public static readonly StyledProperty<DialogManager?> ManagerProperty =
        AvaloniaProperty.Register<DialogHost, DialogManager?>(nameof(Manager));

    public DialogManager? Manager
    {
        get => GetValue(ManagerProperty);
        set => SetValue(ManagerProperty, value);
    }
}
```

Create `dotnet/src/EdgeStudio.UI/Controls/DialogHost.axaml`:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:controls="using:EdgeStudio.UI.Controls">

    <Style Selector="controls|DialogHost">
        <Setter Property="Template">
            <ControlTemplate>
                <Panel IsVisible="{Binding Manager.IsOpen, RelativeSource={RelativeSource TemplatedParent}}">
                    <!-- Backdrop -->
                    <Border Background="#40000000" />

                    <!-- Dialog content centered -->
                    <ContentPresenter Content="{Binding Manager.CurrentDialog, RelativeSource={RelativeSource TemplatedParent}}"
                                      HorizontalAlignment="Center"
                                      VerticalAlignment="Center">
                        <ContentPresenter.ContentTemplate>
                            <DataTemplate>
                                <controls:DialogItem Title="{Binding Title}"
                                                     Message="{Binding Message}" />
                            </DataTemplate>
                        </ContentPresenter.ContentTemplate>
                    </ContentPresenter>
                </Panel>
            </ControlTemplate>
        </Setter>
    </Style>

</Styles>
```

- [ ] **Step 8: Verify full EdgeStudio.UI builds**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio.UI/EdgeStudio.UI.csproj
```

Expected: Build succeeded.

- [ ] **Step 9: Run all tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

Expected: All tests pass (existing + new).

- [ ] **Step 10: Commit**

```bash
git add dotnet/src/EdgeStudio.UI/Services/DialogItemData.cs dotnet/src/EdgeStudio.UI/Services/DialogManager.cs dotnet/src/EdgeStudio.UI/Controls/DialogItem.cs dotnet/src/EdgeStudio.UI/Controls/DialogItem.axaml dotnet/src/EdgeStudio.UI/Controls/DialogHost.cs dotnet/src/EdgeStudio.UI/Controls/DialogHost.axaml dotnet/src/EdgeStudioTests/DialogManagerTests.cs
git commit -m "feat(dotnet): add dialog system with confirmation support and tests"
```

---

## Task 6: Wire EdgeStudio.UI into EdgeStudio App

**Files:**
- Modify: `dotnet/src/EdgeStudio/EdgeStudio.csproj`
- Modify: `dotnet/src/EdgeStudio/App.axaml`
- Modify: `dotnet/src/EdgeStudio/App.axaml.cs`

- [ ] **Step 1: Update EdgeStudio.csproj — remove SukiUI, add EdgeStudio.UI**

In `dotnet/src/EdgeStudio/EdgeStudio.csproj`, remove:

```xml
<PackageReference Include="SukiUI" Version="6.0.3" />
```

Add in the `<ItemGroup>` with project references:

```xml
<ProjectReference Include="..\EdgeStudio.UI\EdgeStudio.UI.csproj" />
```

- [ ] **Step 2: Update App.axaml — replace SukiTheme with StudioTheme**

In `dotnet/src/EdgeStudio/App.axaml`:

Replace the `xmlns:suki` declaration and `<suki:SukiTheme />` usage. The full `<Application.Styles>` section should become:

```xml
<Application.Styles>
    <FluentTheme />
    <StyleInclude Source="avares://AvaloniaEdit/Themes/Fluent/AvaloniaEdit.xaml" />

    <!-- Studio theme (replaces SukiTheme) -->
    <StyleInclude Source="avares://EdgeStudio.UI/Themes/StudioTheme.axaml" />

    <!-- Brand button styling must come after StudioTheme -->
    <StyleInclude Source="avares://EdgeStudio/Styles/ButtonStyles.axaml" />

    <!-- Custom styles -->
    <StyleInclude Source="avares://EdgeStudio/Styles/GlassCardStyles.axaml" />
    <StyleInclude Source="avares://EdgeStudio/Styles/MaterialIconStyles.axaml" />
    <StyleInclude Source="avares://EdgeStudio/Styles/TextStyles.axaml" />
    <StyleInclude Source="avares://EdgeStudio/Styles/WrapPanelStyles.axaml" />
    <materialIcons:MaterialIconStyles />
</Application.Styles>
```

Also remove the `xmlns:suki="https://github.com/kikipoulet/SukiUI"` namespace declaration from the `<Application>` tag.

- [ ] **Step 3: Update App.axaml.cs — replace DI registrations and remove theme code**

In `dotnet/src/EdgeStudio/App.axaml.cs`:

Remove these imports:
```csharp
using SukiUI;
using SukiUI.Models;
```

Replace the toast/dialog DI registrations (around lines 168-179). Remove:
```csharp
services.AddSingleton<SukiUI.Toasts.ISukiToastManager>(provider =>
{
    return new SukiUI.Toasts.SukiToastManager();
});

services.AddSingleton<SukiUI.Dialogs.ISukiDialogManager>(provider =>
{
    return new SukiUI.Dialogs.SukiDialogManager();
});

services.AddSingleton<IDialogService, SukiDialogService>();
services.AddSingleton<IToastService, SukiToastService>();
```

Replace with:
```csharp
services.AddSingleton<EdgeStudio.UI.Services.ToastManager>();
services.AddSingleton<IToastService>(sp => sp.GetRequiredService<EdgeStudio.UI.Services.ToastManager>());
services.AddSingleton<EdgeStudio.UI.Services.DialogManager>();
services.AddSingleton<IDialogService>(sp => sp.GetRequiredService<EdgeStudio.UI.Services.DialogManager>());
```

Remove the `SetupDittoThemes()` method entirely (the method that calls `SukiTheme.GetInstance()`, creates `SukiColorTheme` objects, and calls `ChangeColorTheme`).

Remove the call to `SetupDittoThemes()` from wherever it's invoked.

- [ ] **Step 4: Attempt build — expect errors from SukiUI references in other files**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj 2>&1 | head -50
```

Expected: Build errors in MainWindow, all SukiWindow subclasses, GlassCard XAML references, style files. This is expected — we fix these in the next tasks.

- [ ] **Step 5: Commit the wiring changes (partial — build will break until remaining tasks complete)**

```bash
git add dotnet/src/EdgeStudio/EdgeStudio.csproj dotnet/src/EdgeStudio/App.axaml dotnet/src/EdgeStudio/App.axaml.cs
git commit -m "refactor(dotnet): wire EdgeStudio.UI, remove SukiUI package and theme code

Build is intentionally broken — remaining SukiUI references in windows,
views, and styles will be migrated in subsequent commits."
```

---

## Task 7: Migrate MainWindow (SukiWindow → Window)

**Files:**
- Modify: `dotnet/src/EdgeStudio/Views/MainWindow.axaml`
- Modify: `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs`
- Modify: `dotnet/src/EdgeStudio/ViewModels/MainWindowViewModel.cs`

This is the most complex window migration because MainWindow has toast/dialog hosts, title bar controls, theme callbacks, and direct `DialogManager.CreateDialog()` calls.

- [ ] **Step 1: Update MainWindow.axaml**

Replace the root element and remove all SukiUI-specific sections. The AXAML should change from `<suki:SukiWindow ...>` to `<Window ...>`.

Key changes:
- Root element: `<suki:SukiWindow>` → `<Window>`
- Remove `xmlns:suki="clr-namespace:SukiUI.Controls;assembly=SukiUI"`
- Add `xmlns:studio="using:EdgeStudio.UI.Controls"`
- Remove `BackgroundStyle="Flat"`
- Remove entire `<suki:SukiWindow.Hosts>` section
- Remove entire `<suki:SukiWindow.RightWindowTitleBarControls>` section
- Add toast/dialog hosts as last children of the root Grid inside the Window:

```xml
<!-- Add as last children of the main content Grid -->
<studio:ToastHost Manager="{Binding ToastManager}" />
<studio:DialogHost Manager="{Binding DialogManager}" />
```

- Close tag: `</suki:SukiWindow>` → `</Window>`

> **Menu bar note:** The Settings and Help buttons from `RightWindowTitleBarControls` need a new home. On macOS, the app already has a native menu bar. On Windows/Linux, add a `<Menu>` or `<NativeMenu>` in the toolbar area with Settings and Help items. This can be a follow-up refinement if the buttons aren't critical for the initial migration — the actions are still accessible via other paths in the app.

- [ ] **Step 2: Update MainWindow.axaml.cs**

Remove all SukiUI imports:
```csharp
using SukiUI;
using SukiUI.Controls;
using SukiUI.Dialogs;
using SukiUI.Enums;
using SukiUI.Models;
using SukiUI.Toasts;
```

Change base class: `public partial class MainWindow : SukiWindow` → `public partial class MainWindow : Window`

Remove these properties:
```csharp
public ISukiToastManager ToastManager { get; }
public SukiUI.Dialogs.ISukiDialogManager DialogManager { get; }
```

Remove the toast/dialog manager initialization from the constructor.

Remove `UpdateBackgroundStyle()` method entirely.

Remove `SukiTheme.GetInstance()` usage and `OnColorThemeChanged` callback.

For the direct `DialogManager.CreateDialog()` calls (lines 229 and 253), replace them with the new `DialogManager.ShowConfirmationAsync()`. For example, replace:

```csharp
var tcs = new TaskCompletionSource<bool>();
var builder = DialogManager.CreateDialog();
builder.SetType(NotificationType.Warning);
builder.SetTitle("No Database Connected");
builder.SetContent("No database is currently connected...");
builder.AddActionButton("Continue Anyway", _ => tcs.TrySetResult(true), dismissOnClick: true, classes: []);
builder.AddActionButton("Cancel", _ => tcs.TrySetResult(false), dismissOnClick: true, classes: []);
builder.TryShow();
var shouldContinue = await tcs.Task;
```

With:

```csharp
var dialogManager = App.ServiceProvider?.GetService(typeof(EdgeStudio.UI.Services.DialogManager))
    as EdgeStudio.UI.Services.DialogManager;
var shouldContinue = await (dialogManager?.ShowConfirmationAsync(
    "No Database Connected",
    "No database is currently connected. Quickstart projects will be downloaded but .env files will not be auto-configured with credentials.\n\nYou can manually configure them later.",
    "Continue Anyway",
    "Cancel") ?? Task.FromResult(false));
```

Apply the same pattern to the "Folder Already Exists" dialog (lines 252-261), which has 3 buttons. For that one, use a different approach — add a `ShowChoiceAsync` method or chain two confirmation dialogs. The simplest approach: refactor to use separate confirm calls or add the method to DialogManager.

> **Implementation note:** The existing folder dialog has 3 choices (Replace, Choose Different, Cancel). Rather than adding a generic multi-button API now, handle it with two sequential confirmations or add a targeted `ShowThreeChoiceAsync` to DialogManager. Prefer the simplest approach that works.

- [ ] **Step 3: Update MainWindowViewModel.cs to expose managers**

Add properties to `MainWindowViewModel`:

```csharp
public EdgeStudio.UI.Services.ToastManager ToastManager { get; }
public EdgeStudio.UI.Services.DialogManager DialogManager { get; }
```

Initialize in the constructor from DI:

```csharp
public MainWindowViewModel(
    // ... existing parameters ...,
    EdgeStudio.UI.Services.ToastManager toastManager,
    EdgeStudio.UI.Services.DialogManager dialogManager)
    : base(toastService)
{
    ToastManager = toastManager;
    DialogManager = dialogManager;
    // ... rest of constructor ...
}
```

- [ ] **Step 4: Verify build compiles (may still have errors from other windows)**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj 2>&1 | head -30
```

- [ ] **Step 5: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/MainWindow.axaml dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs dotnet/src/EdgeStudio/ViewModels/MainWindowViewModel.cs
git commit -m "refactor(dotnet): migrate MainWindow from SukiWindow to Window with toast/dialog overlays"
```

---

## Task 8: Migrate All Other SukiWindow Subclasses

**Files:**
- Modify: 14 window `.axaml` + `.axaml.cs` files

All 14 remaining windows follow the same simple pattern. Each needs:

1. **AXAML:** `<suki:SukiWindow>` → `<Window>`, remove `xmlns:suki`, remove `BackgroundStyle="Flat"`, change closing tag
2. **Code-behind:** `: SukiWindow` → `: Window`, remove `using SukiUI.Controls;`

- [ ] **Step 1: Migrate Database windows (6 files)**

Apply to each of these files:

**DatabaseFormWindow.axaml/.cs:**
- AXAML: `<suki:SukiWindow` → `<Window`, remove `xmlns:suki="using:SukiUI.Controls"`, remove `BackgroundStyle="Flat"`, `</suki:SukiWindow>` → `</Window>`
- CS: `SukiWindow` → `Window`, remove `using SukiUI.Controls;`

**IndexFormWindow.axaml/.cs** — same pattern
**ObserverFormWindow.axaml/.cs** — same pattern
**SubscriptionFormWindow.axaml/.cs** — same pattern
**QrCodeDisplayWindow.axaml/.cs** — same pattern
**QrCodeImportWindow.axaml/.cs** — same pattern

- [ ] **Step 2: Migrate Settings windows (2 files)**

**PreferencesWindow.axaml/.cs** — same pattern
**TransportSettingsWindow.axaml/.cs** — same pattern

- [ ] **Step 3: Migrate Help windows (3 files)**

**UserGuideWindow.axaml/.cs** — same pattern
**QuickstartBrowserWindow.axaml/.cs** — same pattern
**QuickstartProgressWindow.axaml/.cs** — same pattern

- [ ] **Step 4: Migrate remaining windows (3 files)**

**AttachmentPickerWindow.axaml/.cs** — same pattern
**DeleteAttachmentWindow.axaml/.cs** — same pattern
**ImportDataWindow.axaml/.cs** — same pattern

- [ ] **Step 5: Verify build**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj 2>&1 | head -30
```

Expected: Remaining errors should only be from GlassCard references and style files (fixed in next tasks).

- [ ] **Step 6: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/
git commit -m "refactor(dotnet): migrate all 14 SukiWindow subclasses to standard Window"
```

---

## Task 9: Migrate GlassCard References in Views

**Files:**
- Modify: 7 view AXAML files that use `suki:GlassCard`

Each file needs: replace `suki:GlassCard` with `studio:GlassCard`, update xmlns declaration from SukiUI to EdgeStudio.UI.Controls.

- [ ] **Step 1: Migrate DatabaseListingView.axaml**

- Replace `xmlns:suki="clr-namespace:SukiUI.Controls;assembly=SukiUI"` with `xmlns:studio="using:EdgeStudio.UI.Controls"`
- Replace all `<suki:GlassCard` with `<studio:GlassCard`
- Replace all `</suki:GlassCard>` with `</studio:GlassCard>`
- Replace all `<suki:GlassCard.ContextMenu>` with `<studio:GlassCard.ContextMenu>`
- Replace all `</suki:GlassCard.ContextMenu>` with `</studio:GlassCard.ContextMenu>`

- [ ] **Step 2: Migrate SubscriptionListingView.axaml**

Same pattern: `suki:GlassCard` → `studio:GlassCard`, update xmlns.

- [ ] **Step 3: Migrate ObserverListingView.axaml**

Same pattern.

- [ ] **Step 4: Migrate TableResultsView.axaml**

Same pattern. Also replace `{DynamicResource SukiLowText}` with `{DynamicResource StudioLowText}`.

- [ ] **Step 5: Migrate IndexesToolView.axaml**

Same pattern.

- [ ] **Step 6: Migrate FavoritesToolView.axaml**

Same pattern.

- [ ] **Step 7: Migrate HistoryToolView.axaml**

Same pattern.

- [ ] **Step 8: Verify build**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj 2>&1 | head -30
```

- [ ] **Step 9: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/
git commit -m "refactor(dotnet): migrate all GlassCard references from SukiUI to EdgeStudio.UI"
```

---

## Task 10: Migrate Style Files

**Files:**
- Modify: `dotnet/src/EdgeStudio/Styles/GlassCardStyles.axaml`
- Modify: `dotnet/src/EdgeStudio/Styles/WrapPanelStyles.axaml`
- Modify: `dotnet/src/EdgeStudio/Styles/CompletionWindowStyles.axaml`

- [ ] **Step 1: Update GlassCardStyles.axaml**

Replace the full content:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:studio="using:EdgeStudio.UI.Controls">

    <Style Selector="studio|GlassCard.HeaderCard">
        <Setter Property="Margin" Value="30,30,30,1" />
    </Style>

</Styles>
```

- [ ] **Step 2: Update WrapPanelStyles.axaml**

Remove the `suki:WrapPanelExtensions.AnimatedScroll` setter and update GlassCard namespace:

```xml
<Styles xmlns="https://github.com/avaloniaui"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:studio="using:EdgeStudio.UI.Controls">

    <Style Selector="WrapPanel.PageContainer">
        <Setter Property="Margin" Value="15,15,0,0" />
        <Setter Property="Orientation" Value="Horizontal" />
        <Style Selector="^ > studio|GlassCard">
            <Setter Property="Margin" Value="15,15,15,15" />
        </Style>
    </Style>

</Styles>
```

- [ ] **Step 3: Update CompletionWindowStyles.axaml**

Replace `{DynamicResource SukiCardBackground}` with `{DynamicResource StudioCardBackground}`.
Replace `{DynamicResource SukiPopupShadow}` with `{DynamicResource StudioPopupShadow}`.
Remove the `suki:BiggestItemListBoxConverter` resource if present and replace its usage with a simple width binding or remove it.

- [ ] **Step 4: Verify build**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj 2>&1 | head -30
```

- [ ] **Step 5: Commit**

```bash
git add dotnet/src/EdgeStudio/Styles/
git commit -m "refactor(dotnet): migrate style files from SukiUI to EdgeStudio.UI resources"
```

---

## Task 11: Delete SukiUI Service Files and Clean Up

**Files:**
- Delete: `dotnet/src/EdgeStudio/Services/SukiDialogService.cs`
- Delete: `dotnet/src/EdgeStudio/Services/SukiToastService.cs`
- Modify: `dotnet/src/EdgeStudioTests/DialogServiceTests.cs`

- [ ] **Step 1: Delete SukiDialogService.cs and SukiToastService.cs**

```bash
rm dotnet/src/EdgeStudio/Services/SukiDialogService.cs
rm dotnet/src/EdgeStudio/Services/SukiToastService.cs
```

- [ ] **Step 2: Update DialogServiceTests.cs**

The existing tests mock `ISukiDialogManager`. Replace with tests against `DialogManager` directly. Update `dotnet/src/EdgeStudioTests/DialogServiceTests.cs`:

```csharp
using EdgeStudio.UI.Services;
using FluentAssertions;

namespace EdgeStudioTests;

public class DialogServiceTests
{
    [Fact]
    public void ShowError_ShouldSetCurrentDialogAndIsOpen()
    {
        var dialogManager = new DialogManager();
        dialogManager.ShowError("Test Title", "Test message");

        dialogManager.CurrentDialog.Should().NotBeNull();
        dialogManager.CurrentDialog!.Title.Should().Be("Test Title");
        dialogManager.IsOpen.Should().BeTrue();
    }

    [Fact]
    public void ShowError_ShouldHaveOkButton()
    {
        var dialogManager = new DialogManager();
        dialogManager.ShowError("Title", "Message");

        dialogManager.CurrentDialog!.Buttons.Should().HaveCount(1);
        dialogManager.CurrentDialog.Buttons[0].Label.Should().Be("OK");
    }
}
```

- [ ] **Step 3: Grep for any remaining SukiUI references**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
grep -rn "SukiUI\|suki:" --include="*.cs" --include="*.axaml" EdgeStudio/ | grep -v "bin/" | grep -v "obj/"
```

Expected: Zero results. If any remain, fix them.

- [ ] **Step 4: Full build and test**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio.sln && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

Expected: Build succeeded. All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A dotnet/src/
git commit -m "refactor(dotnet): remove SukiUI service files and update tests

SukiUI is fully removed from the project. All toast and dialog
functionality now provided by EdgeStudio.UI library."
```

---

## Task 12: Final Verification and Cleanup

- [ ] **Step 1: Verify no SukiUI NuGet package remains**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
grep -rn "SukiUI" --include="*.csproj" .
```

Expected: Zero results.

- [ ] **Step 2: Verify full solution builds clean**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet clean EdgeStudio.sln
dotnet build EdgeStudio.sln --verbosity normal
```

Expected: Build succeeded with zero errors.

- [ ] **Step 3: Run all tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

Expected: All tests pass.

- [ ] **Step 4: Verify no remaining SukiUI references anywhere**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
grep -rn "SukiUI\|suki:" --include="*.cs" --include="*.axaml" --include="*.csproj" . | grep -v "bin/" | grep -v "obj/"
```

Expected: Zero results.

- [ ] **Step 5: Commit final state**

```bash
git add -A dotnet/src/
git commit -m "chore(dotnet): verify clean SukiUI removal — all builds pass, zero references remain"
```
