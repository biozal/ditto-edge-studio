using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using Avalonia.Threading;
using EdgeStudio.Shared.Models;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// SQLite-backed repository for query history.
    /// Replaces HistoryRepository - stores history in the local encrypted SQLite database.
    /// Duplicate queries are handled by updating the createdDate rather than inserting a new row.
    /// </summary>
    public class SqliteHistoryRepository
        : SqliteRepositoryBase, IHistoryRepository, IDisposable
    {
        protected virtual string TableName => "query_history";

        private ObservableCollection<QueryHistory>? _items;
        private bool _disposed;

        public SqliteHistoryRepository(ILocalDatabaseService localDatabaseService)
            : base(localDatabaseService) { }

        public async Task AddQueryHistory(QueryHistory queryHistory)
        {
            using var conn = _db.CreateOpenConnection();

            // Check if this query already exists for the same app
            string? existingId = null;
            using (var checkCmd = conn.CreateCommand())
            {
                checkCmd.CommandText = $@"
                    SELECT id FROM {TableName}
                    WHERE query = $query AND selected_app_id = $selected_app_id
                    LIMIT 1";
                checkCmd.Parameters.AddWithValue("$query", queryHistory.Query);
                checkCmd.Parameters.AddWithValue("$selected_app_id", queryHistory.SelectedAppId);
                var result = await checkCmd.ExecuteScalarAsync();
                existingId = result as string;
            }

            if (existingId != null)
            {
                // Update the timestamp on the existing entry
                using var updateCmd = conn.CreateCommand();
                updateCmd.CommandText = $@"
                    UPDATE {TableName}
                    SET created_date = $created_date
                    WHERE id = $id";
                updateCmd.Parameters.AddWithValue("$created_date", queryHistory.CreatedDate);
                updateCmd.Parameters.AddWithValue("$id", existingId);
                await updateCmd.ExecuteNonQueryAsync();

                if (_items != null)
                    await Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        var existing = _items.FirstOrDefault(h => h.Id == existingId);
                        if (existing != null)
                        {
                            var idx = _items.IndexOf(existing);
                            _items[idx] = existing with { CreatedDate = queryHistory.CreatedDate };
                        }
                    });
            }
            else
            {
                using var insertCmd = conn.CreateCommand();
                insertCmd.CommandText = $@"
                    INSERT INTO {TableName} (id, query, created_date, selected_app_id)
                    VALUES ($id, $query, $created_date, $selected_app_id)";
                insertCmd.Parameters.AddWithValue("$id", queryHistory.Id);
                insertCmd.Parameters.AddWithValue("$query", queryHistory.Query);
                insertCmd.Parameters.AddWithValue("$created_date", queryHistory.CreatedDate);
                insertCmd.Parameters.AddWithValue("$selected_app_id", queryHistory.SelectedAppId);
                await insertCmd.ExecuteNonQueryAsync();

                if (_items != null)
                    await Dispatcher.UIThread.InvokeAsync(() => _items.Add(queryHistory));
            }
        }

        public async Task DeleteQueryHistory(QueryHistory queryHistory)
        {
            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = $"DELETE FROM {TableName} WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", queryHistory.Id);
            await cmd.ExecuteNonQueryAsync();

            if (_items != null)
                await Dispatcher.UIThread.InvokeAsync(() =>
                {
                    var item = _items.FirstOrDefault(h => h.Id == queryHistory.Id);
                    if (item != null) _items.Remove(item);
                });
        }

        /// <summary>
        /// Loads all history entries from SQLite into the provided collection.
        /// The collection is kept in sync with subsequent Add/Delete operations.
        /// </summary>
        public void RegisterObserver(
            ObservableCollection<QueryHistory> queryHistorys,
            Action<string> errorMessage)
        {
            _items = queryHistorys;

            _ = Task.Run(async () =>
            {
                try
                {
                    var items = await LoadAllAsync();
                    await Dispatcher.UIThread.InvokeAsync(() =>
                    {
                        queryHistorys.Clear();
                        foreach (var item in items)
                            queryHistorys.Add(item);
                    });
                }
                catch (Exception ex)
                {
                    errorMessage($"Failed to load history: {ex.Message}");
                }
            });
        }

        private async Task<System.Collections.Generic.List<QueryHistory>> LoadAllAsync()
        {
            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = $@"
                SELECT id, query, created_date, selected_app_id
                FROM {TableName}
                ORDER BY created_date DESC";

            var results = new System.Collections.Generic.List<QueryHistory>();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                results.Add(new QueryHistory
                {
                    Id = reader.GetString(0),
                    Query = reader.GetString(1),
                    CreatedDate = reader.GetString(2),
                    SelectedAppId = reader.GetString(3)
                });
            }
            return results;
        }

        public void Dispose()
        {
            Dispose(true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!_disposed)
            {
                if (disposing) _items = null;
                _disposed = true;
            }
        }
    }
}
