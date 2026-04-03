# Fix Presence Viewer Connection Count & Last Updated Timestamp

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two bugs: (1) connection count in the bottom bar doesn't include all transports (especially Bluetooth) and goes stale when viewing the Presence Viewer tab, and (2) the "Last updated" timestamp in the header is blank on the Presence Viewer tab.

**Architecture:** Both bugs stem from the same design issue — when the user switches to the Presence Viewer tab (index 1), `PeersList.Deactivate()` is called, stopping the peer card observer that's the only source for `PublishConnectionCounts()` and `LastUpdatedText`. The fix is twofold: (1) normalize connection type strings in `PublishConnectionCounts` using the existing `NormalizeConnectionType` method, and (2) also call `PublishConnectionCounts` from the presence graph observer so counts stay current regardless of which tab is active, plus add a `LastUpdatedText` property to `PresenceViewerViewModel` that updates on each graph update.

**Tech Stack:** C# / .NET 10.0, Avalonia UI, CommunityToolkit.Mvvm

---

## Root Cause Analysis

### Bug 1: Connection count missing Bluetooth and going stale

**Two sub-causes:**

**1a. Case mismatch in `PublishConnectionCounts`** (`SystemRepository.cs:475-488`)

The Ditto .NET SDK `ConnectionType.ToString()` can return varying casing (e.g., `"bluetooth"`, `"WiFi"`, `"p2pWifi"`). The switch statement only handles exact capitalized forms like `"Bluetooth"`, `"AccessPoint"`, etc. The renderer already has `NormalizeConnectionType()` that handles all variants — but `PublishConnectionCounts` doesn't use it.

**1b. Counts only updated from peer card observer** (`SystemRepository.cs:199`)

`PublishConnectionCounts()` is ONLY called from the `_syncStatusObserver` callback inside `RegisterPeerCardObservers()`. When the user switches to the Presence Viewer tab, `PeersList.Deactivate()` is called (`SubscriptionDetailsViewModel.cs:59`), and the peer card observer stops updating. The separate presence graph observer (`RegisterPresenceGraphObserver`) does NOT call `PublishConnectionCounts()`.

### Bug 2: "Last updated" blank on Presence Viewer tab

The header in `SubscriptionDetailsView.axaml:41` binds to `PeersList.LastUpdatedText`. This property only updates when `PeerCards.CollectionChanged` fires (`PeersListViewModel.cs:77`). When on the Presence Viewer tab, PeersList is deactivated, so the collection never changes and the timestamp stays at `"--:--:-- --"`.

---

## File Structure

| Action | File | Responsibility |
|--------|------|---------------|
| **Modify** | `EdgeStudio.Shared/Data/Repositories/SystemRepository.cs:452-497` | Use `NormalizeConnectionType` in `PublishConnectionCounts`; also call it from presence graph observer |
| **Modify** | `EdgeStudio/ViewModels/PresenceViewerViewModel.cs` | Add `LastUpdatedText` property, update on graph changes |
| **Modify** | `EdgeStudio/Views/StudioView/Details/SubscriptionDetailsView.axaml:41` | Bind "Last updated" to active tab's timestamp |
| **Modify** | `EdgeStudio/ViewModels/SubscriptionDetailsViewModel.cs` | Expose a computed `LastUpdatedText` that delegates to the active tab's VM |
| **Modify** | `EdgeStudioTests/PresenceViewerViewModelTests.cs` | Test LastUpdatedText updates |

---

## Task 1: Normalize Connection Types in PublishConnectionCounts

**Files:**
- Modify: `dotnet/src/EdgeStudio.Shared/Data/Repositories/SystemRepository.cs:452-497`

The `PublishConnectionCounts` switch statement handles exact casing only. The renderer's `PresenceGraphRenderer.NormalizeConnectionType()` already handles all SDK variants. Use that normalization before the switch.

- [ ] **Step 1: Import the renderer's normalization or inline it**

Since `PublishConnectionCounts` is in `EdgeStudio.Shared` (which can't reference `EdgeStudio` where the renderer lives), we need to either move the normalization to shared or inline it. The simplest approach: replace the raw `typeStr` with a normalized version before the switch.

In `SystemRepository.cs`, inside `PublishConnectionCounts`, after line 469 (`var typeStr = conn.ConnectionType.ToString();`), add normalization:

```csharp
var typeStr = conn.ConnectionType.ToString();
// Normalize casing — SDK returns varying forms (e.g. "bluetooth", "WiFi", "p2pWifi")
var normalizedType = typeStr switch
{
    "WiFi" or "Wifi" or "wifi" or "accessPoint" => "AccessPoint",
    "P2PWiFi" or "p2pwifi" or "P2Pwifi" or "p2pWifi" => "P2PWifi",
    "Awdl" or "awdl" => "AWDL",
    "bluetooth" => "Bluetooth",
    "websocket" or "Websocket" => "WebSocket",
    _ => typeStr
};
if (!seenTypes.Add(normalizedType))
    continue;
```

Then use `normalizedType` instead of `typeStr` in the switch and debug log.

- [ ] **Step 2: Build**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio.Shared/Data/Repositories/SystemRepository.cs
git commit -m "fix(dotnet): normalize connection type casing in PublishConnectionCounts

The Ditto SDK returns varying casing for ConnectionType.ToString()
(e.g. 'bluetooth' vs 'Bluetooth'). The switch statement only matched
exact capitalization, silently dropping Bluetooth and other transports.
Apply the same normalization as PresenceGraphRenderer.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Call PublishConnectionCounts from Presence Graph Observer

**Files:**
- Modify: `dotnet/src/EdgeStudio.Shared/Data/Repositories/SystemRepository.cs:324-422`

The presence graph observer builds a `PresenceGraphSnapshot` but never updates connection counts. When the Presence Viewer tab is active, this is the only observer running (PeersList is deactivated). We need to also call `PublishConnectionCounts` from here.

- [ ] **Step 1: Add PublishConnectionCounts call to RegisterPresenceGraphObserver**

In `SystemRepository.cs`, inside `RegisterPresenceGraphObserver`, after line 410 (`var snapshot = new PresenceGraphSnapshot(...)`) and before `onUpdate(snapshot)`, add:

```csharp
// Update connection counts so the bottom bar stays current even when
// the Peers List tab is not active (it deactivates its own observer).
var dittoServerCount = isConnectedToCloud ? 1 : 0;
PublishConnectionCounts(presenceGraph, dittoServerCount);
```

This ensures that every time the presence graph updates (which happens on the Presence Viewer tab), the connection counts in the bottom bar are also refreshed.

- [ ] **Step 2: Build**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Run tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio.Shared/Data/Repositories/SystemRepository.cs
git commit -m "fix(dotnet): update connection counts from presence graph observer

Previously PublishConnectionCounts was only called from the peer card
observer, which is deactivated when the Presence Viewer tab is active.
Now also called from the presence graph observer so the bottom bar
connection count stays current regardless of which tab is selected.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Add LastUpdatedText to PresenceViewerViewModel

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/PresenceViewerViewModel.cs`
- Modify: `dotnet/src/EdgeStudioTests/PresenceViewerViewModelTests.cs`

The Presence Viewer needs its own "Last updated" timestamp that updates each time the presence graph fires.

- [ ] **Step 1: Add LastUpdatedText property to PresenceViewerViewModel**

Add a new observable property:

```csharp
[ObservableProperty]
private string _lastUpdatedText = "--:--:-- --";
```

In `HandleGraphUpdate`, after setting `_fullSnapshot`, update the timestamp:

```csharp
public void HandleGraphUpdate(PresenceGraphSnapshot snapshot)
{
    _fullSnapshot = snapshot;
    LastUpdatedText = DateTime.Now.ToString("h:mm:ss tt");
    ApplyFilterAndLayout();
}
```

- [ ] **Step 2: Update test for LastUpdatedText**

In `PresenceViewerViewModelTests.cs`, update the constructor defaults test to check for the initial value, and add a test that `HandleGraphUpdate` updates the timestamp:

```csharp
[Fact]
public void HandleGraphUpdate_ShouldUpdateLastUpdatedText()
{
    var vm = new PresenceViewerViewModel(_lazySystemRepo);
    vm.LastUpdatedText.Should().Be("--:--:-- --");

    var snapshot = new PresenceGraphSnapshot(
        new List<PresenceNode> { new("local", "Me", true, false, false, null) },
        new List<PresenceEdge>(),
        "local");

    vm.HandleGraphUpdate(snapshot);

    vm.LastUpdatedText.Should().NotBe("--:--:-- --");
    vm.LastUpdatedText.Should().MatchRegex(@"\d{1,2}:\d{2}:\d{2} [AP]M");
}
```

- [ ] **Step 3: Build and run tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/PresenceViewerViewModel.cs dotnet/src/EdgeStudioTests/PresenceViewerViewModelTests.cs
git commit -m "feat(dotnet): add LastUpdatedText to PresenceViewerViewModel

Updates timestamp each time the presence graph observer fires, so the
header shows when data was last refreshed while on the Presence Viewer tab.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Wire Last Updated to Header Based on Active Tab

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/SubscriptionDetailsViewModel.cs`
- Modify: `dotnet/src/EdgeStudio/Views/StudioView/Details/SubscriptionDetailsView.axaml:41`

The header currently binds to `PeersList.LastUpdatedText` which is blank when on the Presence Viewer tab. We need a computed property that delegates to the active tab's timestamp.

- [ ] **Step 1: Add LastUpdatedText property to SubscriptionDetailsViewModel**

```csharp
/// <summary>
/// Last updated text from the currently active tab's ViewModel.
/// </summary>
public string LastUpdatedText => SelectedTabIndex switch
{
    0 => PeersList.LastUpdatedText,
    1 => PresenceViewer.LastUpdatedText,
    _ => "--:--:-- --"
};
```

Also forward property change notifications. In `OnSelectedTabIndexChanged`, add:

```csharp
OnPropertyChanged(nameof(LastUpdatedText));
```

Subscribe to child property changes so the header updates in real-time. In the constructor, after creating child VMs:

```csharp
PeersList.PropertyChanged += (_, e) =>
{
    if (e.PropertyName == nameof(PeersList.LastUpdatedText) && SelectedTabIndex == 0)
        OnPropertyChanged(nameof(LastUpdatedText));
};

PresenceViewer.PropertyChanged += (_, e) =>
{
    if (e.PropertyName == nameof(PresenceViewerViewModel.LastUpdatedText) && SelectedTabIndex == 1)
        OnPropertyChanged(nameof(LastUpdatedText));
};
```

Note: `PeersListViewModel.LastUpdatedText` is a computed property (not `[ObservableProperty]`), so it may not fire `PropertyChanged`. If it doesn't, we also need to raise it from `PeersListViewModel` when `LastUpdated` changes. Check `PeersListViewModel.OnPeersCollectionChanged` — it sets `LastUpdated` but may not notify for `LastUpdatedText`. If not, add `OnPropertyChanged(nameof(LastUpdatedText))` there too.

- [ ] **Step 2: Update XAML binding**

In `SubscriptionDetailsView.axaml`, change line 41 from:

```xml
<TextBlock Text="{Binding PeersList.LastUpdatedText, FallbackValue='--:--:-- --'}"
```

to:

```xml
<TextBlock Text="{Binding LastUpdatedText, FallbackValue='--:--:-- --'}"
```

- [ ] **Step 3: Ensure PeersListViewModel raises PropertyChanged for LastUpdatedText**

In `PeersListViewModel.cs`, find where `LastUpdated` is set (in `OnPeersCollectionChanged`) and ensure it raises PropertyChanged for both properties:

```csharp
LastUpdated = DateTime.Now;
OnPropertyChanged(nameof(LastUpdated));
OnPropertyChanged(nameof(LastUpdatedText));
```

- [ ] **Step 4: Build and run tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

- [ ] **Step 5: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/SubscriptionDetailsViewModel.cs dotnet/src/EdgeStudio/ViewModels/PeersListViewModel.cs dotnet/src/EdgeStudio/Views/StudioView/Details/SubscriptionDetailsView.axaml
git commit -m "fix(dotnet): wire Last Updated timestamp to active tab's ViewModel

Header now shows timestamp from PeersList when on Peers tab and from
PresenceViewer when on Presence Viewer tab. Previously bound directly
to PeersList which was blank when Presence Viewer was active.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Final Verification

- [ ] **Step 1: Run full test suite**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio.sln --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --verbosity normal
```

- [ ] **Step 2: Manual verification**

1. **Connection count accuracy:**
   - Connect multiple peers with different transports (Bluetooth, LAN, WebSocket, etc.)
   - On Presence Viewer tab: verify bottom bar count matches visible connections
   - On Peers List tab: verify count matches
   - Switch between tabs: count should stay consistent

2. **Last Updated timestamp:**
   - On Presence Viewer tab: "Last updated" should show current time, updating with each graph change
   - On Peers List tab: "Last updated" should show current time, updating with each peer change
   - Switch tabs: timestamp should reflect the active tab's data

3. **Bluetooth specifically:**
   - Ensure Bluetooth connections appear in the count
   - Click the connection count to open flyout: Bluetooth should appear in the breakdown

---

## Summary of Changes

| Change | Impact |
|--------|--------|
| Normalize connection types in `PublishConnectionCounts` | Bluetooth and other variant-cased transports counted correctly |
| Call `PublishConnectionCounts` from presence graph observer | Bottom bar stays current when Presence Viewer tab is active |
| Add `LastUpdatedText` to `PresenceViewerViewModel` | Presence Viewer has its own live timestamp |
| Computed `LastUpdatedText` on `SubscriptionDetailsViewModel` | Header shows timestamp from whichever tab is active |
| Raise `PropertyChanged` for `LastUpdatedText` in `PeersListViewModel` | Peers List timestamp propagates to header binding |
