using System;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CommunityToolkit.Mvvm.Messaging;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Messages;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.ViewModels;

/// <summary>
/// ViewModel for the Subscription Settings tab - manages transport configuration
/// </summary>
public partial class SubscriptionSettingsViewModel : LoadableViewModelBase
{
    private readonly ISyncService _syncService;

    // Platform detection
    private static readonly bool IsMacOS = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
    private static readonly bool IsWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);

    // Transport toggle states
    [ObservableProperty] private bool _isBluetoothEnabled = true;
    [ObservableProperty] private bool _isLanEnabled = true;
    [ObservableProperty] private bool _isAwdlEnabled = true;
    [ObservableProperty] private bool _isWifiAwareEnabled = true;
    [ObservableProperty] private bool _isWebSocketEnabled = true;

    // UI state
    [ObservableProperty] private string _statusMessage = "Ready";
    [ObservableProperty] private bool _isApplyEnabled = true;

    // Platform visibility
    public bool ShowAwdl => IsMacOS;
    public bool ShowWifiAware => IsWindows;

    public SubscriptionSettingsViewModel(ISyncService syncService, IToastService? toastService = null)
        : base(toastService)
    {
        _syncService = syncService;

        // Platform-specific defaults
        IsAwdlEnabled = IsMacOS;
        IsWifiAwareEnabled = IsWindows;
    }

    [RelayCommand]
    private async Task ApplyTransportSettingsAsync()
    {
        await ExecuteOperationAsync(
            operation: async () =>
            {
                IsApplyEnabled = false;
                StatusMessage = "Applying transport configuration...";

                // SyncService handles stop sync, apply config, start sync
                await _syncService.ApplyTransportConfigurationAsync(
                    IsBluetoothEnabled, IsLanEnabled, IsAwdlEnabled,
                    IsWifiAwareEnabled, IsWebSocketEnabled);

                StatusMessage = "Transport settings applied successfully!";
                ShowSuccess("Transport configuration updated", "Settings");
            },
            errorMessage: "Failed to apply transport settings",
            showLoadingState: true
        );

        IsApplyEnabled = true;
        StatusMessage = "Ready";
    }
}
