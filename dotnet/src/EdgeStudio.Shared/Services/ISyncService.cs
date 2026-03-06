using System.Threading.Tasks;

namespace EdgeStudio.Shared.Services;

/// <summary>
/// Service for managing sync operations and transport configuration.
/// Encapsulates business logic for sync lifecycle and observer management.
/// </summary>
public interface ISyncService
{
    /// <summary>
    /// Stops sync and cancels all peer observers.
    /// </summary>
    void StopSync();

    /// <summary>
    /// Starts sync. Observers will be re-registered by ViewModels as needed.
    /// </summary>
    void StartSync();

    /// <summary>
    /// Applies transport configuration. Automatically stops sync, applies config, and restarts sync.
    /// </summary>
    Task ApplyTransportConfigurationAsync(
        bool bluetoothEnabled,
        bool lanEnabled,
        bool awdlEnabled,
        bool wifiAwareEnabled,
        bool webSocketEnabled);
}
