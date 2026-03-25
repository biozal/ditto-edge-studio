using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;

namespace EdgeStudio.Shared.Services;

/// <summary>
/// Service for managing sync operations and transport configuration.
/// Coordinates between DittoManager, SystemRepository, and DatabaseRepository.
/// </summary>
public class SyncService : ISyncService
{
    private readonly IDittoManager _dittoManager;
    private readonly ISystemRepository _systemRepository;
    private readonly IDatabaseRepository _databaseRepository;

    public SyncService(IDittoManager dittoManager, ISystemRepository systemRepository, IDatabaseRepository databaseRepository)
    {
        _dittoManager = dittoManager;
        _systemRepository = systemRepository;
        _databaseRepository = databaseRepository;
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
    /// Applies transport configuration. Stops sync, applies config, persists to database, then restarts sync.
    /// Matches SwiftUI's TransportConfigView.ViewModel.applyTransportConfig() sequence:
    /// 1. Stop sync + cancel observers
    /// 2. Apply config to Ditto
    /// 3. Persist updated flags to database (so reopening the database restores settings)
    /// 4. Restart sync + re-register observers
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

        // Step 2: Apply transport configuration to Ditto
        await _dittoManager.ApplyTransportConfigurationAsync(
            bluetoothEnabled, lanEnabled, awdlEnabled, wifiAwareEnabled, webSocketEnabled);

        // Step 3: Persist updated transport flags to the database so that reopening
        // the database restores the same transport configuration (matches SwiftUI behavior)
        var config = _dittoManager.SelectedDatabaseConfig;
        if (config != null)
        {
            var updated = config with
            {
                IsBluetoothLeEnabled = bluetoothEnabled,
                IsLanEnabled = lanEnabled,
                IsAwdlEnabled = awdlEnabled,
                IsCloudSyncEnabled = webSocketEnabled
            };
            await _databaseRepository.UpdateDatabaseConfig(updated);
            _dittoManager.SelectedDatabaseConfig = updated;
        }

        // Step 4: Start sync and re-register observers
        StartSync();
    }
}
