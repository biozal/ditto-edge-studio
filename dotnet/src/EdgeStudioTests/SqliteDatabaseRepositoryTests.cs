using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using FluentAssertions;
using System;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Integration tests for SqliteDatabaseRepository against a real encrypted SQLite database.
    /// </summary>
    public class SqliteDatabaseRepositoryTests : IAsyncDisposable
    {
        private readonly string _dbPath;
        private readonly SqliteLocalDatabaseService _dbService;
        private readonly SqliteDatabaseRepository _repo;

        public SqliteDatabaseRepositoryTests()
        {
            _dbPath = Path.Combine(Path.GetTempPath(), $"test_dbrepo_{Guid.NewGuid():N}.db");
            _dbService = new SqliteLocalDatabaseService(_dbPath);
            _repo = new SqliteDatabaseRepository(_dbService);
        }

        public async ValueTask DisposeAsync()
        {
            _repo.Dispose();
            _dbService.Dispose();
            if (File.Exists(_dbPath)) File.Delete(_dbPath);
            await Task.CompletedTask;
        }

        private async Task InitAsync()
        {
            await _dbService.InitializeAsync();
        }

        private static DittoDatabaseConfig MakeConfig(string id = "id-1", string name = "Test DB") =>
            new DittoDatabaseConfig(
                Id: id,
                Name: name,
                DatabaseId: "db-" + id,
                AuthToken: "token-" + id,
                AuthUrl: "https://auth.example.com",
                HttpApiUrl: "https://api.example.com",
                HttpApiKey: "key-" + id,
                Mode: "server",
                AllowUntrustedCerts: false,
                IsBluetoothLeEnabled: true,
                IsLanEnabled: true,
                IsAwdlEnabled: false,
                IsCloudSyncEnabled: true,
                WebsocketUrl: "wss://example.com",
                IsStrictModeEnabled: false,
                LogLevel: "debug",
                SharedKey: "secret-" + id
            );

        #region AddDittoDatabaseConfig Tests

        [Fact]
        public async Task AddDittoDatabaseConfig_ShouldPersistRecord()
        {
            await InitAsync();
            var config = MakeConfig();

            await _repo.AddDittoDatabaseConfig(config);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM database_configs WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", config.Id);
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(1);
        }

        [Fact]
        public async Task AddDittoDatabaseConfig_ShouldPersistAllFields()
        {
            await InitAsync();
            var config = MakeConfig("full-id", "Full Config");

            await _repo.AddDittoDatabaseConfig(config);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name, database_id, auth_token, auth_url, mode FROM database_configs WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", config.Id);
            using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();

            reader.GetString(0).Should().Be("Full Config");
            reader.GetString(1).Should().Be("db-full-id");
            reader.GetString(2).Should().Be("token-full-id");
            reader.GetString(3).Should().Be("https://auth.example.com");
            reader.GetString(4).Should().Be("server");
        }

        [Fact]
        public async Task AddDittoDatabaseConfig_WithSameId_ShouldUpsert()
        {
            await InitAsync();
            var config = MakeConfig();
            var updated = config with { Name = "Updated Name" };

            await _repo.AddDittoDatabaseConfig(config);
            await _repo.AddDittoDatabaseConfig(updated);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*), name FROM database_configs WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", config.Id);
            using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            reader.GetInt64(0).Should().Be(1);
            reader.GetString(1).Should().Be("Updated Name");
        }

        #endregion

        #region DeleteDittoDatabaseConfig Tests

        [Fact]
        public async Task DeleteDittoDatabaseConfig_ShouldRemoveRecord()
        {
            await InitAsync();
            var config = MakeConfig();
            await _repo.AddDittoDatabaseConfig(config);

            await _repo.DeleteDittoDatabaseConfig(config);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM database_configs WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", config.Id);
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(0);
        }

        [Fact]
        public async Task DeleteDittoDatabaseConfig_NonExistentId_ShouldNotThrow()
        {
            await InitAsync();
            var config = MakeConfig("does-not-exist");

            var act = async () => await _repo.DeleteDittoDatabaseConfig(config);

            await act.Should().NotThrowAsync();
        }

        #endregion

        #region UpdateDatabaseConfig Tests

        [Fact]
        public async Task UpdateDatabaseConfig_ShouldModifyRecord()
        {
            await InitAsync();
            var config = MakeConfig();
            await _repo.AddDittoDatabaseConfig(config);
            var updated = config with { Name = "New Name", Mode = "smallpeersonly" };

            await _repo.UpdateDatabaseConfig(updated);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name, mode FROM database_configs WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", config.Id);
            using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            reader.GetString(0).Should().Be("New Name");
            reader.GetString(1).Should().Be("smallpeersonly");
        }

        #endregion

        #region SetupDatabaseConfigSubscriptions Tests

        [Fact]
        public async Task SetupDatabaseConfigSubscriptions_ShouldCompleteWithoutError()
        {
            await InitAsync();
            var act = async () => await _repo.SetupDatabaseConfigSubscriptions();

            await act.Should().NotThrowAsync();
        }

        #endregion

        #region CloseSelectedDatabase / ICloseDatabase Tests

        [Fact]
        public void CloseSelectedDatabase_ShouldNotThrow()
        {
            var act = () => _repo.CloseSelectedDatabase();
            act.Should().NotThrow();
        }

        [Fact]
        public async Task CloseDatabaseAsync_ShouldCompleteWithoutError()
        {
            var act = async () => await _repo.CloseDatabaseAsync();
            await act.Should().NotThrowAsync();
        }

        #endregion

        #region Transport and Log Level Tests

        [Fact]
        public async Task AddDittoDatabaseConfig_ShouldPersistTransportAndLogLevel()
        {
            await InitAsync();
            var config = MakeConfig("transport-test", "Transport Test");

            await _repo.AddDittoDatabaseConfig(config);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"SELECT is_bluetooth_le_enabled, is_lan_enabled, is_awdl_enabled,
                                        is_cloud_sync_enabled, log_level, websocket_url, is_strict_mode_enabled
                                 FROM database_configs WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", config.Id);
            using var reader = await cmd.ExecuteReaderAsync();
            (await reader.ReadAsync()).Should().BeTrue();

            reader.GetInt64(0).Should().Be(1); // IsBluetoothLeEnabled
            reader.GetInt64(1).Should().Be(1); // IsLanEnabled
            reader.GetInt64(2).Should().Be(0); // IsAwdlEnabled
            reader.GetInt64(3).Should().Be(1); // IsCloudSyncEnabled
            reader.GetString(4).Should().Be("debug"); // LogLevel
            reader.GetString(5).Should().Be("wss://example.com"); // WebsocketUrl
            reader.GetInt64(6).Should().Be(0); // IsStrictModeEnabled
        }

        #endregion

        #region Multiple Config Tests

        [Fact]
        public async Task AddMultipleConfigs_AllShouldBePersisted()
        {
            await InitAsync();
            var configs = new[]
            {
                MakeConfig("id-1", "Alpha"),
                MakeConfig("id-2", "Beta"),
                MakeConfig("id-3", "Gamma")
            };

            foreach (var c in configs)
                await _repo.AddDittoDatabaseConfig(c);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM database_configs";
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(3);
        }

        #endregion
    }
}
