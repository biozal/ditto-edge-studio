# Plan: DetailBottomBar Port (.NET / Avalonia)

## Goal

Replace the current 26px solid-colored status bar at the bottom of `EdgeStudioView.axaml` with a floating, semi-transparent, collapsible bar that matches the SwiftUI `DetailBottomBar` in look and behaviour.

### SwiftUI Reference Behaviour (from `DetailBottomBar.swift`)

- **Floating overlay** — rendered via `.overlay(alignment: .bottom)` over the detail area, not as a grid row.
- **Expanded state**: antenna icon + total connection count (left) | optional middle content (center) | collapse chevron (right).
- **Collapsed state**: single expand-chevron button, right-aligned.
- **Glass appearance**: `GlassEffectContainer` + `glassEffect(in: RoundedRectangle(cornerRadius: 20))` + `subtleShadow()`.
- **Connections popover**: clicking the antenna icon shows a `Flyout`/`Popover` listing active transport counts with per-transport colored dots.
- **Spring animation** on collapse/expand.

### Screenshots (in `screens/dotnet/`)

- `detail-bottom-bar-closed.png` — collapsed: single `<<` chevron, right-aligned
- `detail-bottom-bar-open.png` — expanded: antenna + "4" count on left, `>>` chevron on right; popover above shows P2P WiFi: 1, Access Point: 2, Ditto Server: 1

---

## What Changes

### Files to Remove / Modify

| File | Change |
|------|--------|
| `EdgeStudio/Views/EdgeStudioView.axaml` | Remove Row 2 (status bar), overlay `DetailBottomBar` on detail panel |
| `EdgeStudio/ViewModels/EdgeStudioViewModel.cs` | Add `ConnectionsByTransport` observable property, subscribe to repository updates |
| `EdgeStudio.Shared/Data/Repositories/ISystemRepository.cs` | Add `event` or `Action` for connection count changes; add `ConnectionsByTransport` getter |
| `EdgeStudio.Shared/Data/Repositories/SystemRepository.cs` | Compute and publish connection counts inside existing observer |

### New Files

| File | Purpose |
|------|---------|
| `EdgeStudio.Shared/Models/ConnectionsByTransport.cs` | Immutable record — per-transport counts, computed totals, active transport list |
| `EdgeStudio/Views/Controls/DetailBottomBar.axaml` | UserControl — glass bar with collapsed/expanded states and connections flyout |
| `EdgeStudio/Views/Controls/DetailBottomBar.axaml.cs` | Code-behind — collapse toggle, flyout logic |

---

## Part 1 — ConnectionsByTransport Model

**File:** `EdgeStudio.Shared/Models/ConnectionsByTransport.cs`

```csharp
namespace EdgeStudio.Shared.Models;

public sealed record ConnectionsByTransport(
    int AccessPoint,
    int Bluetooth,
    int DittoServer,
    int P2PWifi,
    int WebSocket)
{
    public static readonly ConnectionsByTransport Empty = new(0, 0, 0, 0, 0);

    public int TotalConnections => AccessPoint + Bluetooth + DittoServer + P2PWifi + WebSocket;
    public bool HasActiveConnections => TotalConnections > 0;

    // Transport color constants (Ditto rainbow palette, matching SwiftUI):
    //   WebSocket  = #E65100 (orange)
    //   Bluetooth  = #0D47A1 (blue)
    //   P2P WiFi   = #B71C1C (red)
    //   AccessPoint= #1B5E20 (green)
    //   DittoServer= #4A148C (purple)

    public IReadOnlyList<TransportInfo> ActiveTransports
    {
        get
        {
            var list = new List<TransportInfo>();
            if (WebSocket > 0)   list.Add(new("WebSocket",   WebSocket,   MaterialIconKind.Wifi,             "#E65100"));
            if (Bluetooth > 0)   list.Add(new("Bluetooth",   Bluetooth,   MaterialIconKind.Bluetooth,        "#0D47A1"));
            if (P2PWifi > 0)     list.Add(new("P2P WiFi",    P2PWifi,     MaterialIconKind.WifiMarker,       "#B71C1C"));
            if (AccessPoint > 0) list.Add(new("Access Point",AccessPoint, MaterialIconKind.RouterWireless,   "#1B5E20"));
            if (DittoServer > 0) list.Add(new("Ditto Server",DittoServer, MaterialIconKind.CloudOutline,     "#4A148C"));
            return list;
        }
    }
}

public sealed record TransportInfo(
    string Name,
    int Count,
    MaterialIconKind Icon,
    string ColorHex);
```

**Note:** `MaterialIconKind` is in `Material.Icons` which is already referenced in `EdgeStudio.Shared.csproj`. Add `using Material.Icons;` at the top.

---

## Part 2 — SystemRepository Connection Tracking

The existing `RegisterPeerCardObservers` observer fires every time `system:data_sync_info` changes. We add connection-count computation inside that same callback and notify the ViewModel.

### ISystemRepository additions

```csharp
/// <summary>Current aggregated connection counts by transport, updated by the sync-status observer.</summary>
ConnectionsByTransport CurrentConnections { get; }

/// <summary>Raised on the UI thread when CurrentConnections changes.</summary>
event EventHandler<ConnectionsByTransport>? ConnectionsChanged;
```

### SystemRepository additions

Add a private backing field:
```csharp
private ConnectionsByTransport _currentConnections = ConnectionsByTransport.Empty;
```

At the end of the `RegisterPeerCardObservers` observer callback (after the `Dispatcher.UIThread.InvokeAsync` call that updates peer cards), compute and publish new counts:

```csharp
// Compute per-transport counts from the presence graph
var connections = ComputeConnectionsByTransport(ditto.Presence.Graph);

if (connections != _currentConnections)
{
    _currentConnections = connections;
    Dispatcher.UIThread.InvokeAsync(() =>
        ConnectionsChanged?.Invoke(this, connections));
}
```

```csharp
private static ConnectionsByTransport ComputeConnectionsByTransport(DittoPresenceGraph graph)
{
    int accessPoint = 0, bluetooth = 0, dittoServer = 0, p2pWifi = 0, webSocket = 0;

    foreach (var peer in graph.RemotePeers)
    {
        foreach (var conn in peer.Connections)
        {
            switch (conn.ConnectionType)
            {
                case DittoConnectionType.AccessPoint:  accessPoint++;  break;
                case DittoConnectionType.Bluetooth:    bluetooth++;    break;
                case DittoConnectionType.WebSocket:    webSocket++;    break;
                case DittoConnectionType.P2PWifi:      p2pWifi++;      break;
            }
        }
    }

    // Check presence for Ditto server connections
    // (server peers don't appear in RemotePeers, check via IsConnectedToDittoServer)
    // For now, count WebSocket connections that correspond to server sync status entries
    // TODO: refine with actual Ditto server detection if SDK exposes this

    return new ConnectionsByTransport(accessPoint, bluetooth, dittoServer, p2pWifi, webSocket);
}
```

Also call `ConnectionsChanged` with `Empty` inside `CancelPeerCardObservers` to reset the count when sync stops:
```csharp
_currentConnections = ConnectionsByTransport.Empty;
Dispatcher.UIThread.Invoke(() =>
    ConnectionsChanged?.Invoke(this, ConnectionsByTransport.Empty));
```

---

## Part 3 — EdgeStudioViewModel Wiring

Add `ConnectionsByTransport` as an observable property and subscribe to the repository event.

```csharp
[ObservableProperty]
private ConnectionsByTransport _connectionsByTransport = ConnectionsByTransport.Empty;
```

In the constructor, subscribe after the system repository is available:
```csharp
private readonly Lazy<ISystemRepository> _systemRepositoryLazy;

// In constructor:
_systemRepositoryLazy.Value.ConnectionsChanged += OnConnectionsChanged;

private void OnConnectionsChanged(object? sender, ConnectionsByTransport connections)
{
    ConnectionsByTransport = connections;
}
```

Wire up unsubscription in `OnDisposing()`:
```csharp
if (_systemRepositoryLazy.IsValueCreated)
    _systemRepositoryLazy.Value.ConnectionsChanged -= OnConnectionsChanged;
```

**Note:** `EdgeStudioViewModel` does not currently have `ISystemRepository` injected. The two options are:

- **Option A (preferred)**: Pass `Lazy<ISystemRepository>` into `EdgeStudioViewModel` constructor and register the event there — cleanest, no plumbing through child VMs.
- **Option B**: Add a pass-through property from `SubscriptionDetailsViewModel.PeersList` and notify via a message — more coupling, not recommended.

Use Option A. Update `App.axaml.cs` to pass `Lazy<ISystemRepository>` to `EdgeStudioViewModel`.

---

## Part 4 — DetailBottomBar UserControl

**File:** `EdgeStudio/Views/Controls/DetailBottomBar.axaml`

### Visual design

The bar is centered horizontally at the bottom of the detail area, not full-width. Match the SwiftUI proportions (width: content-sized with padding, not stretched to window edge).

**Glass look (no native blur in Avalonia 11):**
- Dark mode approximation: `Background="#B0202028"` (semi-transparent dark)
- Light mode: `Background="#B0E8E8EC"` (semi-transparent light)
- Use a SukiUI `DynamicResource` for the background so both themes work — check `SukiBackground` or use a Brush resource. If no suitable resource exists, use a style trigger on theme.
- `CornerRadius="20"`, `BoxShadow="0 4 20 4 #50000000"`

**AXAML structure:**

```xml
<UserControl x:Class="EdgeStudio.Views.Controls.DetailBottomBar"
             x:DataType="models:ConnectionsByTransport">

    <Panel HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,12">

        <!-- EXPANDED STATE -->
        <Border x:Name="ExpandedBar"
                IsVisible="{Binding !IsCollapsed, RelativeSource={RelativeSource AncestorType=UserControl}}"
                Background="#B0202028"
                CornerRadius="20"
                BoxShadow="0 4 20 4 #50000000"
                Padding="16,0">
            <StackPanel Orientation="Horizontal" Height="44" Spacing="16">

                <!-- Connections Button with Flyout -->
                <Button x:Name="ConnectionsButton" Classes="Flat" Padding="8,0" VerticalAlignment="Center">
                    <Button.Flyout>
                        <Flyout Placement="Top" ShowMode="TransientWithDismissOnPointerMoveAway">
                            <!-- Popover content (see below) -->
                        </Flyout>
                    </Button.Flyout>
                    <StackPanel Orientation="Horizontal" Spacing="4" VerticalAlignment="Center">
                        <avalonia:MaterialIcon Kind="AccessPoint" Width="16" Height="16" Opacity="0.6"/>
                        <TextBlock Text="{Binding TotalConnections}" FontFamily="Monospace" FontSize="14"/>
                    </StackPanel>
                </Button>

                <!-- Collapse Button -->
                <Button x:Name="CollapseButton" Classes="Flat" Padding="8,0" VerticalAlignment="Center"
                        Click="CollapseButton_Click">
                    <avalonia:MaterialIcon Kind="ChevronDoubleRight" Width="16" Height="16" Opacity="0.6"/>
                </Button>

            </StackPanel>
        </Border>

        <!-- COLLAPSED STATE -->
        <Border x:Name="CollapsedBar"
                IsVisible="{Binding IsCollapsed, RelativeSource={RelativeSource AncestorType=UserControl}}"
                Background="#B0202028"
                CornerRadius="20"
                BoxShadow="0 4 20 4 #50000000"
                Padding="12,0">
            <Button Classes="Flat" Padding="8,0" Height="44" VerticalAlignment="Center"
                    Click="ExpandButton_Click">
                <avalonia:MaterialIcon Kind="ChevronDoubleLeft" Width="16" Height="16" Opacity="0.6"/>
            </Button>
        </Border>

    </Panel>

</UserControl>
```

**Flyout content (connections popover):**

```xml
<Border Padding="4,4,4,8" MinWidth="180">
    <StackPanel>
        <!-- "Connections" header -->
        <TextBlock Text="Connections" FontSize="11" Opacity="0.5" Margin="12,8,12,4"/>
        <Separator/>

        <!-- Active transports (shown when HasActiveConnections) -->
        <ItemsControl IsVisible="{Binding HasActiveConnections}"
                      ItemsSource="{Binding ActiveTransports}">
            <ItemsControl.ItemTemplate>
                <DataTemplate DataType="models:TransportInfo">
                    <StackPanel Orientation="Horizontal" Spacing="8" Margin="12,6,12,0">
                        <Border Width="8" Height="8" CornerRadius="4"
                                Background="{Binding ColorHex}"/>
                        <TextBlock FontSize="13">
                            <Run Text="{Binding Name}"/>
                            <Run Text=": "/>
                            <Run Text="{Binding Count}"/>
                        </TextBlock>
                    </StackPanel>
                </DataTemplate>
            </ItemsControl.ItemTemplate>
        </ItemsControl>

        <!-- "No Active Connections" (shown when !HasActiveConnections) -->
        <StackPanel IsVisible="{Binding !HasActiveConnections}"
                    Orientation="Horizontal" Spacing="8" Margin="12,6">
            <avalonia:MaterialIcon Kind="AccessPointOff" Width="16" Height="16" Opacity="0.5"/>
            <TextBlock Text="No Active Connections" Opacity="0.6" FontSize="13"/>
        </StackPanel>
    </StackPanel>
</Border>
```

**Code-behind (`DetailBottomBar.axaml.cs`):**

```csharp
public partial class DetailBottomBar : UserControl
{
    public static readonly StyledProperty<bool> IsCollapsedProperty =
        AvaloniaProperty.Register<DetailBottomBar, bool>(nameof(IsCollapsed));

    public bool IsCollapsed
    {
        get => GetValue(IsCollapsedProperty);
        set => SetValue(IsCollapsedProperty, value);
    }

    public DetailBottomBar() => InitializeComponent();

    private void CollapseButton_Click(object? sender, RoutedEventArgs e) => IsCollapsed = true;
    private void ExpandButton_Click(object? sender, RoutedEventArgs e) => IsCollapsed = false;
}
```

**Note on Flyout colour:** The `Border.Background` in the `Flyout` should use `{DynamicResource SukiCardBackground}` or `{DynamicResource SukiBackground}` to respect light/dark mode. The bar background of `#B0202028` works in dark mode but not light mode. Use a SukiUI theme-aware approach: define a resource or use conditional styles. See "Theme Note" below.

### Theme Note (Light/Dark compatibility)

Avalonia 11 cannot do native glass blur. We approximate using:
- **Dark:** semi-transparent near-black with slight blue tint: `#B0161B26`
- **Light:** semi-transparent white: `#CCF5F5F5`

The cleanest approach in SukiUI is to add two `Style` blocks in `App.axaml` or `DetailBottomBar.axaml` that target `Theme.IsLightTheme`:

```xml
<UserControl.Styles>
    <Style Selector="Border.GlassBar">
        <Setter Property="Background" Value="#B0161B26"/>
    </Style>
</UserControl.Styles>
```

And rely on SukiUI's `SukiTheme.ThemeColor` or `ActualThemeVariant`. Alternatively, define a `DynamicResource GlassBarBackground` in `App.axaml` with separate light/dark values using `ThemeVariantScope`. This detail should be resolved during implementation with reference to the Avalonia theming docs.

---

## Part 5 — EdgeStudioView.axaml Changes

### Remove Row 2 (status bar)

Remove the entire `<Border Grid.Row="2" ...>` block (lines 320–348) and remove the third `RowDefinition`.

### Overlay the DetailBottomBar

Replace the detail-area `Border` (Column 4):

**Before:**
```xml
<Border Grid.Column="4" Background="#05000000">
    <ContentControl Content="{Binding CurrentDetailViewModel}">
        ...
    </ContentControl>
</Border>
```

**After:**
```xml
<Grid Grid.Column="4">
    <!-- Existing detail content -->
    <Border Background="#05000000">
        <ContentControl Content="{Binding CurrentDetailViewModel}">
            ...
        </ContentControl>
    </Border>

    <!-- Floating bottom bar overlay -->
    <controls:DetailBottomBar
        DataContext="{Binding ConnectionsByTransport}"
        VerticalAlignment="Bottom"
        HorizontalAlignment="Center"
        Margin="0,0,0,12"
        IsVisible="{Binding $parent[UserControl].DataContext.SelectedDatabase, Converter={x:Static ObjectConverters.IsNotNull}}"/>
</Grid>
```

Add `xmlns:controls="using:EdgeStudio.Views.Controls"` to `EdgeStudioView.axaml`.

The `IsVisible` binding hides the bar when no database is connected (matching the existing Row 2 behaviour — it was always visible once a database was open).

---

## Part 6 — DI Registration

No new services need registration. The `ISystemRepository` is already registered as a singleton. The only DI change is:

In `App.axaml.cs`, update the `EdgeStudioViewModel` factory to pass `Lazy<ISystemRepository>`:

```csharp
services.AddTransient<EdgeStudioViewModel>(sp => new EdgeStudioViewModel(
    sp.GetRequiredService<IDittoManager>(),
    sp.GetRequiredService<ISyncService>(),
    sp.GetRequiredService<INavigationService>(),
    sp.GetRequiredService<Lazy<NavigationViewModel>>(),
    sp.GetRequiredService<Lazy<SubscriptionViewModel>>(),
    sp.GetRequiredService<Lazy<SubscriptionDetailsViewModel>>(),
    sp.GetRequiredService<Lazy<QueryViewModel>>(),
    sp.GetRequiredService<Lazy<ObserversViewModel>>(),
    sp.GetRequiredService<Lazy<ToolsViewModel>>(),
    new Lazy<ISystemRepository>(sp.GetRequiredService<ISystemRepository>),  // NEW
    sp.GetService<IToastService>()
));
```

---

## New & Modified File Summary

| File | Action |
|------|--------|
| `EdgeStudio.Shared/Models/ConnectionsByTransport.cs` | **NEW** — model + TransportInfo |
| `EdgeStudio/Views/Controls/DetailBottomBar.axaml` | **NEW** — glass bar UserControl |
| `EdgeStudio/Views/Controls/DetailBottomBar.axaml.cs` | **NEW** — code-behind (IsCollapsed property) |
| `EdgeStudio.Shared/Data/Repositories/ISystemRepository.cs` | Add `CurrentConnections` + `ConnectionsChanged` event |
| `EdgeStudio.Shared/Data/Repositories/SystemRepository.cs` | Compute and publish connection counts in observer |
| `EdgeStudio/ViewModels/EdgeStudioViewModel.cs` | Add `ConnectionsByTransport` property + subscribe to repo event |
| `EdgeStudio/Views/EdgeStudioView.axaml` | Remove Row 2, overlay `DetailBottomBar` on detail panel |
| `EdgeStudio/App.axaml.cs` | Pass `Lazy<ISystemRepository>` to `EdgeStudioViewModel` |

---

## Verification

1. `dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal` — zero errors
2. `dotnet test EdgeStudioTests/EdgeStudioTests.csproj` — all tests pass
3. Run the app:
   - Solid-colored status bar at the bottom is gone
   - A floating pill-shaped semi-transparent bar appears at the bottom of the detail panel
   - Collapsed state: single chevron, right-aligned
   - Click chevron → bar expands showing antenna icon + connection count
   - Click antenna icon → flyout shows per-transport counts
   - Bar appears on all three detail areas: Query, Subscription/Peers, Observer
   - Bar hidden when no database is connected
4. Toggle between light and dark OS themes — bar remains legible in both

---

## Out of Scope (Phase 1)

- **Middle content slot** (pagination controls in Query and Observer views) — no equivalent in .NET yet, not needed for v1
- **Spring animation** — Avalonia 11 transitions are defined differently; basic `IsVisible` toggle is acceptable for v1 (can add `Transitions` with `BoolTransition` later)
- **Ditto Server connection count** — requires more SDK investigation to distinguish server vs peer WebSocket connections; defaults to 0 for now with a `// TODO` comment
