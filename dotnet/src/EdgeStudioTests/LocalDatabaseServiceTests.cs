using EdgeStudio.Shared.Data;
using FluentAssertions;
using Microsoft.Data.Sqlite;
using System;
using System.IO;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Tests for SqliteLocalDatabaseService: schema creation, encryption key derivation,
    /// and connection factory behaviour.
    /// </summary>
    public class LocalDatabaseServiceTests : IDisposable
    {
        private readonly string _tempDbPath;

        public LocalDatabaseServiceTests()
        {
            // Use an isolated temp file per test class instance so tests don't share state
            _tempDbPath = Path.Combine(Path.GetTempPath(), $"test_edgestudio_{Guid.NewGuid():N}.db");
        }

        public void Dispose()
        {
            // Clean up temp database file after each test run
            if (File.Exists(_tempDbPath))
                File.Delete(_tempDbPath);
        }

        private SqliteLocalDatabaseService CreateService() => new SqliteLocalDatabaseService(_tempDbPath);

        #region InitializeAsync Tests

        [Fact]
        public async Task InitializeAsync_ShouldCreateDatabaseFile()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            File.Exists(_tempDbPath).Should().BeTrue();
        }

        [Fact]
        public async Task InitializeAsync_CalledTwice_ShouldNotThrow()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();
            var act = async () => await svc.InitializeAsync();

            await act.Should().NotThrowAsync();
        }

        [Fact]
        public async Task InitializeAsync_ShouldCreateDatabaseConfigsTable()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn = svc.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='database_configs'";
            var result = await cmd.ExecuteScalarAsync();

            result.Should().Be("database_configs");
        }

        [Fact]
        public async Task InitializeAsync_ShouldCreateSubscriptionsTable()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn = svc.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='subscriptions'";
            var result = await cmd.ExecuteScalarAsync();

            result.Should().Be("subscriptions");
        }

        [Fact]
        public async Task InitializeAsync_ShouldCreateQueryHistoryTable()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn = svc.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='query_history'";
            var result = await cmd.ExecuteScalarAsync();

            result.Should().Be("query_history");
        }

        [Fact]
        public async Task InitializeAsync_ShouldCreateQueryFavoritesTable()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn = svc.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='query_favorites'";
            var result = await cmd.ExecuteScalarAsync();

            result.Should().Be("query_favorites");
        }

        [Fact]
        public async Task InitializeAsync_ShouldCreateSubscriptionsIndex()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn = svc.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_subscriptions_selected_app_id'";
            var result = await cmd.ExecuteScalarAsync();

            result.Should().Be("idx_subscriptions_selected_app_id");
        }

        #endregion

        #region CreateOpenConnection Tests

        [Fact]
        public async Task CreateOpenConnection_BeforeInitialize_ShouldThrow()
        {
            using var svc = CreateService();
            var act = () => svc.CreateOpenConnection();

            act.Should().Throw<InvalidOperationException>()
                .WithMessage("*InitializeAsync*");
        }

        [Fact]
        public async Task CreateOpenConnection_AfterInitialize_ShouldReturnOpenConnection()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn = svc.CreateOpenConnection();

            conn.Should().NotBeNull();
            conn.State.Should().Be(System.Data.ConnectionState.Open);
        }

        [Fact]
        public async Task CreateOpenConnection_ReturnsNewConnectionEachCall()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn1 = svc.CreateOpenConnection();
            using var conn2 = svc.CreateOpenConnection();

            conn1.Should().NotBeSameAs(conn2);
        }

        [Fact]
        public async Task CreateOpenConnection_EncryptedDatabase_IsReadable()
        {
            using var svc = CreateService();
            await svc.InitializeAsync();

            using var conn = svc.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM database_configs";
            var result = await cmd.ExecuteScalarAsync();

            Convert.ToInt64(result).Should().Be(0);
        }

        [Fact]
        public async Task CreateOpenConnection_SameKeyOnReopenedDatabase_ShouldSucceed()
        {
            // Create and populate the database
            using (var svc = CreateService())
            {
                await svc.InitializeAsync();
                using var conn = svc.CreateOpenConnection();
                using var cmd = conn.CreateCommand();
                cmd.CommandText = "INSERT INTO database_configs (id, name, database_id, auth_token, auth_url, http_api_url, http_api_key, mode, allow_untrusted_certs) VALUES ('1','Test','db1','tok','https://auth','','','online',0)";
                await cmd.ExecuteNonQueryAsync();
            }

            // Re-open the same database - encryption key must be consistent
            using var svc2 = CreateService();
            await svc2.InitializeAsync();
            using var conn2 = svc2.CreateOpenConnection();
            using var cmd2 = conn2.CreateCommand();
            cmd2.CommandText = "SELECT COUNT(*) FROM database_configs";
            var count = Convert.ToInt64(await cmd2.ExecuteScalarAsync());

            count.Should().Be(1);
        }

        #endregion

        #region Device Key Tests

        [Fact]
        public void DeriveDeviceKey_ShouldReturn64HexChars()
        {
            var key = SqliteLocalDatabaseService.DeriveDeviceKey();

            key.Should().HaveLength(64);
        }

        [Fact]
        public void DeriveDeviceKey_ShouldBeDeterministic()
        {
            var key1 = SqliteLocalDatabaseService.DeriveDeviceKey();
            var key2 = SqliteLocalDatabaseService.DeriveDeviceKey();

            key1.Should().Be(key2);
        }

        [Fact]
        public void DeriveDeviceKey_ShouldBeHexadecimal()
        {
            var key = SqliteLocalDatabaseService.DeriveDeviceKey();

            key.Should().MatchRegex("^[0-9a-f]{64}$");
        }

        #endregion
    }
}
