using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Data.Sqlite;

namespace EdgeStudio.Shared.Data
{
    /// <summary>
    /// Manages the local encrypted SQLite database that stores database configs, subscriptions,
    /// query history, and favorites. Encryption uses SQLite3 Multiple Ciphers (ChaCha20-Poly1305)
    /// with a device-derived key so no user password is ever required.
    /// </summary>
    public sealed class SqliteLocalDatabaseService : ILocalDatabaseService
    {
        private readonly string _dbPath;
        private bool _initialized;
        private bool _disposed;

        public SqliteLocalDatabaseService() : this(GetDefaultDbPath()) { }

        public SqliteLocalDatabaseService(string dbPath)
        {
            _dbPath = dbPath;
        }

        private static string GetDefaultDbPath()
        {
            var appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            var dir = Path.Combine(appData, "DittoEdgeStudio");
            Directory.CreateDirectory(dir);
            return Path.Combine(dir, "edgestudio_local.db");
        }

        /// <summary>
        /// Derives a stable 256-bit key from machine-specific identifiers.
        /// The key is deterministic per machine/user combination and never prompts the user.
        /// </summary>
        public static string DeriveDeviceKey()
        {
            // Combine stable machine identifiers that don't change across app restarts
            var fingerprint = $"{Environment.MachineName}:{Environment.UserName}:{RuntimeInformation.OSArchitecture}";
            var hash = SHA256.HashData(Encoding.UTF8.GetBytes(fingerprint));
            return Convert.ToHexString(hash).ToLowerInvariant(); // 64 hex chars = 256-bit key
        }

        public async Task InitializeAsync()
        {
            if (_initialized) return;

            // Initialize the SQLite3MC native provider once per process
            SQLitePCL.Batteries_V2.Init();

            try
            {
                await CreateSchemaAsync();
            }
            catch (SqliteException ex) when (ex.SqliteErrorCode == 26) // SQLITE_NOTADB
            {
                // The file exists but is not a valid SQLite3MC encrypted database.
                // This happens when a plain (unencrypted) SQLite file was left from
                // a previous version, or the file is corrupted. Delete it and start fresh.
                if (File.Exists(_dbPath))
                    File.Delete(_dbPath);
                await CreateSchemaAsync();
            }

            _initialized = true;
        }

        public SqliteConnection CreateOpenConnection()
        {
            if (!_initialized)
                throw new InvalidOperationException("Call InitializeAsync() before using the database.");

            var csb = new SqliteConnectionStringBuilder
            {
                DataSource = _dbPath,
                Mode = SqliteOpenMode.ReadWriteCreate
            };

            var connection = new SqliteConnection(csb.ToString());
            connection.Open();

            // Apply encryption key as the very first operation on this connection.
            // SQLite3MC ChaCha20 raw key syntax - bypasses KDF entirely, no user password.
            using var keyCmd = connection.CreateCommand();
            keyCmd.CommandText = $"PRAGMA key = 'raw:{DeriveDeviceKey()}';";
            keyCmd.ExecuteNonQuery();

            return connection;
        }

        private async Task CreateSchemaAsync()
        {
            using var connection = CreateOpenConnectionInternal();

            using var cmd = connection.CreateCommand();
            cmd.CommandText = @"
                CREATE TABLE IF NOT EXISTS database_configs (
                    id                      TEXT PRIMARY KEY,
                    name                    TEXT NOT NULL,
                    database_id             TEXT NOT NULL,
                    auth_token              TEXT NOT NULL,
                    auth_url                TEXT NOT NULL,
                    http_api_url            TEXT NOT NULL DEFAULT '',
                    http_api_key            TEXT NOT NULL DEFAULT '',
                    mode                    TEXT NOT NULL DEFAULT 'server',
                    allow_untrusted_certs   INTEGER NOT NULL DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS subscriptions (
                    id              TEXT PRIMARY KEY,
                    name            TEXT NOT NULL,
                    query           TEXT NOT NULL,
                    selected_app_id TEXT NOT NULL
                );

                CREATE INDEX IF NOT EXISTS idx_subscriptions_selected_app_id
                    ON subscriptions(selected_app_id);

                CREATE TABLE IF NOT EXISTS query_history (
                    id              TEXT PRIMARY KEY,
                    query           TEXT NOT NULL,
                    created_date    TEXT NOT NULL,
                    selected_app_id TEXT NOT NULL DEFAULT ''
                );

                CREATE INDEX IF NOT EXISTS idx_history_query_app
                    ON query_history(query, selected_app_id);

                CREATE TABLE IF NOT EXISTS query_favorites (
                    id              TEXT PRIMARY KEY,
                    query           TEXT NOT NULL,
                    created_date    TEXT NOT NULL,
                    selected_app_id TEXT NOT NULL DEFAULT ''
                );
            ";
            await cmd.ExecuteNonQueryAsync();
            await MigrateSchemaAsync(connection);
        }

        private static async Task MigrateSchemaAsync(SqliteConnection connection)
        {
            var migrations = new[]
            {
                "ALTER TABLE database_configs ADD COLUMN is_bluetooth_le_enabled INTEGER NOT NULL DEFAULT 1",
                "ALTER TABLE database_configs ADD COLUMN is_lan_enabled INTEGER NOT NULL DEFAULT 1",
                "ALTER TABLE database_configs ADD COLUMN is_awdl_enabled INTEGER NOT NULL DEFAULT 1",
                "ALTER TABLE database_configs ADD COLUMN is_cloud_sync_enabled INTEGER NOT NULL DEFAULT 1",
                "ALTER TABLE database_configs ADD COLUMN is_wifi_aware_enabled INTEGER NOT NULL DEFAULT 0",
                "ALTER TABLE database_configs ADD COLUMN shared_key TEXT NOT NULL DEFAULT ''",
                "ALTER TABLE database_configs ADD COLUMN log_level TEXT NOT NULL DEFAULT 'info'",
                "ALTER TABLE database_configs ADD COLUMN websocket_url TEXT NOT NULL DEFAULT ''",
                "ALTER TABLE database_configs ADD COLUMN is_strict_mode_enabled INTEGER NOT NULL DEFAULT 0",
            };
            foreach (var sql in migrations)
            {
                try
                {
                    using var migCmd = connection.CreateCommand();
                    migCmd.CommandText = sql;
                    await migCmd.ExecuteNonQueryAsync();
                }
                catch (SqliteException ex) when (ex.Message.Contains("duplicate column name"))
                {
                    // Column already exists — safe to ignore
                }
            }
        }

        // Used only during schema creation before _initialized is set
        private SqliteConnection CreateOpenConnectionInternal()
        {
            SQLitePCL.Batteries_V2.Init();

            var csb = new SqliteConnectionStringBuilder
            {
                DataSource = _dbPath,
                Mode = SqliteOpenMode.ReadWriteCreate
            };

            var connection = new SqliteConnection(csb.ToString());
            connection.Open();

            using var keyCmd = connection.CreateCommand();
            keyCmd.CommandText = $"PRAGMA key = 'raw:{DeriveDeviceKey()}';";
            keyCmd.ExecuteNonQuery();

            return connection;
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _disposed = true;
            }
        }
    }
}
