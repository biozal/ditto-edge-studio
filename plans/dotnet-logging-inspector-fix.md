# Plan: Fix Logging Inspector Blank Rendering

## Root Cause (Confirmed via Research)

`MarkdownScrollViewer` auto-detects the active theme via an internal `ThemeDetector` class to select
a rendering style. The detector only checks the **first** item in `Application.Styles`. When SukiUI
is present (even though `FluentTheme` is listed first), detection can fail and falls back to the
**`Standard` style**, which has hardcoded dark text colors. On SukiUI's dark `DittoDark` background
these colors are invisible — the content IS rendering, the text just cannot be seen.

### Why Previous Attempts Failed

| Attempt | Result | Reason |
|---------|--------|--------|
| `StyleInclude` for `MarkdownStyleFluentTheme.axaml` | `MethodAccessException` crash | Class constructor is `internal` — cannot be instantiated via XAML loader |
| `Source="avares://..."` | Silent startup crash | Bug in `MarkdownScrollViewer.Source` in this library version |
| `MarkdownStyleName="FluentTheme"` + `Source=` together | Crash | `Source=` was the crash cause, not `MarkdownStyleName` |
| `Markdown="{Binding LoggingHelpContent}"` alone | Blank (invisible) | Standard style → dark text on dark background |

### Correct Fix

Set `MarkdownStyleName="FluentTheme"` directly on the control. This calls the property setter which
uses reflection to access `MarkdownStyle.FluentTheme` (a static property), bypassing `ThemeDetector`
entirely. The FluentTheme style uses Avalonia's dynamic theme resources that adapt to dark/light mode.

Available `MarkdownStyleName` values: `"Standard"`, `"SimpleTheme"`, `"FluentTheme"`,
`"FluentAvalonia"`, `"GithubLike"`, `"Empty"`.

---

## Implementation Steps

### Step 1 — Update `InspectorView.axaml`

Add `MarkdownStyleName="FluentTheme"` to the `MarkdownScrollViewer`:

```xml
<!-- Before -->
<md:MarkdownScrollViewer Markdown="{Binding LoggingHelpContent}"/>

<!-- After -->
<md:MarkdownScrollViewer Markdown="{Binding LoggingHelpContent}"
                         MarkdownStyleName="FluentTheme"/>
```

No other changes to InspectorView.axaml are needed.

### Step 2 — No App.axaml Changes

Do **not** add any `StyleInclude` for Markdown.Avalonia styles — those all have `internal`
constructors and will crash. No changes needed to `App.axaml` or `App.axaml.cs`.

### Step 3 — Verify `EnsureLoggingHelpLoaded` Is Called

`EdgeStudioViewModel.UpdateCurrentViews` already calls `EnsureLoggingHelpLoaded()` in the
`NavigationItemType.Logging` case. Confirm the asset loads by verifying the avares path:
`avares://EdgeStudio/Assets/Help/logging.md` with assembly name `EdgeStudio`.

---

## Files Changed

| File | Change |
|------|--------|
| `dotnet/src/EdgeStudio/Views/Inspector/InspectorView.axaml` | Add `MarkdownStyleName="FluentTheme"` |

---

## Tests

### Test 1 — `LoggingHelpContent` Is Loaded on Navigation

**File:** `dotnet/src/EdgeStudioTests/ViewModels/EdgeStudioViewModelTests.cs`

Verify that navigating to Logging causes `LoggingHelpContent` to be non-empty:

```csharp
[Fact]
public void LoggingHelpContent_IsLoadedWhenLoggingNavActivated()
{
    // Arrange — set up ViewModel with mocked dependencies
    var vm = CreateTestViewModel();

    // Act — simulate navigation to Logging
    vm.SimulateNavigationToLogging(); // calls UpdateCurrentViews(NavigationItemType.Logging)

    // Assert
    Assert.NotEmpty(vm.LoggingHelpContent);
    Assert.DoesNotContain("unavailable", vm.LoggingHelpContent, StringComparison.OrdinalIgnoreCase);
}
```

### Test 2 — `IsLoggingActive` Toggles on Navigation

```csharp
[Fact]
public void IsLoggingActive_IsTrueWhenLoggingNavSelected()
{
    var vm = CreateTestViewModel();
    Assert.False(vm.IsLoggingActive);

    vm.SimulateNavigationToLogging();

    Assert.True(vm.IsLoggingActive);
}

[Fact]
public void IsLoggingActive_IsFalseWhenOtherNavSelected()
{
    var vm = CreateTestViewModel();
    vm.SimulateNavigationToLogging();
    Assert.True(vm.IsLoggingActive);

    vm.SimulateNavigationToSubscriptions();

    Assert.False(vm.IsLoggingActive);
}
```

### Test 3 — `LoggingHelpContent` Is Only Loaded Once (Lazy)

```csharp
[Fact]
public void LoggingHelpContent_IsLoadedOnlyOnce()
{
    var vm = CreateTestViewModel();

    vm.SimulateNavigationToLogging();
    var firstContent = vm.LoggingHelpContent;

    vm.SimulateNavigationToSubscriptions();
    vm.SimulateNavigationToLogging(); // second navigation

    Assert.Equal(firstContent, vm.LoggingHelpContent); // same reference, loaded once
}
```

---

## Manual Verification Checklist

After implementing:

1. Build: `dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`
2. Run: `open EdgeStudio/bin/Debug/net10.0/EdgeStudio.app`
3. Connect to a database → click Logging in NavBar → click Inspector toggle
   - ✅ Inspector shows formatted markdown content (headings, paragraphs, code blocks)
   - ✅ Text is readable (white/light on dark background)
   - ✅ Content is scrollable
4. Switch to another nav item (e.g., Subscriptions)
   - ✅ Inspector shows History/Favorites/Indexes tabs
5. Switch back to Logging
   - ✅ Markdown content renders again
6. Test in light mode (System Preferences → Appearance → Light)
   - ✅ Text still readable (dark text on light background)
