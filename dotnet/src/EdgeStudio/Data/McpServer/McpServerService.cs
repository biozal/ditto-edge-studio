using System;
using System.Threading;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Services;
using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.AspNetCore;
using ModelContextProtocol.Server;
using Serilog;

namespace EdgeStudio.Data.McpServer
{
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
                var builder = WebApplication.CreateBuilder(new WebApplicationOptions
                {
                    Args = new[] { $"--urls=http://localhost:{Port}" }
                });
                builder.Logging.ClearProviders();

                builder.Services.AddMcpServer(options =>
                {
                    options.ServerInfo = new ModelContextProtocol.Protocol.Implementation
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

                await _webApp.StartAsync(_cts.Token);
                _serverTask = Task.CompletedTask;
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
}
