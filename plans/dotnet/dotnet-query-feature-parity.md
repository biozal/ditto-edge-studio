# Plan: Dotnet Query Feature Parity + UI Polish

## Overview

This plan consolidates all outstanding work across three areas:

1. **Feature gaps** — functionality present in SwiftUI but missing in dotnet
2. **Remaining bugs** — items from prior sessions that are still broken
3. **UI polish** — styling/UX improvements

The plan is divided into **8 sequential steps**. Each step includes automated test specs and a manual checkpoint before proceeding.

---

## Step 1: Fix JSON Syntax Highlighting Regression on Pagination

### Problem

When navigating pages or changing page size, JSON cards on subsequent pages render without syntax highlighting (white text only). The first page loads correctly; all subsequent pages are un-highlighted.

### Root Cause

In `JsonDocumentCard.axaml.cs`:

```csharp
private void SetupSyntaxHighlighting()
{
    var installation = JsonEditor.InstallTextMate(RegistryOptions);  // LOCAL variable!
    installation.SetGrammar(...);
}
```

`installation` is a local variable. After `SetupSyntaxHighlighting()` returns, it gets garbage collected. TextMateSharp requires the `TextMateInstallation` object to remain alive for syntax highlighting to function. When `ItemsControl` recycles/creates new `JsonDocumentCard` instances on page navigation, the installation is GC'd before the new card renders.

### Fix

**File: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/JsonDocumentCard.axaml.cs`**

Store the installation as a field:
```csharp
private TextMateInstallation? _textMateInstallation; // Add this field

private void SetupSyntaxHighlighting()
{
    try
    {
        _textMateInstallation = JsonEditor.InstallTextMate(RegistryOptions);
        _textMateInstallation.SetGrammar(
            RegistryOptions.GetScopeByLanguageId(
                RegistryOptions.GetLanguageByExtension(".json").Id));
    }
    catch { }
}
```

Same fix applies to `DocumentViewerView.axaml.cs` (Inspector JSON Viewer — same pattern):

**File: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/DocumentViewerView.axaml.cs`**

Add `private TextMateInstallation? _textMateInstallation;` field and store the return value in `SetupSyntaxHighlighting()`.

### Automated Tests

**File: `dotnet/src/EdgeStudioTests/JsonResultsViewModelTests.cs`** (existing)

Add test verifying `SetResults()` + `CurrentPage` change populates `PagedDocuments` correctly:
```csharp
[Fact]
public void NavigateToPageTwo_UpdatesPagedDocuments()
{
    var vm = new JsonResultsViewModel();
    vm.PageSize = 2;
    vm.SetResults(new[] { "doc1", "doc2", "doc3", "doc4" });

    vm.CurrentPage = 2;

    Assert.Equal(2, vm.PagedDocuments.Count);
    Assert.Equal("doc3", vm.PagedDocuments[0]);
    Assert.Equal("doc4", vm.PagedDocuments[1]);
}
```

### Manual Checkpoint

1. Execute a query returning 30+ documents
2. Default page size = 25 — verify page 1 JSON cards show colored syntax
3. Click `>` to go to page 2 — verify cards still show colored syntax (not white text)
4. Change page size to 50 — verify all cards show colored syntax

---

## Step 2: Query Editor UX Improvements

### Problem Items

- **2a**: Query editor text starts at the left edge with no left padding — text is too close to the divider
- **2b**: No gap between the execute bar (ComboBox + Play button) and the editor area
- **2c**: Query Editor tab name shows "Query 1", "Query 2", etc. — should show the actual query text, truncated to ~30 chars with `...`

### Fix 2a + 2b

**File: `dotnet/src/EdgeStudio/Views/StudioView/Details/QueryEditorView.axaml`**

Add `Padding="8,0,4,0"` to the `TextEditor` and increase the margin between execute bar and editor:
```xml
<!-- Execute bar — increase bottom margin from 4 to 8 -->
<StackPanel Grid.Row="0" Orientation="Horizontal" Spacing="8" Margin="8,6,8,8">
    ...
</StackPanel>

<!-- Query Editor — add left padding -->
<avaloniaEdit:TextEditor Grid.Row="1"
    Padding="8,4,4,4"
    .../>
```

### Fix 2c

**File: `dotnet/src/EdgeStudio/ViewModels/QueryDocumentViewModel.cs`**

Update `_baseTitle` whenever `QueryText` changes beyond an empty state:
```csharp
private void UpdateDirtyState()
{
    IsDirty = _queryText != _originalQueryText;
    UpdateBaseTitle();
}

private void UpdateBaseTitle()
{
    if (!string.IsNullOrWhiteSpace(_queryText))
    {
        var truncated = _queryText.Trim().Replace('\n', ' ').Replace('\r', ' ');
        _baseTitle = truncated.Length > 30
            ? truncated[..30].TrimEnd() + "..."
            : truncated;
    }
    UpdateTitle();
}
```

Note: The initial `_baseTitle` ("Query 1") should be kept until the user types. Only update `_baseTitle` once `QueryText` is non-empty.

### Automated Tests

**File: `dotnet/src/EdgeStudioTests/QueryViewModelTests.cs`** (existing or add)

```csharp
[Fact]
public void QueryText_Short_ShowsFullTextAsTitle()
{
    var vm = CreateQueryDocumentViewModel(title: "Query 1");
    vm.QueryText = "SELECT * FROM tasks";
    Assert.Equal("SELECT * FROM tasks*", vm.Title); // dirty marker
}

[Fact]
public void QueryText_Long_TruncatesTo30Chars()
{
    var vm = CreateQueryDocumentViewModel(title: "Query 1");
    vm.QueryText = "SELECT * FROM tasks WHERE done = true AND priority > 5";
    Assert.StartsWith("SELECT * FROM tasks WHERE done", vm.Title);
    Assert.EndsWith("...*", vm.Title);
}
```

### Manual Checkpoint

1. Open query editor — text area has visible left padding (not flush to edge)
2. Execute bar has ~8px gap above the editor
3. Type `SELECT * FROM tasks` — tab name updates to that text
4. Type a very long query — tab name truncates with `...`

---

## Step 3: History Deduplication

### Problem

Every time a query is executed, a new entry is appended to history — even if the exact same query was just run. Running `SELECT * FROM tasks` 10 times creates 10 identical entries. The SwiftUI app deduplicates: re-running a query moves it to the top.

### Fix

**File: `dotnet/src/EdgeStudio/ViewModels/HistoryToolViewModel.cs`**

In `OnQueryExecuted`, check if the query already exists. If so, remove the existing entry first, then insert at position 0:

```csharp
private void OnQueryExecuted(object recipient, QueryExecutedMessage message)
{
    var query = message.Query.Trim();
    if (string.IsNullOrWhiteSpace(query)) return;

    Dispatcher.UIThread.InvokeAsync(async () =>
    {
        // Dedup: remove existing entry for same query
        var existing = Items.FirstOrDefault(h =>
            string.Equals(h.Query?.Trim(), query, StringComparison.Ordinal));
        if (existing != null)
        {
            await _historyRepository.DeleteAsync(existing.Id);
            Items.Remove(existing);
        }

        // Insert new entry at top
        var newEntry = new QueryHistory
        {
            Id = Guid.NewGuid().ToString(),
            Query = query,
            Timestamp = DateTime.UtcNow
        };
        await _historyRepository.SaveAsync(newEntry);
        Items.Insert(0, newEntry);
    });
}
```

### Automated Tests

**File: `dotnet/src/EdgeStudioTests/HistoryDeduplicationTests.cs`** (new)

```csharp
[Fact]
public async Task ExecuteSameQuery_MovesToTop()
{
    // Arrange — pre-seed two history items
    var vm = new HistoryToolViewModel(mockRepo, ...);
    vm.Items.Add(new QueryHistory { Query = "SELECT * FROM docs", ... });
    vm.Items.Add(new QueryHistory { Query = "SELECT * FROM tasks", ... });

    // Act — execute the first query again
    WeakReferenceMessenger.Default.Send(
        new QueryExecutedMessage("SELECT * FROM docs", ...));
    await Task.Delay(50); // allow async dispatch

    // Assert
    Assert.Equal(2, vm.Items.Count);        // no new entry
    Assert.Equal("SELECT * FROM docs", vm.Items[0].Query);  // moved to top
    Assert.Equal("SELECT * FROM tasks", vm.Items[1].Query);
}
```

### Manual Checkpoint

1. Execute `SELECT * FROM tasks` — appears in History
2. Execute `SELECT * FROM collections` — appears at top
3. Execute `SELECT * FROM tasks` again — moves to top, no duplicate

---

## Step 4: Double-Click History / Favorites → Load AND Execute

### Problem

Currently, clicking a history/favorites item only loads the query text into the editor (via `LoadQueryRequestedMessage`). The user must then manually press Execute. Double-clicking should load AND immediately execute.

### Fix — New Message

**File: `dotnet/src/EdgeStudio.Shared/Messages/QueryMessages.cs`**

Add:
```csharp
public record LoadAndExecuteQueryRequestedMessage(string Query);
```

### Fix — HistoryToolViewModel

**File: `dotnet/src/EdgeStudio/ViewModels/HistoryToolViewModel.cs`**

Add:
```csharp
[RelayCommand]
private void LoadAndExecuteQuery(QueryHistory item)
{
    WeakReferenceMessenger.Default.Send(
        new LoadAndExecuteQueryRequestedMessage(item.Query));
}
```

### Fix — FavoritesToolViewModel

**File: `dotnet/src/EdgeStudio/ViewModels/FavoritesToolViewModel.cs`**

Add the same `LoadAndExecuteQueryCommand` sending `LoadAndExecuteQueryRequestedMessage`.

### Fix — QueryViewModel

**File: `dotnet/src/EdgeStudio/ViewModels/QueryViewModel.cs`**

Listen for the new message:
```csharp
WeakReferenceMessenger.Default.Register<LoadAndExecuteQueryRequestedMessage>(
    this, (r, msg) =>
    {
        Dispatcher.UIThread.InvokeAsync(async () =>
        {
            // Load query text into current document
            if (CurrentQueryDocument != null)
            {
                CurrentQueryDocument.QueryText = msg.Query;
                await CurrentQueryDocument.ExecuteQueryCommand.ExecuteAsync(null);
            }
        });
    });
```

### Fix — Views (DoubleTapped)

**File: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/HistoryToolView.axaml`**

In the `DataTemplate`, the `Border` already has `Cursor="Hand"`. Add a `DoubleTapped` event:
```xml
<Border ... DoubleTapped="OnItemDoubleTapped">
```

**File: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/HistoryToolView.axaml.cs`** (new code-behind if not present)
```csharp
private void OnItemDoubleTapped(object? sender, TappedEventArgs e)
{
    if (sender is Border { DataContext: QueryHistory item } &&
        DataContext is HistoryToolViewModel vm)
    {
        vm.LoadAndExecuteQueryCommand.Execute(item);
    }
}
```

Same pattern for `FavoritesToolView.axaml` and `.axaml.cs`.

### Automated Tests

```csharp
[Fact]
public void LoadAndExecuteQueryCommand_SendsCorrectMessage()
{
    var received = (LoadAndExecuteQueryRequestedMessage?)null;
    WeakReferenceMessenger.Default.Register<LoadAndExecuteQueryRequestedMessage>(
        this, (r, msg) => received = msg);

    var vm = new HistoryToolViewModel(...);
    var item = new QueryHistory { Query = "SELECT * FROM tasks" };
    vm.LoadAndExecuteQueryCommand.Execute(item);

    Assert.NotNull(received);
    Assert.Equal("SELECT * FROM tasks", received!.Query);
}
```

### Manual Checkpoint

1. Execute a query to add it to history
2. Single-click the history item — loads query text into editor, does NOT execute
3. Double-click the history item — loads AND executes immediately
4. Same for Favorites

---

## Step 5: Double-Click Document → Auto-Open Inspector + Navigate to JSON Viewer

### Problem

Clicking a JSON card or table row correctly sets `SelectedDocumentJson` and updates the Inspector JSON Viewer — but only when the inspector is already open. If the inspector is closed, double-clicking a document should (1) open the inspector and (2) navigate to the JSON Viewer tab.

### Fix — New Message

**File: `dotnet/src/EdgeStudio.Shared/Messages/QueryMessages.cs`**

Add:
```csharp
public record DocumentDoubleClickedMessage(string Json);
```

### Fix — JsonResultsViewModel

**File: `dotnet/src/EdgeStudio/ViewModels/JsonResultsViewModel.cs`**

Add a `DocumentDoubleClicked` event (distinct from `DocumentSelected`):
```csharp
public event Action<string>? DocumentDoubleClicked;
```

Add command:
```csharp
[RelayCommand]
private void DoubleClickDocument(string json)
{
    DocumentDoubleClicked?.Invoke(json);
}
```

### Fix — QueryDocumentViewModel

Subscribe to `DocumentDoubleClicked` in the constructor and forward:
```csharp
if (_jsonResults != null)
    _jsonResults.DocumentDoubleClicked += json =>
    {
        SelectedDocumentJson = json;
        WeakReferenceMessenger.Default.Send(new DocumentDoubleClickedMessage(json));
    };
if (_tableResults != null)
    _tableResults.RowDoubleClicked += json =>
    {
        SelectedDocumentJson = json;
        WeakReferenceMessenger.Default.Send(new DocumentDoubleClickedMessage(json));
    };
```

(Add `RowDoubleClicked` event to `TableResultsViewModel` similarly.)

### Fix — EdgeStudioViewModel

**File: `dotnet/src/EdgeStudio/ViewModels/EdgeStudioViewModel.cs`**

Register for `DocumentDoubleClickedMessage`:
```csharp
WeakReferenceMessenger.Default.Register<DocumentDoubleClickedMessage>(
    this, (r, msg) =>
    {
        // Open inspector if hidden
        if (!IsInspectorVisible)
            ToggleInspectorCommand.Execute(null);

        // Navigate inspector to JSON Viewer tab
        // (Inspector tab index for JSON Viewer — depends on InspectorView implementation)
        WeakReferenceMessenger.Default.Send(new NavigateInspectorToJsonViewerMessage());
    });
```

**File: `dotnet/src/EdgeStudio.Shared/Messages/QueryMessages.cs`**

Add:
```csharp
public record NavigateInspectorToJsonViewerMessage();
```

The `InspectorView` (or its ViewModel) listens for this message and switches the active inspector tab to the JSON Viewer.

### Fix — Views

**File: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/JsonResultsView.axaml`**

Add a `DoubleTapped` event on the `Button` wrapper around each card OR change the `Button` to handle double-tap:

```xml
<Button ...
        Command="{Binding $parent[ItemsControl].DataContext.SelectDocumentCommand}"
        CommandParameter="{Binding}"
        DoubleTapped="OnCardDoubleTapped"
        ...>
```

**File: `dotnet/src/EdgeStudio/Views/StudioView/Inspector/JsonResultsView.axaml.cs`**

```csharp
private void OnCardDoubleTapped(object? sender, TappedEventArgs e)
{
    if (sender is Button { DataContext: string json } &&
        DataContext is JsonResultsViewModel vm)
    {
        vm.DoubleClickDocumentCommand.Execute(json);
    }
}
```

Similar for `TableResultsView.axaml.cs`.

### Manual Checkpoint

1. Close inspector
2. Execute a query with results
3. Double-click a JSON card → inspector opens AND switches to JSON Viewer tab showing the document
4. Inspector already open → double-click a different card → switches to JSON Viewer with new doc
5. Same works for table rows

---

## Step 6: Inspector Icon Styling (Ditto Yellow)

### Problem

Navigation bar icons use hard-coded blue colors:
- **Selected**: `#333F51B5` (dark blue background)
- **Hover**: `#1A3F51B5` (transparent blue)

Per the design spec:
- **Selected**: Ditto Yellow (`DittoAccent`) background, black icon (`DittoJetBlack`)
- **Hover**: Icon color turns Ditto Yellow; background stays transparent

### Fix

**File: `dotnet/src/EdgeStudio/Views/StudioView/Navigation/NavigationBar.axaml`**

Replace the hover and selected styles:
```xml
<Style Selector="Button.NavButton:pointerover">
    <Setter Property="Background" Value="Transparent"/>
</Style>

<Style Selector="Button.NavButton:pointerover materialIcons|MaterialIcon">
    <Setter Property="Foreground" Value="{DynamicResource DittoAccent}"/>
</Style>

<Style Selector="Button.NavButton.Selected">
    <Setter Property="Background" Value="{DynamicResource DittoAccent}"/>
</Style>

<Style Selector="Button.NavButton.Selected materialIcons|MaterialIcon">
    <Setter Property="Foreground" Value="{DynamicResource DittoJetBlack}"/>
</Style>
```

Note: In Avalonia, targeting child elements via style selectors (`ParentClass ChildType`) requires care. If the above child selectors don't work, the alternative is to bind the icon's `Foreground` to the button's `Tag` or use a `TemplateBinding`. Check Avalonia docs for the correct selector syntax for child element styling in item templates.

An alternative approach that always works in Avalonia:
- Wrap the icon in a `Border` in the `ControlTemplate`
- Bind `Border.Background` to button's `Background` (already done via `TemplateBinding`)
- For icon color on hover, use a `ToggleButton` or pass a `Foreground` binding via the template

The simplest reliable approach:
```xml
<!-- In the ControlTemplate, bind icon foreground explicitly -->
<avalonia:MaterialIcon Kind="{TemplateBinding Tag}"
    Foreground="{TemplateBinding Foreground}"
    Width="24" Height="24"/>
```

Then in styles:
```xml
<Style Selector="Button.NavButton">
    <Setter Property="Foreground" Value="{DynamicResource DittoCardText}"/>
    ...
</Style>
<Style Selector="Button.NavButton:pointerover">
    <Setter Property="Background" Value="Transparent"/>
    <Setter Property="Foreground" Value="{DynamicResource DittoAccent}"/>
</Style>
<Style Selector="Button.NavButton.Selected">
    <Setter Property="Background" Value="{DynamicResource DittoAccent}"/>
    <Setter Property="Foreground" Value="{DynamicResource DittoJetBlack}"/>
</Style>
```

This requires moving the `MaterialIcon` into the `ControlTemplate` and binding via `Tag` for the icon kind — or restructuring the template to support foreground propagation.

### Manual Checkpoint

1. Open the app to the Query view
2. Hover over a navigation icon → icon turns Ditto Yellow, background stays transparent
3. Selected icon → yellow background with black icon
4. Deselect (navigate away) → returns to normal state
5. Verify looks correct in both light and dark mode

---

## Step 7: Tab Underline Styling (Ditto Yellow)

### Problem

Both the Query Editor tabs (`QueryView.axaml`) and Query Results tabs (`QueryResultsView.axaml`) use a plain background color change for the selected state. The design spec calls for a **Ditto Yellow bottom underline** on the selected tab (matching SwiftUI).

### Fix

In Avalonia with SukiUI, the `TabItem` selected indicator is typically the `PART_SelectedPipe` element. SukiUI's `TabControl` may have its own template.

First check if SukiUI `TabControl` supports a `HighlightColor` or similar property. If not, use a custom style:

**File: `dotnet/src/EdgeStudio/Views/StudioView/Details/QueryView.axaml`**

Update the selected tab style to add a bottom border:
```xml
<Style Selector="TabItem:selected">
    <Setter Property="Background" Value="{DynamicResource SukiBackground}"/>
    <Setter Property="Foreground" Value="{DynamicResource DittoCardText}"/>
    <Setter Property="BorderBrush" Value="{DynamicResource DittoAccent}"/>
    <Setter Property="BorderThickness" Value="0,0,0,2"/>
</Style>
```

If SukiUI's `TabItem` template ignores `BorderThickness`, target the `PART_SelectedPipe` element directly:
```xml
<Style Selector="TabItem:selected /template/ Border#PART_SelectedPipe">
    <Setter Property="Background" Value="{DynamicResource DittoAccent}"/>
    <Setter Property="Height" Value="2"/>
</Style>
```

Apply the same style to `QueryResultsView.axaml`.

**Check SukiUI source** to determine the correct template part name for the tab underline. Common names: `PART_SelectedPipe`, `PART_Indicator`, `PART_SelectionIndicator`.

### Manual Checkpoint

1. Query Editor tabs — selected tab has visible Ditto Yellow underline at bottom
2. Query Results tabs (JSON/Table) — same underline
3. Underline visible in both light and dark mode
4. Non-selected tabs have no underline

---

## Step 8: Automated Test Coverage and Build Validation

### New Test Files

| Test File | What It Tests |
|-----------|--------------|
| `JsonSyntaxHighlightingTests.cs` | Page navigation doesn't lose syntax highlighting (TextMate installation field stored) |
| `HistoryDeduplicationTests.cs` | Same query moves to top, no duplicates |
| `DoubleClickTests.cs` | LoadAndExecuteQueryCommand sends correct message; DocumentDoubleClickedMessage triggers inspector open |
| `QueryDocumentTitleTests.cs` | Tab name updates when query text changes, truncates at 30 chars |

### Build Validation

After all steps, run:
```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
dotnet test EdgeStudioTests/EdgeStudioTests.csproj --no-build
```

Both must pass with zero errors and zero new warnings.

---

## Files to Modify (13 total)

| File | Step | Change |
|------|------|--------|
| `Inspector/JsonDocumentCard.axaml.cs` | 1 | Store `TextMateInstallation` as field |
| `Inspector/DocumentViewerView.axaml.cs` | 1 | Store `TextMateInstallation` as field |
| `Details/QueryEditorView.axaml` | 2 | Add padding to editor + gap after execute bar |
| `ViewModels/QueryDocumentViewModel.cs` | 2, 5 | Update `_baseTitle` from query text; forward double-click message |
| `Shared/Messages/QueryMessages.cs` | 4, 5 | Add `LoadAndExecuteQueryRequestedMessage`, `DocumentDoubleClickedMessage`, `NavigateInspectorToJsonViewerMessage` |
| `ViewModels/HistoryToolViewModel.cs` | 3, 4 | Deduplication; `LoadAndExecuteQueryCommand` |
| `ViewModels/FavoritesToolViewModel.cs` | 4 | `LoadAndExecuteQueryCommand` |
| `ViewModels/QueryViewModel.cs` | 4 | Listen for `LoadAndExecuteQueryRequestedMessage` |
| `ViewModels/EdgeStudioViewModel.cs` | 5 | Listen for `DocumentDoubleClickedMessage`; open inspector + navigate tab |
| `Inspector/JsonResultsView.axaml` | 5 | Add `DoubleTapped` handler |
| `Inspector/JsonResultsView.axaml.cs` | 5 | `OnCardDoubleTapped` code-behind |
| `Navigation/NavigationBar.axaml` | 6 | Ditto Yellow selected/hover icon styles |
| `Details/QueryView.axaml` | 7 | Ditto Yellow underline on selected tab |
| `Details/QueryResultsView.axaml` | 7 | Ditto Yellow underline on selected tab |

---

## Summary Checklist

- [ ] Step 1: JSON syntax highlighting persists across page navigation
- [ ] Step 2: Editor has left padding + 8px gap; tab name = query text truncated
- [ ] Step 3: History deduplicates — same query moves to top
- [ ] Step 4: Double-click history/favorites loads AND executes
- [ ] Step 5: Double-click document opens inspector + navigates to JSON Viewer
- [ ] Step 6: Selected nav icon = Ditto Yellow bg / black icon; hover = Ditto Yellow icon
- [ ] Step 7: Selected tab has Ditto Yellow bottom underline (both editor and results tabs)
- [ ] Step 8: All tests pass, build clean
