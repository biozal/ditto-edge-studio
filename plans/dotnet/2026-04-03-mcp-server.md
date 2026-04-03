# MCP Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an embedded MCP (Model Context Protocol) server to the dotnet Edge Studio app, matching the 15-tool API surface of the SwiftUI version, using the official `ModelContextProtocol` C# SDK with ASP.NET Core HTTP/SSE transport.

**Architecture:** Use the official `ModelContextProtocol.AspNetCore` NuGet package which provides tool registration via attributes (`[McpServerToolType]`, `[McpServerTool]`), JSON-RPC 2.0 handling, and SSE transport — all out of the box. The server runs as an embedded `WebApplication` on a background thread, started/stopped based on the `mcpServerEnabled` setting from `ISettingsRepository` (Plan A). Tools inject existing DI services (`IDittoManager`, `IQueryService`, `IDatabaseRepository`, etc.) directly as method parameters. The SDK auto-discovers tools via `WithToolsFromAssembly()`.

**Tech Stack:** C# / ModelContextProtocol.AspNetCore / ASP.NET Core (embedded) / Existing Ditto SDK services

**Prerequisite:** Plan A (Settings Window) must be implemented first — the MCP server reads `mcpServerEnabled` and `mcpServerPort` from `ISettingsRepository`.

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `dotnet/src/EdgeStudio/EdgeStudio.csproj` | Modify | Add `ModelContextProtocol.AspNetCore` NuGet reference |
| `dotnet/src/EdgeStudio/Data/McpServer/McpServerService.cs` | Create | Server lifecycle (start/stop embedded WebApplication) |
| `dotnet/src/EdgeStudio/Data/McpServer/DittoDatabaseTools.cs` | Create | Tools: execute_dql, list_databases, get_active_database, list_collections |
| `dotnet/src/EdgeStudio/Data/McpServer/DittoIndexTools.cs` | Create | Tools: create_index, drop_index, list_indexes |
| `dotnet/src/EdgeStudio/Data/McpServer/DittoSyncTools.cs` | Create | Tools: get_sync_status, configure_transport, set_sync, get_peers |
| `dotnet/src/EdgeStudio/Data/McpServer/DittoMetricsTools.cs` | Create | Tools: get_query_metrics, get_app_logs, get_ditto_logs |
| `dotnet/src/EdgeStudio/Data/McpServer/DittoImportTools.cs` | Create | Tool: insert_documents_from_file |
| `dotnet/src/EdgeStudio/App.axaml.cs` | Modify | Register McpServerService in DI, start/stop on setting change |
| `dotnet/src/EdgeStudioTests/McpToolManifestTests.cs` | Create | Validate tool registration and names |
| `dotnet/src/EdgeStudioTests/McpServerServiceTests.cs` | Create | Test server lifecycle |

---

### Task 1: Add NuGet Package Reference

**Files:**
- Modify: `dotnet/src/EdgeStudio/EdgeStudio.csproj`

- [ ] **Step 1: Add the ModelContextProtocol.AspNetCore package**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet add EdgeStudio/EdgeStudio.csproj package ModelContextProtocol.AspNetCore
```

This will also pull in `ModelContextProtocol` (core) and `Microsoft.Extensions.Hosting` as transitive dependencies.

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/EdgeStudio.csproj
git commit -m "build(dotnet): add ModelContextProtocol.AspNetCore NuGet package for MCP server"
```

---

### Task 2: Create McpServerService (Lifecycle)

**Files:**
- Create: `dotnet/src/EdgeStudio/Data/McpServer/McpServerService.cs`

- [ ] **Step 1: Create the server lifecycle service**

Create `dotnet/src/EdgeStudio/Data/McpServer/McpServerService.cs`:

```csharp
using System;
using System.Threading;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using ModelContextProtocol.AspNetCore;
using ModelContextProtocol.Server;
using Serilog;

namespace EdgeStudio.Data.McpServer;

public class McpServerService : IDisposable
{
    private readonly IServiceProvider _appServices;
    private readonly ISettingsRepository _settings;
    private WebApplication? _webApp;
    private CancellationTokenSource? _cts;
    private Task? _serverTask;

    public bool IsRunning { get; private set; }
    public int Port { get; private set; }

    public McpServerService(IServiceProvider appServices, ISettingsRepository settings)
    {
        _appServices = appServices;
        _settings = settings;
    }

    public async Task StartAsync()
    {
        if (IsRunning) return;

        Port = await _settings.GetIntAsync("mcpServerPort", defaultValue: 65269);

        try
        {
            var builder = WebApplication.CreateBuilder();
            builder.Logging.ClearProviders();

            // Register MCP server with HTTP/SSE transport
            builder.Services.AddMcpServer(options =>
            {
                options.ServerInfo = new()
                {
                    Name = "ditto-edge-studio",
                    Version = "1.0.0"
                };
            })
            .WithHttpTransport()
            .WithToolsFromAssembly(typeof(McpServerService).Assembly);

            // Forward app-level services so MCP tools can resolve them
            builder.Services.AddSingleton(_appServices.GetRequiredService<IDittoManager>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<IQueryService>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<IDatabaseRepository>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<ICollectionsRepository>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<ISystemRepository>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<IQueryMetricsService>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<ILoggingService>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<ISyncService>());
            builder.Services.AddSingleton(_appServices.GetRequiredService<IImportService>());

            _webApp = builder.Build();
            _webApp.MapMcp();

            _cts = new CancellationTokenSource();
            _webApp.Urls.Add($"http://localhost:{Port}");

            _serverTask = _webApp.RunAsync(_cts.Token);
            IsRunning = true;

            Log.Information("MCP server started on port {Port}", Port);
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Failed to start MCP server");
            IsRunning = false;
        }
    }

    public async Task StopAsync()
    {
        if (!IsRunning) return;

        try
        {
            _cts?.Cancel();

            if (_webApp != null)
            {
                await _webApp.StopAsync();
                await _webApp.DisposeAsync();
                _webApp = null;
            }

            if (_serverTask != null)
            {
                try { await _serverTask; } catch (OperationCanceledException) { }
                _serverTask = null;
            }

            _cts?.Dispose();
            _cts = null;
        }
        catch (Exception ex)
        {
            Log.Error(ex, "Error stopping MCP server");
        }
        finally
        {
            IsRunning = false;
            Log.Information("MCP server stopped");
        }
    }

    public void Dispose()
    {
        StopAsync().GetAwaiter().GetResult();
    }
}
```

**Important note for implementer:** The service registrations (IDittoManager, IQueryService, etc.) reference interfaces from the existing project. Check the actual interface locations — some may be in `EdgeStudio.Shared.Data`, others in `EdgeStudio.Data` or `EdgeStudio.Services`. Use the same types already registered in `App.axaml.cs`. Add appropriate `using` statements for each.

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/Data/McpServer/McpServerService.cs
git commit -m "feat(dotnet): add McpServerService lifecycle management"
```

---

### Task 3: Create DittoDatabaseTools (4 tools)

**Files:**
- Create: `dotnet/src/EdgeStudio/Data/McpServer/DittoDatabaseTools.cs`

- [ ] **Step 1: Create the database tools**

Create `dotnet/src/EdgeStudio/Data/McpServer/DittoDatabaseTools.cs`:

```csharp
using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer;

[McpServerToolType]
public static class DittoDatabaseTools
{
    [McpServerTool, Description("Execute a DQL query against the active Ditto database. Supports SELECT, INSERT, UPDATE, EVICT, and ALTER statements.")]
    public static async Task<string> ExecuteDql(
        [Description("The DQL query to execute")] string query,
        [Description("Transport: 'local' (default) for direct SDK, 'http' for HTTP API")] string transport,
        IQueryService queryService)
    {
        if (string.IsNullOrWhiteSpace(query))
            return JsonSerializer.Serialize(new { error = "query parameter is required" });

        var effectiveTransport = string.IsNullOrWhiteSpace(transport) ? "local" : transport.ToLowerInvariant();

        if (effectiveTransport != "local")
            return JsonSerializer.Serialize(new { error = "HTTP transport is not yet supported in the dotnet version. Use transport='local'." });

        var result = await queryService.ExecuteLocalAsync(query);

        if (!string.IsNullOrEmpty(result.ErrorMessage))
            return JsonSerializer.Serialize(new { error = result.ErrorMessage });

        return JsonSerializer.Serialize(new
        {
            query,
            transport = effectiveTransport,
            isMutation = result.IsMutation,
            resultCount = result.ResultCount,
            executionTimeMs = result.ExecutionTimeMs,
            results = result.IsMutation ? result.MutatedDocumentIds : result.JsonDocuments
        });
    }

    [McpServerTool, Description("List all configured Ditto databases (does not include credentials).")]
    public static async Task<string> ListDatabases(
        IDatabaseRepository databaseRepository)
    {
        var configs = await databaseRepository.GetAllDatabaseConfigsAsync();
        var summaries = configs.Select(c => new
        {
            id = c.Id,
            name = c.Name,
            databaseId = c.DatabaseId,
            mode = c.Mode
        });
        return JsonSerializer.Serialize(new { databases = summaries });
    }

    [McpServerTool, Description("Get the currently active (selected) Ditto database configuration.")]
    public static string GetActiveDatabase(
        IDittoManager dittoManager)
    {
        var config = dittoManager.SelectedDatabaseConfig;
        if (config == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        return JsonSerializer.Serialize(new
        {
            id = config.Id,
            name = config.Name,
            databaseId = config.DatabaseId,
            mode = config.Mode
        });
    }

    [McpServerTool, Description("List all collections in the active Ditto database with document counts and indexes.")]
    public static async Task<string> ListCollections(
        ICollectionsRepository collectionsRepository,
        IDittoManager dittoManager)
    {
        if (dittoManager.DittoSelectedApp == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        var collections = await collectionsRepository.GetCollectionsAsync();
        return JsonSerializer.Serialize(new { collections });
    }
}
```

**Note for implementer:** The exact method signatures on `IDatabaseRepository` and `ICollectionsRepository` may differ from what's shown above. Check the actual interfaces:
- `IDatabaseRepository` — look for a method that loads all database configs (may be `LoadDatabaseConfigsAsync()` or `GetAllDatabaseConfigsAsync()`)
- `ICollectionsRepository` — look for a method that returns collection info (may be `RefreshCollectionsAsync()` or `GetCollectionsAsync()`)
- `IQueryService` — confirmed as `ExecuteLocalAsync(string dql)` returning `QueryExecutionResult`

Adjust method names and return type mappings to match the actual interfaces.

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/Data/McpServer/DittoDatabaseTools.cs
git commit -m "feat(dotnet): add MCP database tools (execute_dql, list_databases, get_active_database, list_collections)"
```

---

### Task 4: Create DittoIndexTools (3 tools)

**Files:**
- Create: `dotnet/src/EdgeStudio/Data/McpServer/DittoIndexTools.cs`

- [ ] **Step 1: Create the index tools**

Create `dotnet/src/EdgeStudio/Data/McpServer/DittoIndexTools.cs`:

```csharp
using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer;

[McpServerToolType]
public static class DittoIndexTools
{
    [McpServerTool, Description("Create an index on a field in a collection.")]
    public static async Task<string> CreateIndex(
        [Description("The collection name")] string collection,
        [Description("The field name to index")] string field,
        IQueryService queryService)
    {
        if (string.IsNullOrWhiteSpace(collection) || string.IsNullOrWhiteSpace(field))
            return JsonSerializer.Serialize(new { error = "Both 'collection' and 'field' parameters are required." });

        var dql = $"CREATE INDEX ON {collection} (SORT ASC {field})";
        var result = await queryService.ExecuteLocalAsync(dql);

        if (!string.IsNullOrEmpty(result.ErrorMessage))
            return JsonSerializer.Serialize(new { error = result.ErrorMessage });

        return JsonSerializer.Serialize(new { success = true, collection, field, dql });
    }

    [McpServerTool, Description("Drop an index by name.")]
    public static async Task<string> DropIndex(
        [Description("The index name to drop")] string indexName,
        IQueryService queryService)
    {
        if (string.IsNullOrWhiteSpace(indexName))
            return JsonSerializer.Serialize(new { error = "'index_name' parameter is required." });

        var dql = $"DROP INDEX {indexName}";
        var result = await queryService.ExecuteLocalAsync(dql);

        if (!string.IsNullOrEmpty(result.ErrorMessage))
            return JsonSerializer.Serialize(new { error = result.ErrorMessage });

        return JsonSerializer.Serialize(new { success = true, indexName, dql });
    }

    [McpServerTool, Description("List all indexes across every collection in the active database.")]
    public static async Task<string> ListIndexes(
        ICollectionsRepository collectionsRepository,
        IDittoManager dittoManager)
    {
        if (dittoManager.DittoSelectedApp == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        var collections = await collectionsRepository.GetCollectionsAsync();
        // Extract indexes from collections data — adjust based on actual return type
        return JsonSerializer.Serialize(new { collections });
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/Data/McpServer/DittoIndexTools.cs
git commit -m "feat(dotnet): add MCP index tools (create_index, drop_index, list_indexes)"
```

---

### Task 5: Create DittoSyncTools (4 tools)

**Files:**
- Create: `dotnet/src/EdgeStudio/Data/McpServer/DittoSyncTools.cs`

- [ ] **Step 1: Create the sync tools**

Create `dotnet/src/EdgeStudio/Data/McpServer/DittoSyncTools.cs`:

```csharp
using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer;

[McpServerToolType]
public static class DittoSyncTools
{
    [McpServerTool, Description("Get the current sync status including transport configuration and connected peer count.")]
    public static string GetSyncStatus(
        IDittoManager dittoManager,
        ISystemRepository systemRepository)
    {
        if (dittoManager.DittoSelectedApp == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        var config = dittoManager.SelectedDatabaseConfig;
        return JsonSerializer.Serialize(new
        {
            databaseName = config?.Name,
            databaseId = config?.DatabaseId,
            syncActive = config != null,
            transports = new
            {
                bluetooth = config?.IsBluetoothLeEnabled ?? false,
                lan = config?.IsLanEnabled ?? false,
                awdl = config?.IsAwdlEnabled ?? false,
                cloud = config?.IsCloudSyncEnabled ?? false
            }
        });
    }

    [McpServerTool, Description("Configure sync transports (Bluetooth, LAN, AWDL, Cloud). Only provided parameters are changed; others retain current values.")]
    public static async Task<string> ConfigureTransport(
        [Description("Enable/disable Bluetooth LE")] bool? bluetooth,
        [Description("Enable/disable LAN")] bool? lan,
        [Description("Enable/disable AWDL (Apple only)")] bool? awdl,
        [Description("Enable/disable cloud sync")] bool? cloud,
        IDittoManager dittoManager,
        ISyncService syncService)
    {
        if (dittoManager.DittoSelectedApp == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        var config = dittoManager.SelectedDatabaseConfig;
        if (config == null)
            return JsonSerializer.Serialize(new { error = "No database configuration available." });

        var btEnabled = bluetooth ?? config.IsBluetoothLeEnabled;
        var lanEnabled = lan ?? config.IsLanEnabled;
        var awdlEnabled = awdl ?? config.IsAwdlEnabled;
        var cloudEnabled = cloud ?? config.IsCloudSyncEnabled;

        await syncService.ApplyTransportConfigurationAsync(
            btEnabled, lanEnabled, awdlEnabled, false, cloudEnabled);

        return JsonSerializer.Serialize(new
        {
            success = true,
            transports = new
            {
                bluetooth = btEnabled,
                lan = lanEnabled,
                awdl = awdlEnabled,
                cloud = cloudEnabled
            }
        });
    }

    [McpServerTool, Description("Start or stop Ditto sync.")]
    public static string SetSync(
        [Description("true to start sync, false to stop")] bool enabled,
        IDittoManager dittoManager)
    {
        if (dittoManager.DittoSelectedApp == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        if (enabled)
            dittoManager.SelectedAppStartSync();
        else
            dittoManager.SelectedAppStopSync();

        return JsonSerializer.Serialize(new { success = true, syncEnabled = enabled });
    }

    [McpServerTool, Description("Get a snapshot of currently connected peers.")]
    public static string GetPeers(
        IDittoManager dittoManager,
        ISystemRepository systemRepository)
    {
        if (dittoManager.DittoSelectedApp == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        // The system repository tracks peer/presence info
        // Adjust based on actual ISystemRepository API
        return JsonSerializer.Serialize(new { message = "Peer data retrieved from system repository" });
    }
}
```

**Note for implementer:** The `GetPeers` and `GetSyncStatus` tools need adjustment based on the actual `ISystemRepository` API. Check what methods are available for reading peer information and sync status. The SwiftUI version uses `DittoManager.shared.dittoSelectedApp?.presenceGraph()` — find the C# equivalent in the Ditto SDK v5.0.0-rc.1.

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/Data/McpServer/DittoSyncTools.cs
git commit -m "feat(dotnet): add MCP sync tools (get_sync_status, configure_transport, set_sync, get_peers)"
```

---

### Task 6: Create DittoMetricsTools (3 tools)

**Files:**
- Create: `dotnet/src/EdgeStudio/Data/McpServer/DittoMetricsTools.cs`

- [ ] **Step 1: Create the metrics tools**

Create `dotnet/src/EdgeStudio/Data/McpServer/DittoMetricsTools.cs`:

```csharp
using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Services;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer;

[McpServerToolType]
public static class DittoMetricsTools
{
    [McpServerTool, Description("Get recent query execution metrics including timing, result counts, and EXPLAIN output.")]
    public static string GetQueryMetrics(
        [Description("Maximum number of metrics to return (default 200)")] int? count,
        IQueryMetricsService metricsService)
    {
        var maxCount = count ?? 200;
        var metrics = metricsService.GetRecentMetrics(maxCount);
        return JsonSerializer.Serialize(new { metrics });
    }

    [McpServerTool, Description("Get Edge Studio application logs.")]
    public static string GetAppLogs(
        [Description("Number of log lines to return (default 200)")] int? lines,
        [Description("Filter string to match against log entries")] string? filter,
        ILoggingService loggingService)
    {
        var maxLines = lines ?? 200;
        var logs = loggingService.GetRecentLogs(maxLines, filter);
        return JsonSerializer.Serialize(new { logs });
    }

    [McpServerTool, Description("Get Ditto SDK logs from log files.")]
    public static string GetDittoLogs(
        [Description("Number of log lines to return (default 200)")] int? lines,
        [Description("Filter string to match against log entries")] string? filter,
        [Description("Minimum log level: error, warning, info, debug, verbose")] string? level,
        ILoggingService loggingService)
    {
        var maxLines = lines ?? 200;
        var logs = loggingService.GetDittoLogs(maxLines, filter, level);
        return JsonSerializer.Serialize(new { logs });
    }
}
```

**Note for implementer:** Check the actual `IQueryMetricsService` and `ILoggingService` interfaces for the correct method names:
- `IQueryMetricsService` — likely has `GetRecentMetrics()` or a metrics collection property
- `ILoggingService` — likely has methods for reading recent log entries and Ditto SDK logs
Adjust the method calls to match what's actually available.

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/Data/McpServer/DittoMetricsTools.cs
git commit -m "feat(dotnet): add MCP metrics tools (get_query_metrics, get_app_logs, get_ditto_logs)"
```

---

### Task 7: Create DittoImportTools (1 tool)

**Files:**
- Create: `dotnet/src/EdgeStudio/Data/McpServer/DittoImportTools.cs`

- [ ] **Step 1: Create the import tool**

Create `dotnet/src/EdgeStudio/Data/McpServer/DittoImportTools.cs`:

```csharp
using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer;

[McpServerToolType]
public static class DittoImportTools
{
    [McpServerTool, Description("Insert documents from a JSON file into a collection.")]
    public static async Task<string> InsertDocumentsFromFile(
        [Description("Path to the JSON file containing documents")] string filePath,
        [Description("Target collection name")] string collection,
        [Description("Insert mode: 'insert' (default) or 'insert_initial'")] string? mode,
        IImportService importService,
        IDittoManager dittoManager)
    {
        if (dittoManager.DittoSelectedApp == null)
            return JsonSerializer.Serialize(new { error = "No database is currently selected." });

        if (string.IsNullOrWhiteSpace(filePath))
            return JsonSerializer.Serialize(new { error = "'file_path' parameter is required." });

        if (string.IsNullOrWhiteSpace(collection))
            return JsonSerializer.Serialize(new { error = "'collection' parameter is required." });

        if (!System.IO.File.Exists(filePath))
            return JsonSerializer.Serialize(new { error = $"File not found: {filePath}" });

        var effectiveMode = string.IsNullOrWhiteSpace(mode) ? "insert" : mode.ToLowerInvariant();

        try
        {
            var result = await importService.ImportFromFileAsync(filePath, collection, effectiveMode);
            return JsonSerializer.Serialize(result);
        }
        catch (System.Exception ex)
        {
            return JsonSerializer.Serialize(new { error = $"Import failed: {ex.Message}" });
        }
    }
}
```

**Note for implementer:** Check the actual `IImportService` interface for the correct method signature. The SwiftUI version reads the JSON file, parses documents, and inserts them one by one. The C# version may have a different API surface.

- [ ] **Step 2: Build to verify**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal
```

- [ ] **Step 3: Commit**

```bash
git add dotnet/src/EdgeStudio/Data/McpServer/DittoImportTools.cs
git commit -m "feat(dotnet): add MCP import tool (insert_documents_from_file)"
```

---

### Task 8: Register McpServerService and Wire App Lifecycle

**Files:**
- Modify: `dotnet/src/EdgeStudio/App.axaml.cs`

- [ ] **Step 1: Register McpServerService in DI**

In `dotnet/src/EdgeStudio/App.axaml.cs`, in the `InitializeDependencyInjectionAsync()` method, after the `ISettingsRepository` registration (from Plan A), add:

```csharp
// MCP Server
services.AddSingleton<McpServerService>();
```

Add the using:

```csharp
using EdgeStudio.Data.McpServer;
```

- [ ] **Step 2: Start MCP server on app launch if enabled**

In the app startup code (after DI is built and the main window is shown), add logic to check the setting and start the server:

```csharp
// After _serviceProvider is built and main window is created:
var mcpService = _serviceProvider.GetRequiredService<McpServerService>();
var settingsRepo = _serviceProvider.GetRequiredService<ISettingsRepository>();
var mcpEnabled = await settingsRepo.GetBoolAsync("mcpServerEnabled", defaultValue: false);
if (mcpEnabled)
{
    _ = Task.Run(async () => await mcpService.StartAsync());
}
```

- [ ] **Step 3: Stop MCP server on app exit**

In the app shutdown/cleanup handler (look for `OnExit`, `OnFrameworkInitializationCompleted` cleanup, or window closing), add:

```csharp
var mcpService = _serviceProvider?.GetService<McpServerService>();
if (mcpService?.IsRunning == true)
{
    await mcpService.StopAsync();
}
```

- [ ] **Step 4: Build and run full test suite**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj
```

- [ ] **Step 5: Commit**

```bash
git add dotnet/src/EdgeStudio/App.axaml.cs
git commit -m "feat(dotnet): register McpServerService and wire app lifecycle start/stop"
```

---

### Task 9: Write Tests

**Files:**
- Create: `dotnet/src/EdgeStudioTests/McpToolManifestTests.cs`

- [ ] **Step 1: Create tool manifest tests**

Create `dotnet/src/EdgeStudioTests/McpToolManifestTests.cs`:

```csharp
using System.Linq;
using System.Reflection;
using EdgeStudio.Data.McpServer;
using FluentAssertions;
using ModelContextProtocol.Server;
using Xunit;

namespace EdgeStudioTests;

public class McpToolManifestTests
{
    [Fact]
    public void AllToolClasses_HaveMcpServerToolTypeAttribute()
    {
        var toolTypes = typeof(McpServerService).Assembly.GetTypes()
            .Where(t => t.GetCustomAttribute<McpServerToolTypeAttribute>() != null)
            .ToList();

        toolTypes.Should().NotBeEmpty("there should be MCP tool classes in the assembly");
    }

    [Fact]
    public void AllTools_HaveUniqueNames()
    {
        var toolMethods = typeof(McpServerService).Assembly.GetTypes()
            .Where(t => t.GetCustomAttribute<McpServerToolTypeAttribute>() != null)
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Static))
            .Where(m => m.GetCustomAttribute<McpServerToolAttribute>() != null)
            .ToList();

        var names = toolMethods.Select(m => m.Name).ToList();
        names.Should().OnlyHaveUniqueItems("MCP tool names must be unique");
    }

    [Fact]
    public void AllTools_HaveDescriptions()
    {
        var toolMethods = typeof(McpServerService).Assembly.GetTypes()
            .Where(t => t.GetCustomAttribute<McpServerToolTypeAttribute>() != null)
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Static))
            .Where(m => m.GetCustomAttribute<McpServerToolAttribute>() != null)
            .ToList();

        foreach (var method in toolMethods)
        {
            var desc = method.GetCustomAttribute<System.ComponentModel.DescriptionAttribute>();
            desc.Should().NotBeNull($"tool {method.Name} must have a [Description] attribute");
            desc!.Description.Should().NotBeNullOrWhiteSpace($"tool {method.Name} description should not be empty");
        }
    }

    [Fact]
    public void ToolCount_MatchesExpected()
    {
        var toolMethods = typeof(McpServerService).Assembly.GetTypes()
            .Where(t => t.GetCustomAttribute<McpServerToolTypeAttribute>() != null)
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.Static))
            .Where(m => m.GetCustomAttribute<McpServerToolAttribute>() != null)
            .ToList();

        // 15 tools matching SwiftUI version:
        // 4 database + 3 index + 4 sync + 3 metrics + 1 import
        toolMethods.Should().HaveCount(15, "should match the 15 tools from the SwiftUI version");
    }
}
```

- [ ] **Step 2: Run the tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj --filter "FullyQualifiedName~McpToolManifestTests" --logger "console;verbosity=detailed"
```

- [ ] **Step 3: Run full test suite**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet test EdgeStudioTests/EdgeStudioTests.csproj
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudioTests/McpToolManifestTests.cs
git commit -m "test(dotnet): add MCP tool manifest validation tests"
```

---

### Task 10: Update PreferencesWindow to Start/Stop MCP Server on Save

**Files:**
- Modify: `dotnet/src/EdgeStudio/ViewModels/PreferencesViewModel.cs`

- [ ] **Step 1: Inject McpServerService and toggle on save**

Update `PreferencesViewModel` to accept `McpServerService` and start/stop the server when settings are saved:

```csharp
// Add to constructor parameters:
private readonly McpServerService _mcpServer;

public PreferencesViewModel(ISettingsRepository settings, IToastService toastService, McpServerService mcpServer)
    : base(toastService)
{
    _settings = settings;
    _mcpServer = mcpServer;
}

// In SaveSettingsAsync, after persisting to DB:
if (IsMcpServerEnabled && !_mcpServer.IsRunning)
{
    _ = Task.Run(async () => await _mcpServer.StartAsync());
    StatusMessage = "Settings saved. MCP server starting...";
}
else if (!IsMcpServerEnabled && _mcpServer.IsRunning)
{
    _ = Task.Run(async () => await _mcpServer.StopAsync());
    StatusMessage = "Settings saved. MCP server stopped.";
}
```

- [ ] **Step 2: Update PreferencesViewModel tests to pass McpServerService mock**

Update `PreferencesViewModelTests.cs` constructor to create a mock `McpServerService` or adjust the constructor call. Since `McpServerService` is a concrete class, you may need to either:
- Extract an interface `IMcpServerService` (recommended), or
- Pass `null` with a null-forgiving operator for test purposes

The implementer should choose the approach that fits the existing test patterns.

- [ ] **Step 3: Build and run all tests**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet build EdgeStudio/EdgeStudio.csproj --verbosity minimal && dotnet test EdgeStudioTests/EdgeStudioTests.csproj
```

- [ ] **Step 4: Commit**

```bash
git add dotnet/src/EdgeStudio/ViewModels/PreferencesViewModel.cs dotnet/src/EdgeStudioTests/PreferencesViewModelTests.cs
git commit -m "feat(dotnet): toggle MCP server start/stop from preferences save"
```

---

### Task 11: Manual Verification

- [ ] **Step 1: Run the app**

```bash
cd /Users/labeaaa/Developer/ditto-edge-studio/dotnet/src && dotnet run --project EdgeStudio/EdgeStudio.csproj
```

Verify:
1. Open Settings, enable MCP server, Save
2. In a terminal: `curl http://localhost:65269/health` should respond (or SSE endpoint should be reachable)
3. Test with Claude Code: the `.mcp.json` at repo root should auto-connect
4. Disable MCP server in Settings, Save — server should stop
5. Restart app — server should NOT start (disabled by default)
6. Enable in Settings, Save, restart app — server should auto-start

- [ ] **Step 2: Test tool execution**

With the MCP server running and a database selected:
1. Use Claude Code or `curl` to call `tools/list` and verify 15 tools are returned
2. Call `execute_dql` with a simple `SELECT * FROM <collection> LIMIT 1`
3. Call `list_databases` to verify database listing works
4. Call `get_sync_status` to verify sync info is returned
