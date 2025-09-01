using EdgeStudio.Models;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace EdgeStudio.Data.Repositories
{
    public interface ISubscriptionRepository
    {
        Task DeleteDittoSubscription(DittoDatabaseSubscription subscription);
        Task<List<DittoDatabaseSubscription>> GetDittoSubscriptions();
        Task SaveDittoSubscription(DittoDatabaseSubscription subscription);

    }
}
