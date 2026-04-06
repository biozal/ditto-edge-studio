# Bug Fix Plan: Index UI, Field Display, Auto-Refresh, Toolbar State

**Date:** 2026-03-29
**Branch:** release-1.0b4

---

## Overview

Four bugs identified from screenshots (`dotnet-index-field.png`, `dotnet-wrong-toolbar-selected.png`):

1. **QueryListingView doesn't fill container when resized** — wasted screen space
2. **Index field name shows Dictionary type string** — `system:indexes` fields not extracted correctly
3. **UI doesn't auto-update after adding an index** — QueryListingView sidebar tree stays stale
4. **Wrong toolbar icon selected after close/reopen** — navigation highlight doesn't reset to Subscriptions

---

## Bug 1 — Listing Panel Column Doesn't Fill on Resize

### Root Cause

`EdgeStudioView.axaml` line 120 defines the listing panel column as:

```xml
<ColumnDefinition Width="Auto"/>
```

`Width="Auto"` means the column always sizes to its content. The `<Panel>` inside has `Width="250"`, so after a GridSplitter drag, the Panel's render width changes but the column snaps back to the content size on the next layout pass. The user sees no persistent resize.

### Fix

Change the listing panel ColumnDefinition from `Width="Auto"` to a fixed initial width, and move the size constraints there. Remove `Width="250"` from the Panel so the Panel fills the column instead.

**File:** `dotnet/src/EdgeStudio/Views/StudioView/EdgeStudioView.axaml`

Change column 2 (line ~120):
```xml
<!-- Before -->
<ColumnDefinition Width="Auto"/>

<!-- After -->
<ColumnDefinition Width="250" MinWidth="200" MaxWidth="500"/>
```

Change the Panel (line ~153):
```xml
<!-- Before -->
<Panel Grid.Column="2"
       Width="250" MinWidth="200" MaxWidth="500"
       IsVisible="{Binding IsListingPanelVisible}">

<!-- After -->
<Panel Grid.Column="2"
       IsVisible="{Binding IsListingPanelVisible}">
```

When `IsListingPanelVisible=false` the column should collapse to zero. Avalonia collapses `Auto` columns when content is hidden but NOT fixed-width columns. To handle this, keep the column as `Auto` but add a converter, OR (simpler) override the width binding:

```xml
<ColumnDefinition Width="{Binding IsListingPanelVisible, Converter={StaticResource BoolToColumnWidthConverter}, ConverterParameter=250}"/>
```

**Simpler alternative** — keep `Width="Auto"` on the column but give the Panel no fixed width and set `MinWidth`/`MaxWidth` via a style. The real issue is the Panel has a hard-coded `Width="250"`, which causes `Auto` to always measure 250 and never honor drag. Instead:

```xml
<!-- Column stays Auto so it collapses when Panel is hidden -->
<ColumnDefinition Width="Auto"/>

<!-- Panel: no Width, uses its natural size from MinWidth -->
<Panel Grid.Column="2"
       MinWidth="200"
       MaxWidth="500"
       IsVisible="{Binding IsListingPanelVisible}">
```

**BUT** without a starting width the Panel will collapse to the minimum. A better approach that avoids a converter: use a dedicated ColumnDefinition width binding driven by a property, or use a `SplitView`-style approach. The simplest fix that matches Avalonia's GridSplitter behavior:

**Recommended fix:**
- Keep the Panel with no `Width` attribute (remove it)
- Change the ColumnDefinition to `Width="250" MinWidth="200" MaxWidth="500"`
- Add a `IsVisible` → column width collapse: wrap the Panel in an outer element whose visibility collapses the column. In Avalonia, setting `IsVisible=false` on a column child does NOT collapse the column if the column has a fixed width. Add a separate ColumnDefinition collapse mechanism by conditionally setting the column's `Width` to `0` when hidden.

**Cleanest approach without a converter:**

```xml
<ColumnDefinition Width="{Binding ListingPanelWidth}"/>
```

In `EdgeStudioViewModel`:
```csharp
public GridLength ListingPanelWidth => IsListingPanelVisible
    ? new GridLength(250, GridUnitType.Pixel)
    : new GridLength(0);
```

And raise `PropertyChanged` for `ListingPanelWidth` whenever `IsListingPanelVisible` changes.

For now the simplest low-risk fix is to just remove the hardcoded `Width="250"` from the Panel so it can grow with the `Auto` column when the GridSplitter drags it. The GridSplitter modifies the ColumnDefinition's `Width`, and with `Auto` the Panel will take the measured width when visible. Set `MinWidth` on the Panel itself so it has a sensible default:

**Final recommended minimal fix:**

`EdgeStudioView.axaml` — Panel element:
- Remove: `Width="250"`
- Keep: `MinWidth="200" MaxWidth="500"`

The GridSplitter already modifies the ColumnDefinition, and `Auto` will re-measure from the Panel's `MinWidth`. This gives the panel a default of 200 (its minimum), and the GridSplitter will allow it to grow. If 200 feels too narrow as a default, bump `MinWidth` to 250.

---

## Bug 2 — Index Field Shows `System.Collections.Generic.Dicto...`

### Root Cause

The Ditto SDK's `system:indexes` query returns each field entry in the `fields` array as a `Dictionary<string, object>` (e.g., `{"path": "status"}`), not a plain string. Calling `f?.ToString()` on a dictionary produces the type name.

This affects two places:

**File 1:** `dotnet/src/EdgeStudio.Shared/Data/Repositories/CollectionsRepository.cs` — `FetchIndexesAsync`
**File 2:** `dotnet/src/EdgeStudio/ViewModels/IndexesToolViewModel.cs` — `FetchIndexesByCollectionAsync`

Both use:
```csharp
fields.AddRange(fieldList.Select(f => f?.ToString()?.Trim('`') ?? string.Empty).Where(f => f.Length > 0));
```

### Fix

Replace the `f?.ToString()` call with dictionary-aware extraction:

```csharp
fields.AddRange(fieldList.Select(f =>
{
    // SDK may return fields as Dictionary<string, object> with a "path" key
    if (f is IDictionary<string, object> dict)
    {
        var path = dict.TryGetValue("path", out var p) ? p?.ToString()
                 : dict.TryGetValue("name", out var n) ? n?.ToString()
                 : dict.Values.FirstOrDefault()?.ToString();
        return path?.Trim('`') ?? string.Empty;
    }
    return f?.ToString()?.Trim('`') ?? string.Empty;
}).Where(f => f.Length > 0));
```

Apply the same fix to both files. The fallback `dict.Values.FirstOrDefault()` handles any other key names the SDK might use.

> **Note:** If the exact dictionary key is unknown, add a temporary log line `Console.WriteLine(string.Join(", ", dict.Keys))` during dev to confirm. Remove before merge.

---

## Bug 3 — QueryListingView Sidebar Tree Doesn't Update After Index Added

### Root Cause

`IndexesToolViewModel.CreateIndexAsync()` calls `FetchDataAsync()` which refreshes `CollectionNodes` (the Inspector panel tree). However, the sidebar tree in Query mode is driven by `QueryViewModel.Collections`, which is sourced from `ICollectionsRepository`. That repository has its own refresh cycle and is not triggered by index operations.

### Fix

After a successful index create or drop in `IndexesToolViewModel`, send a message that causes the `ICollectionsRepository` to refresh.

**Option A — New message (clean separation):**

1. Add `RefreshCollectionsMessage` to `EdgeStudio.Shared/Messages/`
2. `IndexesToolViewModel.CreateIndexAsync` and `DropIndexAsync` send the message after `FetchDataAsync()`
3. `EdgeStudioViewModel` (or `QueryViewModel`) receives it and calls the collections repository refresh

**Option B — Direct call through EdgeStudioViewModel (simpler):**

`IndexesToolViewModel` already has a reference to `IDittoManager`. Add a method on `QueryViewModel` or expose a refresh on a shared `ICollectionsRepository`, then call it from `IndexesToolViewModel` after index operations.

**Recommended: Option A**

**New file:** `dotnet/src/EdgeStudio.Shared/Messages/CollectionMessages.cs`
```csharp
namespace EdgeStudio.Shared.Messages;

public class RefreshCollectionsRequestedMessage { }
```

In `IndexesToolViewModel.cs`:
```csharp
// At end of CreateIndexAsync and DropIndexAsync, after FetchDataAsync():
WeakReferenceMessenger.Default.Send(new RefreshCollectionsRequestedMessage());
```

In `EdgeStudioViewModel.cs` — register and receive the message:
```csharp
// In constructor or after init:
WeakReferenceMessenger.Default.Register<RefreshCollectionsRequestedMessage>(this, (_, _) =>
{
    if (_queryViewModelLazy.IsValueCreated)
        QueryViewModel.RefreshCollectionsCommand.Execute(null);
});
```

In `QueryViewModel.cs` — expose a refresh command (it likely already calls the collections repository; make it callable externally):
```csharp
[RelayCommand]
public async Task RefreshCollectionsAsync()
{
    await _collectionsRepository.RefreshAsync();
}
```

---

## Bug 4 — Wrong Toolbar Icon Remains Selected After Close/Reopen

### Root Cause

`NavigationViewModel.SelectedItem` has `private set`. When `EdgeStudioViewModel` calls `UpdateCurrentViews(NavigationItemType.Subscriptions)` during database initialization, it switches the content panels correctly but does NOT call back into `NavigationViewModel` to move the selection highlight.

The result: toolbar icon stays on whatever was last selected (e.g., Query), while the content shows Subscriptions.

### Fix

Add a public method to `NavigationViewModel` to programmatically select an item, then call it from `EdgeStudioViewModel` when the database is opened.

**`NavigationViewModel.cs`** — add:
```csharp
/// <summary>
/// Selects the navigation item matching the given type without triggering navigation service.
/// Used when the content is changed externally (e.g., database reopen).
/// </summary>
public void SyncSelectionTo(NavigationItemType type)
{
    var item = NavigationItems.FirstOrDefault(x => x.Type == type);
    if (item != null && item != SelectedItem)
    {
        // Use the private setter via the existing property pathway
        SelectedItem = item;
        // Do NOT call _navigationService.NavigateTo — content is already set externally
    }
}
```

**`EdgeStudioViewModel.cs`** — in the `UpdateCurrentViews` method or wherever `NavigationItemType.Subscriptions` is passed on database init (line ~175), add:

```csharp
QueryViewModel.SetDatabaseConfig(_selectedDatabase);
UpdateCurrentViews(NavigationItemType.Subscriptions);
NavigationViewModel.SyncSelectionTo(NavigationItemType.Subscriptions); // ← add this
_ = IndexesToolViewModel.LoadAsync();
```

---

## Files to Modify

| File | Bug | Change |
|------|-----|--------|
| `EdgeStudio/Views/StudioView/EdgeStudioView.axaml` | 1 | Remove `Width="250"` from Panel; keep `MinWidth`/`MaxWidth` |
| `EdgeStudio.Shared/Data/Repositories/CollectionsRepository.cs` | 2 | Dictionary-aware field extraction in `FetchIndexesAsync` |
| `EdgeStudio/ViewModels/IndexesToolViewModel.cs` | 2, 3 | Dictionary-aware field extraction; send `RefreshCollectionsRequestedMessage` |
| `EdgeStudio.Shared/Messages/CollectionMessages.cs` | 3 | **New file** — `RefreshCollectionsRequestedMessage` |
| `EdgeStudio/ViewModels/QueryViewModel.cs` | 3 | Add/expose `RefreshCollectionsCommand` |
| `EdgeStudio/ViewModels/EdgeStudioViewModel.cs` | 3, 4 | Register `RefreshCollectionsRequestedMessage`; call `NavigationViewModel.SyncSelectionTo` |
| `EdgeStudio/ViewModels/NavigationViewModel.cs` | 4 | Add `SyncSelectionTo(NavigationItemType)` public method |

---

## Build & Test

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src
dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

**Manual verification steps:**

- **Bug 1:** Open a database → Query view → drag the sidebar wider → release → sidebar should stay at the new width
- **Bug 2:** Open a database with indexes → expand a collection in the Inspector → field names should show `status`, `userId`, etc. (not `System.Collections...`)
- **Bug 3:** Add an index via the FAB → Inspector tree updates AND the sidebar tree in Query mode also shows the new index without manual refresh
- **Bug 4:** Select Query view → close the database → reopen the same database → app shows Subscriptions content AND the Subscriptions toolbar icon is highlighted

---

## Implementation Order

1. **Bug 4** (NavigationViewModel + EdgeStudioViewModel) — isolated, no dependencies
2. **Bug 2** (field extraction) — isolated fix in two files
3. **Bug 1** (listing panel layout) — XAML only
4. **Bug 3** (auto-refresh) — depends on new message + QueryViewModel changes; do last
