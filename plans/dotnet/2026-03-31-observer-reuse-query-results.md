# Observer Detail: Reuse Query Results Components

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Observer detail bottom pane's custom Raw/Table/Filter UI with the existing Query Results components (`JsonResultsView`, `TableResultsView`, `TabControl`, `ComboBox`) so the Observer detail matches the Query Results UI exactly.

**Architecture:** Add `JsonResultsViewModel` and `TableResultsViewModel` instances to `ObserversViewModel`. When the selected event or filter changes, feed the filtered data into both ViewModels via `SetResults()`. Replace the bottom pane XAML with a `TabControl` (JSON/Table tabs using the same styling as `QueryResultsView.axaml`) and replace filter RadioButtons with a `ComboBox` dropdown. Remove all custom pagination, raw text, and placeholder code from the bottom pane since `JsonResultsView` and `TableResultsView` handle their own pagination and rendering.

**Tech Stack:** C# / Avalonia UI / SukiUI / AvaloniaEdit + TextMate (for JSON syntax highlighting) / CommunityToolkit.Mvvm / xUnit + Moq + FluentAssertions

---

## Current Problems

| # | Problem | Fix |
|---|---------|-----|
| 1 | Raw/Table switching uses RadioButtons instead of tabs | Replace with `TabControl` matching `QueryResultsView.axaml` styling |
| 2 | JSON viewer is plain monospace text — no syntax highlighting | Replace with `JsonResultsView` (uses `JsonDocumentCard` with AvaloniaEdit + TextMate DarkPlus theme) |
| 3 | Table view shows "Coming Soon" placeholder | Replace with `TableResultsView` (DataGrid with auto-generated columns from JSON) |
| 4 | Filter is RadioButtons instead of dropdown | Replace with `ComboBox` (matches SwiftUI's `.pickerStyle(.menu)`) |
| 5 | Custom pagination in bottom pane | Remove — `JsonResultsView` and `TableResultsView` have built-in pagination |

## File Map

**Files to Modify:**
- `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs` — Add `JsonResultsViewModel` and `TableResultsViewModel` properties, feed data on event/filter change, remove custom detail pagination
- `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml` — Replace bottom pane with TabControl + JsonResultsView/TableResultsView + ComboBox filter
- `dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs` — Update/add tests for new ViewModel behavior

**Files NOT changing:**
- `JsonResultsView.axaml` / `JsonResultsViewModel.cs` — reused as-is
- `TableResultsView.axaml` / `TableResultsViewModel.cs` — reused as-is
- `JsonDocumentCard.axaml` — reused as-is (provides syntax highlighting)
- `QueryResultsView.axaml` — reference only (we copy its TabControl styling)
- Top pane (events DataGrid + pagination) — unchanged

---

### Task 1: Add JsonResultsViewModel and TableResultsViewModel to ObserversViewModel

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs`
- Test: `dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs`

- [ ] **Step 1: Write failing test — JsonResults and TableResults are populated when SelectedEvent changes**

Add to `ObserversViewModelTests.cs`:

```csharp
[Fact]
public void SelectedEvent_PopulatesJsonResultsAndTableResults()
{
    // Arrange
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);
    var testEvent = new ObserverEvent
    {
        ObserverId = "obs1",
        Data = new List<string> { "{\"_id\":\"1\",\"name\":\"test\"}", "{\"_id\":\"2\",\"name\":\"test2\"}" },
        InsertIndexes = new List<int> { 0, 1 },
        EventTime = DateTime.Now
    };

    // Act
    vm.SelectedEvent = testEvent;

    // Assert — default filter is "items", so all data should be in results
    vm.JsonResults.Should().NotBeNull();
    vm.TableResults.Should().NotBeNull();
    vm.JsonResults.TotalCount.Should().Be(2);
    vm.JsonResults.PagedDocuments.Should().HaveCount(2);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "SelectedEvent_PopulatesJsonResultsAndTableResults" -v n`
Expected: FAIL — `JsonResults` property doesn't exist yet.

- [ ] **Step 3: Add JsonResultsViewModel and TableResultsViewModel to ObserversViewModel**

In `ObserversViewModel.cs`:

1. Add the two ViewModel properties (initialized in constructor):

```csharp
/// <summary>
/// JSON results view model — reuses the same component as Query Results.
/// </summary>
public JsonResultsViewModel JsonResults { get; }

/// <summary>
/// Table results view model — reuses the same component as Query Results.
/// </summary>
public TableResultsViewModel TableResults { get; }
```

2. Initialize them in the constructor:

```csharp
public ObserversViewModel(
    IObserverRepository observerRepository,
    IToastService? toastService = null)
    : base(toastService)
{
    _observerRepository = observerRepository;
    JsonResults = new JsonResultsViewModel();
    TableResults = new TableResultsViewModel();
}
```

3. Update `RefreshFilteredEventData()` to feed data into both ViewModels:

```csharp
private void RefreshFilteredEventData()
{
    _allFilteredData = SelectedEvent == null
        ? new List<string>()
        : EventFilterMode switch
        {
            "inserted" => SelectedEvent.GetInsertedData(),
            "updated" => SelectedEvent.GetUpdatedData(),
            _ => SelectedEvent.Data.ToList()
        };

    // Feed data into reusable result viewers
    JsonResults.SetResults(_allFilteredData);
    TableResults.SetResults(_allFilteredData);

    // Keep legacy collections for backwards compat with existing tests
    DetailCurrentPage = 1;
    RefreshPagedFilteredData();

    FilteredEventData.Clear();
    foreach (var item in _allFilteredData)
        FilteredEventData.Add(item);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "SelectedEvent_PopulatesJsonResultsAndTableResults" -v n`
Expected: PASS

- [ ] **Step 5: Write test — filter change updates result viewers**

```csharp
[Fact]
public void EventFilterChange_UpdatesJsonResultsWithFilteredData()
{
    // Arrange
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);
    var testEvent = new ObserverEvent
    {
        ObserverId = "obs1",
        Data = new List<string> { "{\"_id\":\"1\"}", "{\"_id\":\"2\"}", "{\"_id\":\"3\"}" },
        InsertIndexes = new List<int> { 0, 2 },
        UpdatedIndexes = new List<int> { 1 },
        EventTime = DateTime.Now
    };
    vm.SelectedEvent = testEvent;
    vm.JsonResults.TotalCount.Should().Be(3); // all items

    // Act
    vm.EventFilterMode = "inserted";

    // Assert
    vm.JsonResults.TotalCount.Should().Be(2); // only inserted items
}
```

- [ ] **Step 6: Run test and build**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj -v n && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`

- [ ] **Step 7: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs
git commit -m "feat(dotnet): add JsonResultsViewModel and TableResultsViewModel to ObserversViewModel"
```

---

### Task 2: Replace bottom pane XAML with TabControl + ComboBox filter

**Files:**
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml`

This task replaces everything in the bottom pane (Grid.Row="2") of ObserverDetailView.axaml.

- [ ] **Step 1: Replace the entire bottom pane content**

In `ObserverDetailView.axaml`, add the `inspector` namespace to the UserControl root element:

```xml
xmlns:inspector="using:EdgeStudio.Views.StudioView.Inspector"
```

Then replace the entire bottom pane Grid (the `<Grid Grid.Row="2" RowDefinitions="Auto,*,Auto">` and everything inside it) with:

```xml
<!-- Bottom Pane: Event Detail (50%) -->
<Grid Grid.Row="2">

    <!-- No Event Selected -->
    <Border IsVisible="{Binding !HasSelectedEvent}"
            Background="Transparent">
        <StackPanel HorizontalAlignment="Center"
                   VerticalAlignment="Center"
                   Spacing="8">
            <TextBlock Text="visibility_off"
                      FontFamily="avares://EdgeStudio/Assets/Fonts/MaterialSymbolsOutlined.ttf#Material Symbols Outlined"
                      FontSize="48"
                      Opacity="0.3"
                      HorizontalAlignment="Center"/>
            <TextBlock Text="No Event Selected"
                      FontSize="14"
                      FontWeight="SemiBold"
                      HorizontalAlignment="Center"/>
            <TextBlock Text="Select an event from the list above to view its details."
                      FontSize="12"
                      Opacity="0.7"
                      HorizontalAlignment="Center"/>
        </StackPanel>
    </Border>

    <!-- Event Detail with Tabs and Filter -->
    <Grid RowDefinitions="Auto,*"
          IsVisible="{Binding HasSelectedEvent}">

        <!-- Header: Filter ComboBox -->
        <Border Grid.Row="0"
                Padding="12,6"
                BorderThickness="0,0,0,1">
            <Grid ColumnDefinitions="*,Auto">
                <TextBlock Grid.Column="0"
                          Text="Event Data"
                          FontSize="11"
                          FontWeight="Normal"
                          VerticalAlignment="Center"/>
                <StackPanel Grid.Column="1"
                           Orientation="Horizontal"
                           Spacing="8"
                           VerticalAlignment="Center">
                    <TextBlock Text="Filter:"
                              FontSize="11"
                              Opacity="0.7"
                              VerticalAlignment="Center"/>
                    <ComboBox SelectedItem="{Binding EventFilterMode}"
                             FontSize="11"
                             MinWidth="110"
                             Padding="8,4">
                        <ComboBoxItem Content="Items" Tag="items"
                                     IsSelected="{Binding IsFilterItems, Mode=OneWay}"/>
                        <ComboBoxItem Content="Inserted" Tag="inserted"
                                     IsSelected="{Binding IsFilterInserted, Mode=OneWay}"/>
                        <ComboBoxItem Content="Updated" Tag="updated"
                                     IsSelected="{Binding IsFilterUpdated, Mode=OneWay}"/>
                    </ComboBox>
                </StackPanel>
            </Grid>
        </Border>

        <!-- TabControl with JSON and Table tabs (same styling as QueryResultsView) -->
        <TabControl Grid.Row="1"
                    Background="{DynamicResource SukiBackground}">
            <TabControl.Styles>
                <Style Selector="TabItem">
                    <Setter Property="FontSize" Value="13"/>
                    <Setter Property="Padding" Value="14,6"/>
                    <Setter Property="Margin" Value="0,0,2,0"/>
                    <Setter Property="Background" Value="{DynamicResource DittoCardSurface}"/>
                    <Setter Property="Foreground" Value="{DynamicResource DittoCardText}"/>
                    <Setter Property="BorderThickness" Value="0"/>
                </Style>
                <Style Selector="TabItem:selected">
                    <Setter Property="Background" Value="{DynamicResource SukiBackground}"/>
                    <Setter Property="Foreground" Value="{DynamicResource DittoCardText}"/>
                    <Setter Property="BorderBrush" Value="{DynamicResource DittoAccent}"/>
                    <Setter Property="BorderThickness" Value="0,0,0,2"/>
                </Style>
            </TabControl.Styles>

            <TabItem Header="JSON">
                <inspector:JsonResultsView DataContext="{Binding JsonResults}"/>
            </TabItem>
            <TabItem Header="Table">
                <inspector:TableResultsView DataContext="{Binding TableResults}"/>
            </TabItem>
        </TabControl>
    </Grid>
</Grid>
```

**Key changes:**
- RadioButtons for Raw/Table → `TabControl` with `TabItem Header="JSON"` and `TabItem Header="Table"` (identical styling to `QueryResultsView.axaml`)
- Plain text ItemsControl → `JsonResultsView` (provides syntax-highlighted JSON cards via `JsonDocumentCard` with AvaloniaEdit + TextMate)
- "Coming Soon" placeholder → `TableResultsView` (provides DataGrid with auto-generated columns)
- Filter RadioButtons → `ComboBox` dropdown (matches SwiftUI's `.pickerStyle(.menu)`)
- Custom detail pagination removed — both `JsonResultsView` and `TableResultsView` have built-in pagination

- [ ] **Step 2: Build to verify XAML compiles**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`

If the `ComboBox` SelectedItem binding to a string doesn't work directly with `ComboBoxItem`, an alternative approach is to handle `SelectionChanged` in code-behind. See Step 3 if needed.

- [ ] **Step 3: Add code-behind for ComboBox SelectionChanged (if needed)**

If the `ComboBox` SelectedItem binding to the string `EventFilterMode` doesn't work with `ComboBoxItem` elements, add a `SelectionChanged` handler in `ObserverDetailView.axaml.cs`.

First check if there's an existing code-behind file. If not, create one. Add:

```csharp
private void FilterComboBox_SelectionChanged(object? sender, SelectionChangedEventArgs e)
{
    if (sender is ComboBox comboBox &&
        comboBox.SelectedItem is ComboBoxItem selectedItem &&
        DataContext is ObserversViewModel vm)
    {
        var tag = selectedItem.Tag?.ToString();
        if (!string.IsNullOrEmpty(tag))
        {
            vm.SetEventFilterCommand.Execute(tag);
        }
    }
}
```

And in the XAML, change the ComboBox to:
```xml
<ComboBox x:Name="FilterComboBox"
         SelectionChanged="FilterComboBox_SelectionChanged"
         FontSize="11"
         MinWidth="110"
         Padding="8,4">
    <ComboBoxItem Content="Items" Tag="items" IsSelected="{Binding IsFilterItems, Mode=OneWay}"/>
    <ComboBoxItem Content="Inserted" Tag="inserted" IsSelected="{Binding IsFilterInserted, Mode=OneWay}"/>
    <ComboBoxItem Content="Updated" Tag="updated" IsSelected="{Binding IsFilterUpdated, Mode=OneWay}"/>
</ComboBox>
```

- [ ] **Step 4: Build and run all tests**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj -v n`

- [ ] **Step 5: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml.cs
git commit -m "feat(dotnet): replace observer bottom pane with TabControl + JsonResultsView + TableResultsView + ComboBox filter"
```

---

### Task 3: Clean up removed ViewModel properties

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs`
- Modify: `dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs`

Now that the bottom pane uses `JsonResultsView`/`TableResultsView` (which handle their own pagination), we can remove the custom detail pagination and view mode properties that are no longer needed.

- [ ] **Step 1: Remove unused properties from ObserversViewModel**

Remove these properties and methods that are now handled by `JsonResultsViewModel`/`TableResultsViewModel`:

```csharp
// REMOVE these — no longer used by XAML:
private string _detailViewMode = "raw";
public bool IsRawMode => ...
public bool IsTableMode => ...
partial void OnDetailViewModeChanged(...)
[RelayCommand] private void SetDetailViewMode(...)

// REMOVE these — pagination now handled by JsonResultsView/TableResultsView:
private int _detailCurrentPage = 1;
private int _detailPageSize = 10;
public int DetailPageCount => ...
public ObservableCollection<string> PagedFilteredEventData { get; } = new();
private List<string> _allFilteredData = new();
[RelayCommand] private void DetailNextPage()
[RelayCommand] private void DetailPreviousPage()
private void RefreshPagedFilteredData()
```

Keep `_allFilteredData` as a local variable in `RefreshFilteredEventData()` since it's still needed to feed data.

Update `RefreshFilteredEventData()` to be simpler:

```csharp
private void RefreshFilteredEventData()
{
    var filteredData = SelectedEvent == null
        ? new List<string>()
        : EventFilterMode switch
        {
            "inserted" => SelectedEvent.GetInsertedData(),
            "updated" => SelectedEvent.GetUpdatedData(),
            _ => SelectedEvent.Data.ToList()
        };

    // Feed data into reusable result viewers
    JsonResults.SetResults(filteredData);
    TableResults.SetResults(filteredData);

    // Keep legacy FilteredEventData for existing tests
    FilteredEventData.Clear();
    foreach (var item in filteredData)
        FilteredEventData.Add(item);
}
```

- [ ] **Step 2: Update tests — remove references to deleted properties**

In `ObserversViewModelTests.cs`, remove or update any tests that reference:
- `PagedFilteredEventData`
- `DetailPageCount`
- `DetailCurrentPage`
- `DetailNextPageCommand`
- `DetailPreviousPageCommand`
- `IsRawMode` / `IsTableMode`
- `SetDetailViewModeCommand`

Tests for `FilteredEventData` should still work since we kept that property.

Replace the detail pagination tests with a test verifying the results viewers get populated:

```csharp
[Fact]
public void SelectedEvent_FeedsDataToJsonAndTableResults()
{
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);
    var testEvent = new ObserverEvent
    {
        ObserverId = "obs1",
        Data = new List<string> { "{\"_id\":\"1\"}", "{\"_id\":\"2\"}", "{\"_id\":\"3\"}", "{\"_id\":\"4\"}", "{\"_id\":\"5\"}" },
        EventTime = DateTime.Now
    };

    vm.SelectedEvent = testEvent;

    vm.JsonResults.TotalCount.Should().Be(5);
    vm.JsonResults.PagedDocuments.Should().HaveCount(5);
    // TableResults.TableData gets populated by SetResults
    vm.TableResults.TableData.Should().NotBeEmpty();
}
```

- [ ] **Step 3: Build and run all tests**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj -v n`

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs
git commit -m "refactor(dotnet): remove custom detail pagination and view mode, use JsonResultsView/TableResultsView"
```

---

### Task 4: Final integration — build and run all tests

**Files:**
- All modified files from Tasks 1-3

- [ ] **Step 1: Full solution build**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio.sln --verbosity minimal`

- [ ] **Step 2: Run all tests**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj -v n`
Expected: All tests pass

- [ ] **Step 3: Fix any failures and commit**

If any tests fail, diagnose and fix. Build again after fixes.

```bash
git add -u dotnet/
git commit -m "fix(dotnet): final observer detail integration fixes"
```
