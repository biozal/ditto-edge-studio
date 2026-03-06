using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;

namespace EdgeStudio.Shared.Services;

/// <summary>
/// Service for managing sync operations and transport configuration.
/// Coordinates between DittoManager and SystemRepository.
/// </summary>
public class SyncService : ISyncService
{
    private readonly IDittoManager _dittoManager;
    private readonly ISystemRepository _systemRepository;

    public SyncService(IDittoManager dittoManager, ISystemRepository systemRepository)
    {
        _dittoManager = dittoManager;
        _systemRepository = systemRepository;
    }

    /// <summary>
    /// Stops sync and cancels all peer observers.
    /// </summary>
    public void StopSync()
    {
        // Cancel peer observers to prevent stale callbacks
        _systemRepository.CancelPeerCardObservers();

        // Stop sync
        _dittoManager.SelectedAppStopSync();
    }

    /// <summary>
    /// Starts sync and re-registers peer observers.
    /// </summary>
    public void StartSync()
    {
        // Start sync
        _dittoManager.SelectedAppStartSync();

        // Re-register peer observers
        _systemRepository.ReregisterPeerCardObservers();
    }

    /// <summary>
    /// Applies transport configuration. Automatically stops sync, applies config, and restarts sync.
    /// </summary>
    public async Task ApplyTransportConfigurationAsync(
        bool bluetoothEnabled,
        bool lanEnabled,
        bool awdlEnabled,
        bool wifiAwareEnabled,
        bool webSocketEnabled)
    {
        // Step 1: Stop sync and cancel observers
        StopSync();

        // Step 2: Apply transport configuration
        await _dittoManager.ApplyTransportConfigurationAsync(
            bluetoothEnabled, lanEnabled, awdlEnabled, wifiAwareEnabled, webSocketEnabled);

        // Step 3: Start sync and re-register observers
        // NOTE: There's a known issue where system:data_sync_info contains stale data
        // after transport config changes, causing removed peers to reappear.
        // This is a Ditto SDK issue - the system collection doesn't immediately reflect
        // the new transport state after connections are dropped.
        StartSync();
    }
}
