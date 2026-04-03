using System;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Data.McpServer;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels
{
    public partial class PreferencesViewModel : ViewModelBase
    {
        private readonly ISettingsRepository _settings;
        private readonly McpServerService _mcpServer;

        [ObservableProperty]
        private bool _isMcpServerEnabled;

        [ObservableProperty]
        private int _mcpServerPort = 65269;

        [ObservableProperty]
        private string _statusMessage = string.Empty;

        [ObservableProperty]
        private bool _isMcpServerRunning;

        public PreferencesViewModel(ISettingsRepository settings, IToastService? toastService, McpServerService mcpServer)
            : base(toastService)
        {
            _settings = settings;
            _mcpServer = mcpServer;
        }

        public async Task LoadSettingsAsync()
        {
            IsMcpServerEnabled = await _settings.GetBoolAsync("mcpServerEnabled", defaultValue: false);
            McpServerPort = await _settings.GetIntAsync("mcpServerPort", defaultValue: 65269);
            IsMcpServerRunning = _mcpServer?.IsRunning ?? false;
        }

        [RelayCommand]
        private async Task SaveSettingsAsync()
        {
            try
            {
                if (McpServerPort < 1024 || McpServerPort > 65535)
                {
                    StatusMessage = "Port must be between 1024 and 65535.";
                    return;
                }

                await _settings.SetBoolAsync("mcpServerEnabled", IsMcpServerEnabled);
                await _settings.SetIntAsync("mcpServerPort", McpServerPort);

                // Start/stop MCP server based on new setting
                if (_mcpServer != null)
                {
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
                    else
                    {
                        StatusMessage = "Settings saved.";
                    }
                }
                else
                {
                    StatusMessage = "Settings saved.";
                }

                ShowSuccess("Settings saved successfully.");
            }
            catch (Exception ex)
            {
                StatusMessage = $"Failed to save: {ex.Message}";
                ShowError($"Failed to save settings: {ex.Message}");
            }
        }
    }
}
