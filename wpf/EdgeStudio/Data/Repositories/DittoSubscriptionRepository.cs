using DittoSDK;
using EdgeStudio.Models;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace EdgeStudio.Data.Repositories
{
    internal class DittoSubscriptionRepository(IDittoManager _dittoManager) :
        IDisposable, ISubscriptionRepository
    {
        private bool disposedValue;
        private List<DittoSyncSubscription> _activeSubscriptions = new();

        public async Task DeleteDittoSubscription(DittoDatabaseSubscription subscription)
        {
            throw new NotImplementedException();
        }

        public void Dispose()
        {
            // Do not change this code. Put cleanup code in 'Dispose(bool disposing)' method
            Dispose(disposing: true);
            GC.SuppressFinalize(this);
        }

        public Task SaveDittoSubscription(DittoDatabaseSubscription subscription)
        {
            throw new NotImplementedException();
        }

        protected virtual void Dispose(bool disposing)
        {
            if (!disposedValue)
            {
                if (disposing)
                {
                    foreach (var sub in _activeSubscriptions)
                    {
                        sub.Cancel();
                    }
                    _activeSubscriptions.Clear();
                }

                disposedValue = true;
            }
        }
    }
}
