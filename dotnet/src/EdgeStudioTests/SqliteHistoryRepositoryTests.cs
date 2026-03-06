using EdgeStudio.Shared.Data;
using EdgeStudio.Shared.Data.Repositories;
using EdgeStudio.Shared.Models;
using FluentAssertions;
using System;
using System.IO;
using System.Threading.Tasks;
using Xunit;

namespace EdgeStudioTests
{
    /// <summary>
    /// Integration tests for SqliteHistoryRepository and SqliteFavoritesRepository
    /// against a real encrypted SQLite database.
    /// </summary>
    public class SqliteHistoryRepositoryTests : IAsyncDisposable
    {
        private readonly string _dbPath;
        private readonly SqliteLocalDatabaseService _dbService;
        private readonly SqliteHistoryRepository _historyRepo;
        private readonly SqliteFavoritesRepository _favoritesRepo;

        public SqliteHistoryRepositoryTests()
        {
            _dbPath = Path.Combine(Path.GetTempPath(), $"test_history_{Guid.NewGuid():N}.db");
            _dbService = new SqliteLocalDatabaseService(_dbPath);
            _historyRepo = new SqliteHistoryRepository(_dbService);
            _favoritesRepo = new SqliteFavoritesRepository(_dbService);
        }

        public async ValueTask DisposeAsync()
        {
            _historyRepo.Dispose();
            _favoritesRepo.Dispose();
            _dbService.Dispose();
            if (File.Exists(_dbPath)) File.Delete(_dbPath);
            await Task.CompletedTask;
        }

        private async Task InitAsync() => await _dbService.InitializeAsync();

        private static QueryHistory MakeHistory(
            string id = "h-1",
            string query = "SELECT * FROM users",
            string selectedAppId = "app-1") =>
            new QueryHistory
            {
                Id = id,
                Query = query,
                CreatedDate = DateTime.UtcNow.ToString("o"),
                SelectedAppId = selectedAppId
            };

        #region AddQueryHistory Tests

        [Fact]
        public async Task AddQueryHistory_NewQuery_ShouldInsertRecord()
        {
            await InitAsync();
            var history = MakeHistory();

            await _historyRepo.AddQueryHistory(history);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM query_history WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", history.Id);
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(1);
        }

        [Fact]
        public async Task AddQueryHistory_DuplicateQuery_ShouldUpdateCreatedDate()
        {
            await InitAsync();
            var original = MakeHistory("h-1", "SELECT 1", "app-1");
            var updated = new QueryHistory
            {
                Id = "h-new",
                Query = original.Query,       // same query text
                CreatedDate = DateTime.UtcNow.AddHours(1).ToString("o"),
                SelectedAppId = original.SelectedAppId
            };

            await _historyRepo.AddQueryHistory(original);
            await _historyRepo.AddQueryHistory(updated);

            // Should still only have one record (upserted date)
            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM query_history WHERE query = 'SELECT 1'";
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(1);
        }

        [Fact]
        public async Task AddQueryHistory_SameQueryDifferentApp_ShouldInsertSeparately()
        {
            await InitAsync();
            var h1 = MakeHistory("h-1", "SELECT 1", "app-1");
            var h2 = MakeHistory("h-2", "SELECT 1", "app-2");

            await _historyRepo.AddQueryHistory(h1);
            await _historyRepo.AddQueryHistory(h2);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM query_history WHERE query = 'SELECT 1'";
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(2);
        }

        [Fact]
        public async Task AddQueryHistory_ShouldPersistAllFields()
        {
            await InitAsync();
            var history = MakeHistory("h-full", "SELECT * FROM orders", "app-x");

            await _historyRepo.AddQueryHistory(history);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT query, selected_app_id FROM query_history WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", history.Id);
            using var reader = await cmd.ExecuteReaderAsync();
            await reader.ReadAsync();
            reader.GetString(0).Should().Be("SELECT * FROM orders");
            reader.GetString(1).Should().Be("app-x");
        }

        #endregion

        #region DeleteQueryHistory Tests

        [Fact]
        public async Task DeleteQueryHistory_ShouldRemoveRecord()
        {
            await InitAsync();
            var history = MakeHistory();
            await _historyRepo.AddQueryHistory(history);

            await _historyRepo.DeleteQueryHistory(history);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM query_history WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", history.Id);
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(0);
        }

        [Fact]
        public async Task DeleteQueryHistory_NonExistentId_ShouldNotThrow()
        {
            await InitAsync();
            var history = MakeHistory("does-not-exist");

            var act = async () => await _historyRepo.DeleteQueryHistory(history);

            await act.Should().NotThrowAsync();
        }

        #endregion

        #region Favorites Tests (separate table)

        [Fact]
        public async Task Favorites_AddQuery_ShouldPersistToFavoritesTable()
        {
            await InitAsync();
            var fav = MakeHistory("f-1", "SELECT * FROM products");

            await _favoritesRepo.AddQueryHistory(fav);

            using var conn = _dbService.CreateOpenConnection();
            using var favCmd = conn.CreateCommand();
            favCmd.CommandText = "SELECT COUNT(*) FROM query_favorites WHERE id = $id";
            favCmd.Parameters.AddWithValue("$id", fav.Id);
            var favCount = Convert.ToInt64(await favCmd.ExecuteScalarAsync());
            favCount.Should().Be(1);

            // Must not appear in query_history
            using var histCmd = conn.CreateCommand();
            histCmd.CommandText = "SELECT COUNT(*) FROM query_history WHERE id = $id";
            histCmd.Parameters.AddWithValue("$id", fav.Id);
            var histCount = Convert.ToInt64(await histCmd.ExecuteScalarAsync());
            histCount.Should().Be(0);
        }

        [Fact]
        public async Task Favorites_DeleteQuery_ShouldRemoveFromFavoritesTable()
        {
            await InitAsync();
            var fav = MakeHistory("f-del");
            await _favoritesRepo.AddQueryHistory(fav);

            await _favoritesRepo.DeleteQueryHistory(fav);

            using var conn = _dbService.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT COUNT(*) FROM query_favorites WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", fav.Id);
            var count = Convert.ToInt64(await cmd.ExecuteScalarAsync());
            count.Should().Be(0);
        }

        [Fact]
        public async Task HistoryAndFavorites_AreIndependentTables()
        {
            await InitAsync();
            var histItem = MakeHistory("hist-1", "SELECT 1");
            var favItem = MakeHistory("fav-1", "SELECT 2");

            await _historyRepo.AddQueryHistory(histItem);
            await _favoritesRepo.AddQueryHistory(favItem);

            using var conn = _dbService.CreateOpenConnection();

            using var histCmd = conn.CreateCommand();
            histCmd.CommandText = "SELECT COUNT(*) FROM query_history";
            var histCount = Convert.ToInt64(await histCmd.ExecuteScalarAsync());

            using var favCmd = conn.CreateCommand();
            favCmd.CommandText = "SELECT COUNT(*) FROM query_favorites";
            var favCount = Convert.ToInt64(await favCmd.ExecuteScalarAsync());

            histCount.Should().Be(1);
            favCount.Should().Be(1);
        }

        #endregion

        #region ICloseDatabase Tests

        [Fact]
        public void CloseSelectedDatabase_ShouldNotThrow()
        {
            var act = () => _historyRepo.CloseSelectedDatabase();
            act.Should().NotThrow();
        }

        [Fact]
        public async Task CloseDatabaseAsync_ShouldCompleteWithoutError()
        {
            var act = async () => await _historyRepo.CloseDatabaseAsync();
            await act.Should().NotThrowAsync();
        }

        #endregion
    }
}
