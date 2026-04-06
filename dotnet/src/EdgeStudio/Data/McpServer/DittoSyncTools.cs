using System.ComponentModel;
using System.Text.Json;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Services;
using ModelContextProtocol.Server;

namespace EdgeStudio.Data.McpServer
{
    [McpServerToolType]
    public static class DittoSyncTools
    {
        [McpServerTool, Description("Get the current sync status and transport configuration for the active database")]
        public static string GetSyncStatus(IDittoManager dittoManager)
        {
            var config = dittoManager.SelectedDatabaseConfig;
            if (config == null)
            {
                return JsonSerializer.Serialize(new
                {
                    error = "No database is currently selected."
                });
            }

            var ditto = dittoManager.DittoSelectedApp;
            return JsonSerializer.Serialize(new
            {
                databaseName = config.Name,
                databaseId = config.DatabaseId,
                isSyncActive = ditto != null,
                transports = new
                {
                    bluetoothEnabled = config.IsBluetoothLeEnabled,
                    lanEnabled = config.IsLanEnabled,
                    awdlEnabled = config.IsAwdlEnabled,
                    cloudSyncEnabled = config.IsCloudSyncEnabled,
                    websocketUrl = config.WebsocketUrl
                }
            });
        }

        [McpServerTool, Description("Configure transport settings for Ditto sync (Bluetooth, LAN, AWDL, cloud/WebSocket). Omit a parameter to keep its current value.")]
        public static async Task<string> ConfigureTransport(
            [Description("Enable or disable Bluetooth transport. Omit to keep current value.")] bool? bluetooth,
            [Description("Enable or disable LAN transport. Omit to keep current value.")] bool? lan,
            [Description("Enable or disable AWDL transport (Apple Wireless Direct Link). Omit to keep current value.")] bool? awdl,
            [Description("Enable or disable cloud/WebSocket sync. Omit to keep current value.")] bool? cloud,
            IDittoManager dittoManager,
            ISyncService syncService)
        {
            var config = dittoManager.SelectedDatabaseConfig;
            if (config == null)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = "No database is currently selected."
                });
            }

            var btEnabled = bluetooth ?? config.IsBluetoothLeEnabled;
            var lanEnabled = lan ?? config.IsLanEnabled;
            var awdlEnabled = awdl ?? config.IsAwdlEnabled;
            var cloudEnabled = cloud ?? config.IsCloudSyncEnabled;

            await syncService.ApplyTransportConfigurationAsync(
                bluetoothEnabled: btEnabled,
                lanEnabled: lanEnabled,
                awdlEnabled: awdlEnabled,
                wifiAwareEnabled: false,
                webSocketEnabled: cloudEnabled);

            return JsonSerializer.Serialize(new
            {
                success = true,
                message = "Transport configuration applied",
                applied = new
                {
                    bluetooth = btEnabled,
                    lan = lanEnabled,
                    awdl = awdlEnabled,
                    cloud = cloudEnabled
                }
            });
        }

        [McpServerTool, Description("Start or stop Ditto sync")]
        public static string SetSync(
            [Description("True to start sync, false to stop sync")] bool enabled,
            IDittoManager dittoManager,
            ISyncService syncService)
        {
            if (dittoManager.SelectedDatabaseConfig == null)
            {
                return JsonSerializer.Serialize(new
                {
                    success = false,
                    error = "No database is currently selected."
                });
            }

            if (enabled)
            {
                syncService.StartSync();
                return JsonSerializer.Serialize(new
                {
                    success = true,
                    message = "Sync started"
                });
            }
            else
            {
                syncService.StopSync();
                return JsonSerializer.Serialize(new
                {
                    success = true,
                    message = "Sync stopped"
                });
            }
        }

        [McpServerTool, Description("Get the current peer connection counts by transport type")]
        public static string GetPeers(ISystemRepository systemRepository)
        {
            var connections = systemRepository.CurrentConnections;
            return JsonSerializer.Serialize(new
            {
                totalConnections = connections.TotalConnections,
                hasActiveConnections = connections.HasActiveConnections,
                byTransport = new
                {
                    bluetooth = connections.Bluetooth,
                    lan = connections.P2PWifi,
                    accessPoint = connections.AccessPoint,
                    awdl = connections.Awdl,
                    webSocket = connections.WebSocket,
                    dittoServer = connections.DittoServer
                }
            });
        }
    }
}
