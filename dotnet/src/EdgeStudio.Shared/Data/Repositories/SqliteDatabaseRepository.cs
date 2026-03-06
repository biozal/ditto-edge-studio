using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Threading;
using Microsoft.Data.Sqlite;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// SQLite-backed repository for database connection configurations.
    /// Replaces DittoDatabaseRepository - stores configs in the local encrypted SQLite database.
    /// </summary>
    public sealed class SqliteDatabaseRepository : SqliteRepositoryBase, IDatabaseRepository, IDisposable
    {
        private ObservableCollection<DittoDatabaseConfig>? _configs;
        private bool _disposed;

        public SqliteDatabaseRepository(ILocalDatabaseService localDatabaseService)
            : base(localDatabaseService) { }

        public async Task AddDittoDatabaseConfig(DittoDatabaseConfig config)
        {
            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                INSERT INTO database_configs
                    (id, name, database_id, auth_token, auth_url, http_api_url, http_api_key, mode, allow_untrusted_certs,
                     is_bluetooth_le_enabled, is_lan_enabled, is_awdl_enabled, is_cloud_sync_enabled, is_wifi_aware_enabled, shared_key, log_level)
                VALUES
                    ($id, $name, $database_id, $auth_token, $auth_url, $http_api_url, $http_api_key, $mode, $allow_untrusted_certs,
                     $is_bluetooth_le_enabled, $is_lan_enabled, $is_awdl_enabled, $is_cloud_sync_enabled, $is_wifi_aware_enabled, $shared_key, $log_level)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    database_id = excluded.database_id,
                    auth_token = excluded.auth_token,
                    auth_url = excluded.auth_url,
                    http_api_url = excluded.http_api_url,
                    http_api_key = excluded.http_api_key,
                    mode = excluded.mode,
                    allow_untrusted_certs = excluded.allow_untrusted_certs,
                    is_bluetooth_le_enabled = excluded.is_bluetooth_le_enabled,
                    is_lan_enabled = excluded.is_lan_enabled,
                    is_awdl_enabled = excluded.is_awdl_enabled,
                    is_cloud_sync_enabled = excluded.is_cloud_sync_enabled,
                    is_wifi_aware_enabled = excluded.is_wifi_aware_enabled,
                    shared_key = excluded.shared_key,
                    log_level = excluded.log_level";
            BindConfigParams(cmd, config);
            await cmd.ExecuteNonQueryAsync();

            if (_configs != null)
                await Dispatcher.UIThread.InvokeAsync(() => _configs.Add(config));
        }

        public async Task DeleteDittoDatabaseConfig(DittoDatabaseConfig config)
        {
            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM database_configs WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", config.Id);
            await cmd.ExecuteNonQueryAsync();

            if (_configs != null)
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    var item = _configs.FirstOrDefault(c => c.Id == config.Id);
                    if (item != null) _configs.Remove(item);
                });
        }

        public async Task UpdateDatabaseConfig(DittoDatabaseConfig config)
        {
            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                UPDATE database_configs SET
                    name = $name,
                    database_id = $database_id,
                    auth_token = $auth_token,
                    auth_url = $auth_url,
                    http_api_url = $http_api_url,
                    http_api_key = $http_api_key,
                    mode = $mode,
                    allow_untrusted_certs = $allow_untrusted_certs,
                    is_bluetooth_le_enabled = $is_bluetooth_le_enabled,
                    is_lan_enabled = $is_lan_enabled,
                    is_awdl_enabled = $is_awdl_enabled,
                    is_cloud_sync_enabled = $is_cloud_sync_enabled,
                    is_wifi_aware_enabled = $is_wifi_aware_enabled,
                    shared_key = $shared_key,
                    log_level = $log_level
                WHERE id = $id";
            BindConfigParams(cmd, config);
            await cmd.ExecuteNonQueryAsync();

            if (_configs != null)
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    var idx = _configs.IndexOf(_configs.FirstOrDefault(c => c.Id == config.Id)!);
                    if (idx >= 0) _configs[idx] = config;
                });
        }

        /// <summary>
        /// Loads all database configs from SQLite into the provided collection.
        /// The collection is kept in sync with subsequent Add/Update/Delete operations.
        /// The errorMessage callback is retained for interface compatibility.
        /// </summary>
        public void RegisterLocalObservers(
            ObservableCollection<DittoDatabaseConfig> databaseConfigs,
            Action<string> errorMessage)
        {
            _configs = databaseConfigs;

            _ = Task.Run(async () =>
            {
                try
                {
                    var items = await LoadAllConfigsAsync();
                    await Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        databaseConfigs.Clear();
                        foreach (var item in items)
                            databaseConfigs.Add(item);
                    });
                }
                catch (Exception ex)
                {
                    errorMessage($"Failed to load database configurations: {ex.Message}");
                }
            });
        }

        /// <summary>
        /// No-op for SQLite - schema is created during ILocalDatabaseService.InitializeAsync().
        /// Retained for interface and ViewModel compatibility.
        /// </summary>
        public Task SetupDatabaseConfigSubscriptions() => Task.CompletedTask;

        private async Task<System.Collections.Generic.List<DittoDatabaseConfig>> LoadAllConfigsAsync()
        {
            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT id, name, database_id, auth_token, auth_url, http_api_url, http_api_key, mode, allow_untrusted_certs, is_bluetooth_le_enabled, is_lan_enabled, is_awdl_enabled, is_cloud_sync_enabled, is_wifi_aware_enabled, shared_key, log_level FROM database_configs ORDER BY name";

            var results = new System.Collections.Generic.List<DittoDatabaseConfig>();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                results.Add(ReadConfig(reader));
            }
            return results;
        }

        private static DittoDatabaseConfig ReadConfig(SqliteDataReader reader) =>
            new DittoDatabaseConfig(
                Id: reader.GetString(0),
                Name: reader.GetString(1),
                DatabaseId: reader.GetString(2),
                AuthToken: reader.GetString(3),
                AuthUrl: reader.GetString(4),
                HttpApiUrl: reader.GetString(5),
                HttpApiKey: reader.GetString(6),
                Mode: reader.GetString(7),
                AllowUntrustedCerts: reader.GetInt64(8) != 0,
                IsBluetoothLeEnabled: reader.GetInt64(9) != 0,
                IsLanEnabled: reader.GetInt64(10) != 0,
                IsAwdlEnabled: reader.GetInt64(11) != 0,
                IsCloudSyncEnabled: reader.GetInt64(12) != 0,
                IsWifiAwareEnabled: reader.GetInt64(13) != 0,
                SharedKey: reader.IsDBNull(14) ? "" : reader.GetString(14),
                LogLevel: reader.IsDBNull(15) ? "info" : reader.GetString(15)
            );

        private static void BindConfigParams(SqliteCommand cmd, DittoDatabaseConfig config)
        {
            cmd.Parameters.AddWithValue("$id", config.Id);
            cmd.Parameters.AddWithValue("$name", config.Name);
            cmd.Parameters.AddWithValue("$database_id", config.DatabaseId);
            cmd.Parameters.AddWithValue("$auth_token", config.AuthToken);
            cmd.Parameters.AddWithValue("$auth_url", config.AuthUrl);
            cmd.Parameters.AddWithValue("$http_api_url", config.HttpApiUrl);
            cmd.Parameters.AddWithValue("$http_api_key", config.HttpApiKey);
            cmd.Parameters.AddWithValue("$mode", config.Mode);
            cmd.Parameters.AddWithValue("$allow_untrusted_certs", config.AllowUntrustedCerts ? 1 : 0);
            cmd.Parameters.AddWithValue("$is_bluetooth_le_enabled", config.IsBluetoothLeEnabled ? 1 : 0);
            cmd.Parameters.AddWithValue("$is_lan_enabled", config.IsLanEnabled ? 1 : 0);
            cmd.Parameters.AddWithValue("$is_awdl_enabled", config.IsAwdlEnabled ? 1 : 0);
            cmd.Parameters.AddWithValue("$is_cloud_sync_enabled", config.IsCloudSyncEnabled ? 1 : 0);
            cmd.Parameters.AddWithValue("$is_wifi_aware_enabled", config.IsWifiAwareEnabled ? 1 : 0);
            cmd.Parameters.AddWithValue("$shared_key", config.SharedKey);
            cmd.Parameters.AddWithValue("$log_level", config.LogLevel);
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _configs = null;
                _disposed = true;
            }
        }
    }
}
