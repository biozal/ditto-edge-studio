using System;
using System.IO;
using System.Threading.Tasks;
using DittoSDK;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data
{
    public sealed class DittoManager : IDittoManager, IDisposable
    {
        private bool _disposed = false;

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
                await Task.Run(() =>
                {
                    try
                    {
                        DittoSelectedApp.Sync.Stop();
                        DittoSelectedApp.Dispose();
                    }
                    catch (Exception ex)
                    {
                        System.Diagnostics.Debug.WriteLine($"Error closing Ditto database: {ex.Message}");
                    }
                });

                DittoSelectedApp = null;
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

            DittoLogger.MinimumLogLevel = dittoDatabaseConfig.LogLevel switch
            {
                "error"   => DittoLogLevel.Error,
                "warning" => DittoLogLevel.Warning,
                "debug"   => DittoLogLevel.Debug,
                "verbose" => DittoLogLevel.Verbose,
                _         => DittoLogLevel.Info,
            };

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

                this.DittoSelectedApp.DisableSyncWithV3();

                // Apply strict mode BEFORE starting sync (matches SwiftUI hydrateDittoSelectedDatabase order)
                var strictMode = dittoDatabaseConfig.IsStrictModeEnabled ? "true" : "false";
                await this.DittoSelectedApp.Store.ExecuteAsync($"ALTER SYSTEM SET DQL_STRICT_MODE = {strictMode}");

                // Apply transport config BEFORE starting sync — matches SwiftUI startup order.
                // Starting sync first would cause Ditto to connect with default transports,
                // then immediately disconnect and reconnect with the configured transports.
                await ApplyTransportConfigurationAsync(
                    bluetoothEnabled: dittoDatabaseConfig.IsBluetoothLeEnabled,
                    lanEnabled:       dittoDatabaseConfig.IsLanEnabled,
                    awdlEnabled:      dittoDatabaseConfig.IsAwdlEnabled,
                    wifiAwareEnabled: false,
                    webSocketEnabled: dittoDatabaseConfig.IsCloudSyncEnabled);

                this.DittoSelectedApp.Sync.Start();
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

                System.Diagnostics.Debug.WriteLine("=== Transport Configuration Applied ===");
                System.Diagnostics.Debug.WriteLine($"Bluetooth LE: {DittoSelectedApp.TransportConfig.PeerToPeer.BluetoothLE.Enabled}");
                System.Diagnostics.Debug.WriteLine($"LAN: {DittoSelectedApp.TransportConfig.PeerToPeer.Lan.Enabled}");
                System.Diagnostics.Debug.WriteLine($"AWDL: {DittoSelectedApp.TransportConfig.PeerToPeer.Awdl.Enabled}");
                System.Diagnostics.Debug.WriteLine($"WiFi Aware: {DittoSelectedApp.TransportConfig.PeerToPeer.WifiAware.Enabled}");
                System.Diagnostics.Debug.WriteLine($"WebSocket URLs: {DittoSelectedApp.TransportConfig.Connect.WebsocketUrls.Count}");
                System.Diagnostics.Debug.WriteLine("======================================");
            });
        }
    }
}
