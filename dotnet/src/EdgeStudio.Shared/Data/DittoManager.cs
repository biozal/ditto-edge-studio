using System;
using System.IO;
using System.Threading.Tasks;
using DittoSDK;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.Shared.Data
{
    public sealed class DittoManager : IDittoManager, IDisposable
    {
        private bool _disposed = false;
        private readonly ILoggingService? _logger;

        public DittoManager(ILoggingService? logger = null)
        {
            _logger = logger;
        }

        public Ditto? DittoSelectedApp { get; set; } = null;

        public DittoDatabaseConfig? SelectedDatabaseConfig { get; set; } = null;

        public void CloseSelectedDatabase()
        {
            if (DittoSelectedApp != null)
            {
                DittoSelectedApp.Sync.Stop();
                DittoSelectedApp.Dispose();
                DittoSelectedApp = null;
            }
        }

        /// <summary>
        /// Asynchronously closes the selected database by running blocking operations
        /// on a background thread to prevent UI freezing.
        /// </summary>
        public async Task CloseDatabaseAsync()
        {
            if (DittoSelectedApp != null)
            {
                var dittoToClose = DittoSelectedApp;
                DittoSelectedApp = null; // Clear reference immediately so no new work starts

                var closeTask = Task.Run(() =>
                {
                    try
                    {
                        _logger?.Info("Stopping Ditto sync...");
                        dittoToClose.Sync.Stop();
                        _logger?.Info("Ditto sync stopped. Disposing...");
                        dittoToClose.Dispose();
                        _logger?.Info("Ditto disposed successfully.");
                    }
                    catch (Exception ex)
                    {
                        _logger?.Error($"Error closing Ditto database: {ex.Message}");
                    }
                });

                var timeoutTask = Task.Delay(TimeSpan.FromSeconds(10));
                var completed = await Task.WhenAny(closeTask, timeoutTask);

                if (completed == timeoutTask)
                {
                    _logger?.Warning("Ditto database close timed out after 10 seconds. " +
                                     "The SDK may still be running in the background.");
                }
            }
        }

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        private void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing)
                {
                    CloseSelectedDatabase();
                }
                _disposed = true;
            }
        }

        public string? GetPersistenceDirectory()
        {
            if (SelectedDatabaseConfig == null) return null;
            var dbName = $"{SelectedDatabaseConfig.Name.Trim().ToLower()}-{SelectedDatabaseConfig.DatabaseId}";
            var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return Path.Combine(appDataPath, "DittoEdgeStudio", dbName);
        }

        public Ditto GetSelectedAppDitto() => DittoSelectedApp ?? throw new InvalidOperationException("DittoManager is not properly initialized.");

        public async Task<bool> InitializeDittoSelectedApp(DittoDatabaseConfig dittoDatabaseConfig)
        {
            var isSuccess = false;
            CloseSelectedDatabase();

            this.SelectedDatabaseConfig = dittoDatabaseConfig;
            var dbName = $"{dittoDatabaseConfig.Name.Trim().ToLower()}-{dittoDatabaseConfig.DatabaseId}";

            var appDataPath = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var persistenceDirectory = Path.Combine(appDataPath, "DittoEdgeStudio", dbName);

            Directory.CreateDirectory(persistenceDirectory);
            var config = new DittoConfig(dittoDatabaseConfig.DatabaseId,
                connect: new DittoConfigConnect.Server(new Uri(dittoDatabaseConfig.AuthUrl)),
                persistenceDirectory: persistenceDirectory
            );

            DittoLogger.MinimumLogLevel = DittoLogLevelHelper.Parse(dittoDatabaseConfig.LogLevel);

            this.DittoSelectedApp = await Ditto.OpenAsync(config);
            if (this.DittoSelectedApp != null)
            {
                this.DittoSelectedApp.Auth.ExpirationHandler = async (ditto, secondsRemaining) =>
                {
                    try
                    {
                        await ditto.Auth.LoginAsync(dittoDatabaseConfig.AuthToken,
                            DittoAuthenticationProvider.Development);
                    }
                    catch (Exception error)
                    {
                        throw new InvalidOperationException("Ditto authentication failed.", error);
                    }
                };

                DittoSelectedApp.DisableSyncWithV3();

                // Apply strict mode BEFORE starting sync (matches SwiftUI hydrateDittoSelectedDatabase order)
                var strictMode = dittoDatabaseConfig.IsStrictModeEnabled ? "true" : "false";
                await DittoSelectedApp.Store.ExecuteAsync($"ALTER SYSTEM SET DQL_STRICT_MODE = {strictMode}");
              
                //set max connections to 12 for LAN/P2P Wi-Fi
                await DittoSelectedApp.Store.ExecuteAsync("ALTER SYSTEM SET mesh_chooser_max_wlan_clients = 12");
                _logger?.Info("Setting system parameter mesh_chooser_max_wlan_clients to 12");

                // Apply transport config BEFORE starting sync — matches SwiftUI startup order.
                // Starting sync first would cause Ditto to connect with default transports,
                // then immediately disconnect and reconnect with the configured transports.
                await ApplyTransportConfigurationAsync(
                    bluetoothEnabled: dittoDatabaseConfig.IsBluetoothLeEnabled,
                    lanEnabled:       dittoDatabaseConfig.IsLanEnabled,
                    awdlEnabled:      dittoDatabaseConfig.IsAwdlEnabled,
                    wifiAwareEnabled: false,
                    webSocketEnabled: dittoDatabaseConfig.IsCloudSyncEnabled);

                DittoSelectedApp.Sync.Start();
                isSuccess = true;
            }
            else
            {
                throw new InvalidOperationException("Failed to open Ditto instance.");
            }
            return isSuccess;
        }

        public void SelectedAppStartSync()
        {
            if (this.DittoSelectedApp == null)
                throw new InvalidOperationException("DittoSelectedApp is not initialized.");
            this.DittoSelectedApp.Sync.Start();
        }

        public void SelectedAppStopSync()
        {
            if (this.DittoSelectedApp == null)
                throw new InvalidOperationException("DittoSelectedApp is not initialized.");
            this.DittoSelectedApp.Sync.Stop();
        }

        /// <summary>
        /// Applies transport configuration to the selected Ditto database.
        /// Stops sync, updates transport configuration, then restarts sync to disconnect existing peers.
        /// </summary>
        public async Task ApplyTransportConfigurationAsync(
            bool bluetoothEnabled,
            bool lanEnabled,
            bool awdlEnabled,
            bool wifiAwareEnabled,
            bool webSocketEnabled)
        {
            if (DittoSelectedApp == null)
                throw new InvalidOperationException("No database selected.");

            await Task.Run(() =>
            {
                DittoSelectedApp.UpdateTransportConfig(transportConfig =>
                {
                    transportConfig.PeerToPeer.BluetoothLE.Enabled = bluetoothEnabled;
                    transportConfig.PeerToPeer.Lan.Enabled = lanEnabled;
                    transportConfig.PeerToPeer.Awdl.Enabled = awdlEnabled;
                    transportConfig.PeerToPeer.WifiAware.Enabled = wifiAwareEnabled;

                    if (!webSocketEnabled)
                    {
                        transportConfig.Connect.WebsocketUrls.Clear();
                    }
                    else
                    {
                        // Use the stored WebsocketUrl field; fall back to deriving from AuthUrl
                        // if WebsocketUrl was not explicitly set (matches SwiftUI applyTransportConfig)
                        var url = SelectedDatabaseConfig?.WebsocketUrl;
                        if (string.IsNullOrEmpty(url))
                            url = SelectedDatabaseConfig?.AuthUrl.Replace("https:", "wss:");

                        if (!string.IsNullOrEmpty(url) && !transportConfig.Connect.WebsocketUrls.Contains(url))
                            transportConfig.Connect.WebsocketUrls.Add(url);
                    }
                });

                _logger?.Info("Transport Configuration Applied");
                if (_logger != null)
                {
                    var tc = DittoSelectedApp.TransportConfig;
                    _logger.Debug($"Bluetooth LE: {tc.PeerToPeer.BluetoothLE.Enabled}");
                    _logger.Debug($"LAN: {tc.PeerToPeer.Lan.Enabled}");
                    _logger.Debug($"AWDL: {tc.PeerToPeer.Awdl.Enabled}");
                    _logger.Debug($"WiFi Aware: {tc.PeerToPeer.WifiAware.Enabled}");
                    _logger.Debug($"WebSocket URLs: {tc.Connect.WebsocketUrls.Count}");
                }
            });
        }
    }
}
