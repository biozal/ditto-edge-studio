using DittoSDK;
using EdgeStudio.Models;
using System;
using System.Linq;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace EdgeStudio.Data.Repositories
{
    internal class DittoSubscriptionRepository(IDittoManager _dittoManager) :
        IDisposable, ISubscriptionRepository
    {
        private bool disposedValue;
        private readonly Dictionary<string, DittoSyncSubscription> _activeSubscriptions = new();

        public async Task DeleteDittoSubscription(DittoDatabaseSubscription subscription)
        {
            var ditto = _dittoManager.GetLocalDitto();
            var query = "DELETE FROM dittosubscriptions WHERE _id = :id";
            var args = new Dictionary<string, object> { { "id", subscription.Id } };
            await ditto.Store.ExecuteAsync(query, args);
            var existingSub = _activeSubscriptions[subscription.Id];
            if (existingSub != null)
            {
                existingSub.Cancel();
                _activeSubscriptions.Remove(subscription.Id);
            }
        }

        public void Dispose()
        {
            // Do not change this code. Put cleanup code in 'Dispose(bool disposing)' method
            Dispose(disposing: true);
            GC.SuppressFinalize(this);
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!disposedValue)
            {
                if (disposing)
                {
                    foreach (var sub in _activeSubscriptions)
                    {
                        sub.Value.Cancel();
                    }
                    _activeSubscriptions.Clear();
                }

                disposedValue = true;
            }
        }

        public async Task<List<DittoDatabaseSubscription>> GetDittoSubscriptions()
        {
            var ditto = _dittoManager.GetLocalDitto();
            var dittoSelectedApp = _dittoManager.GetSelectedAppDitto();
            var query = "SELECT * FROM dittosubscriptions WHERE selectedApp_id = :selectedApp_id";
            var args = new Dictionary<string, object>
            {
                { "selectedApp_id", _dittoManager.SelectedDatabaseConfig?.Id ?? throw new InvalidStateException("No selected Ditto app") }
            };
            var result = await ditto.Store.ExecuteAsync(query, args);
            var subscriptions = result.Items
                .Select(doc => doc.Value)
                .Select(value =>
                {
                    var id = value["_id"].ToString() ?? throw new InvalidStateException("Subscription document missing _id");
                    var name = value["name"].ToString() ?? throw new InvalidStateException("Subscription document missing name");
                    var queryStr = value["query"].ToString() ?? throw new InvalidStateException("Subscription document missing query");
                    return new DittoDatabaseSubscription(id, name, queryStr);
                })
                .ToList();

            //register the subscriptions with the selected app Ditto instance
            foreach (var subscription in subscriptions)
            {
                if (!_activeSubscriptions.ContainsKey(subscription.Id))
                {
                    var sub = dittoSelectedApp.Sync.RegisterSubscription(subscription.Query);
                    _activeSubscriptions.Add(subscription.Id, sub);
                }
            }
            return subscriptions;
        }

        public async Task SaveDittoSubscription(DittoDatabaseSubscription subscription)
        {
            var ditto = _dittoManager.GetLocalDitto();
            var selectedAppId = _dittoManager.SelectedDatabaseConfig?.Id ?? throw new InvalidStateException("No selected Ditto app");
            var query = "INSERT INTO dittosubscriptions DOCUMENTS (:newSubscription) ON ID CONFLICT DO UPDATE";
            var newSubscription = new Dictionary<string, object>
            {
                { "_id", subscription.Id },
                { "name", subscription.Name },
                { "query", subscription.Query },
                { "selectedApp_id", selectedAppId }
            };
            var args = new Dictionary<string, object> { { "newSubscription", newSubscription } };
            await ditto.Store.ExecuteAsync(query, args);
            if (_activeSubscriptions.ContainsKey(subscription.Id))
            {
                var existingSub = _activeSubscriptions[subscription.Id];
                existingSub.Cancel();
                _activeSubscriptions.Remove(subscription.Id);
            }
            var sub = ditto.Sync.RegisterSubscription(subscription.Query);
            _activeSubscriptions.Add(subscription.Id, sub);
        }
    }
}
