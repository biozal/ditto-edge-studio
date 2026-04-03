# Help Menu: Documentation Window & Ditto Website Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire up the two Help menu items — "Edge Studio Documentation" opens a new window rendering `UserGuide.md` with the existing markdown renderer; "Visit Ditto Website" opens `https://www.ditto.com/` in the system browser.

**Architecture:** Add `UserGuide.md` to the existing help-docs sync build target so it copies into `Assets/Help/` at build time. Create a new `UserGuideWindow` (SukiWindow + XAML) that loads the asset via `AssetLoader` and renders it with the existing `SimpleMarkdownRenderer`. Wire both Help menu items in `MainWindow.axaml` to click handlers in `MainWindow.axaml.cs`. The website item uses the existing cross-platform `Process.Start` pattern from `MainWindowViewModel.OpenDittoPortal()`.

**Tech Stack:** C# / Avalonia UI / SukiUI / existing `SimpleMarkdownRenderer`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `dotnet/src/EdgeStudio/EdgeStudio.csproj` | Modify (line 98) | Add `UserGuide.md` to the SyncHelpDocs Copy list |
| `dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml` | Create | XAML layout for the documentation window (SukiWindow with ScrollViewer + ContentPresenter) |
| `dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml.cs` | Create | Code-behind that loads `UserGuide.md` from assets and renders it with `SimpleMarkdownRenderer` |
| `dotnet/src/EdgeStudio/Views/MainWindow.axaml` | Modify (lines 74-75) | Add `Click` handlers to both Help menu items |
| `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs` | Modify | Add `HelpDocumentation_Click` and `VisitDittoWebsite_Click` event handlers |
| `dotnet/src/EdgeStudioTests/HelpMenuTests.cs` | Create | Tests for URL opening logic and asset loading |

---

### Task 1: Add `UserGuide.md` to the Build Sync Target

**Files:**
- Modify: `dotnet/src/EdgeStudio/EdgeStudio.csproj:98`

- [ ] **Step 1: Add UserGuide.md to the Copy list**

In `dotnet/src/EdgeStudio/EdgeStudio.csproj`, find line 98 (the `<Copy>` element inside the `SyncHelpDocs` target). Add `$(HelpDocsSource)UserGuide.md` to the `SourceFiles` list.

Change:
```xml
<Copy SourceFiles="$(HelpDocsSource)query.md;$(HelpDocsSource)subscription.md;$(HelpDocsSource)logging.md;$(HelpDocsSource)observe.md;$(HelpDocsSource)appmetrics.md;$(HelpDocsSource)querymetrics.md" DestinationFolder="$(HelpDocsDest)" SkipUnchangedFiles="true" />
```

To:
```xml
<Copy SourceFiles="$(HelpDocsSource)query.md;$(HelpDocsSource)subscription.md;$(HelpDocsSource)logging.md;$(HelpDocsSource)observe.md;$(HelpDocsSource)appmetrics.md;$(HelpDocsSource)querymetrics.md;$(HelpDocsSource)UserGuide.md" DestinationFolder="$(HelpDocsDest)" SkipUnchangedFiles="true" />
```

- [ ] **Step 2: Build to verify the file syncs**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity normal
```

Expected: Build succeeds. Verify the file landed:
```bash
ls -la /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src/EdgeStudio/Assets/Help/UserGuide.md
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/EdgeStudio.csproj
git commit -m "build(dotnet): add UserGuide.md to help docs sync target"
```

---

### Task 2: Create UserGuideWindow (XAML + Code-Behind)

**Files:**
- Create: `dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml`
- Create: `dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml.cs`

- [ ] **Step 1: Create the XAML file**

Create `dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml`:

```xml
<suki:SukiWindow xmlns="https://github.com/avaloniaui"
                 xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
                 xmlns:d="http://schemas.microsoft.com/expression/blend/2008"
                 xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006"
                 xmlns:suki="using:SukiUI.Controls"
                 mc:Ignorable="d"
                 d:DesignWidth="750"
                 d:DesignHeight="600"
                 x:Class="EdgeStudio.Views.Help.UserGuideWindow"
                 Title="Edge Studio Documentation"
                 Width="750"
                 Height="700"
                 WindowStartupLocation="CenterOwner"
                 CanResize="True"
                 BackgroundStyle="Flat">

    <ScrollViewer Padding="24,16,24,24">
        <ContentPresenter x:Name="MarkdownContainer" />
    </ScrollViewer>

</suki:SukiWindow>
```

- [ ] **Step 2: Create the code-behind file**

Create `dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml.cs`:

```csharp
using System;
using System.IO;
using Avalonia.Controls;
using Avalonia.Platform.Storage;
using EdgeStudio.Views.StudioView.Inspector;
using SukiUI.Controls;

namespace EdgeStudio.Views.Help;

public partial class UserGuideWindow : SukiWindow
{
    private static readonly Uri UserGuideUri = new("avares://EdgeStudio/Assets/Help/UserGuide.md");

    public UserGuideWindow()
    {
        InitializeComponent();
        LoadMarkdownContent();
    }

    private void LoadMarkdownContent()
    {
        try
        {
            using var stream = Avalonia.Platform.Storage.AssetLoader.Open(UserGuideUri);
            using var reader = new StreamReader(stream);
            var markdown = reader.ReadToEnd();
            MarkdownContainer.Content = SimpleMarkdownRenderer.Render(markdown);
        }
        catch (Exception)
        {
            MarkdownContainer.Content = new TextBlock
            {
                Text = "Unable to load documentation. The UserGuide.md file may be missing.",
                TextWrapping = Avalonia.Media.TextWrapping.Wrap
            };
        }
    }
}
```

**Important:** The `AssetLoader` class is in `Avalonia.Platform.Storage` namespace. Verify the correct using statement by checking how `EdgeStudioViewModel.cs` imports it. The existing code at line 543 uses:
```csharp
using var stream = AssetLoader.Open(LoggingHelpUri);
```
Check the using statements at the top of `EdgeStudioViewModel.cs` to find the correct namespace — it may be `Avalonia.Platform.Storage.AssetLoader` or just `AssetLoader` with a different using. Match whatever the existing codebase uses.

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml dotnet/src/EdgeStudio/Views/Help/UserGuideWindow.axaml.cs
git commit -m "feat(dotnet): add UserGuideWindow for displaying Edge Studio documentation"
```

---

### Task 3: Wire Help Menu Items in MainWindow

**Files:**
- Modify: `dotnet/src/EdgeStudio/Views/MainWindow.axaml:74-75`
- Modify: `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs`

- [ ] **Step 1: Add Click handlers to the XAML menu items**

In `dotnet/src/EdgeStudio/Views/MainWindow.axaml`, change lines 74-75 from:

```xml
<NativeMenuItem Header="Edge Studio Documentation" />
<NativeMenuItem Header="Visit Ditto Website" />
```

To:

```xml
<NativeMenuItem Header="Edge Studio Documentation" Click="HelpDocumentation_Click" />
<NativeMenuItem Header="Visit Ditto Website" Click="VisitDittoWebsite_Click" />
```

- [ ] **Step 2: Add the click handler methods to code-behind**

In `dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs`, add two new using statements at the top (if not already present):

```csharp
using System.Diagnostics;
using EdgeStudio.Views.Help;
```

Then add these two methods to the `MainWindow` class, before the `OnClosed` method:

```csharp
private void HelpDocumentation_Click(object? sender, EventArgs e)
{
    var window = new UserGuideWindow();
    window.Show();
}

private void VisitDittoWebsite_Click(object? sender, EventArgs e)
{
    const string url = "https://www.ditto.com/";
    try
    {
        if (OperatingSystem.IsWindows())
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        else if (OperatingSystem.IsMacOS())
            Process.Start("open", url);
        else
            Process.Start("xdg-open", url);
    }
    catch (Exception ex)
    {
        System.Diagnostics.Debug.WriteLine($"[ERROR] Could not open Ditto website: {ex.Message}");
    }
}
```

- [ ] **Step 3: Build to verify compilation**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/MainWindow.axaml dotnet/src/EdgeStudio/Views/MainWindow.axaml.cs
git commit -m "feat(dotnet): wire Help menu items to documentation window and Ditto website"
```

---

### Task 4: Write Tests

**Files:**
- Create: `dotnet/src/EdgeStudioTests/HelpMenuTests.cs`

- [ ] **Step 1: Write tests for UserGuideWindow asset loading and website URL pattern**

Create `dotnet/src/EdgeStudioTests/HelpMenuTests.cs`:

```csharp
using System;
using System.Diagnostics;
using System.IO;
using Xunit;
using FluentAssertions;

namespace EdgeStudioTests;

public class HelpMenuTests
{
    [Fact]
    public void UserGuide_AssetFile_ExistsInHelpDirectory()
    {
        // Verify the UserGuide.md file exists in the Assets/Help directory
        // This validates the build sync target is working
        var projectDir = FindProjectDirectory();
        var helpFile = Path.Combine(projectDir, "Assets", "Help", "UserGuide.md");
        File.Exists(helpFile).Should().BeTrue(
            because: "UserGuide.md should be synced from docs/help/ by the SyncHelpDocs build target");
    }

    [Fact]
    public void UserGuide_AssetFile_HasContent()
    {
        var projectDir = FindProjectDirectory();
        var helpFile = Path.Combine(projectDir, "Assets", "Help", "UserGuide.md");

        if (!File.Exists(helpFile))
        {
            // Skip if file doesn't exist (build hasn't run yet)
            return;
        }

        var content = File.ReadAllText(helpFile);
        content.Should().NotBeNullOrWhiteSpace(because: "UserGuide.md should contain documentation");
        content.Should().Contain("# ", because: "UserGuide.md should contain markdown headings");
    }

    [Fact]
    public void DittoWebsiteUrl_IsValid()
    {
        const string url = "https://www.ditto.com/";
        var uri = new Uri(url);
        uri.Scheme.Should().Be("https");
        uri.Host.Should().Be("www.ditto.com");
    }

    /// <summary>
    /// Walks up from the test assembly output directory to find the EdgeStudio project directory.
    /// </summary>
    private static string FindProjectDirectory()
    {
        var dir = AppContext.BaseDirectory;
        while (dir != null)
        {
            var candidate = Path.Combine(dir, "EdgeStudio");
            if (Directory.Exists(candidate) && Directory.Exists(Path.Combine(candidate, "Assets")))
                return candidate;

            // Also check if we're already in the src directory
            var csproj = Path.Combine(dir, "EdgeStudio", "EdgeStudio.csproj");
            if (File.Exists(csproj))
                return Path.Combine(dir, "EdgeStudio");

            dir = Directory.GetParent(dir)?.FullName;
        }

        // Fallback: use known relative path from test project
        var testDir = Path.GetDirectoryName(typeof(HelpMenuTests).Assembly.Location)!;
        return Path.GetFullPath(Path.Combine(testDir, "..", "..", "..", "..", "EdgeStudio"));
    }
}
```

- [ ] **Step 2: Run the tests**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~HelpMenuTests" --logger "console;verbosity=detailed"
```

Expected: All 3 tests pass.

- [ ] **Step 3: Run the full test suite to verify no regressions**

Run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj
```

Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudioTests/HelpMenuTests.cs
git commit -m "test(dotnet): add tests for Help menu documentation and website features"
```

---

### Task 5: Manual Verification

- [ ] **Step 1: Run the app and test Help menu**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet run --project EdgeStudio/EdgeStudio.csproj
```

Verify:
1. **Help > Edge Studio Documentation** — opens a new window titled "Edge Studio Documentation" with rendered markdown content (headings, lists, code blocks, tables should all render)
2. **Help > Visit Ditto Website** — opens `https://www.ditto.com/` in the default system browser
3. The documentation window is resizable and scrollable
4. The documentation window works in both light and dark themes
5. Multiple documentation windows can be opened (or verify behavior is acceptable)

- [ ] **Step 2: Verify both themes**

Switch system theme (light/dark) and confirm the documentation window renders readably in both modes. The `SimpleMarkdownRenderer` uses some hardcoded colors for code blocks — this is the existing pattern and acceptable.
