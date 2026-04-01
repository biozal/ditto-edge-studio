# Plan: Unify Query Metrics Detail View with Inspector Query Metrics View

## Problem

The Query Metrics detail view (`QueryMetricsDetailView.axaml`) and the Inspector Query Metrics view (`QueryMetricsView.axaml`) show the same type of data but use completely different UI code. The inspector version is the "correct" one — it has:
- DQL Statement in a styled box
- Stat badges (execution time, doc count, **indexed badge**)
- Timestamp
- EXPLAIN Output header with a **Copy button**
- Color-formatted JSON via `JsonDocumentCard`

The detail view is missing:
- The "Indexed" badge (UsedIndex)
- The Copy button for EXPLAIN output
- The timestamp is embedded in the badges instead of separate

Both views bind to the same `QueryMetricsViewModel`, but the detail view uses `SelectedRecord` (a `QueryMetric`) while the inspector uses `LatestMetric`.

## Solution

Replace the custom detail panel DataTemplate in `QueryMetricsDetailView.axaml` with the `QueryMetricsView` component itself, binding it to the selected record. This eliminates duplicate UI code entirely.

## Files to Change

### 1. `Views/StudioView/Details/QueryMetricsDetailView.axaml`

**What:** Replace the right-side detail panel's inline DataTemplate with the `QueryMetricsView` component, feeding it the selected metric.

The key challenge: `QueryMetricsView` binds to `QueryMetricsViewModel.LatestMetric`, but in the detail view we need it to show `SelectedRecord`. There are two approaches:

**Approach A (Recommended): Set `LatestMetric` when a record is selected**

In `QueryMetricsViewModel`, when `SelectedRecord` changes, also set `LatestMetric` to that record. Then the inspector's `QueryMetricsView` component works as-is when embedded in the detail panel.

Changes in `QueryMetricsViewModel.cs`:
- Add a `partial void OnSelectedRecordChanged(QueryMetric? value)` method (auto-generated hook from `[ObservableProperty]`) that sets `LatestMetric = value`

Changes in `QueryMetricsDetailView.axaml`:
- Replace the entire right-side `<ScrollViewer>` detail panel (lines 93-177) with:
```xml
<Panel Grid.Column="2">
    <!-- Empty state when no selection -->
    <StackPanel IsVisible="{Binding SelectedRecord, Converter={x:Static ObjectConverters.IsNull}}"
                VerticalAlignment="Center"
                HorizontalAlignment="Center"
                Spacing="8"
                Margin="24">
        <materialIcons:MaterialIcon Kind="CursorPointer"
                                    Width="32" Height="32"
                                    Opacity="0.2"
                                    HorizontalAlignment="Center"/>
        <TextBlock Text="Select a query to view details"
                   Opacity="0.5"
                   HorizontalAlignment="Center"/>
    </StackPanel>

    <!-- Reuse inspector component -->
    <inspector:QueryMetricsView
        IsVisible="{Binding SelectedRecord, Converter={x:Static ObjectConverters.IsNotNull}}"/>
</Panel>
```

- Remove the `xmlns:models` namespace (no longer needed since we removed the DataTemplate)
- The `xmlns:inspector` namespace is already present

### 2. `ViewModels/QueryMetricsViewModel.cs`

**What:** Sync `LatestMetric` with `SelectedRecord` so the shared component shows the selected item.

Add after line 28:
```csharp
partial void OnSelectedRecordChanged(QueryMetric? value)
{
    LatestMetric = value;
}
```

This uses the CommunityToolkit.Mvvm source generator hook — when `SelectedRecord` changes (via list selection), it automatically updates `LatestMetric`, which is what `QueryMetricsView` binds to.

**Important:** The `OnMetricsUpdated` handler (line 42) already sets `LatestMetric` when new queries run. To avoid a conflict where selecting a record gets overwritten by a new query result, we should only set `LatestMetric` in `OnMetricsUpdated` when there's no active selection:

Change line 46 from:
```csharp
LatestMetric = _metricsService!.Latest;
```
To:
```csharp
if (SelectedRecord == null)
    LatestMetric = _metricsService!.Latest;
```

### 3. `Views/StudioView/Inspector/QueryMetricsView.axaml`

**What:** Remove `x:CompileBindings` if present, and ensure the view doesn't set its own DataContext — it should inherit from the parent. Currently it declares `x:DataType="vm:QueryMetricsViewModel"` which is correct for both use cases since the same ViewModel is shared.

**No changes needed** — the view already works with the shared `QueryMetricsViewModel`.

## Files NOT Changed
- `QueryMetricsView.axaml.cs` — no changes needed
- `JsonDocumentCard.axaml` / `.cs` — already reused, no changes
- `QueryMetric` model — stays as-is
- `IQueryMetricsService` — stays as-is

## Verification
1. `dotnet build EdgeStudio/EdgeStudio.csproj` — must compile clean
2. Open Query Metrics from the navigation
3. Select a query from the left list
4. Verify the right panel shows identical UI to the inspector: DQL Statement, badges (time, docs, indexed), timestamp, EXPLAIN Output with Copy button and color-formatted JSON
5. Run a new query in the Query Editor — verify the inspector still updates with the latest metric
6. Go back to Query Metrics — verify selecting a different record from the list updates the detail panel correctly
