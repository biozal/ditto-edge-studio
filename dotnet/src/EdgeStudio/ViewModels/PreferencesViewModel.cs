using System;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels
{
    public partial class PreferencesViewModel : ViewModelBase
    {
        private readonly ISettingsRepository _settings;

        [ObservableProperty]
        private bool _isMcpServerEnabled;

        [ObservableProperty]
        private int _mcpServerPort = 65269;

        [ObservableProperty]
        private string _statusMessage = string.Empty;

        public PreferencesViewModel(ISettingsRepository settings, IToastService? toastService)
            : base(toastService)
        {
            _settings = settings;
        }

        public async Task LoadSettingsAsync()
        {
            IsMcpServerEnabled = await _settings.GetBoolAsync("mcpServerEnabled", defaultValue: false);
            McpServerPort = await _settings.GetIntAsync("mcpServerPort", defaultValue: 65269);
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

                StatusMessage = "Settings saved.";
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
