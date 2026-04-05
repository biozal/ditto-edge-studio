using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using DittoSDK;
using DittoSDK.Store;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// SQLite-backed repository for user-defined Ditto observers.
    /// Observer definitions are stored in SQLite while active DittoStoreObserver
    /// instances are tracked in memory at runtime.
    /// </summary>
    public sealed class SqliteObserverRepository
        : SqliteRepositoryBase, IObserverRepository, IDisposable
    {
        private readonly IDittoManager _dittoManager;
        private readonly ILoggingService? _logger;
        private readonly Dictionary<string, DittoStoreObserver> _activeObservers = new();
        private bool _disposed;

        public SqliteObserverRepository(
            ILocalDatabaseService localDatabaseService,
            IDittoManager dittoManager,
            ILoggingService? logger = null)
            : base(localDatabaseService)
        {
            _dittoManager = dittoManager;
            _logger = logger;
        }

        public async Task<List<DittoDatabaseObserver>> GetObserversAsync()
        {
            var selectedAppId = _dittoManager.SelectedDatabaseConfig?.Id
                ?? throw new InvalidStateException("No selected Ditto app");

            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                SELECT id, name, query FROM observers
                WHERE selected_app_id = $selected_app_id
                ORDER BY name";
            cmd.Parameters.AddWithValue("$selected_app_id", selectedAppId);

            var observers = new List<DittoDatabaseObserver>();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                var id = reader.GetString(0);
                observers.Add(new DittoDatabaseObserver(
                    Id: id,
                    Name: reader.GetString(1),
                    Query: reader.GetString(2))
                {
                    IsActive = _activeObservers.ContainsKey(id)
                });
            }

            return observers;
        }

        public async Task SaveObserverAsync(DittoDatabaseObserver observer)
        {
            var selectedAppId = _dittoManager.SelectedDatabaseConfig?.Id
                ?? throw new InvalidStateException("No selected Ditto app");

            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                INSERT INTO observers (id, name, query, selected_app_id)
                VALUES ($id, $name, $query, $selected_app_id)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    query = excluded.query,
                    selected_app_id = excluded.selected_app_id";
            cmd.Parameters.AddWithValue("$id", observer.Id);
            cmd.Parameters.AddWithValue("$name", observer.Name);
            cmd.Parameters.AddWithValue("$query", observer.Query);
            cmd.Parameters.AddWithValue("$selected_app_id", selectedAppId);
            await cmd.ExecuteNonQueryAsync();

            _logger?.Debug($"Saved observer: {observer.Name}");
        }

        public async Task DeleteObserverAsync(string observerId)
        {
            // Cancel the active observer if running
            DeactivateObserver(observerId);

            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM observers WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", observerId);
            await cmd.ExecuteNonQueryAsync();

            _logger?.Debug($"Deleted observer: {observerId}");
        }

        public Task<bool> ActivateObserverAsync(DittoDatabaseObserver observer,
            Action<DittoQueryResult> callback)
        {
            try
            {
                // Cancel existing observer if re-activating
                DeactivateObserver(observer.Id);

                var ditto = _dittoManager.GetSelectedAppDitto();
                var storeObserver = ditto.Store.RegisterObserver(observer.Query, callback);
                _activeObservers[observer.Id] = storeObserver;

                _logger?.Info($"Activated observer: {observer.Name}");
                return Task.FromResult(true);
            }
            catch (Exception ex)
            {
                _logger?.Error($"Failed to activate observer '{observer.Name}': {ex.Message}");
                return Task.FromResult(false);
            }
        }

        public void DeactivateObserver(string observerId)
        {
            if (_activeObservers.TryGetValue(observerId, out var activeObserver))
            {
                try
                {
                    activeObserver.Cancel();
                }
                catch (ObjectDisposedException)
                {
                    // Expected during database switching
                }
                _activeObservers.Remove(observerId);
                _logger?.Info($"Deactivated observer: {observerId}");
            }
        }

        public bool IsObserverActive(string observerId)
        {
            return _activeObservers.ContainsKey(observerId);
        }

        public override void CloseSelectedDatabase()
        {
            foreach (var observer in _activeObservers.Values)
            {
                try { observer.Cancel(); }
                catch (ObjectDisposedException) { /* expected during database switching */ }
            }
            _activeObservers.Clear();
        }

        public override async Task CloseDatabaseAsync()
        {
            if (_activeObservers.Count == 0) return;

            var observersToCancel = _activeObservers.Values.ToList();
            _activeObservers.Clear(); // Clear references before async work

            var cancellationTasks = observersToCancel
                .Select(obs => Task.Run(() =>
                {
                    try { obs.Cancel(); }
                    catch (ObjectDisposedException) { }
                    catch (Exception ex)
                    {
                        _logger?.Error($"Error cancelling observer: {ex.Message}");
                    }
                }))
                .ToArray();

            var allCancelled = Task.WhenAll(cancellationTasks);
            var completed = await Task.WhenAny(allCancelled, Task.Delay(TimeSpan.FromSeconds(5)));
            if (completed != allCancelled)
            {
                _logger?.Warning("Observer cancellation timed out after 5 seconds.");
            }
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                CloseSelectedDatabase();
                _disposed = true;
            }
        }
    }
}
