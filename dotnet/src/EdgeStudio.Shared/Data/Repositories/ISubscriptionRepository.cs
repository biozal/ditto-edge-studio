using EdgeStudio.Shared.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace EdgeStudio.Shared.Data.Repositories
{
    public interface ISubscriptionRepository : ICloseDatabase
    {
        Task DeleteDittoSubscription(DittoDatabaseSubscription subscription);
        Task<List<DittoDatabaseSubscription>> GetDittoSubscriptions();
        Task SaveDittoSubscription(DittoDatabaseSubscription subscription);

    }
}
