using System;
using System.IO;
using System.Threading.Tasks;
using EdgeStudio.Shared.Data;
using FluentAssertions;
using Microsoft.Data.Sqlite;
using Moq;
using Xunit;

namespace EdgeStudioTests
{
    public class SettingsRepositoryTests : IDisposable
    {
        private readonly string _dbPath;
        private readonly Mock<ILocalDatabaseService> _mockDb;
        private readonly SqliteSettingsRepository _repo;

        public SettingsRepositoryTests()
        {
            _dbPath = Path.Combine(Path.GetTempPath(), $"test_settings_{Guid.NewGuid():N}.db");
            _mockDb = new Mock<ILocalDatabaseService>();
            _mockDb.Setup(x => x.CreateOpenConnection()).Returns(() =>
            {
                var conn = new SqliteConnection($"Data Source={_dbPath}");
                conn.Open();
                return conn;
            });
            _repo = new SqliteSettingsRepository(_mockDb.Object);
        }

        public void Dispose()
        {
            if (File.Exists(_dbPath))
                File.Delete(_dbPath);
        }

        [Fact]
        public async Task InitializeAsync_CreatesAppSettingsTable()
        {
            await _repo.InitializeAsync();

            await using var conn = _mockDb.Object.CreateOpenConnection();
            await using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT name FROM sqlite_master WHERE type='table' AND name='app_settings'";
            var result = await cmd.ExecuteScalarAsync();
            result.Should().Be("app_settings");
        }

        [Fact]
        public async Task GetAsync_ReturnsNull_WhenKeyDoesNotExist()
        {
            await _repo.InitializeAsync();

            var result = await _repo.GetAsync("nonexistent");

            result.Should().BeNull();
        }

        [Fact]
        public async Task SetAsync_And_GetAsync_RoundTrip()
        {
            await _repo.InitializeAsync();

            await _repo.SetAsync("testKey", "testValue");
            var result = await _repo.GetAsync("testKey");

            result.Should().Be("testValue");
        }

        [Fact]
        public async Task SetAsync_OverwritesExistingValue()
        {
            await _repo.InitializeAsync();
            await _repo.SetAsync("key", "first");

            await _repo.SetAsync("key", "second");
            var result = await _repo.GetAsync("key");

            result.Should().Be("second");
        }

        [Fact]
        public async Task GetBoolAsync_ReturnsDefault_WhenKeyMissing()
        {
            await _repo.InitializeAsync();

            var result = await _repo.GetBoolAsync("missing", defaultValue: true);

            result.Should().BeTrue();
        }

        [Fact]
        public async Task GetBoolAsync_ReturnsFalseDefault_WhenKeyMissingAndDefaultFalse()
        {
            await _repo.InitializeAsync();

            var result = await _repo.GetBoolAsync("missing", defaultValue: false);

            result.Should().BeFalse();
        }

        [Fact]
        public async Task SetBoolAsync_And_GetBoolAsync_RoundTrip_True()
        {
            await _repo.InitializeAsync();

            await _repo.SetBoolAsync("mcpServerEnabled", true);
            var result = await _repo.GetBoolAsync("mcpServerEnabled");

            result.Should().BeTrue();
        }

        [Fact]
        public async Task SetBoolAsync_And_GetBoolAsync_RoundTrip_False()
        {
            await _repo.InitializeAsync();

            await _repo.SetBoolAsync("mcpServerEnabled", false);
            var result = await _repo.GetBoolAsync("mcpServerEnabled");

            result.Should().BeFalse();
        }

        [Fact]
        public async Task GetIntAsync_ReturnsDefault_WhenKeyMissing()
        {
            await _repo.InitializeAsync();

            var result = await _repo.GetIntAsync("port", defaultValue: 65269);

            result.Should().Be(65269);
        }

        [Fact]
        public async Task GetIntAsync_ReturnsZeroDefault_WhenKeyMissingAndNoDefault()
        {
            await _repo.InitializeAsync();

            var result = await _repo.GetIntAsync("missing");

            result.Should().Be(0);
        }

        [Fact]
        public async Task SetIntAsync_And_GetIntAsync_RoundTrip()
        {
            await _repo.InitializeAsync();

            await _repo.SetIntAsync("mcpServerPort", 8080);
            var result = await _repo.GetIntAsync("mcpServerPort");

            result.Should().Be(8080);
        }

        [Fact]
        public async Task SetIntAsync_OverwritesExistingValue()
        {
            await _repo.InitializeAsync();
            await _repo.SetIntAsync("port", 1234);

            await _repo.SetIntAsync("port", 5678);
            var result = await _repo.GetIntAsync("port");

            result.Should().Be(5678);
        }

        [Fact]
        public async Task MultipleKeys_AreStoredAndRetrievedIndependently()
        {
            await _repo.InitializeAsync();

            await _repo.SetAsync("key1", "value1");
            await _repo.SetAsync("key2", "value2");

            var result1 = await _repo.GetAsync("key1");
            var result2 = await _repo.GetAsync("key2");

            result1.Should().Be("value1");
            result2.Should().Be("value2");
        }
    }
}
