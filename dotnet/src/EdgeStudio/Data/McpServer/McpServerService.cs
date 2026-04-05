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

namespace EdgeStudio.Data.McpServer
{
    public class McpServerService : IDisposable
    {
        private readonly IServiceProvider _appServices;
        private readonly ISettingsRepository _settings;
        private readonly ILoggingService _log;
        private WebApplication? _webApp;
        private CancellationTokenSource? _cts;

        public bool IsRunning { get; private set; }
        public int Port { get; private set; }

        public McpServerService(IServiceProvider appServices, ISettingsRepository settings)
        {
            _appServices = appServices;
            _settings = settings;
            _log = appServices.GetRequiredService<ILoggingService>();
        }

        public async Task StartAsync()
        {
            if (IsRunning) return;

            Port = await _settings.GetIntAsync("mcpServerPort", defaultValue: 65269);
            _log.Info($"MCP server starting on port {Port}...");

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

                // Map MCP at root — SSE endpoint at /sse, Streamable HTTP at /
                _webApp.MapMcp();

                _cts = new CancellationTokenSource();

                await _webApp.StartAsync(_cts.Token);
                IsRunning = true;

                _log.Info($"MCP server started successfully on http://localhost:{Port}");
                _log.Info($"  SSE endpoint: http://localhost:{Port}/sse");
                _log.Info($"  Streamable HTTP endpoint: http://localhost:{Port}/mcp");
            }
            catch (Exception ex)
            {
                _log.Error($"Failed to start MCP server: {ex.Message}");
                IsRunning = false;
            }
        }

        public async Task StopAsync()
        {
            if (!IsRunning) return;

            _log.Info("MCP server stopping...");

            try
            {
                _cts?.Cancel();

                if (_webApp != null)
                {
                    await _webApp.StopAsync();
                    await _webApp.DisposeAsync();
                    _webApp = null;
                }

                _cts?.Dispose();
                _cts = null;
            }
            catch (Exception ex)
            {
                _log.Error($"Error stopping MCP server: {ex.Message}");
            }
            finally
            {
                IsRunning = false;
                _log.Info("MCP server stopped");
            }
        }

        public void Dispose()
        {
            StopAsync().GetAwaiter().GetResult();
        }
    }
}
