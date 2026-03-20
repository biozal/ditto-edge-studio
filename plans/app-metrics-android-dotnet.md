# App Metrics — Android & .NET Implementation Plan

**Status:** Draft — Pending Review
**Date:** 2026-03-19
**Reference:** SwiftUI implementation in `SwiftUI/Edge Debug Helper/Views/Metrics/`

---

## 1. Goal

Implement the App Metrics feature on Android and .NET to match the SwiftUI version in functionality and visual structure. Both platforms already have navigation stubs and partial data foundations; this plan fills the gaps.

---

## 2. SwiftUI Reference Summary

The SwiftUI App Metrics feature consists of two screens accessible via sidebar buttons (shown when Metrics collection is enabled):

### App Metrics Screen
Three sections displayed in a card grid with 15-second auto-refresh:

| Section | Metrics |
|---------|---------|
| **Process** (macOS only) | Resident memory, virtual memory, CPU time, open file descriptors, process uptime |
| **Queries** | Total queries executed, average latency, last latency (with mini line chart) |
| **Storage** | Store, Replication, Attachments, Auth, WAL/SHM, Logs, Other (from `ditto.diskUsage`), plus per-collection breakdown |

### Query Metrics Screen
Two-column layout (40% list / 60% detail):
- **Left:** Scrollable list of executed queries (timestamp, execution time, color-coded, query text preview)
- **Right:** Detail panel — full DQL, stat badges (Time, Results, Index, Timestamp), EXPLAIN JSON output
- Clear all button, refresh button, empty state

### Settings Toggle
"Collect Metrics" toggle in preferences — when off, disables capture, hides sidebar buttons.

---

## 3. Current State Assessment

### Android — What Exists
| Component | Status |
|-----------|--------|
| Nav tab `APP_METRICS` in `StudioNavItem` enum | ✅ Defined |
| Nav tab `QUERY_METRICS` in `StudioNavItem` enum | ✅ Defined |
| `QueryMetricsEntity` Room table | ✅ Exists |
| `QueryMetricsRepository` interface + impl | ✅ Exists |
| `QueryMetrics` domain model (13 fields) | ✅ Exists |
| Metrics capture in `QueryEditorViewModel` | ✅ Exists |
| `QueryMetricsInspector.kt` (inspector sidebar card) | ✅ Exists |
| App Metrics repository | ❌ Missing |
| App Metrics domain model | ❌ Missing |
| App Metrics UI screen | ❌ Missing |
| App Metrics ViewModel | ❌ Missing |
| Query Metrics full-page UI (`APP_METRICS` tab routed) | ❌ Missing |
| `QUERY_METRICS` tab routed in `MainStudioScreen` | ❌ Missing |
| `APP_METRICS` tab routed in `MainStudioScreen` | ❌ Missing |

### .NET — What Exists
| Component | Status |
|-----------|--------|
| `AppMetricsViewModel.cs` | ⚠️ Empty stub |
| `AppMetricsDetailView.axaml` | ⚠️ "Coming soon" stub |
| `QueryMetricsViewModel.cs` | ✅ Mostly complete |
| `QueryMetric.cs` domain model | ✅ Complete |
| `IQueryMetricsService` + `InMemoryQueryMetricsService` | ✅ Complete (in-memory only) |
| `QueryMetricsView.axaml` (inspector card) | ✅ Implemented |
| `QueryMetricsDetailView.axaml` | ⚠️ "Coming soon" stub |
| App metrics service/repository | ❌ Missing |
| App metrics domain model | ❌ Missing |
| Query capture wired into `QueryViewModel` | ❌ Missing |
| Storage breakdown service | ❌ Missing |

---

## 4. Android Implementation Plan

### Phase A — App Metrics (New Feature)

#### A1 — Domain Model
**New file:** `domain/model/AppMetrics.kt`

```kotlin
data class AppMetrics(
    val capturedAt: Instant,
    // Process
    val residentMemoryBytes: Long,
    val virtualMemoryBytes: Long,
    val cpuTimeSeconds: Double,
    val openFileDescriptors: Int,
    val processUptimeSeconds: Long,
    // Queries
    val totalQueryCount: Int,
    val avgQueryLatencyMs: Double,
    val lastQueryLatencyMs: Double?,
    // Storage
    val storeBytes: Long,
    val replicationBytes: Long,
    val attachmentsBytes: Long,
    val authBytes: Long,
    val walShmBytes: Long,
    val logsBytes: Long,
    val otherBytes: Long,
    val collectionBreakdown: List<CollectionStorageInfo>
)

data class CollectionStorageInfo(
    val collectionName: String,
    val documentCount: Int,
    val estimatedBytes: Long
)
```

#### A2 — App Metrics Repository
**New interface:** `data/repository/AppMetricsRepository.kt`
**New impl:** `data/repository/AppMetricsRepositoryImpl.kt`

Key methods:
- `suspend fun snapshot(): AppMetrics` — collects all metrics at a point in time

**Process metrics** — use Android APIs:
- `Debug.MemoryInfo` → `getTotalPrivateDirty()` for resident memory
- `/proc/self/status` → `VmSize`, `VmRSS` for virtual/resident memory
- `Debug.threadCpuTimeNanos()` for CPU time
- `/proc/self/fd` directory count for open file descriptors
- `SystemClock.elapsedRealtime()` for uptime

**Storage metrics** — use Ditto disk usage API:
- `ditto.diskUsage.exec()` → iterate recursive `DiskUsageItem` tree
- Categorize by path prefix: `ditto_store/`, `ditto_replication/`, `ditto_attachments/`, `ditto_auth/`, `.wal`/`.shm`, `ditto_logs/`

**Collection breakdown** — DQL:
```kotlin
ditto.store.execute("SELECT * FROM system:collections")
// For each collection:
ditto.store.execute("SELECT * FROM $collectionName")
// Estimate bytes from document CBOR serialization
```

#### A3 — App Metrics ViewModel
**New file:** `viewmodel/AppMetricsViewModel.kt`

```kotlin
class AppMetricsViewModel(
    private val appMetricsRepository: AppMetricsRepository
) : ViewModel() {
    val metrics = MutableStateFlow<AppMetrics?>(null)
    val lastUpdated = MutableStateFlow<Instant?>(null)
    val isLoading = MutableStateFlow(false)

    fun startAutoRefresh() {
        viewModelScope.launch {
            while (true) {
                refresh()
                delay(15_000)
            }
        }
    }

    suspend fun refresh() { ... }
}
```

#### A4 — App Metrics Screen UI
**New file:** `ui/mainstudio/metrics/AppMetricsScreen.kt`

Layout (Jetpack Compose):
```
Column {
    // Header row
    Row {
        Text("App Metrics")
        Spacer()
        Text("Updated X ago")  // relative timestamp
        IconButton(refresh) { ... }
    }
    Divider()

    // Scrollable content
    LazyColumn {
        // Process Section
        item { SectionHeader("Process") }
        item {
            LazyVerticalGrid(columns = Fixed(2)) {
                MetricCard("Resident Memory", value, icon)
                MetricCard("Virtual Memory", value, icon)
                MetricCard("CPU Time", value, icon)
                MetricCard("Open File Descriptors", value, icon)
                MetricCard("Uptime", value, icon)
            }
        }

        // Query Section
        item { SectionHeader("Queries") }
        item {
            LazyVerticalGrid(columns = Fixed(2)) {
                MetricCard("Total Queries", value, icon)
                MetricCard("Avg Latency", value, icon)  // with mini chart
                MetricCard("Last Latency", value, icon)
            }
        }

        // Storage Section
        item { SectionHeader("Storage") }
        item {
            LazyVerticalGrid(columns = Fixed(2)) {
                MetricCard("Store", value, icon)
                MetricCard("Replication", value, icon)
                MetricCard("Attachments", value, icon)
                MetricCard("Auth", value, icon)
                MetricCard("WAL/SHM", value, icon)
                MetricCard("Logging", value, icon)
                MetricCard("Other", value, icon)
            }
        }

        // Collections Breakdown (if data exists)
        item { SectionHeader("Collections") }
        items(metrics.collectionBreakdown) { info ->
            CollectionStorageCard(info)
        }
    }
}
```

#### A5 — Reusable MetricCard Component
**New file:** `ui/mainstudio/metrics/MetricCard.kt`

```kotlin
@Composable
fun MetricCard(
    title: String,
    value: String,
    icon: ImageVector,
    subtitle: String? = null,
    chartData: List<Float>? = null  // for latency sparkline
) {
    Card(
        modifier = Modifier.fillMaxWidth().padding(4.dp),
        elevation = CardDefaults.cardElevation(2.dp)
    ) {
        Column(modifier = Modifier.padding(12.dp)) {
            Row(verticalAlignment = CenterVertically) {
                Icon(icon, contentDescription = null, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            Text(value, style = MaterialTheme.typography.titleLarge.copy(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold))
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall)
            if (chartData != null) SparkLineChart(chartData)
        }
    }
}
```

#### A6 — Query Metrics Full-Page Screen
**New file:** `ui/mainstudio/metrics/QueryMetricsScreen.kt`

Layout matching SwiftUI `QueryMetricsDetailView`:
```
Column {
    // Header
    Row {
        Text("Query Metrics")
        Spacer()
        Text("${records.size} records")
        IconButton(clear) { viewModel.clearAll() }
        IconButton(refresh) { viewModel.loadRecords() }
    }
    Divider()

    if (records.isEmpty()) {
        // Empty state
        ContentUnavailableView(message = "No queries have been executed yet")
    } else {
        // 2-panel layout (on tablet: side by side; on phone: list → detail navigation)
        Row {
            // Left: query list (40%)
            LazyColumn(modifier = Modifier.weight(0.4f)) {
                items(records) { record ->
                    QueryMetricsListRow(record, isSelected = record == selectedRecord) {
                        selectedRecord = record
                    }
                }
            }
            VerticalDivider()
            // Right: detail panel (60%)
            QueryMetricsDetailPanel(selectedRecord, modifier = Modifier.weight(0.6f))
        }
    }
}
```

`QueryMetricsDetailPanel` shows (matching SwiftUI):
- DQL statement (selectable, monospaced)
- Stat badges: Time (color-coded), Results, Index Used (✓/✗), Timestamp
- EXPLAIN Output section (expandable JSON)

#### A7 — Wire up in MainStudioScreen
**Edit:** `ui/mainstudio/MainStudioScreen.kt`

In the content area's `when (selectedNavItem)` block, add:
```kotlin
StudioNavItem.APP_METRICS -> AppMetricsScreen(viewModel = appMetricsViewModel)
StudioNavItem.QUERY_METRICS -> QueryMetricsScreen(viewModel = queryMetricsViewModel)
```

#### A8 — Settings Toggle
**Edit:** `ui/settings/AppPreferencesView.kt` (or wherever preferences are shown)

Add toggle: "Collect Metrics" backed by a `DataStore<Preferences>` boolean key `metricsEnabled`.

When disabled:
- Query metrics capture skipped in `QueryEditorViewModel`
- App Metrics / Query Metrics tabs hidden from sidebar

#### A9 — DI Registration
**Edit:** `data/di/DataModule.kt`

Register `AppMetricsRepository` and `AppMetricsViewModel` with Koin.

---

### Phase B — Android Test Requirements

New files in `androidTest/` or `test/`:
- `AppMetricsRepositoryTest.kt` — unit tests for metric snapshot collection
- `AppMetricsViewModelTest.kt` — tests for auto-refresh, state updates
- `MetricCardTest.kt` — screenshot/composable tests for MetricCard UI

---

## 5. .NET Implementation Plan

### Phase A — App Metrics (From Stub to Full)

#### A1 — Domain Models
**New file:** `EdgeStudio.Shared/Models/AppMetricsSnapshot.cs`

```csharp
public record AppMetricsSnapshot(
    DateTimeOffset CapturedAt,
    // Process
    long ResidentMemoryBytes,
    long VirtualMemoryBytes,
    double CpuTimeSeconds,
    int OpenHandleCount,
    TimeSpan ProcessUptime,
    // Queries
    int TotalQueryCount,
    double AvgQueryLatencyMs,
    double? LastQueryLatencyMs,
    // Storage
    long StoreBytes,
    long ReplicationBytes,
    long AttachmentsBytes,
    long AuthBytes,
    long WalShmBytes,
    long LogsBytes,
    long OtherBytes,
    IReadOnlyList<CollectionStorageInfo> CollectionBreakdown
);

public record CollectionStorageInfo(
    string CollectionName,
    int DocumentCount,
    long EstimatedBytes
);
```

**New file:** `EdgeStudio.Shared/Models/MetricSample.cs`

```csharp
public record MetricSample(DateTimeOffset Timestamp, double Value);
```

#### A2 — App Metrics Service
**New interface:** `EdgeStudio.Shared/Data/IAppMetricsService.cs`

```csharp
public interface IAppMetricsService
{
    Task<AppMetricsSnapshot> GetSnapshotAsync(CancellationToken ct = default);
    IReadOnlyList<MetricSample> GetLatencySamples();
    void RecordQueryLatency(double latencyMs);
    void IncrementQueryCount();
}
```

**New implementation:** `EdgeStudio.Shared/Data/AppMetricsService.cs`

```csharp
public class AppMetricsService : IAppMetricsService
{
    private readonly IDittoManager _dittoManager;
    private readonly Process _currentProcess = Process.GetCurrentProcess();
    private readonly DateTimeOffset _startTime = DateTimeOffset.UtcNow;
    private int _queryCount = 0;
    private readonly RingBuffer<MetricSample> _latencySamples = new(120);

    public async Task<AppMetricsSnapshot> GetSnapshotAsync(...)
    {
        _currentProcess.Refresh();

        // Process metrics (System.Diagnostics)
        var residentMemory = _currentProcess.WorkingSet64;
        var virtualMemory = _currentProcess.VirtualMemorySize64;
        var cpuTime = _currentProcess.TotalProcessorTime.TotalSeconds;
        var handleCount = _currentProcess.HandleCount;
        var uptime = DateTimeOffset.UtcNow - _startTime;

        // Storage metrics (Ditto disk usage API)
        var storageBreakdown = await FetchStorageBreakdownAsync(ct);

        // Collection breakdown
        var collectionBreakdown = await FetchCollectionBreakdownAsync(ct);

        return new AppMetricsSnapshot(
            CapturedAt: DateTimeOffset.UtcNow,
            ResidentMemoryBytes: residentMemory,
            VirtualMemoryBytes: virtualMemory,
            CpuTimeSeconds: cpuTime,
            OpenHandleCount: handleCount,
            ProcessUptime: uptime,
            TotalQueryCount: _queryCount,
            AvgQueryLatencyMs: _latencySamples.Average(),
            LastQueryLatencyMs: _latencySamples.Latest?.Value,
            // ... storage fields
        );
    }

    private async Task<StorageBreakdown> FetchStorageBreakdownAsync(...)
    {
        // Use Ditto.DiskUsage API, categorize by path prefix
        var items = await _dittoManager.GetDiskUsageAsync(ct);
        // Categorize: ditto_store/, ditto_replication/, ditto_attachments/, etc.
    }

    private async Task<IReadOnlyList<CollectionStorageInfo>> FetchCollectionBreakdownAsync(...)
    {
        // DQL: SELECT * FROM system:collections
        // For each collection: query all docs, estimate CBOR size
    }
}
```

**Note on process metrics:** `System.Diagnostics.Process` works on Windows, macOS, and Linux. On Linux it reads from `/proc`. No platform-specific code needed beyond the standard API.

#### A3 — Update AppMetricsViewModel
**Edit:** `EdgeStudio/ViewModels/AppMetricsViewModel.cs`

Replace empty stub with full implementation:

```csharp
public partial class AppMetricsViewModel : LoadableViewModelBase
{
    private readonly IAppMetricsService _metricsService;
    private CancellationTokenSource? _refreshCts;

    [ObservableProperty] private AppMetricsSnapshot? _currentSnapshot;
    [ObservableProperty] private string _lastUpdatedText = "Never";

    public AppMetricsViewModel(IAppMetricsService metricsService) { ... }

    public async Task StartAutoRefreshAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await RefreshAsync();
            await Task.Delay(TimeSpan.FromSeconds(15), ct);
        }
    }

    [RelayCommand]
    public async Task RefreshAsync()
    {
        CurrentSnapshot = await _metricsService.GetSnapshotAsync();
        LastUpdatedText = FormatRelativeTime(CurrentSnapshot.CapturedAt);
    }
}
```

#### A4 — App Metrics Detail View (AXAML)
**Edit:** `EdgeStudio/Views/Metrics/AppMetricsDetailView.axaml`

Replace stub with full layout:

```xml
<UserControl ...>
  <DockPanel>
    <!-- Header Bar -->
    <Border DockPanel.Dock="Top" ...>
      <Grid ColumnDefinitions="*,Auto,Auto">
        <TextBlock Text="App Metrics" FontWeight="Bold" FontSize="16"/>
        <TextBlock Grid.Column="1" Text="{Binding LastUpdatedText}" Opacity="0.6"/>
        <Button Grid.Column="2" Command="{Binding RefreshCommand}">
          <!-- Refresh icon -->
        </Button>
      </Grid>
    </Border>
    <Separator DockPanel.Dock="Top"/>

    <!-- Scrollable Content -->
    <ScrollViewer>
      <StackPanel Spacing="16" Margin="16">

        <!-- Process Section -->
        <TextBlock Text="Process" Classes="SectionHeader"/>
        <WrapPanel>
          <MetricCard Title="Resident Memory" Value="{Binding CurrentSnapshot.ResidentMemoryFormatted}"/>
          <MetricCard Title="Virtual Memory" Value="{Binding CurrentSnapshot.VirtualMemoryFormatted}"/>
          <MetricCard Title="CPU Time" Value="{Binding CurrentSnapshot.CpuTimeFormatted}"/>
          <MetricCard Title="Open Handles" Value="{Binding CurrentSnapshot.OpenHandleCount}"/>
          <MetricCard Title="Uptime" Value="{Binding CurrentSnapshot.UptimeFormatted}"/>
        </WrapPanel>

        <!-- Query Section -->
        <TextBlock Text="Queries" Classes="SectionHeader"/>
        <WrapPanel>
          <MetricCard Title="Total Queries" Value="{Binding CurrentSnapshot.TotalQueryCount}"/>
          <MetricCard Title="Avg Latency" Value="{Binding CurrentSnapshot.AvgLatencyFormatted}"/>
          <MetricCard Title="Last Latency" Value="{Binding CurrentSnapshot.LastLatencyFormatted}"/>
        </WrapPanel>

        <!-- Storage Section -->
        <TextBlock Text="Storage" Classes="SectionHeader"/>
        <WrapPanel>
          <MetricCard Title="Store" Value="{Binding CurrentSnapshot.StoreBytesFormatted}"/>
          <MetricCard Title="Replication" Value="{Binding CurrentSnapshot.ReplicationBytesFormatted}"/>
          <MetricCard Title="Attachments" Value="{Binding CurrentSnapshot.AttachmentsBytesFormatted}"/>
          <MetricCard Title="Auth" Value="{Binding CurrentSnapshot.AuthBytesFormatted}"/>
          <MetricCard Title="WAL/SHM" Value="{Binding CurrentSnapshot.WalShmBytesFormatted}"/>
          <MetricCard Title="Logging" Value="{Binding CurrentSnapshot.LogsBytesFormatted}"/>
          <MetricCard Title="Other" Value="{Binding CurrentSnapshot.OtherBytesFormatted}"/>
        </WrapPanel>

        <!-- Collections Breakdown -->
        <TextBlock Text="Collections" Classes="SectionHeader"/>
        <ItemsControl ItemsSource="{Binding CurrentSnapshot.CollectionBreakdown}">
          <ItemsControl.ItemTemplate>
            <DataTemplate>
              <MetricCard Title="{Binding CollectionName}" Value="{Binding EstimatedBytesFormatted}" Subtitle="{Binding DocumentCountFormatted}"/>
            </DataTemplate>
          </ItemsControl.ItemTemplate>
        </ItemsControl>

      </StackPanel>
    </ScrollViewer>
  </DockPanel>
</UserControl>
```

#### A5 — Reusable MetricCard Control
**New file:** `EdgeStudio/Views/Controls/MetricCard.axaml`

```xml
<UserControl x:Class="EdgeStudio.Views.Controls.MetricCard" ...>
  <Border CornerRadius="8" Background="{DynamicResource SukiCardBackground}" BorderBrush="{DynamicResource SukiLightBorderBrush}" BorderThickness="1" Padding="12" Width="160" Height="100">
    <StackPanel Spacing="4">
      <TextBlock Text="{TemplateBinding Title}" FontSize="11" Opacity="0.6"/>
      <TextBlock Text="{TemplateBinding Value}" FontSize="22" FontWeight="Bold" FontFamily="Monospace"/>
      <TextBlock Text="{TemplateBinding Subtitle}" FontSize="11" Opacity="0.6"/>
    </StackPanel>
  </Border>
</UserControl>
```

Code-behind adds `Title`, `Value`, `Subtitle` dependency properties.

### Phase B — Query Metrics (Fix Integration + UI)

#### B1 — Wire Capture into QueryViewModel
**Edit:** `EdgeStudio/ViewModels/QueryViewModel.cs`

After executing a query, call:
```csharp
await _queryMetricsService.CaptureAsync(new QueryMetric(
    Id: Guid.NewGuid(),
    DqlQuery: queryText,
    ExecutionTimeMs: elapsedMs,
    ResultCount: results.Count,
    ExplainOutput: explainJson,
    Timestamp: DateTimeOffset.UtcNow
));
_appMetricsService.RecordQueryLatency(elapsedMs);
_appMetricsService.IncrementQueryCount();
```

Also run `EXPLAIN <query>` after each query execution to populate explain output.

#### B2 — Query Metrics Detail View (Replace Stub)
**Edit:** `EdgeStudio/Views/StudioView/Details/QueryMetricsDetailView.axaml`

Replace stub with full 2-column layout:

```xml
<Grid ColumnDefinitions="0.4*,1,0.6*">
  <!-- Left: Query List -->
  <DockPanel Grid.Column="0">
    <Border DockPanel.Dock="Top">
      <Grid ColumnDefinitions="*,Auto,Auto">
        <TextBlock Text="Query Metrics" FontWeight="Bold"/>
        <TextBlock Grid.Column="1" Text="{Binding RecordCountText}" Opacity="0.6"/>
        <Button Grid.Column="2" Command="{Binding ClearAllCommand}" ToolTip.Tip="Clear All">
          <!-- Trash icon -->
        </Button>
      </Grid>
    </Border>
    <Separator DockPanel.Dock="Top"/>

    <!-- Empty State -->
    <TextBlock IsVisible="{Binding !HasRecords}" Text="No queries executed yet" HorizontalAlignment="Center" VerticalAlignment="Center"/>

    <!-- Query List -->
    <ListBox IsVisible="{Binding HasRecords}" ItemsSource="{Binding Records}" SelectedItem="{Binding SelectedRecord}">
      <ListBox.ItemTemplate>
        <DataTemplate>
          <StackPanel Spacing="2" Margin="0,4">
            <TextBlock Text="{Binding FormattedTimestamp}" FontSize="10" Opacity="0.6"/>
            <StackPanel Orientation="Horizontal" Spacing="8">
              <TextBlock Text="{Binding FormattedExecutionTime}" FontWeight="SemiBold" Foreground="{Binding ExecutionTimeColor}"/>
              <TextBlock Text="{Binding IndexIndicator}" Opacity="0.7"/>
            </StackPanel>
            <TextBlock Text="{Binding DqlQuery}" MaxLines="2" TextWrapping="Wrap" FontSize="11" Opacity="0.8"/>
          </StackPanel>
        </DataTemplate>
      </ListBox.ItemTemplate>
    </ListBox>
  </DockPanel>

  <!-- Divider -->
  <Separator Grid.Column="1" Width="1"/>

  <!-- Right: Detail Panel -->
  <ScrollViewer Grid.Column="2">
    <StackPanel Spacing="12" Margin="16" IsVisible="{Binding SelectedRecord, Converter={x:Static ObjectConverters.IsNotNull}}">
      <!-- DQL Statement -->
      <TextBlock Text="DQL Statement" Classes="SectionHeader"/>
      <SelectableTextBlock Text="{Binding SelectedRecord.DqlQuery}" FontFamily="Monospace" TextWrapping="Wrap"/>

      <!-- Stat Badges -->
      <WrapPanel Spacing="8">
        <Border Classes="StatBadge">
          <StackPanel>
            <TextBlock Text="Time" Opacity="0.6" FontSize="10"/>
            <TextBlock Text="{Binding SelectedRecord.FormattedExecutionTime}" Foreground="{Binding SelectedRecord.ExecutionTimeColor}" FontWeight="Bold"/>
          </StackPanel>
        </Border>
        <Border Classes="StatBadge">
          <StackPanel>
            <TextBlock Text="Results" Opacity="0.6" FontSize="10"/>
            <TextBlock Text="{Binding SelectedRecord.ResultCount}" FontWeight="Bold"/>
          </StackPanel>
        </Border>
        <Border Classes="StatBadge">
          <StackPanel>
            <TextBlock Text="Index Used" Opacity="0.6" FontSize="10"/>
            <TextBlock Text="{Binding SelectedRecord.IndexUsedText}" FontWeight="Bold"/>
          </StackPanel>
        </Border>
        <Border Classes="StatBadge">
          <StackPanel>
            <TextBlock Text="Timestamp" Opacity="0.6" FontSize="10"/>
            <TextBlock Text="{Binding SelectedRecord.FormattedTimestamp}" FontWeight="Bold"/>
          </StackPanel>
        </Border>
      </WrapPanel>

      <!-- EXPLAIN Output -->
      <TextBlock Text="EXPLAIN Output" Classes="SectionHeader"/>
      <SelectableTextBlock Text="{Binding SelectedRecord.ExplainOutput}" FontFamily="Monospace" FontSize="11" TextWrapping="Wrap" Opacity="0.9"/>
    </StackPanel>
  </ScrollViewer>
</Grid>
```

#### B3 — Update QueryMetricsViewModel
**Edit:** `EdgeStudio/ViewModels/QueryMetricsViewModel.cs`

Add:
- `Records` observable collection
- `SelectedRecord` observable property
- `HasRecords` computed property
- `RecordCountText` computed property
- `ClearAllCommand` relay command
- Color computation for execution time (green <10ms, orange ≥100ms, default otherwise)

#### B4 — DI Registration
**Edit:** `EdgeStudio/App.axaml.cs` (or wherever services are registered)

```csharp
services.AddSingleton<IAppMetricsService, AppMetricsService>();
// IQueryMetricsService already registered
services.AddTransient<AppMetricsViewModel>();
// QueryMetricsViewModel already registered
```

### Phase C — Settings Toggle (.NET)

**Edit:** Preferences/settings view (wherever app preferences are shown)

Add toggle: "Collect Metrics" backed by a persistent setting (user preferences file or local DB).

When disabled:
- `QueryViewModel` skips `_queryMetricsService.CaptureAsync()`
- App Metrics / Query Metrics items hidden in sidebar

---

## 6. MetricCard Design Spec (Both Platforms)

Both platforms should render metric cards consistently:

```
┌──────────────────────────────┐
│ 🔷 TITLE                     │
│                              │
│  VALUE                       │
│  (monospaced, bold, large)   │
│                              │
│  subtitle (optional)         │
│  [sparkline chart]           │  ← query latency only
└──────────────────────────────┘
```

| Property | Android | .NET |
|----------|---------|------|
| Card background | `Card` with `elevation = 2dp` | `SukiCardBackground` brush |
| Title | `MaterialTheme.typography.labelSmall`, secondary color | 11pt, 60% opacity |
| Value | `titleLarge`, monospace, bold | 22pt, monospace, bold |
| Width | ~`(screenWidth / 2) - padding` | 160dp fixed |
| Chart | `Canvas`-based sparkline | Livecharts2 or custom `Canvas` |

---

## 7. Storage Breakdown Algorithm (Both Platforms)

Both platforms must implement the same categorization logic as SwiftUI:

```
ditto.diskUsage → iterate file tree
For each DiskUsageItem:
  if path contains "ditto_store/"     → storeBytes
  if path contains "ditto_replication/"  → replicationBytes
  if path contains "ditto_attachments/"  → attachmentsBytes
  if path contains "ditto_auth/"     → authBytes
  if path ends with ".wal" or ".shm" → walShmBytes
  if path contains "ditto_logs/"     → logsBytes
  else                               → otherBytes
```

Collection breakdown:
```dql
SELECT * FROM system:collections
→ For each collection name:
    SELECT * FROM <collection>
    → Serialize each document to CBOR
    → Sum CBOR byte sizes
    → Record (name, docCount, estimatedBytes)
→ Sort by estimatedBytes descending
```

---

## 8. Execution Time Color Coding (Both Platforms)

Match SwiftUI color logic:

| Execution Time | Color |
|----------------|-------|
| < 10ms | Green |
| 10ms – 99ms | Default (primary text) |
| ≥ 100ms | Orange/Amber |

---

## 9. Settings Persistence

| Platform | Key | Type | Default |
|----------|-----|------|---------|
| Android | `DataStore<Preferences>` key `metrics_enabled` | Boolean | `false` |
| .NET | User preference file or app settings key `MetricsEnabled` | Boolean | `false` |

---

## 10. Files to Create/Edit

### Android — New Files
| File | Description |
|------|-------------|
| `domain/model/AppMetrics.kt` | App metrics domain model |
| `data/repository/AppMetricsRepository.kt` | Repository interface |
| `data/repository/AppMetricsRepositoryImpl.kt` | Repository implementation |
| `viewmodel/AppMetricsViewModel.kt` | ViewModel with auto-refresh |
| `ui/mainstudio/metrics/AppMetricsScreen.kt` | Main metrics UI screen |
| `ui/mainstudio/metrics/MetricCard.kt` | Reusable card composable |
| `ui/mainstudio/metrics/QueryMetricsScreen.kt` | Query metrics full-page view |

### Android — Edited Files
| File | Change |
|------|--------|
| `ui/mainstudio/MainStudioScreen.kt` | Wire APP_METRICS and QUERY_METRICS tabs |
| `data/di/DataModule.kt` | Register AppMetrics dependencies |
| `ui/settings/AppPreferencesView.kt` | Add Collect Metrics toggle |
| `viewmodel/QueryEditorViewModel.kt` | Respect metrics toggle |

### .NET — New Files
| File | Description |
|------|-------------|
| `EdgeStudio.Shared/Models/AppMetricsSnapshot.cs` | App metrics model |
| `EdgeStudio.Shared/Models/MetricSample.cs` | Latency sample model |
| `EdgeStudio.Shared/Data/IAppMetricsService.cs` | Service interface |
| `EdgeStudio.Shared/Data/AppMetricsService.cs` | Service implementation |
| `EdgeStudio/Views/Controls/MetricCard.axaml` | Reusable metric card control |
| `EdgeStudio/Views/Controls/MetricCard.axaml.cs` | MetricCard code-behind |

### .NET — Edited Files
| File | Change |
|------|--------|
| `EdgeStudio/ViewModels/AppMetricsViewModel.cs` | Replace stub with full impl |
| `EdgeStudio/ViewModels/QueryMetricsViewModel.cs` | Add Records, SelectedRecord, Clear |
| `EdgeStudio/Views/Metrics/AppMetricsDetailView.axaml` | Replace stub with full UI |
| `EdgeStudio/Views/StudioView/Details/QueryMetricsDetailView.axaml` | Replace stub with full UI |
| `EdgeStudio/ViewModels/QueryViewModel.cs` | Wire metrics capture |
| `EdgeStudio/App.axaml.cs` | Register AppMetricsService |

---

## 11. Implementation Order

### Recommended Sequence

**Start with .NET (simpler navigation wiring):**
1. Domain models (`AppMetricsSnapshot`, `MetricSample`)
2. `AppMetricsService` implementation
3. `MetricCard` control
4. `AppMetricsViewModel` full implementation
5. `AppMetricsDetailView` full UI
6. Wire `QueryViewModel` to capture metrics
7. `QueryMetricsViewModel` updates
8. `QueryMetricsDetailView` full UI
9. Settings toggle

**Then Android:**
1. Domain model (`AppMetrics`, `CollectionStorageInfo`)
2. `AppMetricsRepositoryImpl`
3. `AppMetricsViewModel`
4. `MetricCard` composable
5. `AppMetricsScreen` composable
6. `QueryMetricsScreen` composable
7. Wire in `MainStudioScreen`
8. Settings toggle + DI registration

---

## 12. Open Questions

1. **Android tablet layout for QueryMetricsScreen:** Should it use a side-by-side 2-column layout on tablets and a drill-down navigation on phones (matching typical Android UX patterns)? Or always use 2-column like SwiftUI iPad?

2. **.NET metric card width:** Should cards use fixed 160dp widths in a `WrapPanel`, or responsive grid columns? The current SwiftUI uses `LazyVGrid` with 2 adaptive columns.

3. **Latency sparkline chart:** SwiftUI uses native Charts framework. For .NET, should we use LiveCharts2 (already a dependency?) or draw a simple custom `Canvas`-based sparkline? For Android, should we use Vico charts or a custom Canvas?

4. **Collection breakdown performance:** Estimating per-collection size by serializing all documents to CBOR could be slow on large datasets. Should there be a document count cap (e.g., sample first 1000 docs)?

5. **Metrics persistence in .NET:** The current `InMemoryQueryMetricsService` loses data on restart. Should query metrics be persisted to a local SQLite file (like Android uses Room) or kept in-memory only (acceptable since SwiftUI resets on restart too)?

---

## 13. Out of Scope

- Process metrics on iOS/iPadOS (SwiftUI also macOS-only for this section)
- Prometheus export endpoint (SwiftUI has this as a backend hook but doesn't expose UI for it)
- Real-time chart streaming (15-second batch refresh is sufficient)
- Metrics sync across databases (metrics are per-session, per-device)
