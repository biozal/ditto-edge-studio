using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using DittoSDK;
using EdgeStudio.Shared.Models;
using EdgeStudio.Shared.Services;

namespace EdgeStudio.Shared.Data.Repositories
{
    /// <summary>
    /// SQLite-backed repository for user-defined Ditto subscriptions.
    /// Replaces DittoSubscriptionRepository - subscription definitions are stored in SQLite
    /// while active subscriptions are still registered with DittoSelectedApp.
    /// </summary>
    public sealed class SqliteSubscriptionRepository
        : SqliteRepositoryBase, ISubscriptionRepository, IDisposable
    {
        private readonly IDittoManager _dittoManager;
        private readonly ILoggingService? _logger;
        private readonly Dictionary<string, DittoSyncSubscription> _activeSubscriptions = new();
        private bool _disposed;

        public SqliteSubscriptionRepository(
            ILocalDatabaseService localDatabaseService,
            IDittoManager dittoManager,
            ILoggingService? logger = null)
            : base(localDatabaseService)
        {
            _dittoManager = dittoManager;
            _logger = logger;
        }

        public async Task SaveDittoSubscription(DittoDatabaseSubscription subscription)
        {
            var selectedAppId = _dittoManager.SelectedDatabaseConfig?.Id
                ?? throw new InvalidStateException("No selected Ditto app");

            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = @"
                INSERT INTO subscriptions (id, name, query, selected_app_id)
                VALUES ($id, $name, $query, $selected_app_id)
                ON CONFLICT(id) DO UPDATE SET
                    name = excluded.name,
                    query = excluded.query,
                    selected_app_id = excluded.selected_app_id";
            cmd.Parameters.AddWithValue("$id", subscription.Id);
            cmd.Parameters.AddWithValue("$name", subscription.Name);
            cmd.Parameters.AddWithValue("$query", subscription.Query);
            cmd.Parameters.AddWithValue("$selected_app_id", selectedAppId);
            await cmd.ExecuteNonQueryAsync();

            // Cancel and re-register the active Ditto subscription
            if (_activeSubscriptions.TryGetValue(subscription.Id, out var existing))
            {
                existing.Cancel();
                _activeSubscriptions.Remove(subscription.Id);
            }

            var selectedApp = _dittoManager.GetSelectedAppDitto();
            var sub = selectedApp.Sync.RegisterSubscription(subscription.Query);
            _activeSubscriptions[subscription.Id] = sub;
        }

        public async Task<List<DittoDatabaseSubscription>> GetDittoSubscriptions()
        {
            var selectedAppId = _dittoManager.SelectedDatabaseConfig?.Id
                ?? throw new InvalidStateException("No selected Ditto app");

            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "SELECT id, name, query FROM subscriptions WHERE selected_app_id = $selected_app_id";
            cmd.Parameters.AddWithValue("$selected_app_id", selectedAppId);

            var subscriptions = new List<DittoDatabaseSubscription>();
            using var reader = await cmd.ExecuteReaderAsync();
            while (await reader.ReadAsync())
            {
                subscriptions.Add(new DittoDatabaseSubscription(
                    Id: reader.GetString(0),
                    Name: reader.GetString(1),
                    Query: reader.GetString(2)));
            }

            // Register any subscriptions that aren't already active
            var selectedApp = _dittoManager.GetSelectedAppDitto();
            foreach (var sub in subscriptions.Where(s => !_activeSubscriptions.ContainsKey(s.Id)))
            {
                var activeSub = selectedApp.Sync.RegisterSubscription(sub.Query);
                _activeSubscriptions[sub.Id] = activeSub;
            }

            return subscriptions;
        }

        public async Task DeleteDittoSubscription(DittoDatabaseSubscription subscription)
        {
            using var conn = _db.CreateOpenConnection();
            using var cmd = conn.CreateCommand();
            cmd.CommandText = "DELETE FROM subscriptions WHERE id = $id";
            cmd.Parameters.AddWithValue("$id", subscription.Id);
            await cmd.ExecuteNonQueryAsync();

            if (_activeSubscriptions.TryGetValue(subscription.Id, out var activeSub))
            {
                activeSub.Cancel();
                _activeSubscriptions.Remove(subscription.Id);
            }
        }

        public override void CloseSelectedDatabase()
        {
            foreach (var sub in _activeSubscriptions.Values)
            {
                try { sub.Cancel(); }
                catch (ObjectDisposedException) { /* expected during database switching */ }
            }
            _activeSubscriptions.Clear();
        }

        public override async Task CloseDatabaseAsync()
        {
            if (_activeSubscriptions.Count == 0) return;

            var subscriptionsToCancel = _activeSubscriptions.Values.ToList();
            _activeSubscriptions.Clear(); // Clear references before async work

            var cancellationTasks = subscriptionsToCancel
                .Select(sub => Task.Run(() =>
                {
                    try { sub.Cancel(); }
                    catch (ObjectDisposedException) { }
                    catch (Exception ex)
                    {
                        _logger?.Error($"Error cancelling subscription: {ex.Message}");
                    }
                }))
                .ToArray();

            var allCancelled = Task.WhenAll(cancellationTasks);
            var completed = await Task.WhenAny(allCancelled, Task.Delay(TimeSpan.FromSeconds(5)));
            if (completed != allCancelled)
            {
                _logger?.Warning("Subscription cancellation timed out after 5 seconds.");
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
