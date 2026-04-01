# Fix Observer Detail View Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the dotnet Observer detail view so it matches the SwiftUI version's functionality — visible column headers, working event selection with data display, Raw/Table view tabs, filter mode indicators, card button cleanup, and pagination.

**Architecture:** Fix existing ObserversViewModel property change handling, rewrite ObserverDetailView.axaml with proper DataGrid column sizing and a functional bottom pane (Raw JSON + Table tabs with filter mode picker), remove the unnecessary "View" button from sidebar cards, and add pagination to both event list and event detail.

**Tech Stack:** C# / Avalonia UI / SukiUI / CommunityToolkit.Mvvm / xUnit + Moq + FluentAssertions

---

## Issues Identified (from screenshots + code comparison)

| # | Issue | Root Cause |
|---|-------|-----------|
| 1 | DataGrid column headers truncated ("C...", "Ins...", "Up...", "De...", "M...") | Fixed pixel widths too narrow; no `MinWidth` or `*` sizing |
| 2 | Selecting an event row does nothing — bottom pane stays "No Event Selected" | `SelectedEvent` property is set by DataGrid binding but `RefreshFilteredEventData()` is never called because there's no `partial void OnSelectedEventChanged()` override |
| 3 | No Raw/Table view tabs in bottom pane | Only a simple `ItemsControl` with text — SwiftUI has Raw JSON + Table view picker |
| 4 | Filter buttons (All Items/Inserted/Updated) don't show active state | No visual distinction for the currently active filter mode |
| 5 | Useless "View" eye button on sidebar card | SwiftUI has no separate "view" button — clicking the card name itself selects the observer |
| 6 | No pagination for event list or event detail data | SwiftUI has pagination in both panes; dotnet has neither |
| 7 | Clicking observer card doesn't auto-select it for the detail view | Need card click to select observer AND show events in detail |

## File Map

**Files to Modify:**
- `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs` — Add `OnSelectedEventChanged`, pagination properties, view mode toggle
- `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml` — Rewrite DataGrid columns, bottom pane with tabs, pagination, filter indicator
- `dotnet/src/EdgeStudio/Views/StudioView/Sidebar/ObserverListingView.axaml` — Remove "View" button, make card name clickable to select
- `dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs` — Add tests for new behavior

**Files NOT changing:**
- `ObserverEvent.cs`, `DittoDatabaseObserver.cs`, `IObserverRepository.cs`, `SqliteObserverRepository.cs` — models and repository are fine
- `ObserverFormWindow.axaml` — add/edit dialog works correctly

---

### Task 1: Fix SelectedEvent property change to trigger data refresh

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs`
- Test: `dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs`

**Problem:** The DataGrid binds `SelectedItem="{Binding SelectedEvent}"` which sets the `SelectedEvent` property directly via the generated setter. But `RefreshFilteredEventData()` is only called inside the `SelectEvent` RelayCommand — which the DataGrid never invokes. The `[ObservableProperty]` generates a `partial void OnSelectedEventChanged()` hook that is never implemented.

**SwiftUI equivalent:** In `DetailViews.swift`, `onChange(of: viewModel.selectedEventId)` calls `refreshObserveDetailData()`.

- [ ] **Step 1: Write failing test — SelectedEvent change triggers FilteredEventData update**

```csharp
[Fact]
public void SelectedEvent_WhenChanged_RefreshesFilteredEventData()
{
    // Arrange
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);
    var testEvent = new ObserverEvent
    {
        ObserverId = "obs1",
        Data = new List<string> { "{\"_id\":\"1\",\"name\":\"test\"}", "{\"_id\":\"2\",\"name\":\"test2\"}" },
        InsertIndexes = new List<int> { 0 },
        UpdatedIndexes = new List<int> { 1 },
        EventTime = DateTime.Now
    };

    // Act
    vm.SelectedEvent = testEvent;

    // Assert
    vm.FilteredEventData.Should().HaveCount(2); // default "items" mode shows all
    vm.HasSelectedEvent.Should().BeTrue();
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dotnet test src/EdgeStudioTests/EdgeStudioTests.csproj --filter "SelectedEvent_WhenChanged_RefreshesFilteredEventData" -v n`
Expected: FAIL — FilteredEventData is empty because RefreshFilteredEventData() isn't called.

- [ ] **Step 3: Add OnSelectedEventChanged partial method**

In `ObserversViewModel.cs`, add after the `OnEventFilterModeChanged` method:

```csharp
partial void OnSelectedEventChanged(ObserverEvent? value)
{
    OnPropertyChanged(nameof(HasSelectedEvent));
    RefreshFilteredEventData();
}
```

Also remove the redundant `OnPropertyChanged(nameof(HasSelectedEvent))` calls from `SelectEvent` and `LoadEventsForSelectedObserver` since the partial method now handles it.

- [ ] **Step 4: Run test to verify it passes**

Run: `dotnet test src/EdgeStudioTests/EdgeStudioTests.csproj --filter "SelectedEvent_WhenChanged_RefreshesFilteredEventData" -v n`
Expected: PASS

- [ ] **Step 5: Write test — filter modes work via SelectedEvent change**

```csharp
[Fact]
public void SelectedEvent_WithInsertedFilter_ShowsOnlyInsertedData()
{
    // Arrange
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);
    vm.EventFilterMode = "inserted";
    var testEvent = new ObserverEvent
    {
        ObserverId = "obs1",
        Data = new List<string> { "{\"_id\":\"1\"}", "{\"_id\":\"2\"}", "{\"_id\":\"3\"}" },
        InsertIndexes = new List<int> { 0, 2 },
        UpdatedIndexes = new List<int> { 1 },
        EventTime = DateTime.Now
    };

    // Act
    vm.SelectedEvent = testEvent;

    // Assert
    vm.FilteredEventData.Should().HaveCount(2);
    vm.FilteredEventData[0].Should().Be("{\"_id\":\"1\"}");
    vm.FilteredEventData[1].Should().Be("{\"_id\":\"3\"}");
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `dotnet test src/EdgeStudioTests/EdgeStudioTests.csproj --filter "SelectedEvent_WithInsertedFilter_ShowsOnlyInsertedData" -v n`
Expected: PASS (RefreshFilteredEventData already handles this logic)

- [ ] **Step 7: Build to verify no regressions**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`

- [ ] **Step 8: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs
git commit -m "fix(dotnet): trigger FilteredEventData refresh when SelectedEvent changes"
```

---

### Task 2: Fix DataGrid column headers — full names visible

**Files:**
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml`

**Problem:** Column headers show "C...", "Ins...", etc. because fixed pixel widths (70, 80px) are too narrow for the header text at the default font size.

**SwiftUI equivalent:** `ObserverEventsTableView.swift` has columns: Time, Count, Inserted, Updated, Deleted, Moves — all fully visible with flexible sizing.

- [ ] **Step 1: Update DataGrid column definitions with star sizing**

In `ObserverDetailView.axaml`, replace the DataGrid.Columns section:

```xml
<DataGrid.Columns>
    <DataGridTextColumn Header="Time"
                       Binding="{Binding FormattedEventTime}"
                       Width="150"
                       MinWidth="100"/>
    <DataGridTextColumn Header="Count"
                       Binding="{Binding Data.Count}"
                       Width="*"
                       MinWidth="60"/>
    <DataGridTextColumn Header="Inserted"
                       Binding="{Binding InsertIndexes.Count}"
                       Width="*"
                       MinWidth="70"/>
    <DataGridTextColumn Header="Updated"
                       Binding="{Binding UpdatedIndexes.Count}"
                       Width="*"
                       MinWidth="70"/>
    <DataGridTextColumn Header="Deleted"
                       Binding="{Binding DeletedIndexes.Count}"
                       Width="*"
                       MinWidth="70"/>
    <DataGridTextColumn Header="Moves"
                       Binding="{Binding MovedIndexes.Count}"
                       Width="*"
                       MinWidth="60"/>
</DataGrid.Columns>
```

Key changes: `Width="*"` for proportional sizing with `MinWidth` to prevent truncation. Time keeps fixed width since timestamps need consistent space.

- [ ] **Step 2: Build to verify XAML compiles**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml
git commit -m "fix(dotnet): use star sizing for observer DataGrid columns so headers are fully visible"
```

---

### Task 3: Add Raw/Table view mode toggle to bottom pane

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs`
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml`
- Test: `dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs`

**Problem:** The bottom pane only has a simple `ItemsControl` with monospace text. SwiftUI has a picker to toggle between "Raw" (JSON text) and "Table" (data grid with columns parsed from JSON keys) views.

**SwiftUI equivalent:** `DetailViews.swift` lines 809-870 — `Picker("", selection: $selectedObserveDetailMenuItem)` with `ResultJsonViewer` or `ResultTableViewer`.

- [ ] **Step 1: Add DetailViewMode property to ViewModel**

In `ObserversViewModel.cs`, add:

```csharp
[ObservableProperty]
private string _detailViewMode = "raw"; // "raw" or "table"

[RelayCommand]
private void SetDetailViewMode(string mode)
{
    DetailViewMode = mode;
}
```

- [ ] **Step 2: Write test for DetailViewMode**

```csharp
[Fact]
public void SetDetailViewMode_ChangesMode()
{
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);

    vm.SetDetailViewModeCommand.Execute("table");

    vm.DetailViewMode.Should().Be("table");
}
```

- [ ] **Step 3: Run test**

Run: `dotnet test src/EdgeStudioTests/EdgeStudioTests.csproj --filter "SetDetailViewMode_ChangesMode" -v n`

- [ ] **Step 4: Update bottom pane XAML with Raw/Table toggle**

Replace the bottom pane Event Detail Header section in `ObserverDetailView.axaml`:

```xml
<!-- Event Detail Header with View Mode and Filter -->
<Border Grid.Row="0"
        Padding="12,6"
        BorderThickness="0,0,0,1"
        IsVisible="{Binding HasSelectedEvent}">
    <Grid ColumnDefinitions="Auto,*,Auto">
        <!-- View Mode Toggle (Raw / Table) -->
        <StackPanel Grid.Column="0"
                   Orientation="Horizontal"
                   Spacing="2">
            <RadioButton Content="Raw"
                        GroupName="DetailViewMode"
                        IsChecked="{Binding DetailViewMode, Converter={x:Static StringConverters.IsNotNullOrEmpty}, Mode=OneWay}"
                        Command="{Binding SetDetailViewModeCommand}"
                        CommandParameter="raw"
                        Padding="8,4"
                        FontSize="11"/>
            <RadioButton Content="Table"
                        GroupName="DetailViewMode"
                        Command="{Binding SetDetailViewModeCommand}"
                        CommandParameter="table"
                        Padding="8,4"
                        FontSize="11"/>
        </StackPanel>

        <!-- Filter Label -->
        <TextBlock Grid.Column="1"
                  Text="Filter:"
                  FontSize="11"
                  Opacity="0.7"
                  VerticalAlignment="Center"
                  HorizontalAlignment="Right"
                  Margin="0,0,8,0"/>

        <!-- Filter Buttons -->
        <StackPanel Grid.Column="2"
                   Orientation="Horizontal"
                   Spacing="2">
            <RadioButton Content="Items"
                        GroupName="EventFilter"
                        IsChecked="{Binding EventFilterMode, Converter={x:Static StringConverters.IsNotNullOrEmpty}, Mode=OneWay}"
                        Command="{Binding SetEventFilterCommand}"
                        CommandParameter="items"
                        Padding="8,4"
                        FontSize="11"/>
            <RadioButton Content="Inserted"
                        GroupName="EventFilter"
                        Command="{Binding SetEventFilterCommand}"
                        CommandParameter="inserted"
                        Padding="8,4"
                        FontSize="11"/>
            <RadioButton Content="Updated"
                        GroupName="EventFilter"
                        Command="{Binding SetEventFilterCommand}"
                        CommandParameter="updated"
                        Padding="8,4"
                        FontSize="11"/>
        </StackPanel>
    </Grid>
</Border>

<!-- Raw View -->
<ScrollViewer Grid.Row="1"
             VerticalScrollBarVisibility="Auto"
             IsVisible="{Binding HasSelectedEvent}">
    <!-- Show Raw JSON when DetailViewMode is "raw" -->
    <Panel IsVisible="{Binding DetailViewMode, Converter={StaticResource EqualConverter}, ConverterParameter=raw}">
        <ItemsControl ItemsSource="{Binding FilteredEventData}"
                     Margin="4">
            <ItemsControl.ItemTemplate>
                <DataTemplate>
                    <Border Padding="8,4"
                            Margin="0,1"
                            CornerRadius="4">
                        <TextBlock Text="{Binding}"
                                  FontSize="11"
                                  FontFamily="Consolas"
                                  TextWrapping="Wrap"/>
                    </Border>
                </DataTemplate>
            </ItemsControl.ItemTemplate>
        </ItemsControl>
    </Panel>
</ScrollViewer>
```

**Note:** The RadioButton approach needs careful handling in Avalonia. The exact implementation of view mode toggling (Raw vs Table) and filter active state may require using a value converter or binding to boolean computed properties. The implementer should check Avalonia documentation for RadioButton + Command patterns and adjust accordingly. An alternative approach is to use boolean properties like `IsRawMode` and `IsTableMode` that toggle with the commands, and bind `IsChecked` directly to those booleans.

**Alternative simpler approach — use boolean properties instead of converters:**

Add to ViewModel:
```csharp
public bool IsRawMode => DetailViewMode == "raw";
public bool IsTableMode => DetailViewMode == "table";
public bool IsFilterItems => EventFilterMode == "items";
public bool IsFilterInserted => EventFilterMode == "inserted";
public bool IsFilterUpdated => EventFilterMode == "updated";

partial void OnDetailViewModeChanged(string value)
{
    OnPropertyChanged(nameof(IsRawMode));
    OnPropertyChanged(nameof(IsTableMode));
}

// Update existing OnEventFilterModeChanged:
partial void OnEventFilterModeChanged(string value)
{
    RefreshFilteredEventData();
    OnPropertyChanged(nameof(IsFilterItems));
    OnPropertyChanged(nameof(IsFilterInserted));
    OnPropertyChanged(nameof(IsFilterUpdated));
}
```

Then in XAML bind `IsChecked="{Binding IsRawMode, Mode=OneWay}"` etc. This avoids converter issues.

- [ ] **Step 5: Add Table view panel to XAML**

Below the Raw view ScrollViewer, add a Table view that parses JSON keys into columns:

```xml
<!-- Table View (when DetailViewMode is "table") -->
<DataGrid Grid.Row="1"
         ItemsSource="{Binding FilteredEventDataTable}"
         IsVisible="{Binding IsTableMode}"
         IsReadOnly="True"
         CanUserResizeColumns="True"
         AutoGenerateColumns="True"
         HeadersVisibility="Column"
         GridLinesVisibility="Horizontal"/>
```

**Note:** Auto-generating columns from JSON data in Avalonia DataGrid requires either:
- A `DataTable` as the ItemsSource (Avalonia DataGrid supports this)
- Or manually building columns from the first JSON item's keys

Add to ViewModel a property that converts `FilteredEventData` (JSON strings) into a flat table structure. A simple approach: parse JSON into `List<Dictionary<string, object>>` and bind to DataGrid, or use a `DataTable`. The implementer should research Avalonia DataGrid auto-generation support.

If `DataTable` is not straightforward in Avalonia, a simpler MVP approach is: show Raw view only initially and add Table view as a follow-up. The critical fix is getting event selection and Raw view working.

- [ ] **Step 6: Build and verify**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`

- [ ] **Step 7: Run all tests**

Run: `dotnet test src/EdgeStudioTests/EdgeStudioTests.csproj -v n`

- [ ] **Step 8: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs
git commit -m "feat(dotnet): add Raw/Table view mode toggle and filter indicators to observer detail"
```

---

### Task 4: Remove "View" button from sidebar card, make card name clickable

**Files:**
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Sidebar/ObserverListingView.axaml`

**Problem:** The sidebar card has 4 buttons: eye (view), trash (delete), pencil (edit), green play (activate). The "view" button is confusing and doesn't exist in SwiftUI. In SwiftUI, clicking the observer name/row itself selects it and loads events.

**SwiftUI equivalent:** `SidebarViews.swift` — tapping the observer row calls `viewModel.selectedObservable = observer` and `viewModel.loadObservedEvents()`. No separate "view" button.

- [ ] **Step 1: Remove the "View Events" button from the card**

In `ObserverListingView.axaml`, delete this entire Button block from the Action Buttons StackPanel:

```xml
<!-- Select (view events) — REMOVE THIS ENTIRE BLOCK -->
<Button Classes="Flat"
       Width="28" Height="28" Padding="0"
       ToolTip.Tip="View Events"
       Command="{Binding $parent[ItemsControl].DataContext.SelectObserverCommand}"
       CommandParameter="{Binding}">
    <TextBlock Text="visibility"
              FontFamily="avares://EdgeStudio/Assets/Fonts/MaterialSymbolsOutlined.ttf#Material Symbols Outlined"
              FontSize="16"
              HorizontalAlignment="Center"
              VerticalAlignment="Center"/>
</Button>
```

- [ ] **Step 2: Make the card header area clickable to select the observer**

Wrap the card's header StackPanel (name + query) in a Button that triggers SelectObserverCommand:

```xml
<!-- Header with Name and Status — make clickable -->
<Button Classes="Flat"
       HorizontalAlignment="Stretch"
       HorizontalContentAlignment="Stretch"
       Padding="0"
       Command="{Binding $parent[ItemsControl].DataContext.SelectObserverCommand}"
       CommandParameter="{Binding}"
       Cursor="Hand">
    <Grid ColumnDefinitions="*,Auto">
        <StackPanel Grid.Column="0" Spacing="4">
            <TextBlock Text="{Binding Name}"
                      FontSize="14"
                      FontWeight="SemiBold"
                      VerticalAlignment="Center"/>
            <TextBlock Text="{Binding Query}"
                      FontSize="11"
                      Opacity="0.7"
                      TextWrapping="Wrap"
                      MaxLines="2"
                      FontFamily="Consolas"/>
        </StackPanel>

        <!-- Active indicator -->
        <TextBlock Grid.Column="1"
                  Text="Active"
                  FontSize="10"
                  FontWeight="SemiBold"
                  Foreground="Green"
                  VerticalAlignment="Top"
                  IsVisible="{Binding IsActive}"/>
    </Grid>
</Button>
```

- [ ] **Step 3: Build to verify**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal`

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/Views/StudioView/Sidebar/ObserverListingView.axaml
git commit -m "fix(dotnet): remove View button from observer card, make card name clickable to select"
```

---

### Task 5: Add pagination to event list and event detail

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs`
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml`
- Test: `dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs`

**Problem:** No pagination in either pane. Large event lists or large result sets will slow down the UI.

**SwiftUI equivalent:** `DetailViews.swift` has `observerCurrentPage`, `observerPageSize` (25 items), pagination controls for events. Detail pane has separate `observeDetailCurrentPage` with 10 items per page.

- [ ] **Step 1: Add pagination properties to ViewModel**

```csharp
// Event list pagination
[ObservableProperty]
private int _eventCurrentPage = 1;

[ObservableProperty]
private int _eventPageSize = 25;

public int EventPageCount => Events.Count == 0 ? 1 : (int)Math.Ceiling((double)Events.Count / EventPageSize);

public ObservableCollection<ObserverEvent> PagedEvents { get; } = new();

// Detail data pagination
[ObservableProperty]
private int _detailCurrentPage = 1;

[ObservableProperty]
private int _detailPageSize = 10;

public int DetailPageCount => FilteredEventData.Count == 0 ? 1 : (int)Math.Ceiling((double)_allFilteredData.Count / DetailPageSize);

public ObservableCollection<string> PagedFilteredEventData { get; } = new();

private List<string> _allFilteredData = new();

[RelayCommand]
private void EventNextPage()
{
    if (EventCurrentPage < EventPageCount)
    {
        EventCurrentPage++;
        RefreshPagedEvents();
    }
}

[RelayCommand]
private void EventPreviousPage()
{
    if (EventCurrentPage > 1)
    {
        EventCurrentPage--;
        RefreshPagedEvents();
    }
}

[RelayCommand]
private void DetailNextPage()
{
    if (DetailCurrentPage < DetailPageCount)
    {
        DetailCurrentPage++;
        RefreshPagedFilteredData();
    }
}

[RelayCommand]
private void DetailPreviousPage()
{
    if (DetailCurrentPage > 1)
    {
        DetailCurrentPage--;
        RefreshPagedFilteredData();
    }
}

private void RefreshPagedEvents()
{
    PagedEvents.Clear();
    var skip = (EventCurrentPage - 1) * EventPageSize;
    var page = Events.Skip(skip).Take(EventPageSize);
    foreach (var e in page)
        PagedEvents.Add(e);
    OnPropertyChanged(nameof(EventPageCount));
}

private void RefreshPagedFilteredData()
{
    PagedFilteredEventData.Clear();
    var skip = (DetailCurrentPage - 1) * DetailPageSize;
    var page = _allFilteredData.Skip(skip).Take(DetailPageSize);
    foreach (var item in page)
        PagedFilteredEventData.Add(item);
    OnPropertyChanged(nameof(DetailPageCount));
}
```

Update `RefreshFilteredEventData()` to populate `_allFilteredData` first, then call `RefreshPagedFilteredData()`:

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

    DetailCurrentPage = 1;
    RefreshPagedFilteredData();

    // Also update the legacy FilteredEventData for backwards compat
    FilteredEventData.Clear();
    foreach (var item in _allFilteredData)
        FilteredEventData.Add(item);
}
```

Update `LoadEventsForSelectedObserver()` to call `RefreshPagedEvents()` and reset page:

```csharp
private void LoadEventsForSelectedObserver()
{
    Events.Clear();
    SelectedEvent = null;

    if (SelectedObserver != null && _allEvents.TryGetValue(SelectedObserver.Id, out var events))
    {
        foreach (var e in events)
            Events.Add(e);
    }

    EventCurrentPage = 1;
    RefreshPagedEvents();
    OnPropertyChanged(nameof(HasEvents));
}
```

Also update `OnObserverCallback` to refresh paged events after adding:

```csharp
// In the Dispatcher.UIThread.InvokeAsync block:
Dispatcher.UIThread.InvokeAsync(() =>
{
    if (SelectedObserver?.Id == observerId)
    {
        Events.Add(observerEvent);
        RefreshPagedEvents();
        OnPropertyChanged(nameof(HasEvents));
    }
});
```

- [ ] **Step 2: Write pagination tests**

```csharp
[Fact]
public void EventPagination_PagedEventsRespectPageSize()
{
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);
    vm.EventPageSize = 2;

    // Add 5 events
    for (int i = 0; i < 5; i++)
    {
        vm.Events.Add(new ObserverEvent { ObserverId = "obs1", EventTime = DateTime.Now.AddMinutes(i) });
    }

    vm.EventCurrentPage = 1;
    // Trigger refresh (implementer: may need to call RefreshPagedEvents directly or via internal method)

    vm.EventPageCount.Should().Be(3); // ceil(5/2) = 3
}

[Fact]
public void DetailPagination_FilteredDataRespectPageSize()
{
    var mockRepo = new Mock<IObserverRepository>();
    var vm = new ObserversViewModel(mockRepo.Object);
    vm.DetailPageSize = 2;

    var testEvent = new ObserverEvent
    {
        ObserverId = "obs1",
        Data = new List<string> { "a", "b", "c", "d", "e" },
        EventTime = DateTime.Now
    };

    vm.SelectedEvent = testEvent;

    vm.DetailPageCount.Should().Be(3); // ceil(5/2) = 3
    vm.PagedFilteredEventData.Should().HaveCount(2); // first page
}
```

- [ ] **Step 3: Run tests**

Run: `dotnet test src/EdgeStudioTests/EdgeStudioTests.csproj -v n`

- [ ] **Step 4: Add pagination controls to XAML — event list**

Add pagination bar below the DataGrid in the top pane:

```xml
<!-- Pagination for Events -->
<Border Grid.Row="2"
        Padding="8,4"
        IsVisible="{Binding HasEvents}">
    <Grid ColumnDefinitions="*,Auto,Auto,Auto,*">
        <Button Grid.Column="1"
                Content="&lt;"
                Classes="Flat"
                Padding="8,2"
                FontSize="11"
                Command="{Binding EventPreviousPageCommand}"/>
        <TextBlock Grid.Column="2"
                  FontSize="11"
                  VerticalAlignment="Center"
                  Margin="8,0">
            <TextBlock.Text>
                <MultiBinding StringFormat="Page {0} of {1}">
                    <Binding Path="EventCurrentPage"/>
                    <Binding Path="EventPageCount"/>
                </MultiBinding>
            </TextBlock.Text>
        </TextBlock>
        <Button Grid.Column="3"
                Content="&gt;"
                Classes="Flat"
                Padding="8,2"
                FontSize="11"
                Command="{Binding EventNextPageCommand}"/>
    </Grid>
</Border>
```

Update the top pane Grid RowDefinitions to include the pagination row: `RowDefinitions="Auto,*,Auto"`.

Bind the DataGrid to `PagedEvents` instead of `Events`:
```xml
<DataGrid ... ItemsSource="{Binding PagedEvents}" ...>
```

- [ ] **Step 5: Add pagination controls to XAML — detail data**

Add pagination bar at the bottom of the detail pane. Update the bottom Grid RowDefinitions to `"Auto,*,Auto"` and add:

```xml
<!-- Pagination for Detail Data -->
<Border Grid.Row="2"
        Padding="8,4"
        IsVisible="{Binding HasSelectedEvent}">
    <Grid ColumnDefinitions="*,Auto,Auto,Auto,*">
        <Button Grid.Column="1"
                Content="&lt;"
                Classes="Flat"
                Padding="8,2"
                FontSize="11"
                Command="{Binding DetailPreviousPageCommand}"/>
        <TextBlock Grid.Column="2"
                  FontSize="11"
                  VerticalAlignment="Center"
                  Margin="8,0">
            <TextBlock.Text>
                <MultiBinding StringFormat="Page {0} of {1}">
                    <Binding Path="DetailCurrentPage"/>
                    <Binding Path="DetailPageCount"/>
                </MultiBinding>
            </TextBlock.Text>
        </TextBlock>
        <Button Grid.Column="3"
                Content="&gt;"
                Classes="Flat"
                Padding="8,2"
                FontSize="11"
                Command="{Binding DetailNextPageCommand}"/>
    </Grid>
</Border>
```

Bind the detail ItemsControl to `PagedFilteredEventData` instead of `FilteredEventData`:
```xml
<ItemsControl ItemsSource="{Binding PagedFilteredEventData}" ...>
```

- [ ] **Step 6: Build and run all tests**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj -v n`

- [ ] **Step 7: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/ObserversViewModel.cs dotnet/src/EdgeStudio/Views/StudioView/Details/ObserverDetailView.axaml dotnet/src/EdgeStudioTests/ObserversViewModelTests.cs
git commit -m "feat(dotnet): add pagination to observer event list and event detail panes"
```

---

### Task 6: Final integration — build and run all tests

**Files:**
- All modified files from Tasks 1-5

- [ ] **Step 1: Full solution build**

Run: `cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio.sln --verbosity minimal`

- [ ] **Step 2: Run all tests**

Run: `dotnet test src/EdgeStudioTests/EdgeStudioTests.csproj -v n`
Expected: All tests pass (existing 400 + new tests)

- [ ] **Step 3: Fix any failures**

If any tests fail, diagnose and fix. Build again after fixes.

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -u dotnet/
git commit -m "fix(dotnet): final observer detail view integration fixes"
```
